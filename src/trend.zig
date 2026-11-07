//! A trend: a history drawn as bars, oldest first, scaled to its peak,
//! the older bars fainter. A CPU's load, a temperature, traffic over the
//! last minute. The caller keeps the history and adds a reading to it
//! each time one comes.
//!
//!     controls.trend(c, temps, .{ .capacity = 60, .min = 20, .max = 110, .label = "Temperature", .value = "62 °C" });
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const bars_mod = @import("bars.zig");

pub const Options = struct {
    /// How many slots: the history's length when full. A shorter history
    /// leaves the oldest slots, on the left, empty.
    capacity: usize,
    /// The parent's width by default; in a row, the room the rest leaves.
    width: ui.Length = .fill,
    height: ui.Length = .{ .px = 16 },
    /// Between the bars; null keeps a hairline of one point at any scale.
    gap: ?f32 = null,
    /// Every bar's color; null takes the theme's accent.
    color: ?ui.Color = null,
    /// A bar's color by its height (0 to 1), such as from cool to hot.
    /// Takes over from `color`.
    ramp: ?*const fn (at: f32) ui.Color = null,
    /// The value at the bottom.
    min: f32 = 0,
    /// The value at the top, unless the history goes higher: a quiet
    /// history doesn't fill the chart.
    max: f32 = 1,
    /// The shortest bar, as a share of the height, so a reading at `min`
    /// still shows as a line.
    baseline: f32 = 0.03,
    /// The oldest bar's opacity, rising to 1 at the newest; null keeps
    /// every bar opaque.
    fade: ?f32 = 0.35,
    /// What a screen reader calls the chart, and says it shows, as `bars`.
    label: []const u8 = "",
    value: []const u8 = "",
    /// Multiplies the chart's lengths, as `bars`.
    scale: f32 = 1,
};

/// Draws `values`, oldest first, as a bar each, right-aligned in
/// `capacity` slots; with more values than slots, the newest. A value
/// that is not a number or is infinite is no reading: its slot stays
/// empty, and it doesn't count toward the peak.
pub fn trend(c: *ui.Context, values: []const f32, opts: Options) void {
    const col = opts.color orelse kit.tokens(c).primary;
    const shown = values[values.len - @min(values.len, opts.capacity) ..];
    var peak = opts.max;
    for (shown) |v| if (std.math.isFinite(v)) {
        peak = @max(peak, v);
    };
    const empty = opts.capacity - shown.len;
    const baseline = if (opts.baseline > 0) @min(opts.baseline, 1) else 0;
    var b = bars_mod.bars(c, .{
        .count = opts.capacity,
        .width = opts.width,
        .height = opts.height,
        .gap = opts.gap,
        .label = opts.label,
        .value = opts.value,
        .scale = opts.scale,
    });
    defer b.end();
    while (b.next()) |slot| {
        if (slot.index < empty) continue;
        const v = level(shown[slot.index - empty], opts.min, peak) orelse continue;
        const base = if (opts.ramp) |f| f(v) else col;
        bars_mod.stack(c, &.{.{ .value = @max(baseline, v), .color = base.alpha(opacity(slot.index, opts.capacity, opts.fade)) }});
    }
}

/// Where `x` falls between `min` and `peak`, from 0 to 1; null for no
/// reading (not a number, or infinite). A scale with no room between
/// `min` and `peak` puts every reading at 0.
pub fn level(x: f32, min: f32, peak: f32) ?f32 {
    if (!std.math.isFinite(x)) return null;
    const range = peak - min;
    if (!std.math.isFinite(range) or !(range > 0)) return 0;
    return std.math.clamp((x - min) / range, 0, 1);
}

/// Slot `i` of `n`'s opacity: `fade` at the oldest, rising to 1 at the
/// newest; 1 without a fade, or with one slot.
pub fn opacity(i: usize, n: usize, fade: ?f32) f32 {
    const f = fade orelse return 1;
    if (n <= 1) return 1;
    const lo = if (f > 0) @min(f, 1) else 0;
    return lo + (1 - lo) * @as(f32, @floatFromInt(@min(i, n - 1))) / @as(f32, @floatFromInt(n - 1));
}

test {
    _ = @import("trend_tests.zig");
}
