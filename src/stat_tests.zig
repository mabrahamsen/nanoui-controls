//! The stat's tests of units, details, loading, a key, and a stat to
//! click.
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

test "a stat's history takes a scale, and its lengths follow scale" {
    const T = struct {
        k: f32 = 1,
        fn view(x: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(240);
            defer root.end();
            stat_mod.stat(c, "Load", "1%", .{ .history = &.{ 0.005, 0.01 }, .history_max = null, .color = blue, .scale = x.k });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // Scaled to its peak: the newest bar is full, the older half.
    // The trend fades its older bars: their color, at any opacity.
    var h: [2]f32 = undefined;
    var n: usize = 0;
    for (t.ctx.nodes.items) |node| if (node.style.background) |bg| if (bg.r == blue.r and bg.g == blue.g and bg.b == blue.b) {
        if (n < 2) h[n] = t.ctx.rects.get(node.id).?.h;
        n += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expect(h[1] > h[0] * 1.8);
    const pad = t.findText("Load").?.y;
    x.k = 2;
    t.settle(1);
    try std.testing.expect(t.findText("Load").?.y > pad + 10);
}

test "a stat's key is a dot before its label, in a card and without one, and silent" {
    const T = struct {
        card: bool = true,
        fn view(x: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(240);
            defer root.end();
            stat_mod.stat(c, "Read", "2.4 MB/s", .{ .key = red, .card = if (x.card) .{} else null });
        }
        fn dot(t: *ui.Tester) ?ui.Rect {
            for (t.ctx.nodes.items) |node| if (node.style.background) |bg| if (std.meta.eql(bg, red)) return t.ctx.rects.get(node.id).?;
            return null;
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 200 });
    defer t.deinit();
    for ([_]bool{ true, false }) |card| {
        x.card = card;
        t.settle(1);
        const d = T.dot(&t).?;
        const label = t.findText("Read").?;
        try std.testing.expect(d.x + d.w <= label.x);
        // Level with the label.
        try std.testing.expectApproxEqAbs(label.y + label.h / 2, d.y + d.h / 2, 1);
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        var list: std.ArrayList(ui.access.Element) = .empty;
        try ui.access.tree(&t.ctx, arena.allocator(), &list);
        try std.testing.expectEqual(@as(usize, 1), list.items.len);
        try std.testing.expectEqualStrings("Read", list.items[0].label);
    }
}
