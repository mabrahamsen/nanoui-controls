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
//! Rows can be grouped under headings that fold (`groups`, with
//! `GridGroups`), and drawn as cards (`rows = .cards`). While the rows
//! load, `loading` sketches them, or with rows in, draws a thin progress
//! line. `back` and `escaped` report Backspace (or Cmd+Up) and Escape.
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
const groups_mod = @import("grid_groups.zig");
const loading_mod = @import("grid_loading.zig");

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
    /// Shown only while the grid itself is at least this wide, in points
    /// before `scale`: it gives way when a pane beside the grid narrows it,
    /// not only the window.
    min_grid_width: f32 = 0,

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
    /// Lines of text a row has room for: each past the first adds to
    /// `row_height`, for cells drawn with `twoLines`.
    lines: u8 = 1,
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
    /// Shown under the titles when there are no rows, once they have
    /// loaded.
    empty: ?[]const u8 = null,
    /// The rows are loading: with none yet, a spinner, `label` and a
    /// progress bar over rows sketched in the columns; with rows in, a
    /// thin progress line under the titles.
    loading: ?Loading = null,
    /// The rows are grouped under headings: what each row in view is.
    /// `count` is `groups.count()`. Draw a heading's row with `heading`.
    groups: ?groups_mod.Groups = null,
    /// What a screen reader says of a heading whose group is open, and
    /// folded.
    expanded_text: []const u8 = "expanded",
    collapsed_text: []const u8 = "collapsed",
    /// The column titles show; false leaves them out, and sorting by them.
    header: bool = true,
    /// Rows as plain rows, or as cards: the theme's surface, a border and
    /// its corners, with room between them.
    rows: RowLook = .plain,
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

/// How far along loading rows is.
pub const Loading = struct {
    /// What is being waited for ("Asking the server…").
    label: []const u8 = "",
    /// How many of `total` pages or sources have answered; with `total`
    /// 0, how far along isn't known.
    done: usize = 0,
    total: usize = 0,
};

pub const RowLook = enum { plain, cards };

/// A heading's look (`Grid.heading`).
pub const Heading = struct {
    title: []const u8,
    /// Muted, after the title: "4 pull requests".
    detail: []const u8 = "",
    /// The title in the first column's cell, leaving the others for the
    /// caller's `cellAt`, for a group's totals; false spans the columns.
    cells: bool = false,
};

/// A cell's two lines (`Grid.twoLines`).
pub const TwoLines = struct {
    /// The title's size; the detail is a point and a half smaller.
    size: f32 = 13,
    /// Null takes the theme's muted text.
    detail_color: ?ui.Color = null,
    mono_detail: bool = false,
};

/// How far in each level of a group goes: a heading's chevron and the
/// gap after it, in points before `scale`.
const indent_step = 18;

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
    grid: *Grid,

    /// Tints the row's edge in `s`'s color, a card's border or a plain
    /// row's leading edge: a failed run, a warning. Call it before the
    /// row's cells.
    pub fn status(r: Row, s: kit.Status) void {
        r.grid.rowStatus(s);
    }
};

