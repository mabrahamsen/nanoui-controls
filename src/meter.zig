//! A meter: a row of segments, like LEDs, lit up to a value from 0 to 1.
//! Segment `i` of `n` lights when its middle, `(i + 0.5) / n`, is at most
//! the value. Lit segments take one color, or a color by their place (a
//! heat or strength ramp), and can glow in it. Lit all the way and without
//! gaps, it is a strip of colors in steps, for the gradients nanoui can't
//! fill, such as under a slider.
//!
//! It eases to a new value, as the kit's progress bar does. Without gaps,
//! a `radius` rounds the strip's ends only. With `zones`, its segments
//! fall into runs with a wider gap between them, each labelled under it:
//! a scale in bands.
//!
//!     controls.meter(c, load, .{ .ramp = &heat, .glow = 0.6, .label = "CPU load" });
//!     controls.meter(c, 1, .{ .ramp = &hues, .gap = 0, .radius = 0 });
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const chart = @import("chart.zig");

pub const Options = struct {
    /// How many segments.
    segments: usize = 24,
    /// The parent's width by default; in a row, the room the rest leaves.
    width: ui.Length = .fill,
    height: f32 = 8,
    /// Between the segments; 0 makes a strip without seams.
    gap: f32 = 3,
    /// The segments' corner radius; without gaps, the strip's ends'.
    radius: f32 = 2,
    /// Labels under equal runs of the segments, one a run ("<20", "<40",
    /// "80+"), the runs `zone_gap` apart: a scale in bands.
    zones: []const []const u8 = &.{},
    zone_gap: f32 = 6,
    /// Every lit segment's color; null takes the theme's accent.
    color: ?ui.Color = null,
    /// Colors from the first segment to the last, blended between: a lit
    /// segment takes the color at its place, such as a heat or strength
    /// ramp. Takes over from `color`.
    ramp: []const ui.Color = &.{},
    /// An unlit segment's color; null takes the track of the kit's
    /// progress bar.
    track: ?ui.Color = null,
    /// The opacity of a glow around each lit segment, in its color; 0
    /// draws none.
    glow: f32 = 0,
    /// What a screen reader calls the meter ("CPU load"); empty leaves it
    /// out, as a decoration.
    label: []const u8 = "",
    /// What a screen reader says it shows; empty says the value as a
    /// percentage.
    value_text: []const u8 = "",
    /// Multiplies the meter's lengths, as `bars`.
    scale: f32 = 1,
};

/// Draws a meter lit up to `value` (0 to 1); a value that is not a number
/// lights none.
pub fn meter(c: *ui.Context, value: f32, opts: Options) void {
    const k = opts.scale;
    const v = if (std.math.isNan(value)) 0 else std.math.clamp(value, 0, 1);
    const lit = opts.color orelse kit.tokens(c).primary;
    const off = opts.track orelse chart.track(c);
    const n: f32 = @floatFromInt(opts.segments);
    const strip = opts.gap == 0 and opts.radius > 0;
    const zones = @min(opts.zones.len, opts.segments);
    const outer = if (zones > 0) ui.div(c).column().gap(3 * k) else null;
    if (outer) |o| c.node(o.index).style.width = chart.scaled(opts.width, k);
    // Without gaps, the segments overlap by a point: edges that fall
    // between pixels would otherwise show the background through.
    var r = ui.div(c).row().h(opts.height * k).gap(if (zones > 0) opts.zone_gap * k else if (opts.gap > 0) opts.gap * k else -1);
    c.node(r.index).style.width = if (zones > 0) .fill else chart.scaled(opts.width, k);
    // A strip rounded at its ends only: the segments square, cut by it.
    if (strip) r = r.rounded(opts.radius * k).clip();
    // A value that isn't a number says nothing, as a gauge's; one without
    // a label isn't said at all.
    const known = !std.math.isNan(value);
    const said = if (opts.value_text.len > 0 or opts.label.len == 0 or !known) opts.value_text else c.print("{d}%", .{@round(v * 100)});
    chart.describe(c, r.index, opts.label, said, false, "");
    const shown = ui.motion.number(c, "meter", v, .{ .tween = .{ .duration = 0.35 } });
    var run: ?ui.Div = null;
    var zone: usize = 0;
    for (0..opts.segments) |i| {
        // A run of segments a zone, as even as the count allows.
        if (zones > 0 and (run == null or i * zones / opts.segments != zone)) {
            if (run) |x| x.end();
            zone = i * zones / opts.segments;
            // As wide as its share of the segments, so they are one width
            // whatever the zones.
            run = chart.weighted(ui.div(c).row().w(0).hFull().gap(if (opts.gap > 0) opts.gap * k else -1), @floatFromInt(zoneSize(zone, zones, opts.segments)));
        }
        const at = (@as(f32, @floatFromInt(i)) + 0.5) / n;
        var seg = ui.div(c).w(0).grow().hFull().rounded(if (strip) 0 else opts.radius * k);
        if (at <= shown + 1e-6) {
            const col = if (opts.ramp.len > 0) chart.rampColor(opts.ramp, at) else lit;
            seg = seg.bg(col);
            if (opts.glow > 0) seg = seg.shadow(.{ .color = col.alpha(opts.glow), .blur = 6 * k, .y = 0 });
        } else seg = seg.bg(off);
        seg.end();
    }
    if (run) |x| x.end();
    r.end();
    const o = outer orelse return;
    defer o.end();
    const labels = ui.div(c).row().wFull().gap(opts.zone_gap * k);
    defer labels.end();
    ui.access.hide(c, labels.index);
    const t = kit.tokens(c);
    for (opts.zones[0..zones], 0..) |label, z| {
        const cell = chart.weighted(ui.div(c).w(0).row().justifyCenter(), @floatFromInt(zoneSize(z, zones, opts.segments)));
        defer cell.end();
        ui.text(c, label, .{ .size = chart.axis_text_size, .mono = true, .color = t.muted });
    }
}

