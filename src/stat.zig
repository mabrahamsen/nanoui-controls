//! A stat: a figure to read at a glance, in a tile. Its label, the figure
//! large, how it changed (a kit tag in the color of its status), and a
//! trend of its history under it. A dashboard's row of them says how
//! things stand.
//!
//!     controls.stat(c, "Requests", "12,480", .{ .change = "+8%", .status = .success, .history = per_minute });
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
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
    /// The figure's size, as the kit's: `.md` draws it at twice the kit's
    /// text at that size.
    size: kit.Size = .md,
    /// The parent's width by default; in a row, a share of the room the
    /// rest leaves.
    width: ui.Length = .fill,
    /// A tile with a background and a border; without, the stat sits on
    /// what it is drawn on.
    card: bool = true,
};

/// Draws the stat `label` reading `value`.
pub fn stat(c: *ui.Context, label: []const u8, value: []const u8, opts: Options) void {
    const t = kit.tokens(c);
    var box = ui.div(c).column().gap(4);
    c.node(box.index).style.width = opts.width;
    if (opts.card) box = box.p(12).rounded(t.radius).bg(t.surface).border(t.border);
    defer box.end();
    ui.access.describe(c, box.index, .{
        .role = .static_text,
        .label = label,
        .value = if (opts.change.len > 0) c.print("{s}, {s}", .{ value, opts.change }) else value,
    });
    ui.text(c, label, .{ .size = opts.size.text() - 1.5, .color = t.muted, .truncate = .ellipsis });
    {
        const row = ui.div(c).row().itemsCenter().gap(8);
        defer row.end();
        ui.text(c, value, .{ .size = opts.size.text() * 2, .weight = .semibold, .color = t.foreground });
        if (opts.change.len > 0) kit.tag(c, opts.change, .{ .status = opts.status, .size = .xs, .pill = true });
    }
    if (opts.history.len > 0) {
        ui.div(c).h(2).end();
        trend_mod.trend(c, opts.history, .{
            .capacity = if (opts.history_capacity > 0) opts.history_capacity else opts.history.len,
            .head = opts.history_head,
            .height = .{ .px = @round(opts.size.height() * 0.85) },
            .color = opts.color,
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
