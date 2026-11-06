//! A grid: rows of cells under a header of column titles, each column
//! lined up from row to row. Clicking a sortable column's title sorts by
//! it, and clicking it again sorts the other way. Only the rows in view are
//! built, as with `ui.list`, so a long grid costs what a screenful does.
//!
//! The grid fills the room left in its parent, which needs a bounded
//! height: a pane in a window, not something that scrolls itself. Given
//! `rows`, it shows that many instead, without scrolling, and takes only
//! their height.
//!
//! Columns can hide, in narrow windows or when the caller says so, and
//! keep their numbers: build their cells with `cellAt`, which skips a
//! hidden one.
//!
//! Given `selected`, a click selects a row, and while nothing else has
//! the keyboard Up and Down move the selection a row, Page Up and Page
//! Down a view, and Home and End to the ends, scrolling it into view.
//! Enter or a double click opens the row (`Row.opened`). Given `multi`
//! too, Cmd-click (Ctrl-click off the Mac) adds or takes away a row,
//! Shift-click and Shift with the keys select a run of rows, and Cmd+A
//! (Ctrl+A) selects them all.
//!
//! Typing while the grid has the keyboard jumps to a row: the grid keeps
//! the text (`typed`), the caller finds the first row it begins, and
//! `jump` selects that row and scrolls to it.
//!
//!     const columns = [_]controls.GridColumn{
//!         .{ .title = "Name", .sortable = true },
//!         .{ .title = "Size", .width = 80, .alignment = .end, .sortable = true, .descending_first = true },
//!     };
//!     var g = controls.grid(c, &columns, .{ .count = files.len, .sort = &sort });
//!     if (g.sorted) sortFiles(files, sort);
//!     while (g.next()) |row| {
//!         g.cell();
//!         ui.text(c, files[row.index].name, .{});
//!         g.cell();
//!         ui.text(c, files[row.index].size, .{});
//!     }
//!     g.end();
const std = @import("std");
const builtin = @import("builtin");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const keys = @import("grid_keys.zig");

/// The room a scrolling grid leaves at its right edge for the scrollbar's
/// track, in points as the bar's are, unscaled. Its rows stop short of
/// it: nanoui gives a press to a clickable box under the track rather
/// than to the bar, so a row reaching under it would keep the bar from
/// being dragged or clicked.
const scrollbar_gutter = 10;

pub const Column = struct {
    title: []const u8 = "",
    /// Its width in points; null takes a share of the room the fixed
    /// columns leave, as `flex` says.
    width: ?f32 = null,
    /// Its share of the room left, against the other columns without a
    /// width: 2 takes twice what 1 does.
    flex: f32 = 1,
    /// The narrowest it gets, taking room or resized, in points.
    min_width: f32 = 40,
    /// Where its cells' contents sit: numbers line up at the end.
    alignment: Alignment = .start,
    /// Clicking its title sorts by it.
    sortable: bool = false,
    /// Sorts by it largest or newest first, the first time it is clicked.
    descending_first: bool = false,
    /// Shown only in windows at least this wide, in points before `scale`.
    min_window_width: f32 = 0,

    pub const Alignment = enum { start, end };
};

/// The column the rows are sorted by, and which way.
pub const Sort = struct {
    column: usize = 0,
    descending: bool = false,
};

