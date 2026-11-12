//! A stat: a figure to read at a glance, in a tile. Its label, the figure
//! large, how it changed (a kit tag in the color of its status), and a
//! trend of its history under it. A dashboard's row of them says how
//! things stand.
//!
//! The figure can have a unit after it and a line of detail under it, the
//! label a dot in the color of a chart's series it reads, and it shows a
//! spinner while it is loading; `statButton` is a stat that can be
//! clicked, to lead to more.
//!
//!     controls.stat(c, "Requests", "12,480", .{ .change = "+8%", .status = .success, .history = per_minute });
//!     controls.stat(c, "Peak", "87", .{ .unit = "%", .detail = "over the last hour" });
//!     if (controls.statButton(c, "Alerts", "3", .{}).clicked) show(.alerts);
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const focus = @import("focus.zig");
const trend_mod = @import("trend.zig");

pub const Options = struct {
    /// How it changed ("+8%", "−2 since yesterday"), in a tag beside the
    /// figure; empty shows none.
    change: []const u8 = "",
    /// The change's color: success for good news, danger for bad, as the
    /// kit's statuses.
    status: kit.Status = .neutral,
    /// Readings to draw as a trend under the figure, oldest first from
    /// `history_head`; empty draws none.
    history: []const f32 = &.{},
    history_head: usize = 0,
    /// The trend's slots; 0 takes the history's length.
    history_capacity: usize = 0,
    /// The trend's color; null takes the theme's accent.
    color: ?ui.Color = null,
    /// The trend's scale, as a trend takes it: `history_max` rising to the
    /// history's peak unless `history_fixed_max`, null taking the peak.
    history_min: f32 = 0,
    history_max: ?f32 = 1,
    history_fixed_max: bool = false,
    /// The trend's colors by height, as a trend's `ramp`; over `color`.
    history_ramp: []const ui.Color = &.{},
    /// The figure's color, for one that says how something stands
    /// ("Nominal" in the success color); null takes the theme's text.
    value_color: ?ui.Color = null,
    /// The figure's size, as the kit's: `.md` draws it at twice the kit's
    /// text at that size.
    size: kit.Size = .md,
    /// The parent's width by default; in a row, a share of the room the
    /// rest leaves.
    width: ui.Length = .fill,
    /// A tile with a background and a border; without, the stat sits on
    /// what it is drawn on.
    card: bool = true,
    /// After the figure, smaller and muted, on its line: "87" then "%".
    unit: []const u8 = "",
    /// A line of muted text under the figure: "over the last hour".
    detail: []const u8 = "",
    /// A dot before the label in this color, the color of the series the
    /// stat reads in a chart beside it; null draws none.
    key: ?ui.Color = null,
    /// A spinner in place of the figure, which isn't known yet: a figure
    /// still loading never reads as 0.
    loading: bool = false,
    /// What a screen reader says while it is loading.
    loading_text: []const u8 = "loading",
    /// Multiplies its lengths but not its text, as the charts'.
    scale: f32 = 1,
};

/// Draws the stat `label` reading `value`.
pub fn stat(c: *ui.Context, label: []const u8, value: []const u8, opts: Options) void {
    const box = open(c, opts, false);
    defer box.end();
    draw(c, box, label, value, opts, false);
}

/// Draws the stat `label` reading `value` as something to click, which
/// leads to more: the tile lightens under the pointer, shows a pointing
/// hand, and takes the keyboard as a button does (Tab, then Enter or
/// Space). A screen reader hears it as a button.
pub fn statButton(c: *ui.Context, label: []const u8, value: []const u8, opts: Options) ui.Interaction {
    const t = kit.tokens(c);
    var box = open(c, opts, true);
    defer box.end();
    const it = c.interact(box.index, .{ .focusable = true });
    if (it.hovered) {
        c.cursor_hand = true;
        box = box.bg(if (opts.card) t.surface_hover else t.surface_hover.alpha(0.6));
    }
    // Enter or Space clicks it while it has the keyboard, as nanoui
    // clicks any focusable box.
    if (it.focused) box = box.border(focus.ring(c)).borderW(focus.ringWidth(c));
    draw(c, box, label, value, opts, true);
    return it;
}

/// The stat's box: a tile, or padding enough to light up when it can be
/// clicked.
fn open(c: *ui.Context, opts: Options, clickable: bool) ui.Div {
    const t = kit.tokens(c);
    const k = opts.scale;
    var box = ui.div(c).column().gap(4 * k);
    c.node(box.index).style.width = opts.width;
    if (opts.card) {
        box = box.p(12 * k).rounded(t.radius * k).bg(t.surface).border(t.border);
    } else if (clickable) box = box.p(6 * k).rounded(t.radius * k);
    return box;
}

