//! A breakdown: a bar across, broken down into colored parts from the
//! left. A total by kind, as memory in use, with what is left empty; a
//! whole by source, as traffic by app (`whole`); or one part as a level
//! against a maximum, as a fan's speed. The parts ease to new values, as
//! the kit's progress bar does.
//!
//!     controls.breakdown(c, &.{ .{ .value = app, .color = cyan }, .{ .value = wired, .color = violet } }, .{ .label = "Memory", .value_text = "15 of 24 GB" });
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const chart = @import("chart.zig");

pub const Options = struct {
    /// The parent's width by default; in a row, the room the rest leaves.
    width: ui.Length = .fill,
    height: f32 = 6,
    /// The bar's corner radius; null rounds its ends.
    radius: ?f32 = null,
    /// Between the parts; null keeps a hairline of one point at any scale,
    /// and 0 none.
    gap: ?f32 = null,
    /// Where no part is; null takes the track of the kit's progress bar.
    track: ?ui.Color = null,
    /// The parts are the whole: each takes its share of their sum, and
    /// none of the bar is left. Otherwise each is `value` of the bar (0 to
    /// 1), and what they leave stays empty.
    whole: bool = false,
    /// Each part's corner radius, for a level's rounded end.
    part_radius: f32 = 0,
    /// The opacity of a glow around each part, in its color; 0 draws none.
    /// A glowing bar doesn't clip its parts, so the glow shows around it:
    /// give the parts a `part_radius` to keep their ends round.
    glow: f32 = 0,
    /// What a screen reader calls the bar ("Memory") and says it shows
    /// ("15 of 24 GB"); without a label, it is left out, as a decoration.
    label: []const u8 = "",
    value_text: []const u8 = "",
    /// Multiplies the bar's lengths, as `bars`.
    scale: f32 = 1,
};

/// Draws the bar of `parts`. A part that is negative or not a number
/// counts as 0; parts that add up to more than the bar are squeezed to
/// fit, each keeping its share.
pub fn breakdown(c: *ui.Context, parts: []const chart.Part, opts: Options) void {
    const k = opts.scale;
    const h = opts.height * k;
    var r = ui.div(c).row().h(h).rounded(if (opts.radius) |rad| rad * k else h / 2).bg(opts.track orelse chart.track(c));
    c.node(r.index).style.width = chart.scaled(opts.width, k);
    if (opts.glow == 0) r = r.clip();
    // Without gaps, the parts overlap by a point, as a meter's segments.
    r = r.gap(if (opts.gap) |g| (if (g > 0) g * k else -1) else 1);
    chart.describe(c, r.index, opts.label, opts.value_text, false);
    defer r.end();
    // Every part eases first, while the keys they ease under are the same
    // each frame: the boxes after skip parts that are nothing.
    var eased: [max_eased]f32 = undefined;
    var used: f32 = 0;
    for (parts, 0..) |p, i| {
        const v = chart.partShare(p.value);
        const e = if (i < max_eased) ui.motion.number(c, c.print("part-{d}", .{i}), v, .{ .tween = .{ .duration = 0.35 } }) else v;
        if (i < max_eased) eased[i] = e;
        used += e;
    }
    for (parts, 0..) |p, i| {
        const v = if (i < max_eased) eased[i] else chart.partShare(p.value);
        if (!(v > 0)) continue;
        var d = ui.div(c).hFull();
        if (opts.part_radius > 0) d = d.rounded(opts.part_radius * k);
        d = d.bg(p.color);
        if (opts.glow > 0) d = d.shadow(.{ .color = p.color.alpha(opts.glow), .blur = 6 * k, .y = 0 });
        chart.weighted(d, v).end();
    }
    if (!opts.whole and used < 1) chart.weighted(ui.div(c).hFull(), 1 - used).end();
}

/// How many parts ease to new values; any after them move at once.
const max_eased = 32;

const Color = ui.Color;
const cyan: Color = .hex(0x22d3ee);
const violet: Color = .hex(0xa78bfa);

