//! A trend: a history drawn as bars, oldest first, scaled to its peak,
//! the older bars fainter. A CPU's load, a temperature, traffic over the
//! last minute. The caller keeps the history, in a slice or a ring, and
//! adds a reading to it each time one comes.
//!
//!     controls.trend(c, temps, .{ .capacity = 60, .min = 20, .max = 110, .label = "Temperature", .value_text = "62 °C" });
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const chart = @import("chart.zig");
const bars_mod = @import("bars.zig");

pub const Options = struct {
    /// How many slots: the history's length when full. A shorter history
    /// leaves the oldest slots, on the left, empty.
    capacity: usize,
    /// Where the oldest reading is in `values`, for a history kept in a
    /// ring that wraps around its end; 0 for one kept in order.
    head: usize = 0,
    /// The parent's width by default; in a row, the room the rest leaves.
    width: ui.Length = .fill,
    height: ui.Length = .{ .px = 16 },
    /// Between the bars; null keeps a hairline of one point at any scale.
    gap: ?f32 = null,
    /// Every bar's color; null takes the theme's accent.
    color: ?ui.Color = null,
    /// Colors from the bottom to the top, blended between: a bar takes
    /// the color at its height, such as from cool to hot. Takes over from
    /// `color`.
    ramp: []const ui.Color = &.{},
    /// The value at the bottom.
    min: f32 = 0,
    /// The value at the top. A history that goes higher raises the top to
    /// its peak, so a quiet history doesn't fill the chart and a loud one
    /// isn't cut off, unless `fixed_max`.
    max: f32 = 1,
    /// The top stays at `max`, and readings above it are drawn full.
    fixed_max: bool = false,
    /// The shortest bar, as a share of the height, so a reading at `min`
    /// still shows as a line.
    baseline: f32 = 0.03,
    /// The oldest bar's opacity, rising to 1 at the newest; null keeps
    /// every bar opaque.
    fade: ?f32 = 0.35,
    /// Lines across at these values, behind the bars.
    value_lines: []const chart.ValueLine = &.{},
    /// What a screen reader calls the chart, and says it shows, as `bars`.
    label: []const u8 = "",
    value_text: []const u8 = "",
    /// Multiplies the chart's lengths, as `bars`.
    scale: f32 = 1,
};

/// Draws `values`, oldest first (from `head`), as a bar each,
/// right-aligned in `capacity` slots; with more values than slots, the
/// newest. A value that is not a number or is infinite is no reading: its
/// slot stays empty, and it doesn't count toward the peak.
pub fn trend(c: *ui.Context, values: []const f32, opts: Options) void {
    const col = opts.color orelse kit.tokens(c).primary;
    const shown = @min(values.len, opts.capacity);
    const skip = values.len - shown;
    const head = if (values.len > 0) opts.head % values.len else 0;
    var peak = opts.max;
    if (!opts.fixed_max) for (0..shown) |i| {
        const v = values[(head + skip + i) % values.len];
        if (std.math.isFinite(v)) peak = @max(peak, v);
    };
    const empty = opts.capacity - shown;
    const baseline = if (opts.baseline > 0) @min(opts.baseline, 1) else 0;
    var b = bars_mod.bars(c, .{
        .count = opts.capacity,
        .width = opts.width,
        .height = opts.height,
        .gap = opts.gap,
        .label = opts.label,
        .value_text = opts.value_text,
        .scale = opts.scale,
    });
    if (opts.value_lines.len > 0) chart.valueLines(c, opts.value_lines, chart.linesHeight(c, opts.height, opts.scale, b.row.index), 0, opts.min, peak, true);
    defer b.end();
    while (b.next()) |slot| {
        if (slot.index < empty) continue;
        const v = chart.level(chart.slotReading(values, opts.head, opts.capacity, slot.index) orelse continue, opts.min, peak) orelse continue;
        const base = if (opts.ramp.len > 0) chart.rampColor(opts.ramp, v) else col;
        slot.bar(&.{.{ .value = @max(baseline, v), .color = base.alpha(opacity(slot.index, opts.capacity, opts.fade)) }});
    }
}

/// Where `x` falls between `min` and `peak`, as the charts share it.
pub const level = chart.level;

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
