//! A grid: rows of cells under a header of column titles, each column
//! lined up from row to row. Clicking a sortable column's title sorts by
//! it, and clicking it again sorts the other way. Only the rows in view are
//! built, as with `ui.list`, so a long grid costs what a screenful does.
//!
//! The grid fills the room left in its parent, which needs a bounded
//! height: a pane in a window, not something that scrolls itself. Given
//! `max_rows`, it shows at most that many instead, without scrolling, and takes only
//! their height.
//!
//! Columns can hide, in narrow windows or when the caller says so, and
//! keep their numbers: build their cells with `cellAt`, which skips a
//! hidden one.
//!
//! Given `selected`, a click selects a row, and the grid takes the
//! keyboard as the pager does: a click in it or Tab gives it the keyboard
//! (`focused`), and `c.focusNext` before `grid` does at the start. While
//! it has it, Up and Down move the selection a row, Page Up and Page
//! Down a view, and Home and End to the ends, scrolling it into view;
//! the selection is grey while something else has it. Two grids in a
//! window take the keys in turn.
//! Enter or a double click opens the row (`Row.opened`). Given `selection`
//! too, Cmd-click (Ctrl-click off the Mac) adds or takes away a row,
//! Shift-click and Shift with the keys select a run of rows, and Cmd+A
//! (Ctrl+A) selects them all.
//!
//! Typing while the grid has the keyboard jumps to a row: the grid keeps
//! the text (`typed`), the caller finds the first row it begins, and
//! `jump` selects that row and scrolls to it.
//!
//! Given `widths`, dragging the edge between two titles resizes a column
//! and a double click fits it to its contents. Given `order`, dragging a
//! title moves its column. With `scroll_x`, columns that don't fit scroll
//! sideways, the first staying in place with `freeze_first`. A cell whose
//! text is cut off shows all of it on hover.
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
const lay_mod = @import("grid_layout.zig");
const Layout = lay_mod.Layout;
const header = @import("grid_header.zig").header;

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
    /// Where its cells' contents and its title sit: numbers line up at
    /// the end, a mark or a short status may sit in the center.
    alignment: Alignment = .start,
    /// Clicking its title sorts by it.
    sortable: bool = false,
    /// Sorts by it largest or newest first, the first time it is clicked.
    descending_first: bool = false,
    /// Shown only in windows at least this wide, in points before `scale`.
    min_window_width: f32 = 0,

    /// As nanoui's names for where a row's contents go.
    pub const Alignment = enum { start, center, end };
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
    /// Rows light up under the pointer, when they are `clickable`; false
    /// keeps them still, for a grid whose rows take clicks but would
    /// rather not show it.
    hover: bool = true,
    /// Rows take clicks: they report them, select, light up under the
    /// pointer and show the pointing hand. False makes a table to read,
    /// whose rows do none of it (the keys still move `selected`, if
    /// given); a screen reader still hears them as rows.
    clickable: bool = true,
    /// Every other row is shaded.
    striped: bool = false,
    /// A line between rows, in the theme's border color; the rows then
    /// meet it square, without their rounded corners and `gap`.
    row_lines: bool = false,
    /// A line down the middle of the gap between columns, through the
    /// titles and the rows. With `freeze_first`, the frozen column has
    /// one at its edge whenever the others are scrolled.
    column_lines: bool = false,
    /// Shows this many rows at most, without scrolling, and takes only
    /// their height; null fills the room left and scrolls.
    max_rows: ?usize = null,
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
    selection: ?[]bool = null,
    /// Column widths the caller keeps, one a column, which dragging the
    /// edge between two titles changes: the column on its left if it has
    /// a `width`, else the one on its right. A 0 starts at the column's
    /// `width`; a column without one isn't resized, but gives or takes
    /// the room. Null: columns don't resize.
    widths: ?[]f32 = null,
    /// The order the columns show in, kept by the caller: column numbers,
    /// one a place, which dragging a title changes. Cells keep their
    /// numbers whatever the order. Null: the columns' own order, and
    /// titles don't move.
    order: ?[]usize = null,
    /// Columns that don't fit keep their widths, and the grid scrolls
    /// sideways (with the wheel's or the trackpad's x, or the bar under
    /// the rows) rather than cutting them off.
    scroll_x: bool = false,
    /// With `scroll_x`, the first column in the order stays in place as
    /// the others scroll, as a spreadsheet's names do.
    freeze_first: bool = false,
    /// A cell whose text is cut off shows all of it on hover.
    tooltips: bool = true,
    /// A row held and moved a few points starts a drag out of the grid
    /// (`Row.drag_started`), to which the caller gives what it carries
    /// with `dragOut`. The row is selected first, unless it is already,
    /// so the drag carries the selection. nanoui drags text out on macOS
    /// so far.
    drag_rows: bool = false,
    /// Scrolls the grid in this frame so this row is in view.
    scroll_to: ?usize = null,
    /// Shown under the titles when there are no rows.
    empty: ?[]const u8 = null,
    /// Multiplies the grid's lengths (widths, heights, gaps), for an app
    /// that zooms its layout along with `c.setZoom`, which zooms text. The
    /// kit sizes its controls with a `kit.Size`, as the pager does, but
    /// has no sizes for a grid.
    scale: f32 = 1,
    /// How far the header and the rows start their cells in.
    padding: f32 = 10,
    /// A line under the header.
    header_line: bool = true,
    title_style: TitleStyle = .{},
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
    /// It was held and moved far enough to drag: give `dragOut` what the
    /// drag carries, in this frame.
    drag_started: bool = false,
};

