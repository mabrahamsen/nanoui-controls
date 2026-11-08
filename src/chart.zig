//! What the charts share: their part of a bar, ramps of colors, the
//! kit's track, lines at values and an axis for them, texts under a
//! chart, and inspecting a chart's slots with the pointer and the keys,
//! with a tooltip. Not a control of its own.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const focus = @import("focus.zig");

/// One part of a bar: `value` its share, and its color. A part that is
/// negative or not a number counts as 0, unless the chart has room below
/// its zero for negative ones.
pub const Part = struct {
    value: f32,
    color: ui.Color,
};

/// A line across a chart at `value`, on the chart's scale, with an
/// optional label at its start ("50%").
pub const ValueLine = struct {
    value: f32,
    label: []const u8 = "",
};

/// A part's share: 0 for one negative or not a number.
pub fn partShare(v: f32) f32 {
    return if (std.math.isFinite(v) and v > 0) v else 0;
}

/// The color at `at` (0 to 1) along `stops`, blended between the two it
/// falls between; the first and last hold beyond the ends.
pub fn rampColor(stops: []const ui.Color, at: f32) ui.Color {
    if (stops.len == 0) return .{};
    if (stops.len == 1 or !(at > 0)) return stops[0];
    if (at >= 1) return stops[stops.len - 1];
    const x = at * @as(f32, @floatFromInt(stops.len - 1));
    const i: usize = @intFromFloat(@floor(x));
    return stops[i].mix(stops[i + 1], x - @floor(x));
}

/// `div` takes `v` of the room its parent leaves, against its siblings.
pub fn weighted(div: ui.Div, v: f32) ui.Div {
    div.c.node(div.index).style.grow = @max(0, v);
    return div;
}

/// `l` with its points times `k`.
pub fn scaled(l: ui.Length, k: f32) ui.Length {
    return switch (l) {
        .px => |v| .{ .px = v * k },
        else => l,
    };
}

/// The track of the kit's progress bar, for where no part is.
pub fn track(c: *ui.Context) ui.Color {
    const t = kit.tokens(c);
    return t.surface_hover.mix(t.border, 0.5);
}

/// The size of box `index` as the last frame laid it out (`measure.zig`).
pub const lastSize = @import("measure.zig").lastSize;

/// The height of a chart's box `index`, `height` before `scale` `k`: its
/// points, or for one that fills, as the last frame laid it out (0 in its
/// first). For lines across it at values.
pub fn linesHeight(c: *ui.Context, height: ui.Length, k: f32, index: u32) f32 {
    return switch (height) {
        .px => |v| v * k,
        else => if (lastSize(c, index)) |sz| sz.h else 0,
    };
}

/// Where `x` falls between `min` and `max`, from 0 to 1; null for no
/// reading (not a number, or infinite). A scale with no room between
/// `min` and `max` puts every reading at 0.
pub fn level(x: f32, min: f32, max: f32) ?f32 {
    if (!std.math.isFinite(x)) return null;
    const range = max - min;
    if (!std.math.isFinite(range) or !(range > 0)) return 0;
    return std.math.clamp((x - min) / range, 0, 1);
}

/// A chart's scale's top, as every chart with a scale takes it: `max`
/// rising to the data's `peak` unless `fixed`; null takes the peak. A top
/// with no room above `min` is one above it.
pub fn scaleTop(min: f32, max: ?f32, fixed: bool, peak: f32) f32 {
    const hi = if (max) |m| (if (fixed) m else @max(m, peak)) else peak;
    return if (std.math.isFinite(hi) and hi > min) hi else min + 1;
}

/// The reading in slot `i` of `n`, for readings kept oldest first from
/// `head` (a ring once full) and shown right-aligned, the newest in the
/// last slot; with more readings than slots, the newest. Null where there
/// is none, or one that is not a number.
pub fn slotReading(values: []const f32, head: usize, n: usize, i: usize) ?f32 {
    const shown = @min(values.len, n);
    if (i < n - shown or i >= n) return null;
    const skip = values.len - shown;
    const v = values[(head % values.len + skip + i - (n - shown)) % values.len];
    return if (std.math.isFinite(v)) v else null;
}

/// How many parts of a bar ease to new values; any after them move at
/// once.
pub const max_eased = 32;

