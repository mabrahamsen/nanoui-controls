//! The stat's tests of units, details, loading, and a stat to click.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const chart = @import("chart.zig");
const shared = @import("chart_tests.zig");
const heights = shared.heights;
const red = shared.red;
const blue = shared.blue;
const stat_mod = @import("stat.zig");

/// Stats: with a unit and a detail, loading, and one to click.
const Stats = struct {
    loading: bool = false,
    clicks: usize = 0,

    fn view(x: *Stats, c: *ui.Context) void {
        const root = ui.div(c).column().w(240).gap(8);
        defer root.end();
        stat_mod.stat(c, "Peak", "87", .{ .unit = "%", .detail = "over the last hour", .loading = x.loading });
        if (stat_mod.statButton(c, "Alerts", "3", .{}).clicked) x.clicks += 1;
    }
};

test "a stat shows its unit after its figure, a detail under it, and a spinner while loading" {
    var x: Stats = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Stats.view), .{ .width = 300, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const fig = t.findText("87").?;
    const unit = t.findText("%").?;
    try std.testing.expect(unit.x > fig.x + fig.w - 0.5 and unit.h < fig.h);
    try std.testing.expect(t.findText("over the last hour").?.y > fig.y);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqualStrings("87 %", list.items[0].value);
    x.loading = true;
    t.settle(1);
    try std.testing.expect(!t.hasText("87"));
    try std.testing.expect(t.hasText("Peak"));
    list = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqualStrings("loading", list.items[0].value);
}

test "a stat button is clicked by the pointer and the keys, and is a button to a screen reader" {
    var x: Stats = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Stats.view), .{ .width = 300, .height = 300 });
    defer t.deinit();
    t.settle(1);
    try t.clickText("Alerts");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.clicks);
    t.key(.enter);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 2), x.clicks);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(ui.access.Role.button, list.items[1].role);
}
