//! The grid's options checked, and where its columns go: their widths, shared and kept, their order,
//! how far they scroll sideways and which one stays in place, and how wide
//! a cell's contents would be uncut.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const grid_mod = @import("grid.zig");
const Column = grid_mod.Column;
const Options = grid_mod.Options;
const sized = @import("grid_widths.zig").sized;

/// The room a scrolling grid leaves at its right edge for the scrollbar's
/// track, in points as the bar's are, unscaled. Its rows stop short of
/// it: nanoui gives a press to a clickable box under the track rather
/// than to the bar, so a row reaching under it would keep the bar from
/// being dragged or clicked.
pub const scrollbar_gutter = 10;

/// The room left for the scrollbar: none in a grid of a set number of
/// rows, which doesn't scroll.
pub fn gutter(opts: Options) f32 {
    return if (opts.max_rows == null) scrollbar_gutter else 0;
}

/// Panics on options that don't match the columns or the rows.
pub fn check(columns: []const Column, opts: Options) void {
    if (!(opts.scale > 0)) @panic("grid: `scale` needs to be more than 0");
    if (!(rowHeight(opts) > 0)) @panic("grid: `row_height` needs to be more than 0");
    if (opts.groups) |gs| {
        if (gs.count() != opts.count) @panic("grid: `count` needs to be `groups.count()`");
        // Folding changes the rows in view, which `selection`'s flags are.
        if (opts.selection != null) @panic("grid: `selection` doesn't go with `groups`; use `selected`");
    }
    if (opts.hidden) |h| if (h.len != columns.len) @panic("grid: `hidden` needs one flag a column");
    if (opts.widths) |w| if (w.len != columns.len) @panic("grid: `widths` needs one width a column");
    if (opts.selection) |m| {
        if (m.len != opts.count) @panic("grid: `selection` needs one flag a row");
        if (opts.selected == null) @panic("grid: `selection` needs `selected`");
    }
    if (opts.order) |o| {
        if (o.len != columns.len) @panic("grid: `order` needs one column a place");
        for (o, 0..) |col, i| if (col >= columns.len or std.mem.indexOfScalar(usize, o[0..i], col) != null) @panic("grid: `order` needs each column once");
    }
}

/// Column `i` is shown: the caller doesn't hide it, and the window and
/// the grid, `grid_w` wide as last laid out, are wide enough.
pub fn shown(c: *const ui.Context, columns: []const Column, opts: Options, i: usize, grid_w: f32) bool {
    if (opts.hidden) |h| if (h[i]) return false;
    if (grid_w / opts.scale < columns[i].min_grid_width) return false;
    return c.size.w / opts.scale >= columns[i].min_window_width;
}

/// A row's height in points before `scale`: `row_height`, with room for
/// each line past the first.
pub fn rowHeight(opts: Options) f32 {
    return opts.row_height + @as(f32, @floatFromInt(opts.lines -| 1)) * line_room;
}

/// What each line of a cell past the first adds to a row's height.
pub const line_room = 16;

/// The room between rows, in points before `scale`: none with lines
/// between them, which the rows meet, and more between cards.
pub fn rowGap(opts: Options) f32 {
    if (opts.rows == .cards) return @max(opts.gap, 6);
    return if (opts.row_lines) 0 else opts.gap;
}

/// The rows the grid shows: all of them, or with `max_rows`, that many.
pub fn rowsShown(opts: Options) usize {
    return if (opts.max_rows) |n| @min(n, opts.count) else opts.count;
}

/// The grid's `T` between frames, found by a key of its own in the grid's
/// box: the same at the start of `grid` and in `end`, wherever the rows
/// put them. The pointer lasts only until the next state is made, which
/// any widget in a cell may do, so it isn't kept: use it at once.
pub fn state(c: *ui.Context, comptime T: type) *T {
    ui.key(c, "grid-state");
    // Looking a state up doesn't take the key, as a new box would.
    defer c.next_key = null;
    return c.state(T, @typeName(T));
}