fn draw(c: *ui.Context, box: ui.Div, label: []const u8, value: []const u8, opts: Options, clickable: bool) void {
    const t = kit.tokens(c);
    const figure = if (opts.loading) opts.loading_text else if (opts.unit.len > 0) c.print("{s} {s}", .{ value, opts.unit }) else value;
    ui.access.describe(c, box.index, .{
        .role = if (clickable) .button else .static_text,
        .label = label,
        .value = if (opts.change.len > 0 and !opts.loading) c.print("{s}, {s}", .{ figure, opts.change }) else figure,
    });
    if (opts.key) |color| {
        const head = ui.div(c).row().itemsCenter().gap(6 * opts.scale);
        defer head.end();
        ui.div(c).w(6 * opts.scale).h(6 * opts.scale).roundedFull().bg(color).end();
        ui.text(c, label, .{ .size = opts.size.text() - 1.5, .color = t.muted, .truncate = .ellipsis });
    } else ui.text(c, label, .{ .size = opts.size.text() - 1.5, .color = t.muted, .truncate = .ellipsis });
    {
        const size = opts.size.text() * 2;
        const row = ui.div(c).row().itemsCenter().gap(8 * opts.scale);
        defer row.end();
        if (opts.loading) {
            const slot = ui.div(c).h(@round(size * 1.2)).row().itemsCenter();
            defer slot.end();
            kit.spinner(c, .{ .size = @round(size * 0.7) });
        } else if (opts.unit.len > 0) {
            // The unit on the figure's line, at its foot.
            const fig = ui.div(c).row().itemsEnd().gap(3 * opts.scale);
            defer fig.end();
            ui.text(c, value, .{ .size = size, .weight = .semibold, .color = opts.value_color orelse t.foreground });
            const u = ui.div(c).pb(@round(size * 0.12));
            defer u.end();
            ui.text(c, opts.unit, .{ .size = @round(size * 0.55), .weight = .medium, .color = t.muted });
        } else ui.text(c, value, .{ .size = size, .weight = .semibold, .color = opts.value_color orelse t.foreground });
        if (opts.change.len > 0 and !opts.loading) kit.tag(c, opts.change, .{ .status = opts.status, .size = .xs, .pill = true });
    }
    if (opts.detail.len > 0) ui.text(c, opts.detail, .{ .size = opts.size.text() - 1.5, .color = t.muted, .truncate = .ellipsis });
    if (opts.history.len > 0) {
        ui.div(c).h(2 * opts.scale).end();
        trend_mod.trend(c, opts.history, .{
            .capacity = if (opts.history_capacity > 0) opts.history_capacity else opts.history.len,
            .head = opts.history_head,
            .height = .{ .px = @round(opts.size.height() * 0.85) },
            .color = opts.color,
            .min = opts.history_min,
            .max = opts.history_max,
            .fixed_max = opts.history_fixed_max,
            .ramp = opts.history_ramp,
            .scale = opts.scale,
        });
    }
}

test "a stat says its label, figure and change, and a screen reader hears them as one" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(240);
            defer root.end();
            stat(c, "Requests", "12,480", .{ .change = "+8%", .status = .success, .history = &.{ 1, 3, 2, 5 } });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 200 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(t.hasText("Requests") and t.hasText("12,480") and t.hasText("+8%"));
    // The figure is larger than its label.
    try std.testing.expect(t.findText("12,480").?.h > t.findText("Requests").?.h);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings("Requests", list.items[0].label);
    try std.testing.expectEqualStrings("12,480, +8%", list.items[0].value);
}

test "a stat without a change or a history draws neither" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            stat(c, "Uptime", "14 days", .{ .card = false });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 120 });
    defer t.deinit();
    t.settle(1);
    var backgrounds: usize = 0;
    for (t.ctx.nodes.items[1..]) |node| backgrounds += @intFromBool(node.style.background != null);
    try std.testing.expectEqual(@as(usize, 0), backgrounds);
}

test "a stat's figure takes value_color, and the theme's text without it" {
    const T = struct {
        color: ?ui.Color = null,
        fn view(x: *@This(), c: *ui.Context) void {
            stat(c, "Thermal", "Nominal", .{ .card = false, .value_color = x.color });
        }
        fn figure(t: *ui.Tester) ui.Color {
            for (t.ctx.nodes.items) |node| switch (node.content) {
                .text => |tx| if (std.mem.eql(u8, tx.str, "Nominal")) return tx.style.color.?,
                else => {},
            };
            unreachable;
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 120 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expectEqual(kit.tokens(&t.ctx).foreground, T.figure(&t));
    x.color = kit.tokens(&t.ctx).success;
    t.settle(1);
    try std.testing.expectEqual(kit.tokens(&t.ctx).success, T.figure(&t));
}

test {
    _ = @import("stat_tests.zig");
}
