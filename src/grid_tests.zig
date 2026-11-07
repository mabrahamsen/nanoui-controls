//! The grid's tests: sorting, lining up, building only the rows in view,
//! hiding columns, a set number of rows, scale, selection and the keys.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const g_mod = @import("grid.zig");
const grid = g_mod.grid;
const Column = g_mod.Column;
const Sort = g_mod.Sort;

/// A grid of fruit for the tests: a name, a sortable count lined up at
/// the end, and a column that doesn't sort.
pub const Fruit = struct {
    sort: Sort = .{},
    sorted: usize = 0,
    clicked: ?usize = null,
    built: usize = 0,
    count: usize = 3,
    /// The view marked a frame changed.
    changed: bool = false,

    pub const columns = [_]Column{
        .{ .title = "Fruit", .sortable = true },
        .{ .title = "Count", .width = 80, .alignment = .end, .sortable = true, .descending_first = true },
        .{ .title = "Note", .width = 120 },
    };
    pub const names = [_][]const u8{ "apple", "banana", "cherry" };

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
        if (c.changed) f.changed = true;
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
        var g = grid(c, &columns, .{ .count = b.count, .sort = &b.sort, .hidden = &b.hidden, .max_rows = b.rows, .scale = b.scale });
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
    // Everything doubles but the scrollbar's gutter, which the bar
    // doesn't scale either: Note's right edge stays 10 points further in.
    try std.testing.expectApproxEqAbs((note1 + 10) * 2 - 10, t.findText("Note").?.x, 1);
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

test "a grid marks the frame changed when its sort changes or a row is clicked" {
    var f: Fruit = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&f, Fruit.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    f.changed = false;
    t.frame();
    try std.testing.expect(!f.changed);
    try t.clickText("Count");
    try std.testing.expect(f.changed);
    t.settle(1);
    f.changed = false;
    try t.clickText("banana");
    try std.testing.expect(f.changed);
}

test "an empty grid shows its titles and builds no rows" {
    var f: Fruit = .{ .count = 0 };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&f, Fruit.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(t.hasText("Fruit"));
    try std.testing.expectEqual(@as(usize, 0), f.built);
}

test "a grid asked for more rows than it has builds the ones it has" {
    var b: Basket = .{ .rows = 5, .count = 3 };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&b, Basket.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    b.built = 0;
    t.frame();
    try std.testing.expectEqual(@as(usize, 3), b.built);
}

test "a sortable column's title ignores clicks when the caller keeps no sort" {
    const Unsorted = struct {
        sorted: usize = 0,
        fn view(u: *@This(), c: *ui.Context) void {
            var g = grid(c, &Fruit.columns, .{ .count = 3 });
            if (g.sorted) u.sorted += 1;
            while (g.next()) |row| {
                g.cell();
                ui.text(c, Fruit.names[row.index], .{});
                g.cell();
                ui.text(c, "100", .{});
                g.cell();
                ui.text(c, "ripe", .{});
            }
            g.end();
        }
    };
    var u: Unsorted = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&u, Unsorted.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    try t.clickText("Fruit");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 0), u.sorted);
}

