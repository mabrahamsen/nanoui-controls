//! The grid's header: the column titles in their order, which sort when
//! clicked and move when dragged, the edges between them, which resize a
//! column when dragged and fit it when double-clicked, and the room past
//! the last title, where a double click fits them all.
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
const widths_mod = @import("grid_widths.zig");

/// What happened in the header this frame.
pub const Head = struct {
    /// A click changed the sort.
    sorted: bool = false,
    /// The columns a double-click fits to their contents, one width a
    /// column, starting at their titles' (`grid_widths.fits`).
    fit: ?[]f32 = null,
    /// Each column's title box, or `no_title` for a hidden one.
    titles: ?[]const u32 = null,
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
    @memset(titles, widths_mod.no_title);
    var fit: ?usize = null;
    var fit_all = false;
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
            if (nextShown(c, columns, opts, l, f)) |_| edge(c, columns, opts, l, f, opts.column_lines or l.sx > 0, &fit);
        }
        {
            // The rest, cut off past the frozen column and scrolled.
            const cut = ui.div(c).row().grow().clip();
            defer cut.end();
            {
                var inner = ui.div(c).row().itemsCenter().offset(-l.sx, 0);
                if (l.frozen == null) inner = inner.pl(opts.padding * k);
                defer inner.end();
                for (l.order) |i| {
                    if (i == l.frozen or !shown(c, columns, opts, i, l.grid_w)) continue;
                    if (before) |b| if (b != l.frozen) edge(c, columns, opts, l, b, opts.column_lines, &fit);
                    before = i;
                    titles[i] = title(c, columns, opts, l, i, &drag, &head);
                }
                const end_pad = opts.padding * k + lay_mod.gutter(opts);
                if (opts.widths != null) fit_all = pastTitles(c, end_pad) else ui.div(c).w(end_pad).end();
            }
            if (opts.widths != null) fit_all = pastTitles(c, null) or fit_all;
        }
        // Over the titles, not cut off with them: in the grid's own
        // places, as the columns show.
        if (drag.col != null and drag.moved) dropLine(c, columns, opts, l, drag.col.?, outer.index);
    }
    head.titles = titles;
    if (fit_all or fit != null) head.fit = widths_mod.fits(c, columns, opts, l, titles, if (fit_all) null else fit);
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

/// The room past the last title, `width` wide or else the rest of the
/// header, where a double click fits every column: true when it does.
fn pastTitles(c: *ui.Context, width: ?f32) bool {
    var d = ui.div(c).hFull();
    d = if (width) |w| d.w(w) else d.grow();
    defer d.end();
    return d.interaction().double_clicked;
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

/// The gap after column `a`'s title, with a line down its middle if
/// `line`. Given `opts.widths`, dragging it resizes `a`, from the width it
/// has on screen, the flexible columns before it keeping theirs; a
/// double-click fits it to its contents (`fit`); and a line shows it
/// under the pointer, stronger if it has one already.
/// Without `scroll_x`, a drag stops where the other columns would go
/// under their `min_width`.
fn edge(c: *ui.Context, columns: []const Column, opts: Options, l: Layout, a: usize, line: bool, fit: *?usize) void {
    const k = opts.scale;
    const t = kit.tokens(c);
    ui.key(c, c.print("grid-edge-{d}", .{a}));
    const drag = c.state(EdgeDrag, "drag");
    const d = ui.div(c).w(opts.column_gap * k).hFull().center();
    defer d.end();
    const it: ?ui.Interaction = if (opts.widths != null) d.interaction() else null;
    const lit = if (it) |x| x.hovered or x.pressed else false;
    if (line or lit) ui.div(c).w(1).hFull().bg(if (line and lit) t.muted else t.border).end();
    const widths = opts.widths orelse return;
    if (lit) c.cursor = .resize_left_right;
    const it2 = it.?;
    if (it2.double_clicked) fit.* = a;
    if (!it2.pressed) {
        drag.on = false;
        return;
    }
    if (!drag.on) {
        drag.* = .{ .on = true, .x = c.input.mouse.x, .width = l.w[a] / k };
        return;
    }
    // A click, or a double click, that doesn't move changes no width.
    if (!drag.moved) {
        if (c.input.mouse.x == drag.x) return;
        drag.moved = true;
        // The flexible columns before it keep the widths they have, so
        // the edge follows the pointer.
        for (l.order) |j| {
            if (j == a) break;
            if (shown(c, columns, opts, j, l.grid_w) and widths_mod.sized(columns, opts, j) == null) widths[j] = l.w[j] / k;
        }
    }
    var w = drag.width + (c.input.mouse.x - drag.x) / k;
    if (widths_mod.maxWidth(c, columns, opts, l, a)) |most| w = @min(w, most / k);
    w = @max(columns[a].min_width, w);
    if (w != widths[a]) {
        widths[a] = w;
        c.changed = true;
    }
}

/// An edge being dragged: where the pointer and the column's width
/// started, and whether the pointer has moved since.
const EdgeDrag = struct { on: bool = false, x: f32 = 0, width: f32 = 0, moved: bool = false };

/// The column a title dragged to the pointer goes before, or null for
/// after the last. A column scrolled under the frozen one, out of sight,
/// isn't one.
fn dropBefore(c: *ui.Context, columns: []const Column, opts: Options, l: Layout, dragged: usize) ?usize {
    const mx = c.input.mouse.x - l.left;
    for (l.order) |i| {
        if (i == dragged or !shown(c, columns, opts, i, l.grid_w) or hidden(l, i)) continue;
        if (mx < l.at(i) + l.w[i] / 2) return i;
    }
    return null;
}

/// Column `i` is scrolled out of sight under the frozen column.
fn hidden(l: Layout, i: usize) bool {
    return l.frozen != null and l.frozen != i and l.at(i) + l.w[i] <= l.clip_x;
}

/// A line where the dragged title would go, in the header's box `outer`.
fn dropLine(c: *ui.Context, columns: []const Column, opts: Options, l: Layout, dragged: usize, outer: u32) void {
    const k = opts.scale;
    const gap = opts.column_gap * k;
    var x: f32 = 0;
    if (dropBefore(c, columns, opts, l, dragged)) |b| {
        x = l.at(b) - gap / 2;
        // Before the first column past the frozen one, partly under it:
        // where the scrolled ones start.
        if (l.frozen != null and b != l.frozen) x = @max(x, l.clip_x - gap / 2);
    } else for (l.order) |i| {
        if (i != dragged and shown(c, columns, opts, i, l.grid_w)) x = l.at(i) + l.w[i] + gap / 2;
    }
    // The places are the grid's; the header's box starts where the grid
    // does, as the last frame laid it out.
    const origin = if (c.rects.get(c.node(outer).id)) |r| r.x - l.left else 0;
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