pub const Options = struct {
    count: usize,
    row_height: f32 = 28,
    /// Between rows.
    gap: f32 = 2,
    /// Between columns.
    column_gap: f32 = 10,
    /// The order the rows are in, which the header shows and changes.
    sort: ?*Sort = null,
    /// Rows light up under the pointer.
    hover: bool = true,
    /// Rows take clicks: they report them, select, light up under the
    /// pointer and show the pointing hand. False makes a table to read,
    /// whose rows do none of it (the keys still move `selected`, if
    /// given); a screen reader still hears them as rows.
    clickable: bool = true,
    /// Every other row is shaded.
    striped: bool = false,
    /// Shows this many rows at most, without scrolling, and takes only
    /// their height; null fills the room left and scrolls.
    rows: ?usize = null,
    /// Columns the caller hides, one flag a column, on top of their
    /// `min_window_width`.
    hidden: ?[]const bool = null,
    /// The selected row, kept by the caller, which clicks and keys
    /// change; a row past `count` moves back to the last. It is a row's
    /// index, so a caller that sorts finds its row again. Null: rows
    /// don't select.
    selected: ?*?usize = null,
    /// Rows selected together, one flag a row as long as `count`, kept by
    /// the caller; `selected` is then the row the keys move, and is needed
    /// too. A click selects its row alone, Cmd-click (Ctrl-click off the
    /// Mac) adds or takes it away, Shift-click and Shift with the keys
    /// select every row from where the selection started, and Cmd+A
    /// (Ctrl+A) selects them all. Null: only `selected` is.
    multi: ?[]bool = null,
    /// Column widths the caller keeps, one a column, which dragging the
    /// edge between two titles changes: the column on its left if it has
    /// a `width`, else the one on its right. A 0 starts at the column's
    /// `width`; a column without one isn't resized, but gives or takes
    /// the room. Null: columns don't resize.
    widths: ?[]f32 = null,
    /// Scrolls the grid in this frame so this row is in view.
    scroll_to: ?usize = null,
    /// Shown under the titles when there are no rows.
    empty: ?[]const u8 = null,
    /// Multiplies the grid's lengths (widths, heights, gaps), for an app
    /// that zooms its layout along with `c.setZoom`, which zooms text.
    scale: f32 = 1,
    /// How far the header and the rows start their cells in.
    padding: f32 = 10,
    /// A line under the header.
    rule: bool = true,
    title: TitleStyle = .{},
};

/// The look of the column titles; null takes the theme's.
pub const TitleStyle = struct {
    size: f32 = 11,
    mono: bool = false,
    /// Null: medium, and semibold for the sorted column.
    weight: ?ui.Weight = null,
    color: ?ui.Color = null,
    /// The sorted column's title and arrow.
    sorted_color: ?ui.Color = null,
};

/// A row being built.
pub const Row = struct {
    index: usize,
    clicked: bool,
    hovered: bool,
    /// It is the selected row.
    selected: bool = false,
    /// Double-clicked, or Enter pressed while it is selected: open what
    /// it shows.
    opened: bool = false,
    /// Right-clicked, or Control-clicked on the Mac: show its context
    /// menu. It selects the row, unless it is selected already, so the
    /// menu acts on the selection.
    secondary_clicked: bool = false,
};

