//! Bars: a row of slots, one bar each, the oldest on the left, for a bar
//! chart of any kind. Build the slots with `next`, as a grid's rows, and
//! draw each one's bar with `stack`, or leave it empty. `trend` is a
//! history drawn with them.
//!
//!     var b = controls.bars(c, .{ .count = 60, .height = .{ .px = 64 }, .hover = true });
//!     while (b.next()) |slot| {
//!         if (slot.hovered) _ = slot.box.bg(t.surface_hover);
//!         controls.stack(c, &.{ .{ .value = read[slot.index], .color = cyan }, .{ .value = write[slot.index], .color = violet } });
//!     }
//!     b.end();
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

/// One part of a bar: `value` its share, and its color. A part that is
/// negative or not a number counts as 0.
pub const Part = struct {
    value: f32,
    color: ui.Color,
};

/// Draws a bar of `parts` from the bottom up, filling the box it is in:
/// each part `value` of the box's height (0 to 1), and what they leave
/// empty. Parts that add up to more than 1 are squeezed to fit, each
/// keeping its share.
pub fn stack(c: *ui.Context, parts: []const Part) void {
    var used: f32 = 0;
    for (parts) |p| used += partShare(p.value);
    weighted(ui.div(c).wFull(), 1 - @min(1, used)).end();
    var i = parts.len;
    while (i > 0) {
        i -= 1;
        weighted(ui.div(c).wFull().bg(parts[i].color), partShare(parts[i].value)).end();
    }
}

/// A part's share: 0 for one negative or not a number.
pub fn partShare(v: f32) f32 {
    return if (std.math.isFinite(v) and v > 0) v else 0;
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

pub const Options = struct {
    /// How many slots: a bar each, or room for one.
    count: usize,
    /// The parent's width by default; in a row, the room the rest leaves.
    width: ui.Length = .fill,
    height: ui.Length = .{ .px = 26 },
    /// Between the slots; null keeps a hairline of one point at any scale.
    gap: ?f32 = null,
    /// Follows the pointer: `Bars.hovered` is the slot under it.
    hover: bool = false,
    /// What a screen reader calls the chart ("CPU history"); empty leaves
    /// it out, as a decoration.
    label: []const u8 = "",
    /// What a screen reader says it shows ("62 °C, peak 81 °C").
    value: []const u8 = "",
    /// Multiplies the chart's lengths, for an app that zooms its layout
    /// along with `c.setZoom`, which zooms text. The kit sizes its
    /// controls with a `kit.Size`, but has no sizes for a chart.
    scale: f32 = 1,
};

/// A slot being built: draw its bar with `stack`, or leave it empty. Its
/// box can be styled, such as a highlight under the pointer.
pub const Slot = struct {
    index: usize,
    box: ui.Div,
    /// It is under the pointer, with `hover`.
    hovered: bool = false,
};

/// Opens a row of `opts.count` slots: build them with `next`, then `end`.
/// What is drawn before the first `next` (grid lines, absolute) sits
/// behind the bars.
pub fn bars(c: *ui.Context, opts: Options) Bars {
    const k = opts.scale;
    const row = ui.div(c).row().gap(if (opts.gap) |g| g * k else 1);
    const st = &c.node(row.index).style;
    st.width = scaled(opts.width, k);
    st.height = scaled(opts.height, k);
    if (opts.label.len > 0) ui.access.describe(c, row.index, .{ .role = .image, .label = opts.label, .value = opts.value });
    return .{ .hovered = if (opts.hover) hoveredSlot(c, row, opts.count) else null, .c = c, .row = row, .count = opts.count };
}

/// The slot under the pointer, as the row was laid out last frame. The
/// row follows the pointer while it is over it, and keeps the arrow: it
/// isn't clicked.
fn hoveredSlot(c: *ui.Context, row: ui.Div, count: usize) ?usize {
    const it = row.interaction();
    if (!it.hovered) return null;
    c.wants_moves = true;
    c.cursor_hand = false;
    const r = it.rect orelse return null;
    if (!(r.w > 0) or count == 0) return null;
    const n: f32 = @floatFromInt(count);
    return @intFromFloat(std.math.clamp((c.input.mouse.x - r.x) / r.w * n, 0, n - 1));
}

pub const Bars = struct {
    /// The slot under the pointer, with `hover`.
    hovered: ?usize,

    // The rest is the chart's own.
    c: *ui.Context,
    row: ui.Div,
    count: usize,
    next_index: usize = 0,
    open: ?ui.Div = null,

    /// Opens the next slot, ending the one before; null after the last.
    pub fn next(b: *Bars) ?Slot {
        if (b.open) |s| s.end();
        b.open = null;
        if (b.next_index >= b.count) return null;
        const s = ui.div(b.c).column().w(0).grow().hFull();
        b.open = s;
        b.next_index += 1;
        const i = b.next_index - 1;
        return .{ .index = i, .box = s, .hovered = b.hovered == i };
    }

    /// Ends the last slot and the row.
    pub fn end(b: *Bars) void {
        if (b.open) |s| s.end();
        b.open = null;
        b.row.end();
    }
};

const Color = ui.Color;
const cyan: Color = .hex(0x22d3ee);
const violet: Color = .hex(0xa78bfa);

/// The heights of a stack's colored parts in a box 100 points tall, from
/// the top.
fn heights(parts: []const Part) ![4]f32 {
    const T = struct {
        var ps: []const Part = &.{};
        fn view(_: *@This(), c: *ui.Context) void {
            const box = ui.div(c).column().w(40).h(100);
            defer box.end();
            stack(c, ps);
        }
    };
    T.ps = parts;
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 100, .height = 120 });
    defer t.deinit();
    t.settle(1);
    var out: [4]f32 = @splat(0);
    var n: usize = 0;
    // The first box is the window's.
    for (t.ctx.nodes.items[1..]) |node| {
        if (node.style.background == null) continue;
        out[n] = t.ctx.rects.get(node.id).?.h;
        n += 1;
    }
    return out;
}