/// Where each part of a breakdown 200 points wide starts and how wide it is.
fn widths(parts: []const chart.Part, opts: Options) ![3]f32 {
    const T = struct {
        var ps: []const chart.Part = &.{};
        var o: Options = .{};
        fn view(_: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(200);
            defer root.end();
            breakdown(c, ps, o);
        }
    };
    T.ps = parts;
    T.o = opts;
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 40 });
    defer t.deinit();
    t.settle(1);
    var out: [3]f32 = @splat(0);
    var n: usize = 0;
    // The first box is the window's.
    for (t.ctx.nodes.items[1..]) |node| {
        if (node.style.background == null or node.style.height != .fill) continue;
        if (n < out.len) out[n] = t.ctx.rects.get(node.id).?.w;
        n += 1;
    }
    return out;
}

test "a breakdown's parts take their share of the bar, and leave the rest" {
    // Two parts and a hairline between each: 198 points to share.
    const w = try widths(&.{ .{ .value = 0.5, .color = cyan }, .{ .value = 0.25, .color = violet } }, .{});
    try std.testing.expectApproxEqAbs(@as(f32, 99), w[0], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 49.5), w[1], 0.5);
}

test "a whole breakdown shares the bar by the parts' sum" {
    // Without a gap, the parts overlap by a point.
    const w = try widths(&.{ .{ .value = 3, .color = cyan }, .{ .value = 1, .color = violet } }, .{ .whole = true, .gap = 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 150.75), w[0], 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 50.25), w[1], 0.01);
}

test "a breakdown counts bad parts as nothing, and squeezes parts over the bar" {
    const nan = std.math.nan(f32);
    // Parts that are nothing take no room, and no gap: one gap is left.
    const bad = try widths(&.{ .{ .value = nan, .color = cyan }, .{ .value = -1, .color = violet }, .{ .value = 0.5, .color = cyan } }, .{ .gap = 2 });
    try std.testing.expectEqualSlices(f32, &.{ 99, 0, 0 }, &bad);
    const over = try widths(&.{ .{ .value = 0.9, .color = cyan }, .{ .value = 0.9, .color = violet } }, .{ .gap = 2 });
    try std.testing.expectApproxEqAbs(@as(f32, 99), over[0], 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 99), over[1], 0.01);
}

test "a full breakdown reaches the end of its bar" {
    const w = try widths(&.{.{ .value = 1, .color = cyan }}, .{});
    try std.testing.expectEqual(@as(f32, 200), w[0]);
}

test "a breakdown with a label is one image to a screen reader, with its value" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            breakdown(c, &.{.{ .value = 0.6, .color = cyan }}, .{ .label = "Memory", .value_text = "15 of 24 GB" });
            breakdown(c, &.{.{ .value = 0.6, .color = cyan }}, .{});
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 60 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqual(ui.access.Role.image, list.items[0].role);
    try std.testing.expectEqualStrings("Memory", list.items[0].label);
    try std.testing.expectEqualStrings("15 of 24 GB", list.items[0].value);
}

test "a breakdown's parts ease to new values" {
    const T = struct {
        v: f32 = 0.2,
        fn view(x: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(200);
            defer root.end();
            breakdown(c, &.{.{ .value = x.v, .color = cyan }}, .{ .gap = 2 });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 40 });
    defer t.deinit();
    t.settle(1);
    const part = struct {
        fn width(tt: *ui.Tester) f32 {
            for (tt.ctx.nodes.items[1..]) |node| if (node.style.background != null and node.style.height == .fill) return tt.ctx.rects.get(node.id).?.w;
            return 0;
        }
    };
    // 0.2 of 198 points (two gaps of 2 from 202... the track is 200 wide).
    const before = part.width(&t);
    x.v = 0.8;
    t.advance(0.1);
    const moving = part.width(&t);
    t.settle(1);
    const after = part.width(&t);
    try std.testing.expect(moving > before and moving < after);
    try std.testing.expectApproxEqAbs(after, before * 4, 0.5);
}