/// Opens the grid's box, which takes the room left in its parent, and
/// draws the header: build the rows with `next` and `cell`, then `end`.
pub fn grid(c: *ui.Context, columns: []const Column, opts: Options) Grid {
    if (opts.hidden) |h| if (h.len != columns.len) @panic("grid: `hidden` needs one flag a column");
    if (opts.widths) |w| {
        if (w.len != columns.len) @panic("grid: `widths` needs one width a column");
        for (w, columns) |*x, col| if (x.* == 0) if (col.width) |start| {
            x.* = start;
        };
    }
    if (opts.multi) |m| {
        if (m.len != opts.count) @panic("grid: `multi` needs one flag a row");
        if (opts.selected == null) @panic("grid: `multi` needs `selected`");
    }
    const t = kit.tokens(c);
    const k = opts.scale;
    if (opts.selected) |s| if (s.*) |i| if (i >= opts.count) {
        s.* = if (opts.count > 0) opts.count - 1 else null;
    };
    if (opts.multi) |m| if (c.focus == 0 and opts.count > 0 and c.shortcut(.{ .key = 'a', .cmd = true })) @memset(m, true);
    var box = ui.div(c).column().wFull();
    if (opts.rows == null) box = box.grow();
    // Copied in here and written back by `end`.
    const kept = state(c, Kept).*;
    const unit = flexUnit(c, columns, opts, box);
    const sorted = header(c, columns, opts, unit);
    if (opts.rule) ui.div(c).wFull().h(1).bg(t.border).end();
    var g: Grid = .{ .c = c, .box = box, .columns = columns, .opts = opts, .unit = unit, .anchor = kept.anchor, .sorted = sorted };
    if (g.anchor) |a| if (a >= opts.count) {
        g.anchor = null;
    };
    const pitch = (opts.row_height + opts.gap) * k;
    const before = if (opts.selected) |s| s.* else null;
    if (opts.rows) |n| {
        g.rows_end = @min(n, opts.count);
        g.last = g.rows_end;
        g.useKeys(before, keys.useKeys(c, opts.selected, g.rows_end, n));
        g.plain = ui.div(c).column().wFull().gap(opts.gap * k).pt(opts.gap * k);
    } else {
        // The list's scroll and height as the last frame left them, to
        // page by a view, keep a row in it and say which rows it shows.
        const id = c.peekId(null);
        const view_h = if (c.rects.get(id)) |r| r.h else c.size.h;
        g.useKeys(before, keys.useKeys(c, opts.selected, opts.count, @max(1, @as(usize, @intFromFloat(view_h / pitch)))));
        var want = opts.scroll_to;
        if (kept.jump_to) |i| want = i;
        if (opts.selected) |s| if (s.* != before) if (s.*) |i| {
            want = i;
        };
        const count: f32 = @floatFromInt(opts.count);
        var offset = c.scroll.get(id) orelse 0;
        var scroll_to: ?f32 = null;
        if (want) |i| if (i < opts.count) {
            const top = @as(f32, @floatFromInt(i)) * pitch;
            const bottom = top + pitch + opts.gap * k;
            if (top < offset) scroll_to = top else if (bottom > offset + view_h) scroll_to = bottom - view_h;
        };
        if (scroll_to) |y| offset = y;
        offset = std.math.clamp(offset, 0, @max(0, pitch * count - view_h));
        const pad = opts.gap * k;
        g.first = @min(opts.count, @as(usize, @intFromFloat(@floor(@max(0, offset - pad) / pitch))));
        g.last = @min(opts.count, @as(usize, @intFromFloat(@ceil(@max(0, offset + view_h - pad) / pitch))));
        g.list = ui.list(c, .{ .count = opts.count, .row_height = opts.row_height * k, .gap = opts.gap * k, .padding = .{ .top = pad, .right = scrollbar_gutter }, .scroll_to = scroll_to });
    }
    g.typed = keys.useTyping(c, state(c, keys.Typing), opts.count);
    if (opts.count == 0) if (opts.empty) |text| {
        const d = ui.div(c).wFull().px(opts.padding * k).py(8 * k);
        defer d.end();
        ui.text(c, text, .{ .size = 13, .color = t.muted });
    };
    return g;
}

/// The width a column without one gets for each unit of its `flex`: the
/// room the others leave, shared out, with a column whose share would be
/// under its `min_width` held at that and the rest shared again. The
/// room is the grid's width as the last frame laid it out; when it
/// changed, another frame is drawn with the new one.
fn flexUnit(c: *ui.Context, columns: []const Column, opts: Options, box: ui.Div) f32 {
    const k = opts.scale;
    const id = c.node(box.index).id;
    const width = if (c.rects.get(id)) |r| r.w else c.size.w;
    const last = c.state(struct { width: f32 = 0 }, "grid-width");
    if (last.width != width) {
        last.width = width;
        c.frameIn(0);
    }
    var room = width - 2 * opts.padding * k - gutter(opts);
    var shown_count: f32 = 0;
    for (columns, 0..) |col, i| {
        if (!shown(c, columns, opts, i)) continue;
        shown_count += 1;
        if (col.width != null) room -= columnWidth(columns, opts, i, 0);
    }
    room -= @max(0, shown_count - 1) * opts.column_gap * k;
    var unit: f32 = 0;
    // Each pass holds more columns at their minimum, and at most every
    // column is held.
    for (0..columns.len + 1) |_| {
        var left = room;
        var flex: f32 = 0;
        for (columns, 0..) |col, i| {
            if (!shown(c, columns, opts, i) or col.width != null) continue;
            if (col.flex * unit < col.min_width * k and unit > 0) left -= col.min_width * k else flex += col.flex;
        }
        const next = if (flex > 0) @max(0, left / flex) else 0;
        if (next == unit) break;
        unit = next;
    }
    return unit;
}

