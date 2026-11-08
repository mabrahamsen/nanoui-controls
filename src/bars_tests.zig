//! The bars' tests: parts up and down, squeezing, slots, the pointer and
//! the keys, tooltips, value lines and screen readers.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const bars_mod = @import("bars.zig");
const bars = bars_mod.bars;
const Part = bars_mod.Part;
const Color = ui.Color;

const kit = nanoui.kit;
const chart = @import("chart.zig");
const line = @import("line.zig").line;
const shared = @import("chart_tests.zig");
const heights = shared.heights;
const red = shared.red;
const blue = shared.blue;

const cyan: Color = .hex(0x22d3ee);
const violet: Color = .hex(0xa78bfa);

/// The colored parts of a bar in a slot 100 points tall, from the top:
/// each one's top and height.
fn drawn(parts: []const Part, below: f32) ![4][2]f32 {
    const T = struct {
        var ps: []const Part = &.{};
        var b: f32 = 0;
        fn view(_: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(40);
            defer root.end();
            var bc = bars(c, .{ .count = 1, .height = .{ .px = 100 }, .below = b });
            while (bc.next()) |slot| slot.bar(ps);
            bc.end();
        }
    };
    T.ps = parts;
    T.b = below;
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 100, .height = 120 });
    defer t.deinit();
    t.settle(1);
    var out: [4][2]f32 = @splat(.{ 0, 0 });
    var n: usize = 0;
    // The first box is the window's.
    for (t.ctx.nodes.items[1..]) |node| {
        if (node.style.background == null) continue;
        const r = t.ctx.rects.get(node.id).?;
        out[n] = .{ @round(r.y * 100) / 100, @round(r.h * 100) / 100 };
        n += 1;
    }
    return out;
}

test "a bar's parts take their share of the slot from the bottom" {
    // Drawn from the top: the last part first.
    const d = try drawn(&.{ .{ .value = 0.5, .color = cyan }, .{ .value = 0.25, .color = violet } }, 0);
    try std.testing.expectEqualSlices([2]f32, &.{ .{ 25, 25 }, .{ 50, 50 }, .{ 0, 0 }, .{ 0, 0 } }, &d);
}

test "a bar counts bad parts as nothing, and squeezes parts over the slot to fit" {
    const nan = std.math.nan(f32);
    const bad = try drawn(&.{ .{ .value = nan, .color = cyan }, .{ .value = 0.4, .color = violet }, .{ .value = -1, .color = cyan }, .{ .value = std.math.inf(f32), .color = cyan } }, 0);
    try std.testing.expectEqualSlices([2]f32, &.{ .{ 60, 40 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } }, &bad);
    const over = try drawn(&.{ .{ .value = 0.9, .color = cyan }, .{ .value = 0.9, .color = violet } }, 0);
    try std.testing.expectEqualSlices([2]f32, &.{ .{ 0, 50 }, .{ 50, 50 }, .{ 0, 0 }, .{ 0, 0 } }, &over);
}

test "with room below zero, negative parts go down from it, squeezed to their room" {
    // Zero is 40 points up: 60 points above it, 40 below.
    const d = try drawn(&.{ .{ .value = 0.3, .color = cyan }, .{ .value = -0.2, .color = violet }, .{ .value = -0.1, .color = cyan } }, 0.4);
    try std.testing.expectEqualSlices([2]f32, &.{ .{ 30, 30 }, .{ 60, 20 }, .{ 80, 10 }, .{ 0, 0 } }, &d);
    const over = try drawn(&.{ .{ .value = -0.8, .color = violet }, .{ .value = 0.9, .color = cyan } }, 0.4);
    try std.testing.expectEqualSlices([2]f32, &.{ .{ 0, 60 }, .{ 60, 40 }, .{ 0, 0 }, .{ 0, 0 } }, &over);
}

const Inspected = struct {
    current: ?usize = null,
    slot_current: ?usize = null,
    focused: bool = false,
    built: usize = 0,
    fn view(h: *Inspected, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        var b = bars(c, .{ .count = 10, .height = .{ .px = 40 }, .gap = 0, .interactive = true, .label = "Traffic", .value_text = "2.4 MB/s" });
        h.current = b.current;
        h.focused = b.focused;
        h.slot_current = null;
        h.built = 0;
        while (b.next()) |slot| {
            h.built += 1;
            if (slot.current) h.slot_current = slot.index;
            slot.bar(&.{.{ .value = 0.5, .color = cyan }});
        }
        if (b.current) |i| b.tooltip(c.print("Slot {d}", .{i + 1}));
        b.end();
    }
};