/// Opens the grid's box, which takes the room left in its parent, and
/// draws the header: build the rows with `next` and `cell`, then `end`.
pub fn grid(c: *ui.Context, columns: []const Column, opts: Options) Grid {
    lay_mod.check(columns, opts);
    const t = kit.tokens(c);
    const k = opts.scale;
    var box = ui.div(c).column().wFull();
    if (opts.max_rows == null) {
        box = box.grow();
        // It can be shorter than its rows, in a column that grows, and
        // scrolls them.
        c.node(box.index).style.min_height = 0;
    }
    follow(c, opts);
    if (opts.selected) |s| if (s.*) |i| if (i >= opts.count) {
        s.* = if (opts.count > 0) opts.count - 1 else null;
        c.changed = true;
    };
    const own = keys.take(c, box, opts.selected != null);
    if (opts.selection) |m| if (own.focused and opts.count > 0 and c.shortcut(.{ .key = 'a', .cmd = true })) @memset(m, true);
    // Copied in here and written back by `end`.
    const kept = lay_mod.state(c, Kept).*;
    const press: Press = if (c.input.down) lay_mod.state(c, Press).* else .{};
    const opening = lay_mod.state(c, Opening).*;
    if (opts.loading) |l| if (!kept.loading) ui.access.announce(c, l.label);
    const lay = lay_mod.layout(c, columns, opts, box, kept.sx);
    const head: @import("grid_header.zig").Head = if (opts.header) header(c, columns, opts, lay) else .{};
    if (opts.header and opts.header_line) ui.div(c).wFull().h(1).bg(t.border).end();
    if (opts.loading) |l| if (opts.count > 0) loading_mod.line(c, opts, l);
    var g: Grid = .{ .c = c, .box = box, .columns = columns, .opts = opts, .lay = lay, .anchor = kept.anchor, .press = press, .sorted = head.sorted, .focused = own.focused, .own = own.id, .fit = head.fit, .fit_w = head.fit_w };
    g.fadeFrom(opening);
    const row_gap = rowGap(opts);
    if (g.anchor) |a| if (a >= opts.count) {
        g.anchor = null;
    };
    const pitch = (lay_mod.rowHeight(opts) + row_gap) * k;
    const before = if (opts.selected) |s| s.* else null;
    g.groupKeys();
    g.otherKeys();
    // A page of sketched rows, while there are none to show yet.
    var sketched: usize = 0;
    if (opts.max_rows) |n| {
        g.rows_end = @min(n, opts.count);
        g.last = g.rows_end;
        g.useKeys(before, keys.useKeys(c, own.focused, opts.selected, g.rows_end, n));
        g.plain = ui.div(c).column().wFull().gap(row_gap * k).pt(row_gap * k);
        sketched = n;
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
        g.list = ui.list(c, .{ .count = opts.count, .row_height = lay_mod.rowHeight(opts) * k, .gap = row_gap * k, .padding = .{ .top = pad, .right = lay_mod.scrollbar_gutter }, .scroll_to = scroll_to });
        sketched = @max(1, @as(usize, @intFromFloat(@ceil(view_h / pitch))));
    }
    g.typed = keys.useTyping(c, own.focused, lay_mod.state(c, keys.Typing), opts.count);
    if (opts.count == 0) {
        if (opts.loading) |l| {
            loading_mod.sketch(c, columns, opts, lay, l, sketched);
        } else if (opts.empty) |text| {
            const d = ui.div(c).wFull().px(opts.padding * k).py(8 * k);
            defer d.end();
            ui.text(c, text, .{ .size = 13, .color = t.muted });
        }
    }
    return g;
}

/// The room between rows: none with lines between them, which the rows
/// meet, and more between cards.
fn rowGap(opts: Options) f32 {
    if (opts.rows == .cards) return @max(opts.gap, 6);
    return if (opts.row_lines) 0 else opts.gap;
}

/// Keeps `selected` on the row it was on when the rows in view changed
/// under it, as a group above it folded or opened; on the nearest heading
/// over it when it was folded away. A caller that moved the selection
/// itself keeps its own.
fn follow(c: *ui.Context, opts: Options) void {
    const gs = opts.groups orelse return;
    const s = opts.selected orelse return;
    const i = s.* orelse return;
    const was = lay_mod.state(c, Follow).*;
    const item = was.item orelse return;
    if (was.at != i) return;
    if (i < gs.count() and gs.at(i).eql(item)) return;
    if (gs.locate(item)) |j| {
        s.* = j;
        c.changed = true;
    }
}

/// What the grid keeps between frames: where Shift-click and Shift with
/// the keys select from, the row `jump` scrolls to next, how far the
/// columns are scrolled sideways, and whether it was loading.
const Kept = struct { anchor: ?usize = null, jump_to: ?usize = null, sx: f32 = 0, loading: bool = false };

