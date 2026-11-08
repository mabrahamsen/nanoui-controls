//! The grid's header: the column titles in their order, which sort when
//! clicked and move when dragged, and the edges between them, which
//! resize a column when dragged and fit it when double-clicked.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const grid_mod = @import("grid.zig");
const Column = grid_mod.Column;
const Options = grid_mod.Options;
const lay_mod = @import("grid_layout.zig");
const Layout = lay_mod.Layout;
const shown = lay_mod.shown;

/// What happened in the header this frame.
pub const Head = struct {
    /// A click changed the sort.
    sorted: bool = false,
    /// The column a double-click on an edge fits to its contents, and its
    /// title's width.
    fit: ?usize = null,
    fit_w: f32 = 0,
};

/// A title being dragged to move its column: which, where the pointer
/// went down, and whether it has moved far enough to be a drag.
const Reorder = struct { col: ?usize = null, x: f32 = 0, moved: bool = false };

/// Draws the titles and the edges between them. A frozen column's title
/// stays in place; the others are cut off past it and scroll with the
/// rows.
pub fn header(c: *ui.Context, columns: []const Column, opts: Options, l: Layout) Head {
    const k = opts.scale;
    var head: Head = .{};
    var drag = lay_mod.state(c, Reorder).*;
    const titles = c.alloc().alloc(u32, columns.len) catch @panic("grid: out of memory");
    {
        const outer = ui.div(c).row().wFull().itemsCenter().pb(6 * k);
        defer outer.end();
        var before: ?usize = null;
        if (l.frozen) |f| {
            const fixed = ui.div(c).row().itemsCenter().pl(l.x[f]);
            defer fixed.end();
            titles[f] = title(c, columns, opts, l, f, &drag, &head);
            before = f;
            // The edge after it, which stays with it.
            if (nextShown(c, columns, opts, l, f)) |b| edge(c, columns, opts, f, b, opts.column_lines or l.sx > 0, &head);
        }
        // The rest, cut off past the frozen column and scrolled.
        const cut = ui.div(c).row().grow().clip();
        defer cut.end();
        var inner = ui.div(c).row().itemsCenter().offset(-l.sx, 0).pr(opts.padding * k + lay_mod.gutter(opts));
        if (l.frozen == null) inner = inner.pl(opts.padding * k);
        defer inner.end();
        for (l.order) |i| {
            if (i == l.frozen or !shown(c, columns, opts, i, l.grid_w)) continue;
            if (before) |b| if (b != l.frozen) edge(c, columns, opts, b, i, opts.column_lines, &head);
            before = i;
            titles[i] = title(c, columns, opts, l, i, &drag, &head);
        }
        if (drag.col != null and drag.moved) dropLine(c, columns, opts, l, drag.col.?);
    }
    if (head.fit) |f| head.fit_w = lay_mod.natural(c, titles[f]);
    // A drag let go: the column moves where it was dropped.
    if (drag.col) |dragged| if (!c.input.down) {
        if (drag.moved) if (opts.order) |order| {
            move(order, dragged, dropBefore(c, columns, opts, l, dragged));
            c.changed = true;
        };
        drag = .{};
    };
    lay_mod.state(c, Reorder).* = drag;
    return head;
}

/// The shown column after `i` in the order.
fn nextShown(c: *const ui.Context, columns: []const Column, opts: Options, l: Layout, i: usize) ?usize {
    var past = false;
    for (l.order) |j| {
        if (past and shown(c, columns, opts, j, l.grid_w)) return j;
        if (j == i) past = true;
    }
    return null;
}

/// Column `i`'s title, which sorts when clicked and, given `opts.order`,
/// moves when dragged. Returns its box.
fn title(c: *ui.Context, columns: []const Column, opts: Options, l: Layout, i: usize, drag: *Reorder, head: *Head) u32 {
    const t = kit.tokens(c);
    const k = opts.scale;
    const col = columns[i];
    ui.key(c, c.print("grid-column-{d}", .{i}));
    const sort = if (col.sortable) opts.sort else null;
    var box = ui.div(c).row().itemsCenter().gap(opts.column_gap * k / 2).w(l.w[i]);
    box = switch (col.alignment) {
        .start => box,
        .center => box.justifyCenter(),
        .end => box.justifyEnd(),
    };
    if (sort != null or opts.order != null) box = box.control();
    const it = box.interaction();
    defer box.end();
    if (opts.order != null and it.pressed) {
        if (drag.col == null) {
            drag.* = .{ .col = i, .x = c.input.mouse.x };
        } else if (drag.col == i and @abs(c.input.mouse.x - drag.x) > 4 * k) drag.moved = true;
    }
    const dragging = drag.col == i and drag.moved;
    if (dragging) {
        c.node(box.index).style.opacity = 0.5;
        c.cursor = .closed_hand;
    }
    if (sort) |s| if (it.clicked and !dragging) {
        s.* = if (s.column == i) .{ .column = i, .descending = !s.descending } else .{ .column = i, .descending = col.descending_first };
        head.sorted = true;
        c.changed = true;
    };
    const on = if (sort) |s| s.column == i else false;
    // A column header to a screen reader: one that sorts says which way,
    // and what a click does.
    if (sort) |s| {
        ui.access.describe(c, box.index, .{
            .label = col.title,
            .value = if (!on) "" else if (s.descending) opts.descending_text else opts.ascending_text,
            .hint = opts.sort_hint_text,
            .header = true,
        });
    } else ui.access.describe(c, box.index, .{ .role = .static_text, .label = col.title, .header = true });
    const ts = opts.title_style;
    const muted = ts.color orelse t.muted;
    const fg = if (on) ts.sorted_color orelse t.foreground else if (sort != null and it.hovered) muted.mix(t.foreground, 0.5) else muted;
    const arrow = if (sort) |s| (if (s.descending) "chevron.down" else "chevron.up") else "";
    const weight = ts.weight orelse if (on) ui.Weight.semibold else .medium;
    // At the end of a title; before it when the column's numbers line up
    // at the end, so the title lines up with them.
    if (on and col.alignment == .end) ui.icon(c, arrow, .{ .size = 8 * k, .color = fg });
    ui.text(c, col.title, .{ .size = ts.size, .weight = weight, .mono = ts.mono, .color = fg, .truncate = .ellipsis });
    if (on and col.alignment != .end) ui.icon(c, arrow, .{ .size = 8 * k, .color = fg });
    return box.index;
}

