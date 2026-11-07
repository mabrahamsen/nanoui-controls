//! The bars' tests: parts up and down, squeezing, slots, the pointer and
//! the keys, tooltips, value lines and screen readers.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const bars_mod = @import("bars.zig");
const bars = bars_mod.bars;
const Part = bars_mod.Part;
const Color = ui.Color;

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
            var chart = bars(c, .{ .count = 1, .height = .{ .px = 100 }, .below = b });
            while (chart.next()) |slot| slot.bar(ps);
            chart.end();
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