/// The columns in this frame, in points as drawn (scaled).
pub const Layout = struct {
    /// The columns in the order they show.
    order: []const usize,
    /// Each column's width; 0 for a hidden one.
    w: []f32,
    /// Where each column's cells start in a row, before scrolling.
    x: []f32,
    /// The width the columns take, with the padding either side.
    content: f32,
    /// The width a row shows.
    view: f32,
    /// Where the grid starts across the window, and how wide it is, as
    /// the last frame laid it out; infinite before it has been.
    left: f32 = 0,
    grid_w: f32 = std.math.inf(f32),
    /// How far the columns are scrolled sideways.
    sx: f32,
    /// The column that stays in place as the others scroll, and where
    /// the others are cut off: past it and the gap after it.
    frozen: ?usize = null,
    clip_x: f32 = 0,

    /// Where column `i`'s cells start in a row as shown.
    pub fn at(l: Layout, i: usize) f32 {
        return if (l.frozen == i) l.x[i] else l.x[i] - l.sx;
    }

    /// The furthest the columns scroll.
    pub fn maxScroll(l: Layout) f32 {
        return @max(0, l.content - l.view);
    }
};

/// Lays the columns out for this frame in `box`, the grid's, as wide as
/// the last frame laid it out, scrolled `sx` and by this frame's wheel.
pub fn layout(c: *ui.Context, columns: []const Column, opts: Options, box: ui.Div, sx: f32) Layout {
    const k = opts.scale;
    const a = c.alloc();
    const order = if (opts.order) |o| o else blk: {
        const o = a.alloc(usize, columns.len) catch @panic("grid: out of memory");
        for (o, 0..) |*x, i| x.* = i;
        break :blk o;
    };
    const w = a.alloc(f32, columns.len) catch @panic("grid: out of memory");
    const x = a.alloc(f32, columns.len) catch @panic("grid: out of memory");
    const box_rect = c.rects.get(c.node(box.index).id);
    const width = if (box_rect) |r| r.w else c.size.w;
    // Before the grid has a width, every column shows.
    const grid_w = if (box_rect) |r| r.w else std.math.inf(f32);
    const unit = flexUnit(c, columns, opts, width, grid_w);
    var at = opts.padding * k;
    var last: ?usize = null;
    var sharing = false;
    var frozen: ?usize = null;
    for (order) |i| {
        if (!shown(c, columns, opts, i, grid_w)) {
            w[i] = 0;
            x[i] = at;
            continue;
        }
        if (last == null and opts.scroll_x and opts.freeze_first) frozen = i;
        last = i;
        sharing = sharing or sized(columns, opts, i) == null;
        w[i] = columnWidth(columns, opts, i, unit);
        x[i] = at;
        at += w[i] + opts.column_gap * k;
    }
    if (last != null) at -= opts.column_gap * k;
    // Columns meant to share the room, none of them sharing it now (sized
    // by hand, or hidden): the last takes what is left, so the rows still
    // span the grid.
    if (last) |j| if (!sharing and spans(columns)) {
        const slack = width - gutter(opts) - opts.padding * k - at;
        if (slack > 0) {
            w[j] += slack;
            at += slack;
        }
    };
    var l: Layout = .{ .order = order, .w = w, .x = x, .content = at + opts.padding * k, .view = width - gutter(opts), .left = if (box_rect) |r| r.x else 0, .grid_w = grid_w, .sx = 0 };
    if (frozen) |f| {
        l.frozen = f;
        l.clip_x = x[f] + w[f] + opts.column_gap * k;
    }
    if (opts.scroll_x) {
        var s = sx;
        if (box_rect) |r| if (r.contains(c.input.mouse)) {
            s -= c.input.scroll.x;
        };
        l.sx = std.math.clamp(s, 0, l.maxScroll());
    }
    return l;
}

/// Some column shares the room by its `flex`, so the columns are meant to
/// span the grid.
fn spans(columns: []const Column) bool {
    for (columns) |col| if (col.width == null) return true;
    return false;
}