/// The selected row's place in its groups, and where it was in view, to
/// follow it when groups fold or open.
const Follow = struct { item: ?groups_mod.Item = null, at: usize = 0 };

/// The group opened last, and when, whose rows fade in.
const Opening = struct { group: usize = std.math.maxInt(usize), at: f64 = 0 };

/// How long a group's rows take to fade in as it opens, in seconds.
const fade_time = 0.2;

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
    /// Backspace, or Cmd+Up (Alt+Up off the Mac), was pressed while the
    /// grid has the keyboard: a browser goes to the parent folder.
    back: bool = false,
    /// Escape was pressed while the grid has the keyboard, for an app that
    /// clears a search or closes a pane on it.
    escaped: bool = false,

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
    /// The row being built: its index, whether it was clicked, and how
    /// many group levels in it is.
    row_index: usize = 0,
    row_clicked: bool = false,
    row_depth: u8 = 0,
    /// The group whose rows fade in, as it opened, and how far they are;
    /// and the group opened this frame, which `end` keeps.
    fade_group: ?usize = null,
    fade: f32 = 1,
    opened_group: ?usize = null,

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
        const cards = g.opts.rows == .cards;
        const item: ?groups_mod.Item = if (g.opts.groups) |gs| gs.at(i) else null;
        const is_heading = if (item) |it| it == .heading else false;
        // Its cells are placed by the layout, in the columns' order.
        var r = ui.div(g.c).wFull().h(lay_mod.rowHeight(g.opts) * k);
        if (cards) {
            r = r.rounded(t.radius).bg(t.surface).border(t.border);
        } else if (!g.opts.row_lines) r = r.rounded(t.radius - 2);
        if (item) |it| if (g.fade < 1) if (g.fade_group) |f| {
            const gs = g.opts.groups.?;
            if (gs.within(it.group(), f) and !(is_heading and it.group() == f)) g.c.node(r.index).style.opacity = g.fade;
        };
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
            const accent = if (lit) t.primary else t.muted;
            if (cards) {
                r = r.bg(t.surface.mix(accent, 0.1)).border(if (lit) accent else accent.alpha(0.6));
            } else r = r.bg(if (lit) t.primary.alpha(0.18) else t.muted.alpha(0.2));
        } else if (g.opts.striped and !cards and i % 2 == 1) r = r.bg(t.surface.alpha(0.35));
        // A selected row stays the selection's color under the pointer.
        if (g.opts.hover and g.opts.clickable) r = r.hover(if (selected) (if (lit) t.primary.alpha(0.26) else t.muted.alpha(0.28)) else if (cards) t.surface_hover else t.surface_hover.alpha(0.6));
        // A row to a screen reader, read as its cells' text; a heading
        // describes itself.
        if (!is_heading) ui.access.describe(g.c, r.index, .{ .role = .row, .selected = selected });
        g.row = r;
        g.row_hovered = it.hovered;
        g.row_index = i;
        g.row_clicked = it.clicked;
        g.row_depth = if (item) |x| x.depth() else 0;
        g.column = 0;
        return .{ .index = i, .clicked = it.clicked, .hovered = it.hovered, .selected = selected, .opened = !is_heading and (it.double_clicked or g.opened == i), .secondary_clicked = it.secondary_clicked, .drag_started = drag_started, .grid = g };
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
        const h = lay_mod.rowHeight(g.opts) * k;
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
        // The first column steps in for each level of groups the row is in.
        if (i == 0 and g.row_depth > 0) d = d.pl(@as(f32, @floatFromInt(g.row_depth)) * indent_step * k);
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
        return lay_mod.shown(g.c, g.columns, g.opts, i, g.lay.grid_w);
    }

    /// Draws the row being built as its group's heading: a chevron, the
    /// title and the detail, across the columns, or with `cells` in the
    /// first column's cell, the caller's `cellAt` filling the others. A
    /// click on it folds or opens its group.
    pub fn heading(g: *Grid, opts: Heading) void {
        const gs = g.opts.groups orelse @panic("grid: `heading` needs `groups`");
        const item = gs.at(g.row_index);
        if (item != .heading) @panic("grid: `heading` on a row that isn't one");
        const group = item.heading.group;
        if (g.row_clicked) g.toggle(group);
        const open = gs.open[group];
        const c = g.c;
        const t = kit.tokens(c);
        const k = g.opts.scale;
        // In the first column's cell, unless that column is hidden.
        const in_cell = opts.cells and g.cellAt(0);
        const box = if (in_cell) g.cell_box.? else blk: {
            const x = (g.opts.padding + @as(f32, @floatFromInt(item.heading.depth)) * indent_step) * k;
            break :blk ui.div(c).absolute().offset(x, 0).w(@max(0, g.lay.view - x - g.opts.padding * k)).h(lay_mod.rowHeight(g.opts) * k).row().itemsCenter().gap(g.opts.column_gap * k / 2);
        };
        {
            const slot = ui.div(c).w((indent_step - g.opts.column_gap / 2) * k).h(12 * k).center();
            defer slot.end();
            ui.icon(c, if (open) "chevron.down" else "chevron.right", .{ .size = 9.5, .color = t.muted });
        }
        ui.text(c, opts.title, .{ .size = 13, .weight = .semibold, .truncate = .ellipsis });
        if (opts.detail.len > 0) ui.text(c, opts.detail, .{ .size = 12, .color = t.muted, .truncate = .ellipsis });
        if (!in_cell) box.end();
        const label = if (opts.detail.len > 0) c.print("{s}, {s}", .{ opts.title, opts.detail }) else opts.title;
        ui.access.describe(c, g.row.?.index, .{
            .role = .row,
            .label = label,
            .value = if (open) g.opts.expanded_text else g.opts.collapsed_text,
            .selected = g.isSelected(g.row_index),
        });
    }

    /// Draws a title over a muted detail in the cell open, each cut short
    /// with an ellipsis, and whole in the cell's tooltip. Give the grid
    /// `lines = 2` for the room.
    pub fn twoLines(g: *Grid, title: []const u8, detail: []const u8, opts: TwoLines) void {
        std.debug.assert(g.cell_box != null);
        const c = g.c;
        const col = ui.div(c).column().wFull().gap(1 * g.opts.scale);
        defer col.end();
        ui.text(c, title, .{ .size = opts.size, .truncate = .ellipsis });
        ui.text(c, detail, .{ .size = opts.size - 1.5, .color = opts.detail_color orelse kit.tokens(c).muted, .mono = opts.mono_detail, .truncate = .ellipsis });
    }

    /// Folds or opens `group`; its rows fade in as it opens.
    fn toggle(g: *Grid, group: usize) void {
        const gs = g.opts.groups orelse return;
        gs.open[group] = !gs.open[group];
        if (gs.open[group]) g.opened_group = group;
        g.c.changed = true;
    }

    /// Where the rows of the group opened last are in fading in.
    fn fadeFrom(g: *Grid, o: Opening) void {
        if (g.opts.groups == null or o.group == std.math.maxInt(usize)) return;
        const c = g.c;
        const u: f32 = if (c.reduced_motion) 1 else @floatCast(std.math.clamp((c.time - o.at) / fade_time, 0, 1));
        if (u >= 1) return;
        g.fade_group = o.group;
        g.fade = ui.motion.Easing.sample(.ease_out, u)[0];
        c.animationFrame();
    }

    /// The row's edge in `s`'s color (`Row.status`).
    fn rowStatus(g: *Grid, s: kit.Status) void {
        const r = g.row orelse return;
        const c = g.c;
        const t = kit.tokens(c);
        const k = g.opts.scale;
        const color = if (s == .neutral) t.primary else kit.statusColor(t, s);
        if (g.opts.rows == .cards) {
            _ = r.border(color);
            return;
        }
        g.endCell();
        g.endCut();
        const h = lay_mod.rowHeight(g.opts) * k;
        ui.div(c).absolute().offset(2 * k, 5 * k).w(3 * k).h(@max(0, h - 10 * k)).roundedFull().bg(color).end();
    }

    /// The keys on groups, while the grid has the keyboard: Left folds a
    /// heading or goes from a row to its heading, Right opens a heading or
    /// goes to its first row, and Enter or Space folds or opens one.
    fn groupKeys(g: *Grid) void {
        const gs = g.opts.groups orelse return;
        const s = g.opts.selected orelse return;
        const i = s.* orelse return;
        if (!g.focused or i >= gs.count()) return;
        const c = g.c;
        switch (gs.at(i)) {
            .heading => |h| {
                const open = gs.open[h.group];
                if (c.shortcut(.{ .key = ui.Shortcut.enter }) or c.shortcut(.{ .key = ' ' })) return g.toggle(h.group);
                if (std.mem.eql(u8, c.input.chars, " ")) {
                    c.input.chars = "";
                    return g.toggle(h.group);
                }
                const key = c.input.key orelse return;
                switch (key) {
                    .enter => g.toggle(h.group),
                    .left => if (open) {
                        g.toggle(h.group);
                    } else if (gs.parent(h.group)) |p| {
                        if (gs.locate(.{ .heading = .{ .group = p, .depth = 0 } })) |j| g.pick(j, .only);
                    },
                    .right => if (!open) {
                        g.toggle(h.group);
                    } else if (i + 1 < gs.count() and gs.within(gs.at(i + 1).group(), h.group)) {
                        g.pick(i + 1, .only);
                    },
                    else => return,
                }
                c.input.key = null;
                c.changed = true;
            },
            .row => |r| if (c.input.key == .left) {
                // Its group's heading; a group of one shown as its row goes
                // to the heading over it.
                var to = gs.locate(.{ .heading = .{ .group = r.group, .depth = 0 } });
                if (to == i) to = if (gs.parent(r.group)) |p| gs.locate(.{ .heading = .{ .group = p, .depth = 0 } }) else null;
                if (to) |j| g.pick(j, .only);
                c.input.key = null;
                c.changed = true;
            },
        }
    }

    /// Backspace or Cmd+Up (Alt+Up off the Mac), and Escape, while the
    /// grid has the keyboard.
    fn otherKeys(g: *Grid) void {
        if (!g.focused) return;
        const c = g.c;
        const mac = builtin.os.tag.isDarwin();
        if (c.shortcut(.{ .key = ui.Shortcut.up, .cmd = mac, .alt = !mac })) {
            g.back = true;
            return;
        }
        const key = c.input.key orelse return;
        switch (key) {
            .backspace => g.back = true,
            .up => if (if (mac) c.input.cmd else c.input.alt) {
                g.back = true;
            } else return,
            .escape => g.escaped = true,
            else => return,
        }
        c.input.key = null;
        c.changed = true;
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
        lay_mod.state(g.c, Kept).* = .{ .anchor = g.anchor, .jump_to = g.jump_to, .sx = g.lay.sx, .loading = g.opts.loading != null };
        lay_mod.state(g.c, Press).* = g.press;
        if (g.opts.groups) |gs| {
            const sel = if (g.opts.selected) |s| s.* else null;
            lay_mod.state(g.c, Follow).* = if (sel) |i| (if (i < gs.count()) .{ .item = gs.at(i), .at = i } else .{}) else .{};
            if (g.opened_group) |o| lay_mod.state(g.c, Opening).* = .{ .group = o, .at = g.c.time };
        }
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
        const h = lay_mod.rowHeight(g.opts) * k;
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
        if (g.opts.row_lines and g.opts.rows != .cards) ui.div(c).absolute().offset(0, h - 1).w(l.view).h(1).bg(border).end();
    }
};

test {
    _ = @import("grid_tests.zig");
    _ = @import("grid_columns_tests.zig");
    _ = @import("grid_select_tests.zig");
    _ = @import("grid_keys_tests.zig");
    _ = @import("grid_groups.zig");
    _ = @import("grid_more_tests.zig");
}