/// Eases each of the first `max_eased` parts' shares to its new value,
/// into `out`, in an order kept from frame to frame; the rest as they
/// are. Returns their sum.
pub fn easeParts(c: *ui.Context, parts: []const Part, out: *[max_eased]f32) f32 {
    var sum: f32 = 0;
    for (parts, 0..) |p, i| {
        const v = partShare(p.value);
        const e = if (i < max_eased) ui.motion.number(c, c.print("part-{d}", .{i}), v, .{ .tween = .{ .duration = 0.35 } }) else v;
        if (i < max_eased) out[i] = e;
        sum += e;
    }
    return sum;
}

/// Part `i`'s share as `easeParts` left it.
pub fn eased(parts: []const Part, out: *const [max_eased]f32, i: usize) f32 {
    return if (i < max_eased) out[i] else partShare(parts[i].value);
}

/// The size of the small figures charts set beside or under them: value
/// lines' labels, an axis, zones.
pub const axis_text_size = 9.5;

/// A part of the ring between `r_in` and `r_out`, from angle `a0` to `a1`
/// clockwise from the top, in `color`: in pieces of at most half a turn,
/// each a little over the next, so a whole ring has no seam.
pub fn arc(c: *ui.Context, cv: *ui.Canvas, center: ui.Point, r_out: f32, r_in: f32, a0: f32, a1: f32, color: ui.Color) void {
    var from = a0;
    while (from < a1) {
        const to = @min(a1, from + std.math.pi);
        piece(c, cv, center, r_out, r_in, from, if (to < a1) to + 0.01 else to, color);
        from = to;
    }
}

fn piece(c: *ui.Context, cv: *ui.Canvas, center: ui.Point, r_out: f32, r_in: f32, a0: f32, a1: f32, color: ui.Color) void {
    // About a step every 4 degrees, at least two.
    const steps: usize = @max(2, @as(usize, @intFromFloat(@ceil((a1 - a0) / 0.07))));
    const pts = c.alloc().alloc(ui.Point, 2 * (steps + 1)) catch return;
    for (0..steps + 1) |i| {
        const a = a0 + (a1 - a0) * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
        const dx = @sin(a);
        const dy = -@cos(a);
        pts[i] = .{ .x = center.x + dx * r_out, .y = center.y + dy * r_out };
        pts[pts.len - 1 - i] = .{ .x = center.x + dx * r_in, .y = center.y + dy * r_in };
    }
    cv.fill(pts, color);
}

/// Draws `lines` across the open box, `h` points tall, behind what
/// follows: on a scale from `lo` at the bottom to `hi` at `top` points
/// down, each with its label above it at the start, unless `labels` is
/// false (an axis says them). Lines off the scale are left out. They sit
/// in a box of their own, so what follows keeps its place among the
/// box's children as lines come and go.
pub fn valueLines(c: *ui.Context, lines: []const ValueLine, h: f32, top: f32, lo: f32, hi: f32, labels: bool) void {
    if (lines.len == 0) return;
    const t = kit.tokens(c);
    const box = ui.div(c).absolute().wFull().h(h);
    defer box.end();
    for (lines) |l| {
        if (!(hi > lo) or !(l.value >= lo and l.value <= hi)) continue;
        const y = @round(top + (hi - l.value) / (hi - lo) * (h - top));
        ui.div(c).absolute().offset(0, @min(y, h - 1)).wFull().h(1).bg(t.border.alpha(0.8)).end();
        if (labels and l.label.len > 0) {
            const d = ui.div(c).absolute().offset(2, @max(0, y - 13)).h(12);
            defer d.end();
            ui.text(c, l.label, .{ .size = axis_text_size, .mono = true, .color = t.muted });
        }
    }
}

/// Where a chart's axis goes: none, or a gutter at its start or its end
/// with its value lines' labels in it.
pub const Axis = enum { none, start, end };

/// What a chart's frame draws around it: an axis, and texts under it.
pub const FrameSpec = struct {
    axis: Axis = .none,
    lines: []const ValueLine = &.{},
    /// The scale, as `valueLines` takes it.
    lo: f32 = 0,
    hi: f32 = 1,
    top: f32 = 0,
    start_text: []const u8 = "",
    end_text: []const u8 = "",
    scale: f32 = 1,

    fn framed(f: FrameSpec) bool {
        return f.axis != .none or f.start_text.len > 0 or f.end_text.len > 0;
    }
};

const axis_style: ui.TextStyle = .{ .size = axis_text_size, .mono = true };