test "a stack's parts take their share of the box from the bottom" {
    // Drawn from the top: the last part first.
    const h = try heights(&.{ .{ .value = 0.5, .color = cyan }, .{ .value = 0.25, .color = violet } });
    try std.testing.expectEqualSlices(f32, &.{ 25, 50, 0, 0 }, &h);
}

test "a stack counts bad parts as nothing, and squeezes parts over 1 to fit" {
    const bad = try heights(&.{ .{ .value = std.math.nan(f32), .color = cyan }, .{ .value = 0.4, .color = violet }, .{ .value = -1, .color = cyan } });
    try std.testing.expectEqualSlices(f32, &.{ 0, 40, 0, 0 }, &bad);
    const over = try heights(&.{ .{ .value = 0.9, .color = cyan }, .{ .value = 0.9, .color = violet } });
    try std.testing.expectEqualSlices(f32, &.{ 50, 50, 0, 0 }, &over);
    const inf = try heights(&.{.{ .value = std.math.inf(f32), .color = cyan }});
    try std.testing.expectEqualSlices(f32, &.{ 0, 0, 0, 0 }, &inf);
}

const Hover = struct {
    hovered: ?usize = null,
    slot_hovered: ?usize = null,
    built: usize = 0,
    fn view(h: *Hover, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        var b = bars(c, .{ .count = 10, .height = .{ .px = 40 }, .gap = 0, .hover = true });
        h.hovered = b.hovered;
        h.slot_hovered = null;
        h.built = 0;
        while (b.next()) |slot| {
            h.built += 1;
            if (slot.hovered) h.slot_hovered = slot.index;
        }
        b.end();
    }
};

test "bars build a slot each" {
    var h: Hover = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&h, Hover.view), .{ .width = 300, .height = 100 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 10), h.built);
}

test "bars follow the pointer: the slot under it, none off it" {
    var h: Hover = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&h, Hover.view), .{ .width = 300, .height = 100 });
    defer t.deinit();
    t.settle(1);
    // Ten slots of 30 points: 95 is in the fourth.
    t.moveTo(95, 20);
    t.frame();
    try std.testing.expectEqual(@as(?usize, 3), h.hovered);
    try std.testing.expectEqual(@as(?usize, 3), h.slot_hovered);
    try std.testing.expect(t.ctx.wants_moves and !t.ctx.cursor_hand);
    t.moveTo(299, 20);
    t.frame();
    try std.testing.expectEqual(@as(?usize, 9), h.hovered);
    // Below the bars: none.
    t.moveTo(95, 80);
    t.frame();
    try std.testing.expectEqual(@as(?usize, null), h.hovered);
    try std.testing.expectEqual(@as(?usize, null), h.slot_hovered);
}

test "bars with nothing to show draw nothing, and don't fail" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            var b = bars(c, .{ .count = 0, .hover = true });
            while (b.next()) |_| unreachable;
            b.end();
            stack(c, &.{});
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 200, .height = 60 });
    defer t.deinit();
    t.settle(1);
    t.moveTo(10, 10);
    t.frame();
}

test "bars with a label are one image to a screen reader, with its value" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            var b = bars(c, .{ .count = 3, .label = "Traffic", .value = "2.4 MB/s" });
            while (b.next()) |_| stack(c, &.{.{ .value = 0.5, .color = cyan }});
            b.end();
            // Without a label, a decoration: nothing to read.
            var d = bars(c, .{ .count = 3 });
            while (d.next()) |_| stack(c, &.{.{ .value = 0.5, .color = cyan }});
            d.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 100 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqual(ui.access.Role.image, list.items[0].role);
    try std.testing.expectEqualStrings("Traffic", list.items[0].label);
    try std.testing.expectEqualStrings("2.4 MB/s", list.items[0].value);
}