/// Opens the grid's box, which takes the room left in its parent, and
/// draws the header: build the rows with `next` and `cell`, then `end`.
pub fn grid(c: *ui.Context, columns: []const Column, opts: Options) Grid {
    lay_mod.check(columns, opts);
    const t = kit.tokens(c);
    const k = opts.scale;
    if (opts.selected) |s| if (s.*) |i| if (i >= opts.count) {
        s.* = if (opts.count > 0) opts.count - 1 else null;
        c.changed = true;
    };
    var box = ui.div(c).column().wFull();
    if (opts.max_rows == null) box = box.grow();
    const own = keys.take(c, box, opts.selected != null);
    if (opts.selection) |m| if (own.focused and opts.count > 0 and c.shortcut(.{ .key = 'a', .cmd = true })) @memset(m, true);
    // Copied in here and written back by `end`.
    const kept = lay_mod.state(c, Kept).*;
    const press: Press = if (c.input.down) lay_mod.state(c, Press).* else .{};
    const lay = lay_mod.layout(c, columns, opts, box, kept.sx);
    const head = header(c, columns, opts, lay);
    if (opts.header_line) ui.div(c).wFull().h(1).bg(t.border).end();
    var g: Grid = .{ .c = c, .box = box, .columns = columns, .opts = opts, .lay = lay, .anchor = kept.anchor, .press = press, .sorted = head.sorted, .focused = own.focused, .own = own.id, .fit = head.fit, .fit_w = head.fit_w };
    // Rows with lines between them meet the lines, without a gap.
    const row_gap = if (opts.row_lines) 0 else opts.gap;
    if (g.anchor) |a| if (a >= opts.count) {
        g.anchor = null;
    };
    const pitch = (opts.row_height + row_gap) * k;
    const before = if (opts.selected) |s| s.* else null;
    if (opts.max_rows) |n| {
        g.rows_end = @min(n, opts.count);
        g.last = g.rows_end;
        g.useKeys(before, keys.useKeys(c, own.focused, opts.selected, g.rows_end, n));
        g.plain = ui.div(c).column().wFull().gap(row_gap * k).pt(row_gap * k);
    } else {
        // The list's scroll and height as the last frame left them, to
        // page by a view, keep a row in it and say which rows it shows.
        const id = c.peekId(null);
        const view_h = if (c.rects.get(id)) |r| r.h else c.size.h;
        g.useKeys(before, keys.useKeys(c, own.focused, opts.selected, opts.count, @max(1, @as(usize, @intFromFloat(view_h / pitch)))));
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
            const bottom = top + pitch + row_gap * k;
            if (top < offset) scroll_to = top else if (bottom > offset + view_h) scroll_to = bottom - view_h;
        };
        if (scroll_to) |y| offset = y;
        offset = std.math.clamp(offset, 0, @max(0, pitch * count - view_h));
        const pad = row_gap * k;
        g.first = @min(opts.count, @as(usize, @intFromFloat(@floor(@max(0, offset - pad) / pitch))));
        g.last = @min(opts.count, @as(usize, @intFromFloat(@ceil(@max(0, offset + view_h - pad) / pitch))));
        g.list = ui.list(c, .{ .count = opts.count, .row_height = opts.row_height * k, .gap = row_gap * k, .padding = .{ .top = pad, .right = lay_mod.scrollbar_gutter }, .scroll_to = scroll_to });
    }
    g.typed = keys.useTyping(c, own.focused, lay_mod.state(c, keys.Typing), opts.count);
    if (opts.count == 0) if (opts.empty) |text| {
        const d = ui.div(c).wFull().px(opts.padding * k).py(8 * k);
        defer d.end();
        ui.text(c, text, .{ .size = 13, .color = t.muted });
    };
    return g;
}

