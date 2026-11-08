//! The line chart's tests: lines broken where there is no reading, areas,
//! the scale, the pointer and the keys, tooltips and screen readers.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const line_mod = @import("line.zig");
const line = line_mod.line;
const Series = line_mod.Series;

/// How many shapes the chart's canvas drew: a line between each two
/// readings in a run, a dot for a reading on its own, and an area's
/// triangles.
fn shapes(series: []const Series, opts: line_mod.Options) !usize {
    const T = struct {
        var ss: []const Series = &.{};
        var o: line_mod.Options = .{ .capacity = 0 };
        fn view(_: *@This(), c: *ui.Context) void {
            var l = line(c, ss, o);
            l.end();
        }
    };
    T.ss = series;
    T.o = opts;
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 100 });
    defer t.deinit();
    t.settle(1);
    var n: usize = 0;
    for (t.ctx.nodes.items) |node| switch (node.content) {
        .canvas => |cv| n += cv.shapes.items.len,
        else => {},
    };
    return n;
}

test "a line joins its readings, and breaks where there is none" {
    try std.testing.expectEqual(@as(usize, 5), try shapes(&.{.{ .values = &.{ 1, 2, 3, 4, 5, 6 } }}, .{ .capacity = 6 }));
    const nan = std.math.nan(f32);
    // Two runs: 1 2, then 3 4 5.
    try std.testing.expectEqual(@as(usize, 3), try shapes(&.{.{ .values = &.{ 1, 2, nan, 3, 4, 5 } }}, .{ .capacity = 6 }));
    // A reading on its own is a dot.
    try std.testing.expectEqual(@as(usize, 1), try shapes(&.{.{ .values = &.{ nan, 2, nan } }}, .{ .capacity = 3 }));
}

test "an area fills under its line" {
    const plain = try shapes(&.{.{ .values = &.{ 1, 2, 3 } }}, .{ .capacity = 3 });
    const filled = try shapes(&.{.{ .values = &.{ 1, 2, 3 }, .area = 0.2 }}, .{ .capacity = 3 });
    try std.testing.expect(filled > plain);
}

test "a line with nothing to show draws nothing, and doesn't fail" {
    try std.testing.expectEqual(@as(usize, 0), try shapes(&.{.{ .values = &.{} }}, .{ .capacity = 10 }));
    try std.testing.expectEqual(@as(usize, 0), try shapes(&.{}, .{ .capacity = 10, .interactive = true }));
    try std.testing.expectEqual(@as(usize, 0), try shapes(&.{.{ .values = &.{ 1, 2 } }}, .{ .capacity = 0 }));
}

const Disk = struct {
    current: ?usize = null,
    focused: bool = false,
    const read = [_]f32{ 1, 4, 2, 8, 5 };
    fn view(d: *Disk, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        var l = line(c, &.{.{ .values = &read }}, .{ .capacity = 5, .height = .{ .px = 60 }, .interactive = true, .label = "Disk", .value_text = "5 MB/s" });
        d.current = l.current;
        d.focused = l.focused;
        if (l.current) |i| l.tooltip(c.print("{d} MB/s", .{read[i]}));
        l.end();
    }
};

test "an interactive line follows the pointer to the nearest reading, and says it" {
    var d: Disk = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&d, Disk.view), .{ .width = 400, .height = 100 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, null), d.current);
    // Five readings 100 points apart: 170 is nearest the third.
    t.moveTo(170, 30);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 2), d.current);
    try std.testing.expect(t.hasText("2 MB/s"));
    t.moveTo(399, 30);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 4), d.current);
    t.moveTo(140, 90);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, null), d.current);
}

test "an interactive line takes the keyboard, and a screen reader hears the current reading" {
    var d: Disk = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&d, Disk.view), .{ .width = 400, .height = 100 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings("Disk", list.items[0].label);
    try std.testing.expectEqualStrings("5 MB/s", list.items[0].value);
    t.key(.tab);
    t.settle(1);
    try std.testing.expect(d.focused);
    try std.testing.expectEqual(@as(?usize, 4), d.current);
    t.key(.home);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 0), d.current);
    list.clearRetainingCapacity();
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqualStrings("1 MB/s", list.items[0].value);
}