/// A chart's frame, with an axis beside it or texts under it: open it
/// before the chart, which then takes its width, and close it after.
/// Without either, it draws nothing, and the chart takes `width` itself.
/// With `fill_height`, the frame fills its parent's height, and the
/// chart the room its texts leave.
pub const Frame = struct {
    spec: FrameSpec = .{},
    outer: ?ui.Div = null,
    across: ?ui.Div = null,
    gutter: f32 = 0,

    pub fn open(c: *ui.Context, width: ui.Length, spec: FrameSpec, fill_height: bool) Frame {
        if (!spec.framed()) return .{ .spec = spec };
        const k = spec.scale;
        var outer = ui.div(c).column().gap(3 * k);
        c.node(outer.index).style.width = scaled(width, k);
        if (fill_height) outer = outer.hFull();
        var across = ui.div(c).row().wFull();
        if (fill_height) {
            across = across.grow();
            c.node(across.index).style.min_height = 0;
        }
        var f: Frame = .{ .spec = spec, .outer = outer, .across = across };
        if (spec.axis != .none) {
            for (spec.lines) |l| if (l.label.len > 0) {
                f.gutter = @max(f.gutter, @ceil(c.text.width(l.label, axis_style)) + 6 * k);
            };
        }
        if (spec.axis == .start) f.drawGutter(c);
        return f;
    }

    /// Gives the chart's box, `index`, its size: `width` and `height`
    /// themselves, or in a frame, the width its gutter leaves and, for a
    /// height that fills, the frame's.
    pub fn size(f: Frame, c: *ui.Context, index: u32, width: ui.Length, height: ui.Length) void {
        const st = &c.node(index).style;
        const k = f.spec.scale;
        if (f.outer == null) {
            st.width = scaled(width, k);
            st.height = scaled(height, k);
            return;
        }
        st.width = .{ .px = 0 };
        st.grow = 1;
        st.height = if (height == .px) scaled(height, k) else .fill;
    }

    pub fn close(f: Frame, c: *ui.Context) void {
        const outer = f.outer orelse return;
        if (f.spec.axis == .end) f.drawGutter(c);
        f.across.?.end();
        if (f.spec.start_text.len > 0 or f.spec.end_text.len > 0) {
            var foot = ui.div(c).row().wFull();
            if (f.spec.axis == .start) foot = foot.pl(f.gutter) else if (f.spec.axis == .end) foot = foot.pr(f.gutter);
            defer foot.end();
            const t = kit.tokens(c);
            var style = axis_style;
            style.color = t.muted;
            ui.text(c, f.spec.start_text, style);
            ui.spacer(c);
            ui.text(c, f.spec.end_text, style);
        }
        outer.end();
    }

    /// The labels of the value lines, each level with its line, at the
    /// gutter's edge by the chart; one that would overlap the one above
    /// it is left out.
    fn drawGutter(f: Frame, c: *ui.Context) void {
        const s = f.spec;
        const k = s.scale;
        const g = ui.div(c).w(f.gutter).hFull();
        defer g.end();
        ui.access.hide(c, g.index);
        const h = if (lastSize(c, g.index)) |sz| sz.h else return;
        if (!(s.hi > s.lo)) return;
        const t = kit.tokens(c);
        var style = axis_style;
        style.color = t.muted;
        // The highest first, so the ones nearer the top win.
        const order = c.alloc().alloc(usize, s.lines.len) catch return;
        for (order, 0..) |*o, i| o.* = i;
        std.mem.sort(usize, order, s.lines, struct {
            fn above(lines: []const ValueLine, a: usize, b: usize) bool {
                return lines[a].value > lines[b].value;
            }
        }.above);
        var last: ?f32 = null;
        for (order) |i| {
            const l = s.lines[i];
            if (l.label.len == 0 or !(l.value >= s.lo and l.value <= s.hi)) continue;
            const y = @round(s.top + (s.hi - l.value) / (s.hi - s.lo) * (h - s.top));
            if (last) |prev| if (y - prev < 11 * k) continue;
            last = y;
            const tw = @ceil(c.text.width(l.label, style));
            const x = if (s.axis == .start) f.gutter - tw - 4 * k else 4 * k;
            const d = ui.div(c).absolute().offset(x, std.math.clamp(y - 6 * k, 0, @max(0, h - 12 * k))).h(12 * k);
            defer d.end();
            ui.text(c, l.label, style);
        }
    }
};

