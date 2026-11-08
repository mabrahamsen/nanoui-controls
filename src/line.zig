//! A line chart: one or more histories drawn as lines, oldest on the
//! left, each optionally filled under as an area, on a scale that rises
//! to their peak. A reading that is not a number breaks its line. Drawn
//! with `ui.canvas`.
//!
//!     var l = controls.line(c, &.{ .{ .values = read, .area = 0.15 }, .{ .values = write, .color = t.success } }, .{
//!         .capacity = 60,
//!         .max = 10,
//!         .interactive = true,
//!         .label = "Disk",
//!     });
//!     // `current` is a slot: with a history shorter than `capacity`, its
//!     // readings start `capacity - read.len` slots in.
//!     if (l.current) |i| if (i >= 60 - read.len) l.tooltip(c.print("{d:.1} MB/s", .{read[i - (60 - read.len)]}));
//!     l.end();
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const chart = @import("chart.zig");
const trend_mod = @import("trend.zig");

/// One line of the chart.
pub const Series = struct {
    /// The readings, oldest first from `head`, as a trend's.
    values: []const f32,
    head: usize = 0,
    /// Null takes the theme's accent.
    color: ?ui.Color = null,
    /// The opacity of the area under the line, in its color; 0 fills none.
    area: f32 = 0,
};

pub const Options = struct {
    /// How many readings across: a history's length when full. A shorter
    /// history starts further right.
    capacity: usize,
    /// The parent's width by default; in a row, the room the rest leaves.
    width: ui.Length = .fill,
    height: ui.Length = .{ .px = 64 },
    /// The value at the bottom, and at the top unless a reading goes
    /// higher, as a trend's.
    min: f32 = 0,
    max: f32 = 1,
    fixed_max: bool = false,
    line_width: f32 = 1.5,
    /// Lines across at these values, behind the lines.
    value_lines: []const chart.ValueLine = &.{},
    /// The value lines' labels in a gutter at the chart's start or end,
    /// as `bars`' axis.
    axis: chart.Axis = .none,
    /// Under the chart at its two ends, as `bars`' ("-60 s", "now").
    start_text: []const u8 = "",
    end_text: []const u8 = "",
    /// The user can point at a reading, or take the keyboard and move
    /// from one to the next with Left and Right, as `bars`: `Line.current`
    /// is its index in the slots, and the chart marks it.
    interactive: bool = false,
    /// What a screen reader calls the chart and says it shows, as `bars`.
    label: []const u8 = "",
    value_text: []const u8 = "",
    /// Multiplies the chart's lengths, as `bars`.
    scale: f32 = 1,
};