test "a line's value lines sit behind its lines" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            var l = line(c, &.{.{ .values = &.{ 1, 2, 3 } }}, .{ .capacity = 3, .max = 4, .value_lines = &.{.{ .value = 2, .label = "2" }} });
            l.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 100 });
    defer t.deinit();
    t.settle(1);
    // Boxes paint in order: the line across comes before the canvas.
    var line_at: ?usize = null;
    var canvas_at: ?usize = null;
    for (t.ctx.nodes.items, 0..) |node, i| switch (node.content) {
        .canvas => canvas_at = i,
        else => if (node.style.background != null and node.style.height == .px and line_at == null) {
            line_at = i;
        },
    };
    try std.testing.expect(line_at.? < canvas_at.?);
}

test "a line without a label is left out of what a screen reader hears, unless it is interactive" {
    const T = struct {
        interactive: bool = false,
        fn view(x: *@This(), c: *ui.Context) void {
            var l = line(c, &.{.{ .values = &.{ 1, 2, 3 } }}, .{ .capacity = 3, .value_lines = &.{.{ .value = 0.5, .label = "half" }}, .interactive = x.interactive });
            l.end();
        }
    };
    for ([_]bool{ false, true }) |interactive| {
        var x: T = .{ .interactive = interactive };
        var t: ui.Tester = undefined;
        try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 100 });
        defer t.deinit();
        t.settle(1);
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        var list: std.ArrayList(ui.access.Element) = .empty;
        try ui.access.tree(&t.ctx, arena.allocator(), &list);
        if (!interactive) {
            try std.testing.expectEqual(@as(usize, 0), list.items.len);
        } else {
            try std.testing.expectEqual(@as(usize, 1), list.items.len);
            try std.testing.expectEqualStrings("Chart", list.items[0].label);
        }
    }
}

/// A line of three readings in eight slots.
const Short = struct {
    current: ?usize = null,
    read: ?f32 = null,

    fn view(x: *Short, c: *ui.Context) void {
        const root = ui.div(c).column().w(200).p(10);
        defer root.end();
        var l = line(c, &.{.{ .values = &.{ 0.2, 0.5, 0.8 } }}, .{ .capacity = 8, .interactive = true });
        x.current = l.current;
        x.read = if (l.current) |i| l.reading(0, i) else null;
        l.end();
    }
};

test "an interactive line with a short history stops only on its readings, and says each" {
    var x: Short = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Short.view), .{ .width = 300, .height = 200 });
    defer t.deinit();
    t.settle(1);
    t.ctx.focusCycle(false);
    t.settle(1);
    t.key(.home);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 5), x.current);
    try std.testing.expectEqual(@as(?f32, 0.2), x.read);
    t.key(.left);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 5), x.current);
    t.key(.end);
    t.settle(1);
    try std.testing.expectEqual(@as(?f32, 0.8), x.read);
}

test "a line without a max scales to its peak, as every chart with a scale does" {
    const T = struct {
        top: ?f32 = null,
        fn view(x: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(200).p(10);
            defer root.end();
            var l = line(c, &.{.{ .values = &.{ 0.1, 0.2 } }}, .{ .capacity = 2, .max = x.top, .height = .{ .px = 100 }, .value_lines = &.{.{ .value = 0.2 }} });
            l.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 200 });
    defer t.deinit();
    t.settle(1);
    // The line at the peak, 0.2, sits at the top.
    var y: ?f32 = null;
    for (t.ctx.nodes.items) |node| if (node.style.height == .px and node.style.height.px == 1 and node.style.background != null) {
        y = t.ctx.rects.get(node.id).?.y;
    };
    try std.testing.expect(y.? < 10 + 3);
    // With max 1, it sits low.
    x.top = 1;
    t.settle(1);
    for (t.ctx.nodes.items) |node| if (node.style.height == .px and node.style.height.px == 1 and node.style.background != null) {
        y = t.ctx.rects.get(node.id).?.y;
    };
    try std.testing.expect(y.? > 10 + 70);
}
