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
};

/// Opens the grid's box, which takes the room left in its parent, and
/// draws the header: build the rows with `next` and `cell`, then `end`.
pub fn grid(c: *ui.Context, columns: []const Column, opts: Options) Grid {
    const t = kit.tokens(c);
    const k = opts.scale;
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
    if (opts.rows) |n| {
        g.last = @min(n, opts.count);
        g.plain = ui.div(c).column().wFull().gap(opts.gap * k).pt(opts.gap * k);
    } else {
        g.list = ui.list(c, .{ .count = opts.count, .row_height = opts.row_height * k, .gap = opts.gap * k, .padding = .{ .top = opts.gap * k } });
    }
    return g;
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
        if (g.opts.striped and i % 2 == 1) r = r.bg(t.surface.alpha(0.35));
        if (g.opts.hover) r = r.hover(t.surface_hover.alpha(0.6));
        const it = r.interaction();
        if (it.clicked) g.c.changed = true;
        g.row = r;
        g.column = 0;
        return .{ .index = i, .clicked = it.clicked, .hovered = it.hovered };
    }

    /// Opens the row's next cell, ending the one before: what is drawn
    /// until the next `cell` goes in it. When columns hide, use `cellAt`.
    pub fn cell(g: *Grid) void {
        std.debug.assert(g.cellAt(g.column));
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

/// A grid of fruit for the tests: a name, a sortable count lined up at
/// the end, and a column that doesn't sort.
const Fruit = struct {
    sort: Sort = .{},
    sorted: usize = 0,
    clicked: ?usize = null,
    built: usize = 0,
    count: usize = 3,

    const columns = [_]Column{
        .{ .title = "Fruit", .sortable = true },
        .{ .title = "Count", .width = 80, .alignment = .end, .sortable = true, .descending_first = true },
        .{ .title = "Note", .width = 120 },
    };
    const names = [_][]const u8{ "apple", "banana", "cherry" };

    fn view(f: *Fruit, c: *ui.Context) void {
        var g = grid(c, &columns, .{ .count = f.count, .sort = &f.sort });
        if (g.sorted) f.sorted += 1;
        while (g.next()) |row| {
            f.built += 1;
            if (row.clicked) f.clicked = row.index;
            g.cell();
            ui.text(c, if (row.index < names.len) names[row.index] else "more", .{});
            g.cell();
            ui.text(c, c.print("{d}", .{row.index * 100}), .{});
            g.cell();
            ui.text(c, "ripe", .{});
        }
        g.end();
    }
};

test "a grid's titles sort: a new column its own way first, again the other way" {
    var f: Fruit = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&f, Fruit.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // Largest first, as the column asks.
    try t.clickText("Count");
    t.settle(1);
    try std.testing.expectEqual(Sort{ .column = 1, .descending = true }, f.sort);
    try t.clickText("Count");
    t.settle(1);
    try std.testing.expectEqual(Sort{ .column = 1, .descending = false }, f.sort);
    try t.clickText("Fruit");
    t.settle(1);
    try std.testing.expectEqual(Sort{ .column = 0, .descending = false }, f.sort);
    // A column that doesn't sort ignores clicks.
    try t.clickText("Note");
    t.settle(1);
    try std.testing.expectEqual(Sort{ .column = 0, .descending = false }, f.sort);
    try std.testing.expectEqual(@as(usize, 3), f.sorted);
}

test "a grid's cells line up under their titles, and its rows report clicks" {
    var f: Fruit = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&f, Fruit.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const fruit = t.findText("Fruit").?;
    const apple = t.findText("apple").?;
    try std.testing.expectApproxEqAbs(fruit.x, apple.x, 0.5);
    // Lined up at the end: the right edges meet.
    const count = t.findText("Count").?;
    const hundred = t.findText("100").?;
    try std.testing.expectApproxEqAbs(count.x + count.w, hundred.x + hundred.w, 0.5);
    try std.testing.expect(hundred.y > count.y);
    const note = t.findText("Note").?;
    try std.testing.expectApproxEqAbs(note.x, t.findText("ripe").?.x, 0.5);
    try t.clickText("banana");
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 1), f.clicked);
}

test "a long grid builds only the rows in view" {
    var f: Fruit = .{ .count = 10_000 };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&f, Fruit.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    f.built = 0;
    t.frame();
    try std.testing.expect(f.built > 0 and f.built < 30);
}