/// Draws `series` and returns the chart, open for a tooltip: `end` it.
pub fn line(c: *ui.Context, series: []const Series, opts: Options) Line {
    const t = kit.tokens(c);
    const k = opts.scale;
    var peak = opts.max;
    if (!opts.fixed_max) for (series) |s| {
        for (0..@min(s.values.len, opts.capacity)) |j| {
            const v = reading(s, opts.capacity, opts.capacity - @min(s.values.len, opts.capacity) + j) orelse continue;
            peak = @max(peak, v);
        }
    };
    const pad = inset(opts);
    const frame: chart.Frame = .open(c, opts.width, .{ .axis = opts.axis, .lines = opts.value_lines, .lo = opts.min, .hi = peak, .top = pad, .start_text = opts.start_text, .end_text = opts.end_text, .scale = k }, opts.height != .px);
    const box = ui.div(c);
    frame.size(c, box.index, opts.width, opts.height);
    const in: chart.Inspect = if (opts.interactive) .begin(c, box.index, opts.capacity, true) else .{};
    // The value lines first, so the canvas draws over them.
    if (opts.value_lines.len > 0) {
        const lines_h = switch (opts.height) {
            .px => |v| v * k,
            else => if (chart.lastSize(c, box.index)) |sz| sz.h else 0,
        };
        chart.valueLines(c, opts.value_lines, lines_h, pad, opts.min, peak, opts.axis == .none);
    }
    const cv = ui.canvas(c, .{ .absolute = true, .width = .fill, .height = .fill });
    const w = cv.size.w;
    const h = cv.size.h;
    const n = opts.capacity;
    const at = struct {
        fn x(i: usize, count: usize, width: f32, p: f32) f32 {
            return p + (if (count <= 1) 1 else @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(count - 1))) * (width - 2 * p);
        }
        fn y(f: f32, height: f32, p: f32) f32 {
            return p + (1 - f) * (height - p);
        }
    };
    if (w > 0 and h > 0) for (series) |s| {
        const col = s.color orelse t.primary;
        // Each run of readings, between breaks, as a line and its area.
        var pts: std.ArrayList(ui.Point) = .empty;
        var i: usize = n - @min(s.values.len, n);
        while (i <= n) : (i += 1) {
            const v = if (i < n) reading(s, n, i) else null;
            if (v) |r| {
                const f = trend_mod.level(r, opts.min, peak) orelse 0;
                pts.append(c.alloc(), .{ .x = at.x(i, n, w, pad), .y = at.y(f, h, pad) }) catch break;
                continue;
            }
            if (pts.items.len > 0) {
                // The area, two triangles down from each step of the line,
                // only the line's edge smoothed, so they meet without seams.
                if (s.area > 0) for (pts.items[0 .. pts.items.len - 1], pts.items[1..]) |a, b| {
                    const fill = col.alpha(s.area);
                    cv.triangle(a, b, .{ .x = b.x, .y = h }, fill, 1);
                    cv.triangle(a, .{ .x = b.x, .y = h }, .{ .x = a.x, .y = h }, fill, 0);
                };
                if (pts.items.len == 1) cv.circle(pts.items[0], opts.line_width * k, col) else cv.polyline(pts.items, .{ .width = opts.line_width * k, .color = col });
                pts.clearRetainingCapacity();
            }
        }
    };
    // The current reading: a line down through it, and a dot on each series.
    if (in.current) |i| if (w > 0 and h > 0) {
        const x = at.x(i, n, w, pad);
        cv.line(.{ .x = x, .y = 0 }, .{ .x = x, .y = h }, .{ .width = 1, .color = t.muted.alpha(0.6) });
        for (series) |s| {
            const r = reading(s, n, i) orelse continue;
            const f = trend_mod.level(r, opts.min, peak) orelse continue;
            cv.circle(.{ .x = x, .y = at.y(f, h, pad) }, 3.5 * k, t.background);
            cv.circle(.{ .x = x, .y = at.y(f, h, pad) }, 2.5 * k, s.color orelse t.primary);
        }
    };
    return .{ .current = in.current, .focused = in.focused, .c = c, .box = box, .frame = frame, .opts = opts, .inspect = in };
}

/// How far the readings sit in from the chart's sides and top, so the
/// lines, and the dots marking the current reading, aren't cut off there.
fn inset(opts: Options) f32 {
    return (if (opts.interactive) 3.5 else opts.line_width / 2) * opts.scale;
}

/// Series `s`'s reading in slot `i` of `n`, right-aligned; null where it
/// has none, or one that is not a number.
fn reading(s: Series, n: usize, i: usize) ?f32 {
    const shown = @min(s.values.len, n);
    if (i < n - shown or i >= n) return null;
    const skip = s.values.len - shown;
    const v = s.values[(s.head % s.values.len + skip + i - (n - shown)) % s.values.len];
    return if (std.math.isFinite(v)) v else null;
}

pub const Line = struct {
    /// The slot pointed at, or moved to with the keys, with `interactive`.
    current: ?usize,
    /// The chart has the keyboard.
    focused: bool,

    // The rest is the chart's own.
    c: *ui.Context,
    box: ui.Div,
    frame: chart.Frame,
    opts: Options,
    inspect: chart.Inspect,
    tip: []const u8 = "",

    /// Says `text` in a tooltip by the current reading, and to a screen
    /// reader, as `Bars.tooltip`.
    pub fn tooltip(l: *Line, text: []const u8) void {
        l.tip = text;
    }

    /// Ends the chart.
    pub fn end(l: *Line) void {
        const c = l.c;
        const tip = l.current != null and l.tip.len > 0;
        if (tip) if (c.rects.get(c.node(l.box.index).id)) |r| {
            const n = l.opts.capacity;
            const pad = inset(l.opts);
            const x = pad + (if (n <= 1) 1 else @as(f32, @floatFromInt(l.current.?)) / @as(f32, @floatFromInt(n - 1))) * (r.w - 2 * pad);
            l.inspect.tooltip(c, .{ .x = r.x + x - 1, .y = r.y, .w = 2, .h = r.h }, l.tip);
        };
        chart.describe(c, l.box.index, l.opts.label, if (tip) l.tip else l.opts.value_text, l.opts.interactive);
        l.box.end();
        l.frame.close(c);
    }
};

test {
    _ = @import("line_tests.zig");
}