test "bars build a slot each" {
    var h: Inspected = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&h, Inspected.view), .{ .width = 300, .height = 100 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 10), h.built);
    try std.testing.expectEqual(@as(?usize, null), h.current);
}

test "interactive bars follow the pointer, and say the slot's figures in a tooltip" {
    var h: Inspected = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&h, Inspected.view), .{ .width = 300, .height = 100 });
    defer t.deinit();
    t.settle(1);
    // Ten slots of 30 points: 95 is in the fourth.
    t.moveTo(95, 20);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 3), h.current);
    try std.testing.expectEqual(@as(?usize, 3), h.slot_current);
    try std.testing.expect(t.ctx.wants_moves and !t.ctx.cursor_hand);
    try std.testing.expect(t.hasText("Slot 4"));
    t.moveTo(299, 20);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 9), h.current);
    // Below the bars: none, and no tooltip.
    t.moveTo(95, 80);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, null), h.current);
    try std.testing.expectEqual(@as(?usize, null), h.slot_current);
    try std.testing.expect(!t.hasText("Slot 10"));
}

test "interactive bars take the keyboard, and the keys move from slot to slot" {
    var h: Inspected = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&h, Inspected.view), .{ .width = 300, .height = 100 });
    defer t.deinit();
    t.settle(1);
    // Without the keyboard, the keys are someone else's.
    try std.testing.expect(!t.shortcut(.{ .key = ui.Shortcut.left }));
    t.key(.tab);
    t.settle(1);
    try std.testing.expect(h.focused);
    // It starts at the newest slot.
    try std.testing.expectEqual(@as(?usize, 9), h.current);
    try std.testing.expect(t.shortcut(.{ .key = ui.Shortcut.left }));
    try std.testing.expectEqual(@as(?usize, 8), h.current);
    t.key(.home);
    try std.testing.expectEqual(@as(?usize, 0), h.current);
    t.key(.left);
    try std.testing.expectEqual(@as(?usize, 0), h.current);
    t.key(.end);
    try std.testing.expectEqual(@as(?usize, 9), h.current);
    t.key(.right);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 9), h.current);
    try std.testing.expect(t.hasText("Slot 10"));
}

test "after a click on interactive bars, the keys move on from the slot clicked" {
    var h: Inspected = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&h, Inspected.view), .{ .width = 300, .height = 100 });
    defer t.deinit();
    t.settle(1);
    // Ten slots of 30 points: 50 is in the second.
    t.click(50, 20);
    t.settle(1);
    try std.testing.expect(h.focused);
    try std.testing.expectEqual(@as(?usize, 1), h.current);
    // The pointer stays where it was, over the chart.
    t.key(.right);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 2), h.current);
    t.key(.right);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 3), h.current);
    try std.testing.expect(t.hasText("Slot 4"));
    // Moving the pointer takes the slot under it again.
    t.moveTo(275, 20);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 9), h.current);
}

/// The chart's element for a screen reader, the only one.
fn element(t: *ui.Tester, arena: std.mem.Allocator) !ui.access.Element {
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena, &list);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    return list.items[0];
}

test "a screen reader hears the chart's value, or the current slot's tooltip" {
    var h: Inspected = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&h, Inspected.view), .{ .width = 300, .height = 100 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var e = try element(&t, arena.allocator());
    try std.testing.expectEqual(ui.access.Role.image, e.role);
    try std.testing.expectEqualStrings("Traffic", e.label);
    try std.testing.expectEqualStrings("2.4 MB/s", e.value);
    t.key(.tab);
    t.settle(1);
    t.key(.home);
    t.settle(1);
    e = try element(&t, arena.allocator());
    try std.testing.expectEqualStrings("Slot 1", e.value);
}

test "bars without a label are left out of what a screen reader hears" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            var b = bars(c, .{ .count = 3, .label = "Traffic" });
            while (b.next()) |slot| slot.bar(&.{.{ .value = 0.5, .color = cyan }});
            b.end();
            var d = bars(c, .{ .count = 3 });
            while (d.next()) |slot| slot.bar(&.{.{ .value = 0.5, .color = cyan }});
            d.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 100 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    _ = try element(&t, arena.allocator());
}

test "bars with nothing to show draw nothing, and don't fail" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            var b = bars(c, .{ .count = 0, .interactive = true });
            while (b.next()) |_| unreachable;
            if (b.current != null) unreachable;
            b.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 200, .height = 60 });
    defer t.deinit();
    t.settle(1);
    t.moveTo(10, 10);
    t.key(.tab);
    t.key(.left);
    t.settle(1);
}

