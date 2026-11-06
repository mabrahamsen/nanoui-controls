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
//! Enter or a double click opens the row (`Row.opened`).
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
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;

pub const Column = struct {
    title: []const u8 = "",
    /// Its width in points; null takes the room the fixed columns leave.
    /// Leave it null on one column only: more aren't tested.
    width: ?f32 = null,
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
};

/// Opens the grid's box, which takes the room left in its parent, and
/// draws the header: build the rows with `next` and `cell`, then `end`.
pub fn grid(c: *ui.Context, columns: []const Column, opts: Options) Grid {
    if (opts.hidden) |h| if (h.len != columns.len) @panic("grid: `hidden` needs one flag a column");
    const t = kit.tokens(c);
    const k = opts.scale;
    if (opts.selected) |s| if (s.*) |i| if (i >= opts.count) {
        s.* = if (opts.count > 0) opts.count - 1 else null;
    };
    var box = ui.div(c).column().wFull();
    if (opts.rows == null) box = box.grow();
    var sorted = false;
    {
        const head = ui.div(c).row().wFull().itemsCenter().gap(opts.column_gap * k).px(opts.padding * k).pb(6 * k);
        defer head.end();
        for (columns, 0..) |col, i| {
            if (!shown(c, columns, opts, i)) continue;
            ui.key(c, c.print("grid-column-{d}", .{i}));
            const sort = if (col.sortable) opts.sort else null;
            var title = cellBox(c, col, opts);
            if (sort != null) title = title.control();
            const it = title.interaction();
            defer title.end();
            if (sort) |s| if (it.clicked) {
                s.* = if (s.column == i) .{ .column = i, .descending = !s.descending } else .{ .column = i, .descending = col.descending_first };
                sorted = true;
                c.changed = true;
            };
            const on = if (sort) |s| s.column == i else false;
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
    }
    if (opts.rule) ui.div(c).wFull().h(1).bg(t.border).end();
    var g: Grid = .{ .c = c, .box = box, .columns = columns, .opts = opts, .sorted = sorted };
    const pitch = (opts.row_height + opts.gap) * k;
    if (opts.rows) |n| {
        g.last = @min(n, opts.count);
        g.opened = useKeys(c, opts.selected, g.last, n);
        g.plain = ui.div(c).column().wFull().gap(opts.gap * k).pt(opts.gap * k);
    } else {
        // The list's scroll and height as the last frame left them, to
        // page by a view and keep the selection in it.
        const id = c.peekId(null);
        const view_h = if (c.rects.get(id)) |r| r.h else c.size.h;
        const before = if (opts.selected) |s| s.* else null;
        g.opened = useKeys(c, opts.selected, opts.count, @max(1, @as(usize, @intFromFloat(view_h / pitch))));
        var scroll_to: ?f32 = null;
        if (opts.selected) |s| if (s.*) |i| if (before != s.*) {
            const offset = c.scroll.get(id) orelse 0;
            const top = @as(f32, @floatFromInt(i)) * pitch;
            const bottom = top + pitch + opts.gap * k;
            if (top < offset) scroll_to = top else if (bottom > offset + view_h) scroll_to = bottom - view_h;
        };
        g.list = ui.list(c, .{ .count = opts.count, .row_height = opts.row_height * k, .gap = opts.gap * k, .padding = .{ .top = opts.gap * k }, .scroll_to = scroll_to });
    }
    return g;
}

/// Moves the selection by the keys pressed this frame, while nothing else
/// has the keyboard, among `count` rows of which `page` fit in a view.
/// Returns the row Enter opens.
fn useKeys(c: *ui.Context, selected: ?*?usize, count: usize, page: usize) ?usize {
    const s = selected orelse return null;
    if (c.focus != 0 or count == 0) return null;
    const last = count - 1;
    const i = s.*;
    var to: ?usize = null;
    var opened: ?usize = null;
    if (c.shortcut(.{ .key = ui.Shortcut.down })) {
        to = if (i) |n| @min(n + 1, last) else 0;
    } else if (c.shortcut(.{ .key = ui.Shortcut.up })) {
        to = if (i) |n| n -| 1 else 0;
    } else if (c.shortcut(.{ .key = ui.Shortcut.enter })) {
        opened = i;
    } else if (c.input.key) |key| {
        switch (key) {
            .down => to = if (i) |n| @min(n + 1, last) else 0,
            .up => to = if (i) |n| n -| 1 else 0,
            .page_down => to = if (i) |n| @min(n + page, last) else @min(page, last),
            .page_up => to = if (i) |n| n -| page else 0,
            .home => to = 0,
            .end => to = last,
            .enter => opened = i,
            else => return null,
        }
        c.input.key = null;
        c.changed = true;
    }
    if (to) |n| s.* = n;
    return opened;
}

/// Column `i` is shown: the caller doesn't hide it, and the window is
/// wide enough.
fn shown(c: *const ui.Context, columns: []const Column, opts: Options, i: usize) bool {
    if (opts.hidden) |h| if (h[i]) return false;
    return c.size.w / opts.scale >= columns[i].min_window_width;
}

/// A cell of `col`: its width, its contents placed as it says.
fn cellBox(c: *ui.Context, col: Column, opts: Options) ui.Div {
    var d = ui.div(c).row().itemsCenter().gap(opts.column_gap * opts.scale / 2);
    d = if (col.width) |w| d.w(w * opts.scale) else d.wFull();
    if (col.alignment == .end) d = d.justifyEnd();
    return d;
}

pub const Grid = struct {
    c: *ui.Context,
    box: ui.Div,
    columns: []const Column,
    opts: Options,
    /// The rows in view; null with `opts.rows`, which builds them in
    /// `plain` from `next` up to `last`.
    list: ?ui.ListRows = null,
    plain: ?ui.Div = null,
    next_row: usize = 0,
    last: usize = 0,
    /// The header changed the sort this frame: sort the rows before
    /// building them.
    sorted: bool,
    /// The row Enter opened this frame.
    opened: ?usize = null,
    /// The row and the cell being built, ended by the next or by `end`.
    row: ?ui.Div = null,
    cell_box: ?ui.Div = null,
    column: usize = 0,

    /// Opens the next row in view, or null when the view is full.
    pub fn next(g: *Grid) ?Row {
        g.endRow();
        const i = if (g.list) |*l| l.next() orelse return null else blk: {
            if (g.next_row >= g.last) return null;
            g.next_row += 1;
            break :blk g.next_row - 1;
        };
        const t = kit.tokens(g.c);
        const k = g.opts.scale;
        var r = ui.div(g.c).row().wFull().h(g.opts.row_height * k).itemsCenter().gap(g.opts.column_gap * k).px(g.opts.padding * k).rounded(t.radius - 2);
        const it = r.interaction();
        if (it.clicked) {
            if (g.opts.selected) |s| s.* = i;
            g.c.changed = true;
        }
        const selected = if (g.opts.selected) |s| s.* == i else false;
        if (selected) {
            r = r.bg(t.primary.alpha(0.18));
        } else if (g.opts.striped and i % 2 == 1) r = r.bg(t.surface.alpha(0.35));
        if (g.opts.hover) r = r.hover(t.surface_hover.alpha(0.6));
        g.row = r;
        g.column = 0;
        return .{ .index = i, .clicked = it.clicked, .hovered = it.hovered, .selected = selected, .opened = it.double_clicked or g.opened == i };
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
        g.cell_box = cellBox(g.c, g.columns[i], g.opts);
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
}
