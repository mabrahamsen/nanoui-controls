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

/// Interactive bars, then a text field, and whether a key reached what
/// comes after the chart.
const Keyed = struct {
    count: usize = 6,
    field: ui.TextBuffer = .{},
    field_focused: bool = false,
    key_left: bool = false,
    current: ?usize = null,

    fn view(x: *Keyed, c: *ui.Context) void {
        const root = ui.div(c).column().w(240).gap(8);
        defer root.end();
        var b = @import("bars.zig").bars(c, .{ .count = x.count, .height = .{ .px = 40 }, .interactive = true, .label = "Traffic" });
        while (b.next()) |slot| slot.bar(&.{.{ .value = 0.5, .color = red }});
        x.current = b.current;
        b.end();
        x.key_left = c.input.key != null;
        x.field_focused = ui.textField(c, &x.field, .{}).focused;
    }
};

test "an interactive chart uses up the keys it moves by, even at an end" {
    var x: Keyed = .{};
    defer x.field.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Keyed.view), .{ .width = 300, .height = 120 });
    defer t.deinit();
    t.settle(1);
    t.key(.tab);
    t.key(.home);
    try std.testing.expectEqual(@as(?usize, 0), x.current);
    try std.testing.expect(!x.key_left);
    t.key(.left);
    try std.testing.expectEqual(@as(?usize, 0), x.current);
    try std.testing.expect(!x.key_left);
    t.key(.right);
    try std.testing.expectEqual(@as(?usize, 1), x.current);
    try std.testing.expect(!x.key_left);
    // A key it doesn't move by is left for what comes after it.
    t.key(.enter);
    try std.testing.expect(x.key_left);
}

test "an interactive chart with nothing to point at doesn't take Tab" {
    var x: Keyed = .{ .count = 0 };
    defer x.field.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Keyed.view), .{ .width = 300, .height = 120 });
    defer t.deinit();
    t.settle(1);
    t.key(.tab);
    t.settle(1);
    try std.testing.expect(x.field_focused);
}