/// A long grid whose rows select, under a search field the keys go to
/// when it has the focus.
const Picker = struct {
    selected: ?usize = null,
    opened: ?usize = null,
    count: usize = 1000,
    rows: ?usize = null,
    field: bool = false,
    search: ui.TextBuffer = .{},
    /// Asked of the grid for one frame.
    scroll_to: ?usize = null,
    /// The rows the grid says are in view.
    first: usize = 0,
    last: usize = 0,

    fn view(p: *Picker, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        if (p.field) _ = ui.textField(c, &p.search, .{ .placeholder = "Search" });
        var g = grid(c, &Fruit.columns, .{ .count = p.count, .selected = &p.selected, .max_rows = p.rows, .scroll_to = p.scroll_to });
        p.scroll_to = null;
        p.first = g.first;
        p.last = g.last;
        while (g.next()) |row| {
            if (row.opened) p.opened = row.index;
            g.cell();
            ui.text(c, c.print("fruit {d}", .{row.index}), .{});
            g.cell();
            ui.text(c, c.print("{d}", .{row.index * 100}), .{});
            g.cell();
            ui.text(c, if (row.selected) "picked" else "-", .{});
        }
        g.end();
    }

    /// Where row `i`'s first cell starts, if it is built.
    fn top(t: *ui.Tester, i: usize) ?f32 {
        var buf: [32]u8 = undefined;
        const r = t.findText(std.fmt.bufPrint(&buf, "fruit {d}", .{i}) catch unreachable) orelse return null;
        return r.y;
    }

    /// Row `i` is built and inside the window, not just in the overscan.
    fn inView(t: *ui.Tester, i: usize) bool {
        var buf: [32]u8 = undefined;
        const r = t.findText(std.fmt.bufPrint(&buf, "fruit {d}", .{i}) catch unreachable) orelse return false;
        return r.y >= 0 and r.y + r.h <= t.size.h;
    }
};

test "a click selects a row, and the row says it is selected" {
    var p: Picker = .{};
    defer p.search.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Picker.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(!t.hasText("picked"));
    try t.clickText("fruit 2");
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 2), p.selected);
    const picked = t.findText("picked").?;
    try std.testing.expectApproxEqAbs(t.findText("fruit 2").?.y, picked.y, 1);
}

test "the keys move the selection and keep it in view" {
    var p: Picker = .{};
    defer p.search.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Picker.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // Down with nothing selected selects the first row; Up stops there.
    t.key(.down);
    try std.testing.expectEqual(@as(?usize, 0), p.selected);
    try std.testing.expect(t.shortcut(.{ .key = ui.Shortcut.down }));
    try std.testing.expectEqual(@as(?usize, 1), p.selected);
    t.key(.up);
    t.key(.up);
    try std.testing.expectEqual(@as(?usize, 0), p.selected);
    // Down past the bottom of the view scrolls the row into it.
    for (0..30) |_| t.key(.down);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 30), p.selected);
    try std.testing.expect(Picker.inView(&t, 30));
    t.key(.end);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 999), p.selected);
    try std.testing.expect(Picker.inView(&t, 999));
    t.key(.home);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 0), p.selected);
    try std.testing.expect(Picker.inView(&t, 0));
    // A page is about a view's worth of rows: 300 points of 30.
    t.key(.page_down);
    t.settle(1);
    const page = p.selected.?;
    try std.testing.expect(page >= 5 and page <= 10);
    try std.testing.expect(Picker.inView(&t, page));
    t.key(.page_down);
    try std.testing.expectEqual(@as(?usize, page * 2), p.selected);
    t.key(.page_up);
    t.key(.page_up);
    t.key(.page_up);
    try std.testing.expectEqual(@as(?usize, 0), p.selected);
}

test "Enter and a double click open a row" {
    var p: Picker = .{};
    defer p.search.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Picker.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // Enter with nothing selected opens nothing.
    t.key(.enter);
    try std.testing.expectEqual(@as(?usize, null), p.opened);
    try t.clickText("fruit 3");
    t.settle(1);
    t.key(.enter);
    try std.testing.expectEqual(@as(?usize, 3), p.opened);
    const five = t.findText("fruit 5").?;
    t.doubleClick(five.x + five.w / 2, five.y + five.h / 2);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 5), p.opened);
    try std.testing.expectEqual(@as(?usize, 5), p.selected);
}

test "a focused text field keeps the keys from the grid" {
    var p: Picker = .{ .field = true };
    defer p.search.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Picker.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    try t.clickText("Search");
    t.settle(1);
    try std.testing.expect(!t.shortcut(.{ .key = ui.Shortcut.down }));
    t.key(.end);
    try std.testing.expectEqual(@as(?usize, null), p.selected);
    // A click on a row takes the keyboard back.
    try t.clickText("fruit 1");
    t.settle(1);
    t.key(.down);
    try std.testing.expectEqual(@as(?usize, 2), p.selected);
}

