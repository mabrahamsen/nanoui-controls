//! The meter's tests of a strip rounded at its ends, zones, and a value
//! that is not a number.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const chart = @import("chart.zig");
const shared = @import("chart_tests.zig");
const heights = shared.heights;
const red = shared.red;
const blue = shared.blue;
const meter = @import("meter.zig").meter;

test "a meter without gaps rounds only its ends, and zones label runs of its segments" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(300).gap(10);
            defer root.end();
            meter(c, 1, .{ .gap = 0, .radius = 4, .segments = 6, .color = blue });
            meter(c, 0.5, .{ .segments = 10, .zones = &.{ "<20", "<40", "<60", "<80", "80+" }, .color = red });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 400, .height = 200 });
    defer t.deinit();
    t.settle(1);
    var rounded_rows: usize = 0;
    for (t.ctx.nodes.items) |node| {
        if (node.style.background) |b| if (std.meta.eql(b, blue)) try std.testing.expectEqual(@as(f32, 0), node.style.radius);
        if (node.style.clip and node.style.radius == 4) rounded_rows += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), rounded_rows);
    try std.testing.expect(t.hasText("<20") and t.hasText("80+"));
    // Each label sits under its run: "<20" left of "<40", centered on a
    // fifth of the width.
    try std.testing.expectApproxEqAbs(@as(f32, 30), t.findText("<20").?.x + t.findText("<20").?.w / 2, 3);
}

test "a meter's zones keep its segments one width when they don't divide evenly, and no value says nothing" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(300);
            defer root.end();
            meter(c, 1, .{ .segments = 7, .gap = 2, .zone_gap = 2, .zones = &.{ "a", "b", "c" }, .color = blue });
            meter(c, std.math.nan(f32), .{ .label = "Load" });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 400, .height = 200 });
    defer t.deinit();
    t.settle(1);
    var lo: f32 = 1000;
    var hi: f32 = 0;
    for (t.ctx.nodes.items) |node| if (node.style.background) |b| if (std.meta.eql(b, blue)) {
        const w = t.ctx.rects.get(node.id).?.w;
        lo = @min(lo, w);
        hi = @max(hi, w);
    };
    try std.testing.expect(hi - lo < 1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    for (list.items) |e| if (std.mem.eql(u8, e.label, "Load")) try std.testing.expectEqualStrings("", e.value);
}

test "a meter and a gauge take their own min and max" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(200);
            defer root.end();
            meter(c, 65, .{ .min = 20, .max = 110, .segments = 10, .color = blue, .label = "Heat" });
            @import("gauge.zig").gauge(c, 65, .{ .min = 20, .max = 110, .label = "Gauge" });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // Halfway: five of ten lit.
    var lit: usize = 0;
    for (t.ctx.nodes.items) |node| if (node.style.background) |b| if (std.meta.eql(b, blue)) {
        lit += 1;
    };
    try std.testing.expectEqual(@as(usize, 5), lit);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    for (list.items) |e| try std.testing.expectEqualStrings("50%", e.value);
}