/// How many of `segments` fall in zone `z` of `zones`, as `meter` deals
/// them out.
fn zoneSize(z: usize, zones: usize, segments: usize) usize {
    var n: usize = 0;
    for (0..segments) |i| n += @intFromBool(i * zones / segments == z);
    return n;
}

const Color = ui.Color;
const cyan: Color = .hex(0x22d3ee);

/// The meter's segments' colors, left to right.
fn colors(value: f32, opts: Options) ![8]?Color {
    const T = struct {
        var v: f32 = 0;
        var o: Options = .{};
        fn view(_: *@This(), c: *ui.Context) void {
            meter(c, v, o);
        }
    };
    T.v = value;
    T.o = opts;
    T.o.segments = 8;
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 200, .height = 40 });
    defer t.deinit();
    t.settle(1);
    var out: [8]?Color = @splat(null);
    var n: usize = 0;
    for (t.ctx.nodes.items) |node| {
        if (node.style.height != .fill) continue;
        out[n] = node.style.background;
        n += 1;
    }
    return out;
}

/// Lit segments, from the left.
fn litCount(value: f32) !usize {
    const segs = try colors(value, .{ .color = cyan });
    var n: usize = 0;
    for (segs) |s| n += @intFromBool(std.meta.eql(s, cyan));
    return n;
}

test "a meter lights the segments whose middle the value reaches" {
    // Eight segments: their middles are at 1/16, 3/16, …
    try std.testing.expectEqual(@as(usize, 0), try litCount(0));
    try std.testing.expectEqual(@as(usize, 0), try litCount(0.06));
    try std.testing.expectEqual(@as(usize, 1), try litCount(0.0625));
    try std.testing.expectEqual(@as(usize, 4), try litCount(0.5));
    try std.testing.expectEqual(@as(usize, 8), try litCount(1));
    // Out of range is held to it; not a number lights none.
    try std.testing.expectEqual(@as(usize, 8), try litCount(7));
    try std.testing.expectEqual(@as(usize, 0), try litCount(-1));
    try std.testing.expectEqual(@as(usize, 0), try litCount(std.math.nan(f32)));
}

test "a meter's ramp colors lit segments by their place, and unlit ones are the track" {
    const segs = try colors(0.7, .{ .ramp = &.{ .hex(0x000000), .hex(0xffffff) }, .track = .hex(0x101010) });
    // The first segment's middle is 1/16 along: nearly black.
    try std.testing.expectApproxEqAbs(@as(f32, 1.0 / 16.0), segs[0].?.r, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 11.0 / 16.0), segs[5].?.r, 1e-6);
    try std.testing.expectEqual(Color.hex(0x101010), segs[6].?);
}

test "a meter eases to a new value" {
    const T = struct {
        v: f32 = 0,
        fn view(x: *@This(), c: *ui.Context) void {
            meter(c, x.v, .{ .segments = 8, .color = cyan });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 200, .height = 40 });
    defer t.deinit();
    t.settle(1);
    const lit = struct {
        fn count(tt: *ui.Tester) usize {
            var n: usize = 0;
            for (tt.ctx.nodes.items) |node| n += @intFromBool(node.style.background != null and std.meta.eql(node.style.background.?, cyan));
            return n;
        }
    };
    try std.testing.expectEqual(@as(usize, 0), lit.count(&t));
    x.v = 1;
    t.advance(0.1);
    const moving = lit.count(&t);
    try std.testing.expect(moving > 0 and moving < 8);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 8), lit.count(&t));
}

test "a meter with a label reads as its value, a percentage unless given" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            meter(c, 0.624, .{ .label = "CPU load" });
            meter(c, 0.5, .{ .label = "Strength", .value_text = "Fair" });
            meter(c, 0.5, .{});
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
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqualStrings("CPU load", list.items[0].label);
    try std.testing.expectEqualStrings("62%", list.items[0].value);
    try std.testing.expectEqualStrings("Fair", list.items[1].value);
}
