//! The bars' tests of a scale all below zero, as readings in dBm are:
//! bars hang from its top, measured from there.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const bars = @import("bars.zig").bars;
const red = @import("chart_tests.zig").red;

test "on a scale all below zero, bars hang from its top, as long as their distance from it" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(200);
            defer root.end();
            const values = [_]f32{ -60, -40, -90, -30 };
            var b = bars(c, .{ .count = values.len, .units = true, .min = -90, .max = -30, .fixed_max = true, .height = .{ .px = 120 } });
            while (b.next()) |slot| slot.bar(&.{.{ .value = values[slot.index], .color = red }});
            b.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 200 });
    defer t.deinit();
    t.settle(1);
    var top: ?f32 = null;
    var hs: [4]f32 = undefined;
    var n: usize = 0;
    for (t.ctx.nodes.items) |node| if (node.style.background) |bg| if (std.meta.eql(bg, red)) {
        top = @min(top orelse node.rect.y, node.rect.y);
        hs[n] = node.rect.h;
        n += 1;
    };
    // -30 is the top: no bar. The rest, from -30 down: 30, 10 and 60 of
    // the scale's 60.
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectApproxEqAbs(@as(f32, 60), hs[0], 1);
    try std.testing.expectApproxEqAbs(@as(f32, 20), hs[1], 1);
    try std.testing.expectApproxEqAbs(@as(f32, 120), hs[2], 1);
    // Each hangs from the chart's top.
    for (t.ctx.nodes.items) |node| if (node.style.background) |bg| if (std.meta.eql(bg, red)) {
        try std.testing.expectApproxEqAbs(top.?, node.rect.y, 1);
    };
}