/// A grid of fruit whose columns hide, in a window `Tester` sizes.
const Basket = struct {
    sort: Sort = .{},
    hidden: [3]bool = .{ false, false, false },
    rows: ?usize = null,
    scale: f32 = 1,
    count: usize = 3,
    built: usize = 0,
    hidden_cells: usize = 0,

    const columns = [_]Column{
        .{ .title = "Fruit", .sortable = true },
        .{ .title = "Count", .width = 80, .alignment = .end, .sortable = true, .min_window_width = 500 },
        .{ .title = "Note", .width = 120 },
    };

    fn view(b: *Basket, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        var g = grid(c, &columns, .{ .count = b.count, .sort = &b.sort, .hidden = &b.hidden, .rows = b.rows, .scale = b.scale });
        while (g.next()) |row| {
            b.built += 1;
            if (g.cellAt(0)) ui.text(c, c.print("fruit {d}", .{row.index}), .{});
            if (g.cellAt(1)) ui.text(c, c.print("{d}", .{row.index * 100}), .{}) else b.hidden_cells += 1;
            if (g.cellAt(2)) ui.text(c, "ripe", .{}) else b.hidden_cells += 1;
        }
        g.end();
        ui.text(c, "below", .{});
    }
};

test "a grid's columns hide in narrow windows and when the caller hides them" {
    var b: Basket = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&b, Basket.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // Narrower than Count's 500: its title and cells are gone.
    try std.testing.expect(t.findText("Count") == null);
    try std.testing.expect(t.findText("100") == null);
    try std.testing.expect(b.hidden_cells > 0);
    try std.testing.expectApproxEqAbs(t.findText("Note").?.x, t.findText("ripe").?.x, 0.5);
    b.hidden[2] = true;
    t.settle(1);
    try std.testing.expect(t.findText("Note") == null);
    try std.testing.expect(t.findText("ripe") == null);
    try std.testing.expect(t.findText("fruit 0") != null);
}

test "a grid's columns show in wide windows, keeping their numbers" {
    var b: Basket = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&b, Basket.view), .{ .width = 600, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const count = t.findText("Count").?;
    const hundred = t.findText("100").?;
    try std.testing.expectApproxEqAbs(count.x + count.w, hundred.x + hundred.w, 0.5);
    try std.testing.expectEqual(@as(usize, 0), b.hidden_cells);
    try t.clickText("Count");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), b.sort.column);
}

test "a grid of a few rows builds that many, takes their height and doesn't fill the room" {
    var b: Basket = .{ .rows = 2, .count = 100 };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&b, Basket.view), .{ .width = 400, .height = 600 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(t.findText("fruit 1") != null);
    try std.testing.expect(t.findText("fruit 2") == null);
    b.built = 0;
    t.frame();
    try std.testing.expectEqual(@as(usize, 2), b.built);
    // What follows sits under the two rows, not at the bottom of the window.
    const below = t.findText("below").?;
    const last = t.findText("fruit 1").?;
    try std.testing.expect(below.y > last.y and below.y < last.y + 40);
}

test "a grid's lengths follow its scale" {
    var b: Basket = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&b, Basket.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const note1 = t.findText("Note").?.x;
    const row1 = t.findText("fruit 1").?.y - t.findText("fruit 0").?.y;
    b.scale = 2;
    // 800 wide at scale 2: as wide as 400 is at 1, so Count stays hidden.
    t.resize(800, 600);
    t.settle(1);
    try std.testing.expect(t.findText("Count") == null);
    try std.testing.expectApproxEqAbs(note1 * 2, t.findText("Note").?.x, 1);
    try std.testing.expectApproxEqAbs(row1 * 2, t.findText("fruit 1").?.y - t.findText("fruit 0").?.y, 1);
}

test "a long name in the column that takes the room left keeps the others in line" {
    const Long = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            var g = grid(c, &Fruit.columns, .{ .count = 1 });
            while (g.next()) |_| {
                g.cell();
                ui.text(c, "a name far too long for the room the fixed columns leave it, and then some", .{ .truncate = .ellipsis });
                g.cell();
                ui.text(c, "100", .{});
                g.cell();
                ui.text(c, "ripe", .{});
            }
            g.end();
        }
    };
    var l: Long = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&l, Long.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expectApproxEqAbs(t.findText("Note").?.x, t.findText("ripe").?.x, 0.5);
    const count = t.findText("Count").?;
    const hundred = t.findText("100").?;
    try std.testing.expectApproxEqAbs(count.x + count.w, hundred.x + hundred.w, 0.5);
}
