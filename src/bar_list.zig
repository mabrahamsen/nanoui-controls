//! A bar list: rows of a label, a bar across and a figure, the bars
//! scaled to the largest. The busiest processes, disk use by folder,
//! visits by page. Rows can be clicked, to open what they stand for.
//! A row can lead with an icon or a badge and end with a detail, and the
//! bars can take a ramp's colors, glow, or be meters lit in steps: a
//! level per row, such as a temperature or a fan's speed.
//!
//!     const items = [_]controls.BarListItem{
//!         .{ .label = "Photos", .value = 41.2, .value_text = "41.2 GB" },
//!         .{ .label = "Music", .value = 12.9, .value_text = "12.9 GB" },
//!     };
//!     if (controls.barList(c, &items, .{ .clickable = true })) |i| open(items[i]);
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const focus = @import("focus.zig");
const breakdown_mod = @import("breakdown.zig");
const meter_mod = @import("meter.zig");
const chart = @import("chart.zig");

/// One row of the list.
pub const Item = struct {
    label: []const u8,
    /// Its bar's length, on the list's scale: a negative value or one
    /// that is not a number draws none.
    value: f32,
    /// The figure at the end ("41.2 GB"), and what a screen reader says.
    value_text: []const u8 = "",
    /// Its bar's color; null takes the list's, or its ramp's.
    color: ?ui.Color = null,
    /// A symbol before the label, in a slot of its own, so labels line up
    /// whatever the icons.
    icon: ?[]const u8 = null,
    /// A short text before the label in a small tinted tag ("P", "GPU"),
    /// in `badge_color`, or the row's color.
    badge: []const u8 = "",
    badge_color: ?ui.Color = null,
    /// A second, muted figure after the first, such as a maximum ("max 94").
    detail: []const u8 = "",
    /// The figure's color, such as the ramp's for its level; null takes
    /// the theme's muted text.
    value_color: ?ui.Color = null,
};

/// How a row's bar is drawn.
pub const Style = enum {
    /// A bar across, filled to the value.
    bar,
    /// A meter of `segments`, lit to the value: a level read in steps.
    meter,
};

pub const Options = struct {
    /// The value of a full bar; null takes the largest item's.
    max: ?f32 = null,
    /// The value of an empty bar: a temperature from 20 to 110 fills the
    /// bar from its start.
    min: f32 = 0,
    /// The labels' column, wide enough for most labels; longer ones are
    /// cut short with an ellipsis.
    label_width: f32 = 120,
    /// The figures' column, at the end.
    value_width: f32 = 64,
    bar_height: f32 = 6,
    /// Between the rows.
    gap: f32 = 2,
    /// The text's size, as the kit's.
    size: kit.Size = .sm,
    /// The bars' color; null takes the theme's accent.
    color: ?ui.Color = null,
    /// Colors from an empty bar to a full one: each bar takes the color
    /// at its level, as a meter's segments do. A row's own color wins.
    ramp: []const ui.Color = &.{},
    /// Where no bar is; null takes the kit's progress track.
    track: ?ui.Color = null,
    /// The opacity of a glow around each bar, in its color; 0 draws none.
    glow: f32 = 0,
    /// The bars' corners; null rounds their ends.
    bar_radius: ?f32 = null,
    style: Style = .bar,
    /// With `.meter`, how many segments a row's meter has.
    segments: usize = 12,
    /// The details' column, at the end; nothing is kept for it when no row
    /// has a detail.
    detail_width: f32 = 56,
    /// Rows light up under the pointer and can be clicked, or reached
    /// with Tab and clicked with Enter.
    clickable: bool = false,
    /// Multiplies its lengths but not its text, as the charts'.
    scale: f32 = 1,
};

