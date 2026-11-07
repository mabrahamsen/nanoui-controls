//! A bar list: rows of a label, a bar across and a figure, the bars
//! scaled to the largest. The busiest processes, disk use by folder,
//! visits by page. Rows can be clicked, to open what they stand for.
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
const breakdown_mod = @import("breakdown.zig");

/// One row of the list.
pub const Item = struct {
    label: []const u8,
    /// Its bar's length, on the list's scale: a negative value or one
    /// that is not a number draws none.
    value: f32,
    /// The figure at the end ("41.2 GB"), and what a screen reader says.
    value_text: []const u8 = "",
    /// Its bar's color; null takes the list's.
    color: ?ui.Color = null,
};

pub const Options = struct {
    /// The value of a full bar; null takes the largest item's.
    max: ?f32 = null,
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
            if (in.focused) row = row.border(t.primary.alpha(0.6));
            if (in.clicked or (in.focused and c.input.key == .enter)) clicked = i;
        }
        defer row.end();
        {
            const l = ui.div(c).w(opts.label_width * k);
            defer l.end();
            ui.text(c, it.label, .{ .size = text, .color = t.foreground, .truncate = .ellipsis });
        }
        const share = if (max > 0 and std.math.isFinite(it.value) and it.value > 0) @min(it.value / max, 1) else 0;
        breakdown_mod.breakdown(c, &.{.{ .value = share, .color = it.color orelse opts.color orelse t.primary }}, .{ .height = opts.bar_height, .scale = k });
        {
            const v = ui.div(c).w(opts.value_width * k).row().justifyEnd();
            defer v.end();
            ui.text(c, it.value_text, .{ .size = text - 1, .mono = true, .color = t.muted });
        }
        ui.access.describe(c, row.index, .{ .role = if (opts.clickable) .button else .static_text, .label = it.label, .value = it.value_text });
    }
    return clicked;
}

const Folders = struct {
    clicked: ?usize = null,
    const items = [_]Item{
        .{ .label = "Photos", .value = 40, .value_text = "40 GB" },
        .{ .label = "Music", .value = 10, .value_text = "10 GB" },
        .{ .label = "Broken", .value = std.math.nan(f32), .value_text = "?" },
    };
    fn view(f: *Folders, c: *ui.Context) void {
        const root = ui.div(c).column().w(400);
        defer root.end();
        if (barList(c, &items, .{ .clickable = true })) |i| f.clicked = i;
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
    t.key(.enter);
    try std.testing.expectEqual(@as(?usize, 1), f.clicked);
}