test "value lines sit at their share of the height above zero, with their labels" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            var b = bars(c, .{ .count = 2, .height = .{ .px = 100 }, .below = 0.2, .value_lines = &.{ .{ .value = 0.4, .label = "40%" }, .{ .value = 0 }, .{ .value = 2 } } });
            while (b.next()) |_| {}
            b.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 200, .height = 120 });
    defer t.deinit();
    t.settle(1);
    var ys: [4]f32 = undefined;
    var n: usize = 0;
    for (t.ctx.nodes.items[1..]) |node| {
        if (node.style.background == null) continue;
        ys[n] = t.ctx.rects.get(node.id).?.y;
        n += 1;
    }
    // Zero is 20 points up, 0.4 is 40 above it; 2 is off the scale.
    try std.testing.expectEqualSlices(f32, &.{ 40, 80 }, ys[0..n]);
    try std.testing.expect(t.findText("40%").?.y < 40);
}

/// Bars of `values` in units, 100 points tall.
const Units = struct {
    values: []const f32 = &.{ 40, 20 },
    min: f32 = 0,
    max: f32 = 100,
    fixed: bool = true,
    readings: ?usize = null,
    count: usize = 2,
    interactive: bool = false,
    slots: [16]?usize = @splat(null),
    built: usize = 0,
    current: ?usize = null,

    fn view(x: *Units, c: *ui.Context) void {
        const root = ui.div(c).column().w(200).p(10);
        defer root.end();
        var b = bars(c, .{ .count = x.count, .height = .{ .px = 100 }, .units = true, .min = x.min, .max = x.max, .fixed_max = x.fixed, .readings = x.readings, .interactive = x.interactive });
        x.current = b.current;
        x.built = 0;
        while (b.next()) |slot| {
            x.slots[x.built] = slot.reading;
            x.built += 1;
            const v = x.values[slot.reading orelse slot.index];
            slot.bar(&.{.{ .value = v, .color = if (v < 0) red else blue }});
        }
        b.end();
    }
};

fn startUnits(x: *Units, t: *ui.Tester) !void {
    try t.init(std.testing.allocator, .init(x, Units.view), .{ .width = 300, .height = 200 });
    t.settle(1);
}

test "bars in units take their share of the scale" {
    var x: Units = .{};
    var t: ui.Tester = undefined;
    try startUnits(&x, &t);
    defer t.deinit();
    var buf: [4]f32 = undefined;
    const h = heights(&t, blue, &buf);
    try std.testing.expectApproxEqAbs(@as(f32, 40), h[0], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 20), h[1], 0.5);
}

test "a scale that isn't fixed rises to the tallest bar, and a fixed one squeezes it" {
    var x: Units = .{ .values = &.{ 200, 50 }, .fixed = false };
    var t: ui.Tester = undefined;
    try startUnits(&x, &t);
    defer t.deinit();
    var buf: [4]f32 = undefined;
    var h = heights(&t, blue, &buf);
    try std.testing.expectApproxEqAbs(@as(f32, 100), h[0], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 25), h[1], 0.5);
    x.fixed = true;
    t.settle(1);
    h = heights(&t, blue, &buf);
    try std.testing.expectApproxEqAbs(@as(f32, 100), h[0], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 50), h[1], 0.5);
}

test "a scale from below zero has room for negative bars, and one from above zero starts the bars there" {
    var x: Units = .{ .values = &.{ 25, -25 }, .min = -50, .max = 50 };
    var t: ui.Tester = undefined;
    try startUnits(&x, &t);
    defer t.deinit();
    var buf: [4]f32 = undefined;
    try std.testing.expectApproxEqAbs(@as(f32, 25), heights(&t, blue, &buf)[0], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 25), heights(&t, red, &buf)[0], 0.5);
    // Zero is halfway: the negative bar starts where the positive ends.
    var top_red: f32 = 0;
    var bottom_blue: f32 = 0;
    for (t.ctx.nodes.items) |node| if (node.style.background) |b| {
        const r = t.ctx.rects.get(node.id) orelse continue;
        if (std.meta.eql(b, red)) top_red = r.y;
        if (std.meta.eql(b, blue)) bottom_blue = r.y + r.h;
    };
    try std.testing.expectApproxEqAbs(bottom_blue, top_red, 0.5);
    x.values = &.{ 70, 20 };
    x.min = 20;
    x.max = 120;
    t.settle(1);
    const h = heights(&t, blue, &buf);
    try std.testing.expectApproxEqAbs(@as(f32, 50), h[0], 0.5);
    try std.testing.expectEqual(@as(usize, 1), h.len);
}