/// Draws a row for each of `items`, and returns the one clicked this
/// frame, with `clickable`.
pub fn barList(c: *ui.Context, items: []const Item, opts: Options) ?usize {
    const t = kit.tokens(c);
    const k = opts.scale;
    var max: f32 = 0;
    if (opts.max) |m| {
        max = m;
    } else for (items) |it| {
        if (std.math.isFinite(it.value)) max = @max(max, it.value);
    }
    const col = ui.div(c).column().wFull().gap(opts.gap * k);
    defer col.end();
    var clicked: ?usize = null;
    const text = opts.size.text();
    // Slots and columns only when a row has something for them, so the
    // rest line up.
    var icons = false;
    var details = false;
    for (items) |it| {
        icons = icons or it.icon != null;
        details = details or it.detail.len > 0;
    }
    for (items, 0..) |it, i| {
        ui.keyInt(c, i);
        var row = ui.div(c).row().wFull().itemsCenter().gap(10 * k).px(6 * k).py(@round(text * 0.35) * k).rounded(@max(0, t.radius - 2));
        if (opts.clickable) {
            // Each row takes the keyboard, as a button does: Tab moves
            // from row to row, and Enter clicks the one that has it.
            const in = c.interact(row.index, .{ .focusable = true });
            if (in.hovered) {
                row = row.bg(t.surface_hover);
                c.cursor_hand = true;
            }
            if (in.focused) row = row.border(focus.ring(c));
            // Enter or Space clicks the row that has the keyboard, and is
            // the list's: nothing after it sees it.
            const pressed = in.focused and (c.input.key == .enter or c.shortcut(.{ .key = ' ' }) or std.mem.eql(u8, c.input.chars, " "));
            if (pressed) {
                c.input.key = null;
                c.input.chars = "";
            }
            if (in.clicked or pressed) {
                clicked = i;
                c.changed = true;
            }
        }
        defer row.end();
        if (icons) {
            const slot = ui.div(c).w(@round(text * 1.3) * k).h(text * k).center();
            defer slot.end();
            if (it.icon) |name| ui.icon(c, name, .{ .size = text - 0.5, .color = t.muted });
        }
        // A value that is not a number draws no bar.
        const share = chart.level(it.value, opts.min, max) orelse 0;
        const bar_color = it.color orelse if (opts.ramp.len > 0) chart.rampColor(opts.ramp, share) else opts.color orelse t.primary;
        {
            const l = ui.div(c).w(opts.label_width * k).row().itemsCenter().gap(@round(text * 0.4) * k);
            defer l.end();
            if (it.badge.len > 0) {
                const tint = it.badge_color orelse bar_color;
                const b = ui.div(c).px(@round(text * 0.35) * k).py(1 * k).rounded(3 * k).bg(tint.alpha(0.15)).border(tint.alpha(0.4));
                defer b.end();
                ui.text(c, it.badge, .{ .size = text - 3, .weight = .bold, .mono = true, .color = tint });
            }
            ui.text(c, it.label, .{ .size = text, .color = t.foreground, .truncate = .ellipsis });
        }
        switch (opts.style) {
            .bar => breakdown_mod.breakdown(c, &.{.{ .value = share, .color = bar_color }}, .{
                .height = opts.bar_height,
                .radius = opts.bar_radius,
                .part_radius = if (opts.glow > 0) (opts.bar_radius orelse opts.bar_height / 2) else 0,
                .glow = opts.glow,
                .track = opts.track,
                .scale = k,
            }),
            .meter => meter_mod.meter(c, share, .{
                .segments = opts.segments,
                .height = opts.bar_height,
                .color = if (it.color != null or opts.ramp.len == 0) bar_color else null,
                .ramp = if (it.color == null) opts.ramp else &.{},
                .glow = opts.glow,
                .track = opts.track,
                .radius = opts.bar_radius orelse 2,
                .scale = k,
            }),
        }
        {
            const v = ui.div(c).w(opts.value_width * k).row().justifyEnd();
            defer v.end();
            ui.text(c, it.value_text, .{ .size = text - 1, .mono = true, .color = it.value_color orelse t.muted });
        }
        if (details) {
            const d = ui.div(c).w(opts.detail_width * k).row().justifyEnd();
            defer d.end();
            ui.text(c, it.detail, .{ .size = text - 2, .mono = true, .color = t.muted.alpha(0.8), .truncate = .ellipsis });
        }
        const value = if (it.detail.len > 0) c.print("{s}, {s}", .{ it.value_text, it.detail }) else it.value_text;
        ui.access.describe(c, row.index, .{ .role = if (opts.clickable) .button else .static_text, .label = it.label, .value = value });
    }
    return clicked;
}