/// The gap between the titles of columns `a` and `b`, with a line down
/// its middle if `line`. Given `opts.widths`, dragging it resizes `a` if
/// it has a width, else `b`, a double-click fits that column to its
/// contents, and a line shows it under the pointer, stronger if it has
/// one already.
fn edge(c: *ui.Context, columns: []const Column, opts: Options, a: usize, b: usize, line: bool, head: *Head) void {
    const k = opts.scale;
    const t = kit.tokens(c);
    ui.key(c, c.print("grid-edge-{d}", .{a}));
    const drag = c.state(EdgeDrag, "drag");
    const d = ui.div(c).w(opts.column_gap * k).hFull().center();
    defer d.end();
    // The column a drag resizes, and which way: `b` narrows as the edge
    // moves right.
    const target: ?struct { usize, f32 } = if (opts.widths == null) null else if (columns[a].width != null) .{ a, 1 } else if (columns[b].width != null) .{ b, -1 } else null;
    const it: ?ui.Interaction = if (target != null) d.interaction() else null;
    const lit = if (it) |x| x.hovered or x.pressed else false;
    if (line or lit) ui.div(c).w(1).hFull().bg(if (line and lit) t.muted else t.border).end();
    const widths = opts.widths orelse return;
    const i, const way = target orelse return;
    if (lit) c.cursor = .resize_left_right;
    const it2 = it.?;
    if (it2.double_clicked) head.fit = i;
    if (!it2.pressed) {
        drag.on = false;
        return;
    }
    if (!drag.on) {
        drag.* = .{ .on = true, .x = c.input.mouse.x, .width = widths[i] };
        return;
    }
    const w = @max(columns[i].min_width, drag.width + way * (c.input.mouse.x - drag.x) / k);
    if (w != widths[i]) {
        widths[i] = w;
        c.changed = true;
    }
}

/// An edge being dragged: where the pointer and the column's width
/// started.
const EdgeDrag = struct { on: bool = false, x: f32 = 0, width: f32 = 0 };

/// The column a title dragged to the pointer goes before, or null for
/// after the last.
fn dropBefore(c: *ui.Context, columns: []const Column, opts: Options, l: Layout, dragged: usize) ?usize {
    const mx = c.input.mouse.x - l.left;
    for (l.order) |i| {
        if (i == dragged or !shown(c, columns, opts, i, l.grid_w)) continue;
        if (mx < l.at(i) + l.w[i] / 2) return i;
    }
    return null;
}

/// A line where the dragged title would go.
fn dropLine(c: *ui.Context, columns: []const Column, opts: Options, l: Layout, dragged: usize) void {
    const k = opts.scale;
    const gap = opts.column_gap * k;
    var x: f32 = 0;
    if (dropBefore(c, columns, opts, l, dragged)) |b| {
        x = l.at(b) - gap / 2;
    } else for (l.order) |i| {
        if (i != dragged and shown(c, columns, opts, i, l.grid_w)) x = l.at(i) + l.w[i] + gap / 2;
    }
    // In the scrolled titles' row, whose boxes start past the frozen
    // column, or past the padding, and scroll.
    const origin = (if (l.frozen != null) l.clip_x else opts.padding * k) - l.sx;
    ui.div(c).absolute().offset(x - origin - 1, 0).w(2).hFull().bg(kit.tokens(c).primary).end();
}

/// Moves column `col` in `order` to just before column `before`, or to
/// the end.
fn move(order: []usize, col: usize, before: ?usize) void {
    const from = std.mem.indexOfScalar(usize, order, col) orelse return;
    std.mem.copyForwards(usize, order[from .. order.len - 1], order[from + 1 ..]);
    const rest = order[0 .. order.len - 1];
    const to = if (before) |b| std.mem.indexOfScalar(usize, rest, b) orelse rest.len else rest.len;
    std.mem.copyBackwards(usize, order[to + 1 ..], order[to .. order.len - 1]);
    order[to] = col;
}
