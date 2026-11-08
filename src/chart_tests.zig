//! What the charts' tests share, and the tests of what the charts share:
//! a box's measured size, and a chart with no room asking for no frames.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const chart = @import("chart.zig");

pub const red: ui.Color = .hex(0xef4444);
pub const blue: ui.Color = .hex(0x3b82f6);

/// The heights of the boxes in `color`, in the order drawn.
pub fn heights(t: *ui.Tester, color: ui.Color, out: []f32) []f32 {
    var n: usize = 0;
    for (t.ctx.nodes.items) |node| if (node.style.background) |b| if (std.meta.eql(b, color)) {
        const r = t.ctx.rects.get(node.id) orelse continue;
        if (n < out.len) out[n] = r.h;
        n += 1;
    };
    return out[0..@min(n, out.len)];
}

test "a donut and a gauge with no room don't ask for frame after frame" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(300);
            defer root.end();
            @import("donut.zig").donut(c, &.{.{ .value = 0.5, .color = blue }}, .{ .diameter = 0 });
            @import("gauge.zig").gauge(c, 0.5, .{ .diameter = 0 });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 400, .height = 200 });
    defer t.deinit();
    t.settle(1);
    t.frame();
    try std.testing.expectEqual(@as(?f32, null), t.ctx.frame_in);
}

test "a box's measured size is kept by the box, not by where it is looked up" {
    const T = struct {
        extra: bool = false,
        fn view(x: *@This(), c: *ui.Context) void {
            const box = ui.div(c).column().w(120).h(40);
            defer box.end();
            // A child before the lookup, from some frame on, as a caller's
            // content changes.
            if (x.extra) ui.div(c).h(4).end();
            _ = chart.lastSize(c, box.index);
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 200 });
    defer t.deinit();
    t.settle(1);
    // The box's size hasn't changed: no frame is asked for.
    x.extra = true;
    t.frame();
    try std.testing.expectEqual(@as(?f32, null), t.ctx.frame_in);
}