/// Names box `index` for a screen reader as a chart: one image called
/// `label`, saying `value`. Without a label, an interactive chart is
/// called `unnamed` (its `chart_text`), and any other is left out, as a
/// decoration.
pub fn describe(c: *ui.Context, index: u32, label: []const u8, value: []const u8, interactive: bool, unnamed: []const u8) void {
    if (label.len == 0 and !interactive) return ui.access.hide(c, index);
    ui.access.describe(c, index, .{ .role = .image, .label = if (label.len > 0) label else unnamed, .value = value });
}

/// What the pointer or the keys point at in a chart of `count` slots
/// across box `index`: the pointer's slot when it moves over the chart,
/// and, while the chart has the keyboard, the one Left and Right (and
/// Home and End) move to from there, until the pointer moves again. The
/// box takes the keyboard on a click or Tab. Slots are `count` equal
/// widths, or with `points`, points from one end to the other, the
/// nearest taken.
pub const Inspect = struct {
    current: ?usize = null,
    focused: bool = false,
    id: u64 = 0,

    pub fn begin(c: *ui.Context, index: u32, count: usize, points: bool) Inspect {
        return beginFrom(c, index, count, 0, points);
    }

    /// As `begin`, the slots before `first` empty: neither the pointer nor
    /// the keys stop on them.
    pub fn beginFrom(c: *ui.Context, index: u32, count: usize, first: usize, points: bool) Inspect {
        const it = c.interact(index, .{ .focusable = true });
        // The slot pointed at or moved to, and where the pointer was when
        // it last picked one (none while it is off the chart).
        const kept = c.state(struct { slot: ?usize = null, x: ?f32 = null }, "chart-slot");
        if (count == 0 or first >= count) return .{ .focused = it.focused, .id = it.id };
        if (kept.slot) |s| if (s >= count) {
            kept.slot = count - 1;
        };
        if (it.focused) c.node(index).style.border = focus.ring(c);
        if (!it.hovered) kept.x = null;
        if (it.hovered) {
            c.wants_moves = true;
            c.cursor_hand = false;
            if (it.rect) |r| if (r.w > 0 and kept.x != c.input.mouse.x) {
                kept.x = c.input.mouse.x;
                const n: f32 = @floatFromInt(count);
                const x = (c.input.mouse.x - r.x) / r.w;
                kept.slot = @intFromFloat(std.math.clamp(if (points) @round(x * (n - 1)) else x * n, 0, n - 1));
            };
        }
        if (it.focused) kept.slot = keys(c, kept.slot orelse count - 1, count, first);
        if (kept.slot) |s| if (s < first) {
            kept.slot = if (it.focused) first else null;
        };
        if (!it.hovered and !it.focused) return .{ .id = it.id };
        return .{ .current = kept.slot, .focused = it.focused, .id = it.id };
    }

    /// A tooltip saying `text` over `rect` (as last laid out), at once.
    pub fn tooltip(in: Inspect, c: *ui.Context, rect: ?ui.Rect, text: []const u8) void {
        if (in.current == null) return;
        kit.tooltip(c, .{ .id = in.id, .rect = rect, .hovered = true, .pressed = false, .clicked = false, .focused = in.focused }, text, .{ .delay = 0 });
    }
};

/// Left and Right move a slot, Home and End to the ends: from `first`.
fn keys(c: *ui.Context, slot: usize, count: usize, first: usize) usize {
    if (c.shortcut(.{ .key = ui.Shortcut.left })) return @max(first, slot -| 1);
    if (c.shortcut(.{ .key = ui.Shortcut.right })) return @min(slot + 1, count - 1);
    const key = c.input.key orelse return slot;
    return switch (key) {
        .left => @max(first, slot -| 1),
        .right => @min(slot + 1, count - 1),
        .home => first,
        .end => count - 1,
        else => slot,
    };
}

test {
    _ = @import("chart_tests.zig");
}

test "rampColor blends between stops and holds at the ends" {
    const a: ui.Color = .hex(0x000000);
    const b: ui.Color = .hex(0xffffff);
    const stops = [_]ui.Color{ a, b };
    try std.testing.expectEqual(a, rampColor(&stops, 0));
    try std.testing.expectEqual(b, rampColor(&stops, 1));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), rampColor(&stops, 0.5).r, 1e-6);
    try std.testing.expectEqual(a, rampColor(&stops, -3));
    try std.testing.expectEqual(b, rampColor(&stops, 7));
    try std.testing.expectEqual(a, rampColor(&stops, std.math.nan(f32)));
    try std.testing.expectEqual(a, rampColor(&.{a}, 0.7));
}
