//! Bars: a row of slots, one bar each, the oldest on the left, for a bar
//! chart of any kind. Build the slots with `next`, as a grid's rows, and
//! draw each one's bar of parts with `slot.bar`, or leave it empty.
//! `trend` is a history drawn with them.
//!
//! Parts are shares of the height, or with `max`, values in units on a
//! scale from `min` that grows to the tallest bar. With `readings`, a
//! history shorter than the slots sits at the right. An `axis` puts the
//! value lines' labels beside the chart, and `start_text` and `end_text`
//! go under it ("-60 s", "now").
//!
//!     var b = controls.bars(c, .{ .count = 60, .max = 10, .readings = read.len, .height = .{ .px = 64 }, .interactive = true, .label = "Traffic" });
//!     while (b.next()) |slot| {
//!         const i = slot.reading.?;
//!         slot.bar(&.{ .{ .value = read[i], .color = t.primary }, .{ .value = write[i], .color = t.success } });
//!     }
//!     if (b.current) |i| b.tooltip(c.print("{d:.1} MB/s", .{read[i] + write[i]}));
//!     b.end();
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const chart = @import("chart.zig");

pub const Part = chart.Part;

pub const Options = struct {
    /// How many slots: a bar each, or room for one.
    count: usize,
    /// The parent's width by default; in a row, the room the rest leaves.
    width: ui.Length = .fill,
    height: ui.Length = .{ .px = 26 },
    /// Between the slots; null keeps a hairline of one point at any scale.
    gap: ?f32 = null,
    /// With `max`, the parts are in units, on a scale from `min` at the
    /// bottom to `max` at the top: a bar of 40 on a scale of 0 to 100 is
    /// 40% of the height. Unless `fixed_max`, the top rises to the tallest
    /// bar, its parts stacked, so none is cut off. A `min` below zero
    /// leaves that room below zero for negative parts; one above zero
    /// starts the bars there. Null: parts are shares of the height.
    min: f32 = 0,
    max: ?f32 = null,
    fixed_max: bool = false,
    /// Without `max`: the share of the height below zero, for bars of
    /// negative parts (a loss, a change down); 0 keeps every bar above
    /// the bottom.
    below: f32 = 0,
    /// Lines across at values on the scale (shares of the height above
    /// zero without `max`: 0.5 is halfway up), behind the bars.
    value_lines: []const chart.ValueLine = &.{},
    /// How many readings there are, for a history shorter than the slots:
    /// they sit in the slots at the right, the newest last, and the slots
    /// on the left stay empty. `next` gives only the slots with one, and
    /// `Slot.reading` says which. Null: every slot is the caller's.
    readings: ?usize = null,
    /// The value lines' labels in a gutter at the chart's start or end,
    /// level with their lines, instead of inside the chart.
    axis: chart.Axis = .none,
    /// Under the chart at its two ends, in muted text ("-60 s", "now").
    start_text: []const u8 = "",
    end_text: []const u8 = "",
    /// The user can point at a slot, or take the keyboard (a click or Tab)
    /// and move from slot to slot with Left and Right: `Bars.current` is
    /// that slot, and `tooltip` says what it shows.
    interactive: bool = false,
    /// What a screen reader calls an interactive chart without a `label`.
    chart_text: []const u8 = "Chart",
    /// What a screen reader calls the chart ("Traffic"); empty leaves it
    /// out, as a decoration.
    label: []const u8 = "",
    /// What a screen reader says it shows ("2.4 MB/s, peak 9.1 MB/s"),
    /// unless a slot is current: then its tooltip.
    value_text: []const u8 = "",
    /// Multiplies the chart's lengths, for an app that zooms its layout
    /// along with `c.setZoom`, which zooms text. The kit sizes its
    /// controls with a `kit.Size`, but has no sizes for a chart.
    scale: f32 = 1,
};