/// Column `i`'s width in this frame, scaled: its own, the caller's, or
/// its share of the room left at `unit` a flex.
fn columnWidth(columns: []const Column, opts: Options, i: usize, unit: f32) f32 {
    const col = columns[i];
    const k = opts.scale;
    if (col.width) |w| return (if (opts.widths) |ws| ws[i] else w) * k;
    return @max(col.min_width * k, col.flex * unit);
}

/// The room left for the scrollbar: none in a grid of a set number of
/// rows, which doesn't scroll.
fn gutter(opts: Options) f32 {
    return if (opts.rows == null) scrollbar_gutter else 0;
}

/// What the grid keeps between frames: where Shift-click and Shift with
/// the keys select from, and the row `jump` scrolls to next.
const Kept = struct { anchor: ?usize = null, jump_to: ?usize = null };

/// The grid's `T` between frames, found by a key of its own in the grid's
/// box: the same at the start of `grid` and in `end`, wherever the rows
/// put them. The pointer lasts only until the next state is made, which
/// any widget in a cell may do, so it isn't kept: use it at once.
fn state(c: *ui.Context, comptime T: type) *T {
    ui.key(c, "grid-state");
    // Looking a state up doesn't take the key, as a new box would.
    defer c.next_key = null;
    return c.state(T, @typeName(T));
}

/// Draws the column titles, with the edges between them that resize
/// columns, and returns whether a click changed the sort.
fn header(c: *ui.Context, columns: []const Column, opts: Options, unit: f32) bool {
    const t = kit.tokens(c);
    const k = opts.scale;
    var sorted = false;
    // No gap of its own: the edges between titles take its room. Over the
    // scrollbar's gutter, so the titles line up with the rows.
    const head = ui.div(c).row().wFull().itemsCenter().pl(opts.padding * k).pr(opts.padding * k + gutter(opts)).pb(6 * k);
    defer head.end();
    var before: ?usize = null;
    for (columns, 0..) |col, i| {
        if (!shown(c, columns, opts, i)) continue;
        if (before) |b| edge(c, columns, opts, b, i);
        before = i;
        ui.key(c, c.print("grid-column-{d}", .{i}));
        const sort = if (col.sortable) opts.sort else null;
        var title = cellBox(c, columns, opts, unit, i);
        if (sort != null) title = title.control();
        const it = title.interaction();
        defer title.end();
        if (sort) |s| if (it.clicked) {
            s.* = if (s.column == i) .{ .column = i, .descending = !s.descending } else .{ .column = i, .descending = col.descending_first };
            sorted = true;
            c.changed = true;
        };
        const on = if (sort) |s| s.column == i else false;
        if (sort) |s| ui.access.describe(c, title.index, .{
            .label = col.title,
            .value = if (!on) "" else if (s.descending) "sorted descending" else "sorted ascending",
            .hint = "Sorts the rows by this column",
        });
        const ts = opts.title;
        const muted = ts.color orelse t.muted;
        const fg = if (on) ts.sorted_color orelse t.foreground else if (sort != null and it.hovered) muted.mix(t.foreground, 0.5) else muted;
        const arrow = if (sort) |s| (if (s.descending) "chevron.down" else "chevron.up") else "";
        const weight = ts.weight orelse if (on) ui.Weight.semibold else .medium;
        // At the end of a title; before it when the column's numbers
        // line up at the end, so the title lines up with them.
        if (on and col.alignment == .end) ui.icon(c, arrow, .{ .size = 8 * k, .color = fg });
        ui.text(c, col.title, .{ .size = ts.size, .weight = weight, .mono = ts.mono, .color = fg, .truncate = .ellipsis });
        if (on and col.alignment == .start) ui.icon(c, arrow, .{ .size = 8 * k, .color = fg });
    }
    return sorted;
}

