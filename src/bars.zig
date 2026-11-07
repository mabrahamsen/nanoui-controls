//! Bars: a row of slots, one bar each, the oldest on the left, for a bar
//! chart of any kind. Build the slots with `next`, as a grid's rows, and
//! draw each one's bar of parts with `slot.bar`, or leave it empty.
//! `trend` is a history drawn with them.
//!
//!     var b = controls.bars(c, .{ .count = 60, .height = .{ .px = 64 }, .interactive = true, .label = "Traffic" });
//!     while (b.next()) |slot| {
//!         slot.bar(&.{ .{ .value = read[slot.index], .color = t.primary }, .{ .value = write[slot.index], .color = t.success } });
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
    /// The share of the height below zero, for bars of negative parts (a
    /// loss, a change down); 0 keeps every bar above the bottom.
    below: f32 = 0,
    /// Lines across at shares of the height above zero (0.5 is halfway
    /// up), behind the bars.
    value_lines: []const chart.ValueLine = &.{},
    /// The user can point at a slot, or take the keyboard (a click or Tab)
    /// and move from slot to slot with Left and Right: `Bars.current` is
    /// that slot, and `tooltip` says what it shows.
    interactive: bool = false,
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

/// A slot being built: draw its bar with `bar`, or leave it empty. Its box
/// can be styled.
pub const Slot = struct {
    index: usize,
    box: ui.Div,
    /// It is the slot pointed at, or moved to with the keys.
    current: bool = false,

    // The rest is the slot's own.
    below: f32 = 0,

    /// Draws a bar of `parts` from zero: each part `value` of the slot's
    /// height, positive ones up and, with room `below`, negative ones
    /// down; the first part is nearest zero. Parts that add up to more
    /// than their side's room are squeezed to fit, each keeping its share.
    pub fn bar(s: Slot, parts: []const Part) void {
        const c = s.box.c;
        const down_room = if (s.below > 0) @min(s.below, 1) else 0;
        const up_room = 1 - down_room;
        var up: f32 = 0;
        var down: f32 = 0;
        for (parts) |p| {
            up += chart.partShare(p.value);
            if (down_room > 0) down += chart.partShare(-p.value);
        }
        const up_k = if (up > up_room) up_room / up else 1;
        const down_k = if (down > down_room) down_room / down else 1;
        chart.weighted(ui.div(c).wFull(), up_room - up * up_k).end();
        var i = parts.len;
        while (i > 0) {
            i -= 1;
            const v = chart.partShare(parts[i].value);
            if (v > 0) chart.weighted(ui.div(c).wFull().bg(parts[i].color), v * up_k).end();
        }
        if (down_room == 0) return;
        for (parts) |p| {
            const v = chart.partShare(-p.value);
            if (v > 0) chart.weighted(ui.div(c).wFull().bg(p.color), v * down_k).end();
        }
        chart.weighted(ui.div(c).wFull(), down_room - down * down_k).end();
    }
};

/// Opens a row of `opts.count` slots: build them with `next`, then `end`.
/// What is drawn before the first `next` (absolute) sits behind the bars.
pub fn bars(c: *ui.Context, opts: Options) Bars {
    const k = opts.scale;
    const row = ui.div(c).row().gap(if (opts.gap) |g| g * k else 1);
    const st = &c.node(row.index).style;
    st.width = chart.scaled(opts.width, k);
    st.height = chart.scaled(opts.height, k);
    const in: chart.Inspect = if (opts.interactive) .begin(c, row.index, opts.count, false) else .{};
    if (opts.value_lines.len > 0) {
        const h = switch (opts.height) {
            .px => |v| v * k,
            else => if (chart.lastSize(c, row.index)) |sz| sz.h else 0,
        };
        const below = if (opts.below > 0) @min(opts.below, 1) else 0;
        chart.valueLines(c, opts.value_lines, h, 0, -below, 1 - below);
    }
    return .{ .current = in.current, .focused = in.focused, .c = c, .row = row, .opts = opts, .inspect = in };
}

pub const Bars = struct {
    /// The slot pointed at, or moved to with the keys, with `interactive`.
    current: ?usize,
    /// The chart has the keyboard.
    focused: bool,

    // The rest is the chart's own.
    c: *ui.Context,
    row: ui.Div,
    opts: Options,
    inspect: chart.Inspect,
    next_index: usize = 0,
    open: ?ui.Div = null,
    current_box: ?u32 = null,
    tip: []const u8 = "",

    /// Opens the next slot, ending the one before; null after the last.
    pub fn next(b: *Bars) ?Slot {
        if (b.open) |s| s.end();
        b.open = null;
        if (b.next_index >= b.opts.count) return null;
        const s = ui.div(b.c).column().w(0).grow().hFull();
        b.open = s;
        b.next_index += 1;
        const i = b.next_index - 1;
        if (b.current == i) b.current_box = s.index;
        return .{ .index = i, .box = s, .current = b.current == i, .below = b.opts.below };
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
        chart.describe(c, b.row.index, b.opts.label, if (tip) b.tip else b.opts.value_text, b.opts.interactive);
        b.row.end();
    }
};

test {
    _ = @import("bars_tests.zig");
}