/// The width a column without one gets for each unit of its `flex`: the
/// room the others leave in `width`, shared out, with a column whose share
/// would be under its `min_width` held at that and the rest shared again.
/// The width is the grid's as the last frame laid it out; when it
/// changed, another frame is drawn with the new one.
fn flexUnit(c: *ui.Context, columns: []const Column, opts: Options, width: f32, grid_w: f32) f32 {
    const k = opts.scale;
    const last = c.state(struct { width: f32 = 0 }, "grid-width");
    if (last.width != width) {
        last.width = width;
        c.frameIn(0);
    }
    var room = width - 2 * opts.padding * k - gutter(opts);
    var shown_count: f32 = 0;
    for (0..columns.len) |i| {
        if (!shown(c, columns, opts, i, grid_w)) continue;
        shown_count += 1;
        if (sized(columns, opts, i) != null) room -= columnWidth(columns, opts, i, 0);
    }
    room -= @max(0, shown_count - 1) * opts.column_gap * k;
    var unit: f32 = 0;
    // Each pass holds more columns at their minimum, and at most every
    // column is held.
    for (0..columns.len + 1) |_| {
        var left = room;
        var flex: f32 = 0;
        for (columns, 0..) |col, i| {
            if (!shown(c, columns, opts, i, grid_w) or sized(columns, opts, i) != null) continue;
            if (col.flex * unit < col.min_width * k and unit > 0) left -= col.min_width * k else flex += col.flex;
        }
        const next = if (flex > 0) @max(0, left / flex) else 0;
        if (next == unit) break;
        unit = next;
    }
    return unit;
}

/// Column `i`'s width in this frame, scaled: the caller's, its own, or
/// its share of the room left at `unit` a flex.
fn columnWidth(columns: []const Column, opts: Options, i: usize, unit: f32) f32 {
    const col = columns[i];
    const k = opts.scale;
    if (sized(columns, opts, i)) |w| return w * k;
    return @max(col.min_width * k, col.flex * unit);
}

/// How wide box `index`'s contents would be, uncut: its texts' widths as
/// set, its icons' sizes, its boxes' fixed widths or theirs in turn, and
/// the gaps and padding between them; in a column, the widest of them.
/// A box placed absolutely takes no room among them.
pub fn natural(c: *ui.Context, index: u32) f32 {
    const n = c.node(index);
    const across = n.style.direction == .row;
    var w: f32 = 0;
    var count: f32 = 0;
    var child = n.first_child;
    // nanoui's "no box" in its tree, which it doesn't export.
    while (child != std.math.maxInt(u32)) : (child = c.node(child).next) {
        const ch = c.node(child);
        if (ch.style.absolute) continue;
        count += 1;
        const cw = switch (ch.content) {
            .text => |t| c.text.width(t.str, t.style),
            // Without a frame, an icon is as wide as its size.
            .icon => |ic| switch (ch.style.width) {
                .px => |px| px,
                else => ic.size,
            },
            else => switch (ch.style.width) {
                .px => |px| px,
                else => natural(c, child),
            },
        };
        w = if (across) w + cw else @max(w, cw);
    }
    const gaps = if (across) n.style.gap * @max(0, count - 1) else 0;
    return w + gaps + n.style.padding.horizontal();
}

/// The sideways scrollbar's thumb being dragged: where the pointer and
/// the scroll started.
const BarDrag = struct { on: bool = false, x: f32 = 0, sx: f32 = 0 };

/// A bar under the rows, its thumb as wide as the share of the columns in
/// view, dragged to scroll them sideways: changes `l.sx`.
pub fn sideBar(c: *ui.Context, opts: Options, l: *Layout) void {
    const k = opts.scale;
    const t = kit.tokens(c);
    const track = ui.div(c).wFull().h(10 * k).pr(gutter(opts));
    defer track.end();
    const thumb_w = @max(24 * k, l.view * l.view / l.content);
    const travel = @max(1, l.view - thumb_w);
    const drag = state(c, BarDrag);
    const thumb = ui.div(c).absolute().offset(l.sx / l.maxScroll() * travel, 2 * k).w(thumb_w).h(6 * k).rounded(3 * k).bg(t.muted.alpha(0.45)).control();
    defer thumb.end();
    const it = thumb.interaction();
    if (!it.pressed) {
        drag.on = false;
        return;
    }
    if (!drag.on) {
        drag.* = .{ .on = true, .x = c.input.mouse.x, .sx = l.sx };
        return;
    }
    l.sx = std.math.clamp(drag.sx + (c.input.mouse.x - drag.x) / travel * l.maxScroll(), 0, l.maxScroll());
    c.changed = true;
}