/// What the grid keeps between frames: where Shift-click and Shift with
/// the keys select from, the row `jump` scrolls to next, and how far the
/// columns are scrolled sideways.
const Kept = struct { anchor: ?usize = null, jump_to: ?usize = null, sx: f32 = 0 };

/// A row held down: which, where the pointer went down, and whether it
/// has moved far enough to drag.
const Press = struct { row: ?usize = null, x: f32 = 0, y: f32 = 0, dragging: bool = false };

pub const Grid = struct {
    /// The rows in view this frame, from `first` up to but not including
    /// `last`: a caller that loads rows as they come into view fetches
    /// these, and the ones around them.
    first: usize = 0,
    last: usize = 0,
    /// The header changed the sort this frame: sort the rows before
    /// building them.
    sorted: bool,
    /// What has been typed to jump to a row, with this frame's typing;
    /// null when nothing was typed this frame. The caller finds the first
    /// row it begins (ignoring case, as Finder does) and `jump`s to it.
    typed: ?[]const u8 = null,
    /// The grid has the keyboard: its arrows, Enter, Cmd+A and typing are
    /// its. A click in it or Tab gives it the keyboard, and so does
    /// `c.focusNext` called just before `grid`.
    focused: bool,

    // The rest is the grid's own: callers read the fields above, and use
    // the methods.
    c: *ui.Context,
    box: ui.Div,
    columns: []const Column,
    opts: Options,
    /// The id of the box that takes the keyboard for the grid; 0 without
    /// `selected`.
    own: u64,
    /// Where the columns go this frame.
    lay: Layout,
    /// Where Shift-click and Shift with the keys select from, and the row
    /// held down, kept by `end` for the next frame.
    anchor: ?usize,
    press: Press,
    /// The rows built; null with `opts.max_rows`, which builds them in
    /// `plain` from `next` up to `rows_end`.
    list: ?ui.ListRows = null,
    plain: ?ui.Div = null,
    next_row: usize = 0,
    rows_end: usize = 0,
    /// The row Enter opened this frame.
    opened: ?usize = null,
    /// The row `jump` scrolls to, in the next frame.
    jump_to: ?usize = null,
    /// The column a double-click on an edge fits, and the widest of its
    /// title and its cells in view.
    fit: ?usize = null,
    fit_w: f32 = 0,
    /// The row and the cell being built, ended by the next or by `end`;
    /// the box past the frozen column that cuts the row's other cells
    /// off; and whether the row is under the pointer.
    row: ?ui.Div = null,
    cut: ?ui.Div = null,
    cell_box: ?ui.Div = null,
    cell_column: usize = 0,
    column: usize = 0,
    row_hovered: bool = false,

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
        // Its cells are placed by the layout, in the columns' order.
        var r = ui.div(g.c).wFull().h(g.opts.row_height * k);
        if (!g.opts.row_lines) r = r.rounded(t.radius - 2);
        const it: ui.Interaction = if (g.opts.clickable) r.interaction() else .{ .id = 0, .rect = null, .hovered = false, .pressed = false, .clicked = false, .focused = false };
        if (it.secondary_clicked) {
            // The menu's keys go to the grid, as a click's do.
            if (g.own != 0) g.c.focus = g.own;
            if (!g.isSelected(i)) g.pick(i, .only);
        } else if (it.clicked) {
            const in = g.c.input;
            const adds = if (builtin.os.tag.isDarwin()) in.cmd else in.ctrl;
            g.pick(i, if (in.shift) .extend else if (adds) .toggle else .only);
        }
        if (it.clicked or it.secondary_clicked) g.c.changed = true;
        const drag_started = g.opts.drag_rows and it.pressed and g.pressDrags(i);
        const selected = g.isSelected(i);
        // The selection is the accent's color while the grid has the
        // keyboard, and grey while something else does.
        const lit = g.focused or g.own == 0;
        if (selected) {
            r = r.bg(if (lit) t.primary.alpha(0.18) else t.muted.alpha(0.2));
        } else if (g.opts.striped and i % 2 == 1) r = r.bg(t.surface.alpha(0.35));
        // A selected row stays the selection's color under the pointer.
        if (g.opts.hover and g.opts.clickable) r = r.hover(if (selected) (if (lit) t.primary.alpha(0.26) else t.muted.alpha(0.28)) else t.surface_hover.alpha(0.6));
        // A row to a screen reader, read as its cells' text.
        ui.access.describe(g.c, r.index, .{ .role = .row, .selected = selected });
        g.row = r;
        g.row_hovered = it.hovered;
        g.column = 0;
        return .{ .index = i, .clicked = it.clicked, .hovered = it.hovered, .selected = selected, .opened = it.double_clicked or g.opened == i, .secondary_clicked = it.secondary_clicked, .drag_started = drag_started };
    }

    /// Follows row `i` held down: true once it has moved far enough to
    /// drag, when the row is selected unless it is already.
    fn pressDrags(g: *Grid, i: usize) bool {
        const m = g.c.input.mouse;
        if (g.press.row != i) {
            g.press = .{ .row = i, .x = m.x, .y = m.y };
            return false;
        }
        if (g.press.dragging or @abs(m.x - g.press.x) + @abs(m.y - g.press.y) < 4 * g.opts.scale) return false;
        g.press.dragging = true;
        if (!g.isSelected(i)) g.pick(i, .only);
        g.c.changed = true;
        return true;
    }

    /// Starts dragging `text` out of the grid, with the row being built as
    /// what is seen dragged: in the frame `Row.drag_started` says so.
    pub fn dragOut(g: *Grid, text: []const u8) void {
        const r = g.row orelse return;
        g.c.startDrag(r.index, text);
    }

    /// Selects row `i` alone, if rows select, and scrolls it into view:
    /// where `typed` leads. The grid is drawn again to show it.
    pub fn jump(g: *Grid, i: usize) void {
        if (i >= g.opts.count) return;
        g.pick(i, .only);
        g.jump_to = i;
        g.c.changed = true;
    }

    /// Row `i` is selected: among `selection`'s, or `selected` without it.
    fn isSelected(g: *const Grid, i: usize) bool {
        if (g.opts.selection) |m| return m[i];
        return if (g.opts.selected) |s| s.* == i else false;
    }

    const Pick = enum { only, toggle, extend };

    /// Makes row `i` the selected one, and changes `selection` as `how` says:
    /// `i` alone, `i` added or taken away, or every row from the anchor
    /// to `i`.
    fn pick(g: *Grid, i: usize, how: Pick) void {
        const s = g.opts.selected orelse return;
        s.* = i;
        const m = g.opts.selection orelse return;
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

    /// Follows the keys with `selection`: the row they moved to alone, or with
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
        if (!g.isShown(i)) return false;
        const c = g.c;
        const l = g.lay;
        const k = g.opts.scale;
        const h = g.opts.row_height * k;
        // The frozen column's cell sits in the row; the others in a box
        // past it that cuts them off as they scroll.
        var origin: f32 = 0;
        if (l.frozen == i) {
            g.endCut();
        } else {
            if (g.cut == null) g.cut = ui.div(c).absolute().offset(l.clip_x, 0).w(@max(0, l.view - l.clip_x)).h(h).clip();
            origin = l.clip_x;
        }
        var d = ui.div(c).absolute().offset(l.at(i) - origin, 0).w(l.w[i]).h(h).row().itemsCenter().gap(g.opts.column_gap * k / 2);
        d = switch (g.columns[i].alignment) {
            .start => d,
            .center => d.justifyCenter(),
            .end => d.justifyEnd(),
        };
        g.cell_box = d;
        g.cell_column = i;
        return true;
    }

    /// Column `i` is shown this frame.
    pub fn isShown(g: *const Grid, i: usize) bool {
        return lay_mod.shown(g.c, g.columns, g.opts, i);
    }

    pub fn end(g: *Grid) void {
        g.endRow();
        if (g.list) |*l| l.end();
        if (g.plain) |p| p.end();
        if (g.fit) |f| if (g.opts.widths) |widths| {
            widths[f] = @max(g.columns[f].min_width, @ceil(g.fit_w / g.opts.scale) + 1);
            g.c.changed = true;
        };
        if (g.opts.scroll_x and g.lay.maxScroll() > 0) lay_mod.sideBar(g.c, g.opts, &g.lay);
        lay_mod.state(g.c, Kept).* = .{ .anchor = g.anchor, .jump_to = g.jump_to, .sx = g.lay.sx };
        lay_mod.state(g.c, Press).* = g.press;
        // A press in the grid that left nothing with the keyboard (on a
        // row, a title, the scrollbar) gives the keyboard to the grid.
        const c = g.c;
        if (g.own != 0 and c.input.pressed and c.focus == 0) if (c.rects.get(c.node(g.box.index).id)) |r| if (r.contains(c.input.mouse)) {
            c.focus = g.own;
        };
        g.box.end();
    }

    /// Ends the cell, measuring it for a fit, and showing its whole text on
    /// hover if it is cut off.
    fn endCell(g: *Grid) void {
        const b = g.cell_box orelse return;
        const i = g.cell_column;
        if (g.fit == i) g.fit_w = @max(g.fit_w, lay_mod.natural(g.c, b.index));
        if (g.opts.tooltips) g.tooltip(b, i);
        b.end();
        g.cell_box = null;
    }

    /// The cell's whole text over it, while the pointer rests on it and
    /// the text is cut off. Asked of every cut-off cell in view, under the
    /// pointer or not, so its wait starts when the pointer comes.
    fn tooltip(g: *Grid, b: ui.Div, i: usize) void {
        const c = g.c;
        const id = c.node(b.index).id;
        const rect = c.rects.get(id) orelse return;
        if (lay_mod.natural(c, b.index) <= g.lay.w[i] + 0.5) return;
        // Not where the frozen column covers it.
        const visible = g.lay.frozen == i or c.input.mouse.x >= g.lay.left + g.lay.clip_x;
        const over = g.row_hovered and visible and rect.contains(c.input.mouse);
        const text = ui.access.textOf(c, c.alloc(), b.index) catch return;
        kit.tooltip(c, .{ .id = id, .rect = rect, .hovered = over, .pressed = false, .clicked = false, .focused = false }, text, .{});
    }

    fn endCut(g: *Grid) void {
        if (g.cut) |d| d.end();
        g.cut = null;
    }

    fn endRow(g: *Grid) void {
        g.endCell();
        if (g.row != null) g.lines();
        g.endCut();
        if (g.row) |r| r.end();
        g.row = null;
    }

    /// The row's lines: down the gaps between its columns, the scrolled
    /// ones' cut off past the frozen column, and along its bottom.
    fn lines(g: *Grid) void {
        const c = g.c;
        const l = g.lay;
        const k = g.opts.scale;
        const h = g.opts.row_height * k;
        const border = kit.tokens(c).border;
        const half = g.opts.column_gap * k / 2;
        if (g.opts.column_lines) {
            if (g.cut == null) g.cut = ui.div(c).absolute().offset(l.clip_x, 0).w(@max(0, l.view - l.clip_x)).h(h).clip();
            var last: ?usize = null;
            for (l.order) |i| if (l.w[i] > 0) {
                last = i;
            };
            for (l.order) |i| {
                if (l.w[i] == 0 or i == last or i == l.frozen) continue;
                ui.div(c).absolute().offset(l.at(i) + l.w[i] + half - l.clip_x, 0).w(1).h(h).bg(border).end();
            }
        }
        g.endCut();
        if (l.frozen) |f| if (g.opts.column_lines or l.sx > 0) {
            ui.div(c).absolute().offset(l.x[f] + l.w[f] + half, 0).w(1).h(h).bg(border).end();
        };
        if (g.opts.row_lines) ui.div(c).absolute().offset(0, h - 1).w(l.view).h(1).bg(border).end();
    }
};

test {
    _ = @import("grid_tests.zig");
    _ = @import("grid_columns_tests.zig");
    _ = @import("grid_select_tests.zig");
    _ = @import("grid_keys_tests.zig");
}
