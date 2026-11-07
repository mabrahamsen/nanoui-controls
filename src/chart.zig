//! What the charts share: their part of a bar, ramps of colors, the
//! kit's track, lines at values, and inspecting a chart's slots with the
//! pointer and the keys, with a tooltip. Not a control of its own.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;

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

/// The size of box `index` as the last frame laid it out, or null in its
/// first frame. Then, or when it changed, another frame is drawn with the
/// new one, as the grid does with its width.
pub fn lastSize(c: *ui.Context, index: u32) ?ui.Size {
    const r = c.rects.get(c.node(index).id) orelse {
        c.frameIn(0);
        return null;
    };
    const last = c.state(struct { w: f32 = 0, h: f32 = 0 }, "chart-size");
    if (last.w != r.w or last.h != r.h) {
        last.* = .{ .w = r.w, .h = r.h };
        c.frameIn(0);
    }
    return .{ .w = r.w, .h = r.h };
}

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
/// down, each with its label above it at the start. Lines off the scale
/// are left out. They sit in a box of their own, so what follows keeps
/// its place among the box's children as lines come and go.
pub fn valueLines(c: *ui.Context, lines: []const ValueLine, h: f32, top: f32, lo: f32, hi: f32) void {
    if (lines.len == 0) return;
    const t = kit.tokens(c);
    const box = ui.div(c).absolute().wFull().h(h);
    defer box.end();
    for (lines) |l| {
        if (!(hi > lo) or !(l.value >= lo and l.value <= hi)) continue;
        const y = @round(top + (hi - l.value) / (hi - lo) * (h - top));
        ui.div(c).absolute().offset(0, @min(y, h - 1)).wFull().h(1).bg(t.border.alpha(0.8)).end();
        if (l.label.len > 0) {
            const d = ui.div(c).absolute().offset(2, @max(0, y - 13)).h(12);
            defer d.end();
            ui.text(c, l.label, .{ .size = 9.5, .mono = true, .color = t.muted });
        }
    }
}

/// Names box `index` for a screen reader as a chart: one image called
/// `label`, saying `value`. Without a label, an interactive chart is
/// called "Chart", and any other is left out, as a decoration.
pub fn describe(c: *ui.Context, index: u32, label: []const u8, value: []const u8, interactive: bool) void {
    if (label.len == 0 and !interactive) return ui.access.hide(c, index);
    ui.access.describe(c, index, .{ .role = .image, .label = if (label.len > 0) label else "Chart", .value = value });
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
        const it = c.interact(index, .{ .focusable = true });
        // The slot pointed at or moved to, and where the pointer was when
        // it last picked one (none while it is off the chart).
        const kept = c.state(struct { slot: ?usize = null, x: ?f32 = null }, "chart-slot");
        if (count == 0) return .{ .focused = it.focused, .id = it.id };
        if (kept.slot) |s| if (s >= count) {
            kept.slot = count - 1;
        };
        if (it.focused) c.node(index).style.border = kit.tokens(c).primary.alpha(0.6);
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
        if (it.focused) kept.slot = keys(c, kept.slot orelse count - 1, count);
        if (!it.hovered and !it.focused) return .{ .id = it.id };
        return .{ .current = kept.slot, .focused = it.focused, .id = it.id };
    }

    /// A tooltip saying `text` over `rect` (as last laid out), at once.
    pub fn tooltip(in: Inspect, c: *ui.Context, rect: ?ui.Rect, text: []const u8) void {
        if (in.current == null) return;
        kit.tooltip(c, .{ .id = in.id, .rect = rect, .hovered = true, .pressed = false, .clicked = false, .focused = in.focused }, text, .{ .delay = 0 });
    }
};

/// Left and Right move a slot, Home and End to the ends.
fn keys(c: *ui.Context, slot: usize, count: usize) usize {
    if (c.shortcut(.{ .key = ui.Shortcut.left })) return slot -| 1;
    if (c.shortcut(.{ .key = ui.Shortcut.right })) return @min(slot + 1, count - 1);
    const key = c.input.key orelse return slot;
    return switch (key) {
        .left => slot -| 1,
        .right => @min(slot + 1, count - 1),
        .home => 0,
        .end => count - 1,
        else => slot,
    };
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