test "a history shorter than the slots sits at the right, and only its slots can be pointed at" {
    var x: Units = .{ .values = &.{ 10, 20, 30 }, .count = 8, .readings = 3, .interactive = true };
    var t: ui.Tester = undefined;
    try startUnits(&x, &t);
    defer t.deinit();
    try std.testing.expectEqual(@as(usize, 3), x.built);
    try std.testing.expectEqual(@as(?usize, 0), x.slots[0]);
    try std.testing.expectEqual(@as(?usize, 2), x.slots[2]);
    // The bars sit in the last three of eight slots, 180 points wide.
    var first_x: f32 = 1000;
    for (t.ctx.nodes.items) |node| if (node.style.background) |b| if (std.meta.eql(b, blue)) {
        first_x = @min(first_x, t.ctx.rects.get(node.id).?.x);
    };
    try std.testing.expect(first_x > 10 + 180 * 5 / 8 - 2);
    // On the empty slots, nothing is current; on the last, its reading.
    t.moveTo(30, 60);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, null), x.current);
    t.moveTo(185, 60);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 2), x.current);
    // The keys stop at the first reading.
    t.moveTo(500, 500);
    t.ctx.focusCycle(false);
    t.settle(1);
    t.key(.home);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 0), x.current);
    t.key(.left);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 0), x.current);
}

test "bars on a fixed scale don't ask for a frame when their tallest bar changes" {
    var x: Units = .{};
    var t: ui.Tester = undefined;
    try startUnits(&x, &t);
    defer t.deinit();
    x.values = &.{ 90, 10 };
    t.frame();
    try std.testing.expectEqual(@as(?f32, null), t.ctx.frame_in);
}

/// A chart with an axis and texts under it: bars or a line.
const Framed = struct {
    axis: chart.Axis = .start,
    use_line: bool = false,
    close: bool = false,
    box: u32 = 0,

    fn view(x: *Framed, c: *ui.Context) void {
        const root = ui.div(c).column().w(300).p(10);
        defer root.end();
        const lines = [_]chart.ValueLine{ .{ .value = 100, .label = "100" }, .{ .value = 50, .label = "50" }, .{ .value = if (x.close) 52 else 0, .label = "near" } };
        if (x.use_line) {
            var l = line(c, &.{.{ .values = &.{ 20, 60, 80 } }}, .{ .capacity = 3, .max = 100, .fixed_max = true, .height = .{ .px = 100 }, .value_lines = &lines, .axis = x.axis, .start_text = "-60 s", .end_text = "now" });
            x.box = l.box.index;
            l.end();
            return;
        }
        var b = bars(c, .{ .count = 3, .units = true, .max = 100, .fixed_max = true, .height = .{ .px = 100 }, .value_lines = &lines, .axis = x.axis, .start_text = "-60 s", .end_text = "now" });
        x.box = b.row.index;
        while (b.next()) |slot| slot.bar(&.{.{ .value = 40, .color = blue }});
        b.end();
    }
};

fn chartRect(t: *ui.Tester, x: *const Framed) ui.Rect {
    return t.ctx.rects.get(t.ctx.node(x.box).id).?;
}

test "an axis puts the value lines' labels beside the chart, level with them, and texts go under it" {
    var x: Framed = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Framed.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const r = chartRect(&t, &x);
    const fifty = t.findText("50").?;
    try std.testing.expect(fifty.x + fifty.w <= r.x + 0.5);
    try std.testing.expectApproxEqAbs(r.y + 50, fifty.y + fifty.h / 2, 2);
    try std.testing.expect(t.findText("-60 s").?.y >= r.y + r.h);
    try std.testing.expectApproxEqAbs(r.x, t.findText("-60 s").?.x, 0.5);
    try std.testing.expectApproxEqAbs(r.x + r.w, t.findText("now").?.x + t.findText("now").?.w, 1);
    // At the end, past the chart.
    x.axis = .end;
    t.settle(1);
    try std.testing.expect(t.findText("50").?.x >= chartRect(&t, &x).x + chartRect(&t, &x).w - 0.5);
}

test "an axis leaves out a label that would overlap the one above it" {
    var x: Framed = .{ .close = true };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Framed.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // The higher of the two keeps its label.
    try std.testing.expect(t.hasText("near"));
    try std.testing.expect(!t.hasText("50"));
    try std.testing.expect(t.hasText("100"));
}

test "a line chart takes an axis and texts under it, as bars do" {
    var x: Framed = .{ .use_line = true, .axis = .end };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Framed.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const r = chartRect(&t, &x);
    try std.testing.expect(t.findText("100").?.x >= r.x + r.w - 0.5);
    try std.testing.expect(t.findText("now").?.y >= r.y + r.h);
}