test "a selection past the rows moves back to the last, or to none" {
    var p: Picker = .{ .count = 10, .selected = 50 };
    defer p.search.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Picker.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 9), p.selected);
    p.count = 0;
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, null), p.selected);
    t.key(.down);
    try std.testing.expectEqual(@as(?usize, null), p.selected);
}

test "a grid of a set number of rows keeps the selection among them" {
    var p: Picker = .{ .rows = 3 };
    defer p.search.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Picker.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    t.key(.end);
    try std.testing.expectEqual(@as(?usize, 2), p.selected);
    t.key(.page_up);
    try std.testing.expectEqual(@as(?usize, 0), p.selected);
}

test "a grid says which rows are in view, as it scrolls" {
    var p: Picker = .{};
    defer p.search.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Picker.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 0), p.first);
    // The last row in view starts inside the window, perhaps cut off at
    // its bottom; the next starts below it.
    try std.testing.expect(Picker.top(&t, p.last - 1).? < t.size.h);
    try std.testing.expect(Picker.top(&t, p.last).? >= t.size.h);
    t.key(.end);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1000), p.last);
    try std.testing.expect(p.first > 980);
    // The first row in view ends inside it, perhaps cut off at its top.
    const first = t.findText("fruit 0");
    try std.testing.expect(first == null or first.?.y < 0);
    try std.testing.expect(Picker.top(&t, p.first).? + 20 > t.findText("Fruit").?.y);
}

test "a grid of a set number of rows has them all in view" {
    var p: Picker = .{ .rows = 3 };
    defer p.search.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Picker.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 0), p.first);
    try std.testing.expectEqual(@as(usize, 3), p.last);
}

test "scroll_to brings a row into view, and leaves the scroll alone after" {
    var p: Picker = .{};
    defer p.search.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Picker.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    p.scroll_to = 500;
    t.settle(1);
    try std.testing.expect(Picker.inView(&t, 500));
    try std.testing.expect(p.first <= 500 and 500 < p.last);
    // A row already in view doesn't move.
    const first = p.first;
    p.scroll_to = first + 1;
    t.settle(1);
    try std.testing.expectEqual(first, p.first);
    // Nor does the scroll jump back once the caller stops asking.
    t.scroll(200, 200, -60);
    t.settle(1);
    try std.testing.expect(p.first != first);
}

test "the scrollbar's thumb drags and its track clicks, over the rows" {
    var p: Picker = .{};
    defer p.search.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Picker.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // The thumb starts at the top of the rows, at the window's right edge.
    const top = t.findText("fruit 0").?.y;
    t.drag(396, top + 10, 396, top + 120);
    t.settle(1);
    try std.testing.expect(p.first > 0);
    try std.testing.expectEqual(@as(?usize, null), p.selected);
    // A press low on the track jumps toward the end.
    t.click(396, t.size.h - 10);
    t.settle(1);
    try std.testing.expect(p.first > 900);
    try std.testing.expectEqual(@as(?usize, null), p.selected);
}

test "a scrolling grid's rows stop short of the scrollbar, and the titles with them" {
    var f: Fruit = .{ .count = 100 };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&f, Fruit.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // Note ends at the window's edge less the padding and the gutter.
    const ripe = t.findText("ripe").?;
    try std.testing.expect(t.findText("Note").?.x + 120 <= 400 - 10 - 10 + 0.5);
    try std.testing.expectApproxEqAbs(t.findText("Note").?.x, ripe.x, 0.5);
    const count = t.findText("Count").?;
    const hundred = t.findText("100").?;
    try std.testing.expectApproxEqAbs(count.x + count.w, hundred.x + hundred.w, 0.5);
}
