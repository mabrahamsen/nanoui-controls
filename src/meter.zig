//! A meter: a row of segments, like LEDs, lit up to a value from 0 to 1.
//! Segment `i` of `n` lights when its middle, `(i + 0.5) / n`, is at most
//! the value. Lit segments take one color, or a color by their place (a
//! heat or strength ramp), and can glow in it. Lit all the way and without
//! gaps, it is a strip of colors in steps, for the gradients nanoui can't
//! fill, such as under a slider.
//!
//!     controls.meter(c, load, .{ .ramp = heat, .glow = 0.6, .label = "CPU load" });
//!     controls.meter(c, 1, .{ .ramp = hues, .gap = 0, .radius = 0 });
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const bars_mod = @import("bars.zig");
const split_mod = @import("split.zig");

pub const Options = struct {
    /// How many segments.
    segments: usize = 24,
    /// The parent's width by default; in a row, the room the rest leaves.
    width: ui.Length = .fill,
    height: f32 = 8,
    /// Between the segments; 0 makes a strip without seams.
    gap: f32 = 3,
    /// The segments' corner radius.
    radius: f32 = 2,
    /// Every lit segment's color; null takes the theme's accent.
    color: ?ui.Color = null,
    /// A lit segment's color by its place: called with the segment's
    /// middle, 0 to 1. Takes over from `color`.
    ramp: ?*const fn (at: f32) ui.Color = null,
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
    value: []const u8 = "",
    /// Multiplies the meter's lengths, as `bars`.
    scale: f32 = 1,
};

/// Draws a meter lit up to `value` (0 to 1); a value that is not a number
/// lights none.
pub fn meter(c: *ui.Context, value: f32, opts: Options) void {
    const k = opts.scale;
    const v = if (std.math.isNan(value)) 0 else std.math.clamp(value, 0, 1);
    const lit = opts.color orelse kit.tokens(c).primary;
    const off = opts.track orelse split_mod.track(c);
    const n: f32 = @floatFromInt(opts.segments);
    // Without gaps, the segments overlap by a point: edges that fall
    // between pixels would otherwise show the background through.
    const r = ui.div(c).row().h(opts.height * k).gap(if (opts.gap > 0) opts.gap * k else -1);
    c.node(r.index).style.width = bars_mod.scaled(opts.width, k);
    if (opts.label.len > 0) ui.access.describe(c, r.index, .{
        .role = .image,
        .label = opts.label,
        .value = if (opts.value.len > 0) opts.value else c.print("{d}%", .{@round(v * 100)}),
    });
    defer r.end();
    for (0..opts.segments) |i| {
        const at = (@as(f32, @floatFromInt(i)) + 0.5) / n;
        var seg = ui.div(c).w(0).grow().hFull().rounded(opts.radius * k);
        if (at <= v) {
            const col = if (opts.ramp) |f| f(at) else lit;
            seg = seg.bg(col);
            if (opts.glow > 0) seg = seg.shadow(.{ .color = col.alpha(opts.glow), .blur = 6 * k, .y = 0 });
        } else seg = seg.bg(off);
        seg.end();
    }
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

fn twoTone(at: f32) Color {
    return if (at < 0.5) cyan else .hex(0xfb7185);
}

test "a meter's ramp colors lit segments by their place, and unlit ones are the track" {
    const segs = try colors(0.7, .{ .ramp = twoTone, .track = .hex(0x101010) });
    try std.testing.expectEqual(cyan, segs[0].?);
    try std.testing.expectEqual(Color.hex(0xfb7185), segs[5].?);
    try std.testing.expectEqual(Color.hex(0x101010), segs[6].?);
}

test "a meter with a label reads as its value, a percentage unless given" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            meter(c, 0.624, .{ .label = "CPU load" });
            meter(c, 0.5, .{ .label = "Strength", .value = "Fair" });
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