/// The chart's scale this frame: the values at its bottom and top, where
/// bars start from, and whether bars taller than it are squeezed to fit.
const Scale = struct {
    lo: f32,
    hi: f32,
    base: f32,
    squeeze: bool,

    fn of(opts: Options, peak: f32) Scale {
        if (opts.max) |m| {
            const hi = if (opts.fixed_max) m else @max(m, peak);
            return .{ .lo = opts.min, .hi = hi, .base = @max(opts.min, 0), .squeeze = opts.fixed_max };
        }
        const below = if (opts.below > 0) @min(opts.below, 1) else 0;
        return .{ .lo = -below, .hi = 1 - below, .base = 0, .squeeze = true };
    }
};

/// A slot being built: draw its bar with `bar`, or leave it empty. Its box
/// can be styled.
pub const Slot = struct {
    index: usize,
    /// With `Options.readings`, the reading in this slot, from 0 for the
    /// oldest.
    reading: ?usize = null,
    box: ui.Div,
    /// It is the slot pointed at, or moved to with the keys.
    current: bool = false,

    // The rest is the slot's own.
    scale: Scale,
    /// The tallest bar so far this frame, in units.
    peak: *f32,

    /// Draws a bar of `parts` from zero (or from `min` above it): on the
    /// chart's scale, positive ones up and, with room below zero, negative
    /// ones down; the first part is nearest zero. On a fixed scale, parts
    /// that add up to more than their side's room are squeezed to fit,
    /// each keeping its share.
    pub fn bar(s: Slot, parts: []const Part) void {
        const c = s.box.c;
        const sc = s.scale;
        const range = sc.hi - sc.lo;
        if (!(range > 0)) return;
        const up_room = (sc.hi - sc.base) / range;
        const down_room = (sc.base - sc.lo) / range;
        const ups = c.alloc().alloc(f32, parts.len) catch return;
        var up: f32 = 0;
        var down: f32 = 0;
        var total: f32 = 0;
        // Above zero, a scale that starts higher takes its start off the
        // bars, from the part nearest it.
        var skip = @max(sc.base, 0);
        for (parts, ups) |p, *u| {
            const v = chart.partShare(p.value);
            total += v;
            const cut = @min(v, skip);
            skip -= cut;
            u.* = (v - cut) / range;
            up += u.*;
            if (down_room > 0) down += chart.partShare(-p.value) / range;
        }
        s.peak.* = @max(s.peak.*, total);
        const up_k = if (up > up_room and (sc.squeeze or up_room <= 0)) (if (up > 0) up_room / up else 1) else 1;
        const down_k = if (down > down_room) down_room / down else 1;
        chart.weighted(ui.div(c).wFull(), @max(0, up_room - up * up_k)).end();
        var i = parts.len;
        while (i > 0) {
            i -= 1;
            if (ups[i] > 0) chart.weighted(ui.div(c).wFull().bg(parts[i].color), ups[i] * up_k).end();
        }
        if (down_room == 0) return;
        for (parts) |p| {
            const v = chart.partShare(-p.value) / range;
            if (v > 0) chart.weighted(ui.div(c).wFull().bg(p.color), v * down_k).end();
        }
        chart.weighted(ui.div(c).wFull(), @max(0, down_room - down * down_k)).end();
    }
};

/// What the chart keeps between frames: its tallest bar, in units, which
/// the scale rises to.
const Kept = struct { peak: f32 = 0 };

fn kept(c: *ui.Context) *Kept {
    ui.key(c, "bars-state");
    defer c.next_key = null;
    return c.state(Kept, "bars");
}