/// The gap between the titles of columns `a` and `b`. Given
/// `opts.widths`, dragging it resizes `a` if it has a width, else `b`,
/// and a line shows it under the pointer.
fn edge(c: *ui.Context, columns: []const Column, opts: Options, a: usize, b: usize) void {
    const k = opts.scale;
    ui.key(c, c.print("grid-edge-{d}", .{a}));
    const drag = c.state(EdgeDrag, "drag");
    const d = ui.div(c).w(opts.column_gap * k).hFull().center();
    defer d.end();
    const widths = opts.widths orelse return;
    // The column the drag resizes, and which way: `b` narrows as the
    // edge moves right.
    const i, const way: f32 = if (columns[a].width != null) .{ a, 1 } else if (columns[b].width != null) .{ b, -1 } else return;
    const it = d.interaction();
    if (it.hovered or it.pressed) {
        c.cursor = .resize_left_right;
        ui.div(c).w(1).hFull().bg(kit.tokens(c).border).end();
    }
    if (!it.pressed) {
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

/// Column `i` is shown: the caller doesn't hide it, and the window is
/// wide enough.
fn shown(c: *const ui.Context, columns: []const Column, opts: Options, i: usize) bool {
    if (opts.hidden) |h| if (h[i]) return false;
    return c.size.w / opts.scale >= columns[i].min_window_width;
}

/// A cell of column `i`: its width, and its contents placed as it says.
fn cellBox(c: *ui.Context, columns: []const Column, opts: Options, unit: f32, i: usize) ui.Div {
    var d = ui.div(c).row().itemsCenter().gap(opts.column_gap * opts.scale / 2).w(columnWidth(columns, opts, i, unit));
    if (columns[i].alignment == .end) d = d.justifyEnd();
    return d;
}

pub const Grid = struct {
    c: *ui.Context,
    box: ui.Div,
    columns: []const Column,
    opts: Options,
    /// The width of a unit of `flex` (`flexUnit`).
    unit: f32,
    /// Where Shift-click and Shift with the keys select from, kept by
    /// `end` for the next frame.
    anchor: ?usize,
    /// The rows in view this frame, from `first` up to but not including
    /// `last`: a caller that loads rows as they come into view fetches
    /// these, and the ones around them.
    first: usize = 0,
    last: usize = 0,
    /// The rows built; null with `opts.rows`, which builds them in
    /// `plain` from `next` up to `rows_end`.
    list: ?ui.ListRows = null,
    plain: ?ui.Div = null,
    next_row: usize = 0,
    rows_end: usize = 0,
    /// The header changed the sort this frame: sort the rows before
    /// building them.
    sorted: bool,
    /// The row Enter opened this frame.
    opened: ?usize = null,
    /// What has been typed to jump to a row, with this frame's typing;
    /// null when nothing was typed this frame. The caller finds the first
    /// row it begins (ignoring case, as Finder does) and `jump`s to it.
    typed: ?[]const u8 = null,
    /// The row `jump` scrolls to, in the next frame.
    jump_to: ?usize = null,
    /// The row and the cell being built, ended by the next or by `end`.
    row: ?ui.Div = null,
    cell_box: ?ui.Div = null,
    column: usize = 0,

    /// Opens the next row in view, or null when the view is full.
    pub fn next(g: *Grid) ?Row {
        g.endRow();
        const i = if (g.list) |*l| l.next() orelse return null else blk: {
            if (g.next_row >= g.rows_end) return null;
            g.next_row += 1;
            break :blk g.next_row - 1;
        };
        const t = kit.tokens(g.c);
        const k = g.opts.scale;
        var r = ui.div(g.c).row().wFull().h(g.opts.row_height * k).itemsCenter().gap(g.opts.column_gap * k).px(g.opts.padding * k).rounded(t.radius - 2);
        const it: ui.Interaction = if (g.opts.clickable) r.interaction() else .{ .id = 0, .rect = null, .hovered = false, .pressed = false, .clicked = false, .focused = false };
        if (it.secondary_clicked) {
            if (!g.isSelected(i)) g.pick(i, .only);
        } else if (it.clicked) {
            const in = g.c.input;
            const adds = if (builtin.os.tag.isDarwin()) in.cmd else in.ctrl;
            g.pick(i, if (in.shift) .extend else if (adds) .toggle else .only);
        }
        if (it.clicked or it.secondary_clicked) g.c.changed = true;
        const selected = g.isSelected(i);
        if (selected) {
            r = r.bg(t.primary.alpha(0.18));
        } else if (g.opts.striped and i % 2 == 1) r = r.bg(t.surface.alpha(0.35));
        // A selected row stays the selection's color under the pointer.
        if (g.opts.hover and g.opts.clickable) r = r.hover(if (selected) t.primary.alpha(0.26) else t.surface_hover.alpha(0.6));
        // A row to a screen reader, read as its cells' text.
        ui.access.describe(g.c, r.index, .{ .role = .row, .selected = selected });
        g.row = r;
        g.column = 0;
        return .{ .index = i, .clicked = it.clicked, .hovered = it.hovered, .selected = selected, .opened = it.double_clicked or g.opened == i, .secondary_clicked = it.secondary_clicked };
    }

    /// Selects row `i` alone, if rows select, and scrolls it into view:
    /// where `typed` leads. The grid is drawn again to show it.
    pub fn jump(g: *Grid, i: usize) void {
        if (i >= g.opts.count) return;
        g.pick(i, .only);
        g.jump_to = i;
        g.c.changed = true;
    }

    /// Row `i` is selected: among `multi`'s, or `selected` without it.
    fn isSelected(g: *const Grid, i: usize) bool {
        if (g.opts.multi) |m| return m[i];
        return if (g.opts.selected) |s| s.* == i else false;
    }

    const Pick = enum { only, toggle, extend };

    /// Makes row `i` the selected one, and changes `multi` as `how` says:
    /// `i` alone, `i` added or taken away, or every row from the anchor
    /// to `i`.
    fn pick(g: *Grid, i: usize, how: Pick) void {
        const s = g.opts.selected orelse return;
        s.* = i;
        const m = g.opts.multi orelse return;
        switch (how) {
            .only => {
                @memset(m, false);
                m[i] = true;
                g.anchor = i;
            },
            .toggle => {
                m[i] = !m[i];
                g.anchor = i;
            },
            .extend => {
                const from = g.anchor orelse i;
                g.anchor = from;
                @memset(m, false);
                @memset(m[@min(from, i) .. @max(from, i) + 1], true);
            },
        }
    }

    /// Follows the keys with `multi`: the row they moved to alone, or with
    /// Shift the rows from the anchor to it.
    fn useKeys(g: *Grid, before: ?usize, k: keys.Keys) void {
        g.opened = k.opened;
        const s = g.opts.selected orelse return;
        const i = s.* orelse return;
        if (i != before) g.pick(i, if (k.extend) .extend else .only);
    }

    /// Opens the row's next cell, ending the one before: what is drawn
    /// until the next `cell` goes in it. When columns hide, use `cellAt`,
    /// as this panics on a hidden one.
    pub fn cell(g: *Grid) void {
        if (!g.cellAt(g.column)) @panic("grid: `cell` opened a hidden column; use `cellAt`");
    }

    /// Opens column `i`'s cell, ending the one before, and returns true;
    /// false when the column is hidden, with nothing to draw. Columns go
    /// in order: `i` is past the cell before.
    pub fn cellAt(g: *Grid, i: usize) bool {
        g.endCell();
        std.debug.assert(g.row != null and i >= g.column and i < g.columns.len);
        g.column = i + 1;
        if (!g.shows(i)) return false;
        g.cell_box = cellBox(g.c, g.columns, g.opts, g.unit, i);
        return true;
    }

    /// Column `i` is shown this frame.
    pub fn shows(g: *const Grid, i: usize) bool {
        return shown(g.c, g.columns, g.opts, i);
    }

    pub fn end(g: *Grid) void {
        g.endRow();
        if (g.list) |*l| l.end();
        if (g.plain) |p| p.end();
        state(g.c, Kept).* = .{ .anchor = g.anchor, .jump_to = g.jump_to };
        g.box.end();
    }

    fn endCell(g: *Grid) void {
        if (g.cell_box) |b| b.end();
        g.cell_box = null;
    }

    fn endRow(g: *Grid) void {
        g.endCell();
        if (g.row) |r| r.end();
        g.row = null;
    }
};

test {
    _ = @import("grid_tests.zig");
    _ = @import("grid_columns_tests.zig");
    _ = @import("grid_select_tests.zig");
    _ = @import("grid_keys_tests.zig");
}
