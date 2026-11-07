//! The trend's tests: where a reading falls on the scale, which slots it
//! fills, fading, and a sweep and a fuzz test over awkward floats.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const trend_mod = @import("trend.zig");
const trend = trend_mod.trend;
const level = trend_mod.level;
const opacity = trend_mod.opacity;
const Color = ui.Color;

test "level: where a reading falls on the scale" {
    try std.testing.expectEqual(@as(?f32, 0.5), level(5, 0, 10));
    try std.testing.expectEqual(@as(?f32, 0.25), level(-50, -90, 70));
    // Out of range reads as the nearest end.
    try std.testing.expectEqual(@as(?f32, 0), level(-1, 0, 10));
    try std.testing.expectEqual(@as(?f32, 1), level(11, 0, 10));
    // No reading: not a number, or infinite.
    try std.testing.expectEqual(@as(?f32, null), level(std.math.nan(f32), 0, 10));
    try std.testing.expectEqual(@as(?f32, null), level(std.math.inf(f32), 0, 10));
    try std.testing.expectEqual(@as(?f32, null), level(-std.math.inf(f32), 0, 10));
    // A scale with no room puts every reading at the bottom: zeros on a
    // scale of 0 to 0 don't fill the chart.
    try std.testing.expectEqual(@as(?f32, 0), level(0, 0, 0));
    try std.testing.expectEqual(@as(?f32, 0), level(5, 10, 3));
    try std.testing.expectEqual(@as(?f32, 0), level(5, 0, std.math.nan(f32)));
    try std.testing.expectEqual(@as(?f32, 0), level(5, -std.math.inf(f32), 10));
}

test "opacity: faint at the oldest, opaque at the newest" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.35), opacity(0, 30, 0.35), 1e-6);
    try std.testing.expectEqual(@as(f32, 1), opacity(29, 30, 0.35));
    try std.testing.expect(opacity(10, 30, 0.35) < opacity(11, 30, 0.35));
    // One slot is the newest; no fade keeps everything opaque.
    try std.testing.expectEqual(@as(f32, 1), opacity(0, 1, 0.35));
    try std.testing.expectEqual(@as(f32, 1), opacity(0, 30, null));
    // A fade out of range is held to 0 to 1, and a slot past the end is
    // the newest.
    try std.testing.expectEqual(@as(f32, 1), opacity(0, 30, 2));
    try std.testing.expectEqual(@as(f32, 0), opacity(0, 30, -1));
    try std.testing.expectEqual(@as(f32, 1), opacity(99, 30, 0.35));
}

/// Floats that break naive arithmetic.
const awkward = [_]f32{
    0,                       -0.0,              1,                  -1,
    0.5,                     1e-45,             -1e-45,             std.math.floatMax(f32),
    -std.math.floatMax(f32), std.math.inf(f32), -std.math.inf(f32), std.math.nan(f32),
    110,                     -90,
};

/// No reading for a value that isn't one; otherwise 0 to 1, and 0 on a
/// scale with no room.
fn checkLevel(x: f32, min: f32, peak: f32) !void {
    const v = level(x, min, peak);
    if (!std.math.isFinite(x)) return std.testing.expectEqual(@as(?f32, null), v);
    const got = v orelse return error.TestUnexpectedNull;
    try std.testing.expect(!std.math.isNan(got) and got >= 0 and got <= 1);
    const range = peak - min;
    if (!std.math.isFinite(range) or !(range > 0)) try std.testing.expectEqual(@as(f32, 0), got);
}

fn checkOpacity(i: usize, n: usize, fade: f32) !void {
    const a = opacity(i, n, fade);
    try std.testing.expect(!std.math.isNan(a) and a >= 0 and a <= 1);
}

test "level and opacity stay in range, whatever the floats" {
    for (awkward) |x| for (awkward) |min| for (awkward) |peak| try checkLevel(x, min, peak);
    for (awkward) |f| for ([_]usize{ 0, 1, 2, 30 }) |n| for ([_]usize{ 0, 1, 29, 99 }) |i| try checkOpacity(i, n, f);
}

fn fuzzLevel(_: void, smith: *std.testing.Smith) anyerror!void {
    try checkLevel(@bitCast(smith.value(u32)), @bitCast(smith.value(u32)), @bitCast(smith.value(u32)));
    try checkOpacity(smith.value(u16), smith.value(u16), @bitCast(smith.value(u32)));
}

test "fuzz: level and opacity stay in range" {
    try std.testing.fuzz({}, fuzzLevel, .{});
}

/// The levels a trend's bars were drawn at, oldest first.
var drawn_levels: [64]f32 = undefined;

/// Draws `values` as a trend of `capacity` slots, as `opts` says, 100
/// points tall, and returns the levels its bars were drawn at, oldest
/// first: their heights, as the baseline is 0.
fn levelsWith(values: []const f32, capacity: usize, opts: trend_mod.Options) ![]const f32 {
    const T = struct {
        var vs: []const f32 = &.{};
        var o: trend_mod.Options = .{ .capacity = 0 };
        fn view(_: *@This(), c: *ui.Context) void {
            trend(c, vs, o);
        }
    };
    T.vs = values;
    T.o = opts;
    T.o.capacity = capacity;
    T.o.height = .{ .px = 100 };
    T.o.baseline = 0;
    T.o.fade = null;
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 120 });
    defer t.deinit();
    t.settle(1);
    var n: usize = 0;
    // The first box is the window's.
    for (t.ctx.nodes.items[1..]) |node| {
        if (node.style.background == null) continue;
        drawn_levels[n] = t.ctx.rects.get(node.id).?.h / 100;
        n += 1;
    }
    return drawn_levels[0..n];
}