/// Opens a row of `opts.count` slots: build them with `next`, then `end`.
/// What is drawn before the first `next` (absolute) sits behind the bars.
pub fn bars(c: *ui.Context, opts: Options) Bars {
    const k = opts.scale;
    const empty = if (opts.readings) |r| opts.count - @min(r, opts.count) else 0;
    // The scale is known before the row, for the frame's axis: the tallest
    // bar is the last frame's, kept by the frame around the chart.
    const framed = opts.axis != .none or opts.start_text.len > 0 or opts.end_text.len > 0;
    const holder = ui.div(c).column();
    c.node(holder.index).style.width = chart.scaled(opts.width, k);
    // As tall as the chart, unless its frame adds texts under it.
    if (!(framed and opts.height == .px)) c.node(holder.index).style.height = chart.scaled(opts.height, k);
    const peak = kept(c).peak;
    const sc = Scale.of(opts, peak);
    const frame: chart.Frame = .open(c, .fill, .{ .axis = opts.axis, .lines = opts.value_lines, .lo = sc.lo, .hi = sc.hi, .start_text = opts.start_text, .end_text = opts.end_text, .scale = k }, opts.height != .px);
    const row = ui.div(c).row().gap(if (opts.gap) |g| g * k else 1);
    frame.size(c, row.index, .fill, if (framed) opts.height else .fill);
    const in: chart.Inspect = if (opts.interactive) .beginFrom(c, row.index, opts.count, empty, false) else .{};
    if (opts.value_lines.len > 0) {
        chart.valueLines(c, opts.value_lines, chart.linesHeight(c, opts.height, k, row.index), 0, sc.lo, sc.hi, opts.axis == .none);
    }
    const current = if (in.current) |s| (if (opts.readings != null) s - empty else s) else null;
    return .{ .current = current, .focused = in.focused, .c = c, .holder = holder, .frame = frame, .row = row, .opts = opts, .inspect = in, .scale = sc, .empty = empty, .current_slot = in.current, .last_peak = peak };
}

pub const Bars = struct {
    /// The slot pointed at, or moved to with the keys, with `interactive`;
    /// with `readings`, the reading in it.
    current: ?usize,
    /// The chart has the keyboard.
    focused: bool,

    // The rest is the chart's own.
    c: *ui.Context,
    holder: ui.Div,
    frame: chart.Frame,
    row: ui.Div,
    opts: Options,
    inspect: chart.Inspect,
    scale: Scale,
    /// The slots on the left without a reading.
    empty: usize,
    current_slot: ?usize,
    /// The tallest bar the last frame, and so far this one.
    last_peak: f32,
    peak: f32 = 0,
    next_index: usize = 0,
    open: ?ui.Div = null,
    current_box: ?u32 = null,
    tip: []const u8 = "",

    /// Opens the next slot, ending the one before; null after the last.
    pub fn next(b: *Bars) ?Slot {
        if (b.open) |s| s.end();
        b.open = null;
        // The empty slots before the readings take their room.
        while (b.next_index < b.empty) : (b.next_index += 1) ui.div(b.c).column().w(0).grow().hFull().end();
        if (b.next_index >= b.opts.count) return null;
        const s = ui.div(b.c).column().w(0).grow().hFull();
        b.open = s;
        b.next_index += 1;
        const i = b.next_index - 1;
        if (b.current_slot == i) b.current_box = s.index;
        return .{
            .index = i,
            .reading = if (b.opts.readings != null) i - b.empty else null,
            .box = s,
            .current = b.current_slot == i,
            .scale = b.scale,
            .peak = &b.peak,
        };
    }

    /// Says `text` in a tooltip over the current slot, and to a screen
    /// reader: what it shows ("Tuesday: 2.4 MB/s").
    pub fn tooltip(b: *Bars, text: []const u8) void {
        b.tip = text;
    }

    /// Ends the last slot and the row.
    pub fn end(b: *Bars) void {
        if (b.open) |s| s.end();
        b.open = null;
        const c = b.c;
        const tip = b.current != null and b.tip.len > 0;
        if (tip) if (b.current_box) |i| b.inspect.tooltip(c, c.rects.get(c.node(i).id), b.tip);
        chart.describe(c, b.row.index, b.opts.label, if (tip) b.tip else b.opts.value_text, b.opts.interactive, b.opts.chart_text);
        b.row.end();
        b.frame.close(c);
        // A new tallest bar on a scale that rises: draw again with it.
        if (b.opts.max != null and !b.opts.fixed_max and b.peak != b.last_peak) {
            kept(c).peak = b.peak;
            c.frameIn(0);
        }
        b.holder.end();
    }
};

test {
    _ = @import("bars_tests.zig");
}