const Folders = struct {
    clicked: ?usize = null,
    /// Keys left for the app after the list, and frames marked changed.
    leaked: usize = 0,
    changed: usize = 0,
    const items = [_]Item{
        .{ .label = "Photos", .value = 40, .value_text = "40 GB" },
        .{ .label = "Music", .value = 10, .value_text = "10 GB" },
        .{ .label = "Broken", .value = std.math.nan(f32), .value_text = "?" },
    };
    fn view(f: *Folders, c: *ui.Context) void {
        const root = ui.div(c).column().w(400);
        defer root.end();
        if (barList(c, &items, .{ .clickable = true })) |i| f.clicked = i;
        if (c.input.key != null) f.leaked += 1;
        if (c.changed) f.changed += 1;
    }
};

/// The width of each row's bar, from the top.
fn barWidths(t: *ui.Tester) [3]f32 {
    var out: [3]f32 = @splat(-1);
    var n: usize = 0;
    var track: f32 = 0;
    for (t.ctx.nodes.items[1..]) |node| {
        const r = t.ctx.rects.get(node.id) orelse continue;
        if (node.style.background == null) continue;
        if (node.style.height == .fill) {
            out[n - 1] = r.w / track;
        } else if (r.h <= 6.5) {
            track = r.w;
            n += 1;
            out[n - 1] = 0;
        }
    }
    return out;
}

test "a bar list scales its bars to the largest, and draws none for a bad value" {
    var f: Folders = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&f, Folders.view), .{ .width = 500, .height = 200 });
    defer t.deinit();
    t.settle(1);
    const w = barWidths(&t);
    try std.testing.expectApproxEqAbs(@as(f32, 1), w[0], 0.02);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), w[1], 0.02);
    try std.testing.expectEqual(@as(f32, 0), w[2]);
    try std.testing.expect(t.hasText("Photos") and t.hasText("40 GB"));
}

test "a clickable bar list says which row was clicked, and names each row" {
    var f: Folders = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&f, Folders.view), .{ .width = 500, .height = 200 });
    defer t.deinit();
    t.settle(1);
    try t.clickText("Music");
    try std.testing.expectEqual(@as(?usize, 1), f.clicked);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(@as(usize, 3), list.items.len);
    try std.testing.expectEqual(ui.access.Role.button, list.items[0].role);
    try std.testing.expectEqualStrings("Photos", list.items[0].label);
    try std.testing.expectEqualStrings("40 GB", list.items[0].value);
}

test "a clickable bar list's rows take the keyboard, and Enter clicks one" {
    var f: Folders = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&f, Folders.view), .{ .width = 500, .height = 200 });
    defer t.deinit();
    t.settle(1);
    t.ctx.focusCycle(false);
    t.settle(1);
    t.ctx.focusCycle(false);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, null), f.clicked);
    const changed = f.changed;
    t.key(.enter);
    try std.testing.expectEqual(@as(?usize, 1), f.clicked);
    // Enter is the list's, and a click is a change.
    try std.testing.expectEqual(@as(usize, 0), f.leaked);
    try std.testing.expect(f.changed > changed);
    // Space clicks too.
    f.clicked = null;
    try std.testing.expect(t.shortcut(.{ .key = ' ' }));
    try std.testing.expectEqual(@as(?usize, 1), f.clicked);
}

test {
    _ = @import("bar_list_tests.zig");
}