fn levels(values: []const f32, capacity: usize, max: f32) ![]const f32 {
    return levelsWith(values, capacity, .{ .capacity = capacity, .max = max });
}

test "a trend scales to its max, or to its peak above it" {
    try std.testing.expectEqualSlices(f32, &.{ 0.25, 0.5 }, try levels(&.{ 1, 2 }, 10, 4));
    try std.testing.expectEqualSlices(f32, &.{ 0.5, 1 }, try levels(&.{ 4, 8 }, 10, 4));
}

test "a trend leaves a slot empty for no reading, which doesn't count toward the peak" {
    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    // Without the infinity in the peak, 4 is the top: 2 is half.
    try std.testing.expectEqualSlices(f32, &.{ 0.5, 1 }, try levels(&.{ nan, 2, inf, 4, -inf }, 10, 1));
}

test "a trend of zeros on a scale with no room draws no bar above its baseline" {
    try std.testing.expectEqualSlices(f32, &.{}, try levels(&.{ 0, 0, 0 }, 10, 0));
}

test "a trend with a fixed max cuts readings above it off at the top" {
    try std.testing.expectEqualSlices(f32, &.{ 0.5, 1 }, try levelsWith(&.{ 2, 8 }, 10, .{ .capacity = 10, .max = 4, .fixed_max = true }));
}

test "a trend reads a ring from its head, oldest first" {
    // The ring holds 4, 1, 2, 3 with the oldest at 1: 1 2 3 4.
    try std.testing.expectEqualSlices(f32, &.{ 0.25, 0.5, 0.75, 1 }, try levelsWith(&.{ 4, 1, 2, 3 }, 10, .{ .capacity = 10, .max = 4, .head = 1 }));
    // With fewer slots, the newest of the ring: 3 4.
    try std.testing.expectEqualSlices(f32, &.{ 0.75, 1 }, try levelsWith(&.{ 4, 1, 2, 3 }, 2, .{ .capacity = 2, .max = 4, .head = 1 }));
}

test "a trend's ramp colors each bar by its height" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            trend(c, &.{ 0, 1 }, .{ .capacity = 2, .fade = null, .ramp = &.{ .hex(0x000000), .hex(0xffffff) } });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 100, .height = 40 });
    defer t.deinit();
    t.settle(1);
    var colors: [2]Color = undefined;
    var n: usize = 0;
    for (t.ctx.nodes.items[1..]) |node| {
        const bg = node.style.background orelse continue;
        colors[n] = bg;
        n += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqual(Color.hex(0x000000), colors[0]);
    try std.testing.expectEqual(Color.hex(0xffffff), colors[1]);
}

test "a trend with more values than slots shows the newest, scaled to them" {
    // 100 is no longer shown, so it doesn't set the peak.
    try std.testing.expectEqualSlices(f32, &.{ 0.5, 1 }, try levels(&.{ 100, 1, 2 }, 2, 0));
}

test "a trend with nothing to show draws nothing, and doesn't fail" {
    try std.testing.expectEqual(@as(usize, 0), (try levels(&.{}, 10, 1)).len);
    try std.testing.expectEqual(@as(usize, 0), (try levels(&.{ 1, 2 }, 0, 1)).len);
}

/// The bars of a trend 10 slots wide and 100 points tall, from the
/// oldest slot: each one's height and opacity, or null where it is empty.
fn drawn(values: []const f32, opts: trend_mod.Options) ![10]?struct { f32, f32 } {
    const T = struct {
        var vs: []const f32 = &.{};
        var o: trend_mod.Options = .{ .capacity = 10 };
        fn view(_: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(100);
            defer root.end();
            trend(c, vs, o);
        }
    };
    T.vs = values;
    T.o = opts;
    T.o.capacity = 10;
    T.o.height = .{ .px = 100 };
    T.o.gap = 0;
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 200, .height = 120 });
    defer t.deinit();
    t.settle(1);
    var out: [10]?struct { f32, f32 } = @splat(null);
    // The first box is the window's.
    for (t.ctx.nodes.items[1..]) |node| {
        const bg = node.style.background orelse continue;
        const r = t.ctx.rects.get(node.id).?;
        out[@intFromFloat(@floor(r.x / 10))] = .{ r.h, bg.a };
    }
    return out;
}

test "a trend's bars sit on the right, the oldest faintest" {
    const bars = try drawn(&.{ 0.5, 1 }, .{ .capacity = 10 });
    for (bars[0..8]) |b| try std.testing.expect(b == null);
    try std.testing.expectEqual(@as(f32, 50), bars[8].?[0]);
    try std.testing.expectEqual(@as(f32, 100), bars[9].?[0]);
    try std.testing.expect(bars[8].?[1] < bars[9].?[1]);
    try std.testing.expectEqual(@as(f32, 1), bars[9].?[1]);
}

test "a trend's baseline shows a reading at its min, and no fade keeps bars opaque" {
    const bars = try drawn(&.{ 0, 1 }, .{ .capacity = 10, .baseline = 0.05, .fade = null });
    try std.testing.expectEqual(@as(f32, 5), bars[8].?[0]);
    try std.testing.expectEqual(@as(f32, 1), bars[8].?[1]);
}

test "a trend with a label is one image to a screen reader, with its value" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            trend(c, &.{ 1, 2, 3 }, .{ .capacity = 10, .label = "Temperature", .value_text = "62 °C, peak 81 °C" });
            trend(c, &.{ 1, 2, 3 }, .{ .capacity = 10 });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 100 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings("Temperature", list.items[0].label);
    try std.testing.expectEqualStrings("62 °C, peak 81 °C", list.items[0].value);
}
