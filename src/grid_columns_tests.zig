//! The grid's tests of its columns: sharing the room left, keeping
//! their minimum widths, resizing and fitting by their edges, moving by
//! their titles, scrolling sideways, tooltips for cut-off cells, and the
//! text of an empty grid under them.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const g_mod = @import("grid.zig");
const grid = g_mod.grid;
const Column = g_mod.Column;
const Fruit = @import("grid_tests.zig").Fruit;

test "an empty grid says so under its titles" {
    const Empty = struct {
        count: usize = 0,
        fn view(e: *@This(), c: *ui.Context) void {
            var g = grid(c, &Fruit.columns, .{ .count = e.count, .empty = "No fruit" });
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
    var e: Empty = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&e, Empty.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const text = t.findText("No fruit").?;
    try std.testing.expect(text.y > t.findText("Fruit").?.y);
    e.count = 2;
    t.settle(1);
    try std.testing.expect(!t.hasText("No fruit"));
    try std.testing.expect(t.hasText("banana"));
}

/// A grid of two columns that share the room left, two to one, and a
/// fixed one, whose widths the caller keeps.
const Shares = struct {
    widths: [3]f32 = .{ 0, 0, 0 },
    resize: bool = false,
    hide_narrow: bool = false,
    scroll: bool = false,

    const columns = [_]Column{
        .{ .title = "Wide", .flex = 2 },
        .{ .title = "Narrow", .flex = 1, .min_width = 60 },
        .{ .title = "Fixed", .width = 80, .min_width = 50 },
    };

    fn view(s: *Shares, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        var g = grid(c, &columns, .{ .count = 1, .widths = if (s.resize) &s.widths else null, .hidden = &.{ false, s.hide_narrow, false }, .scroll_x = s.scroll });
        while (g.next()) |_| {
            for ([_][]const u8{ "w", "n", "f" }, 0..) |text, i| if (g.cellAt(i)) ui.text(c, text, .{});
        }
        g.end();
    }

    /// Where column `title`'s cells start.
    fn x(t: *ui.Tester, title: []const u8) f32 {
        return t.findText(title).?.x;
    }

    /// How wide column `title`'s title box is: the widest box that starts
    /// where its text does, in the header.
    fn w(t: *ui.Tester, title: []const u8) f32 {
        const text = t.findText(title).?;
        var widest: f32 = 0;
        for (t.ctx.nodes.items) |node| {
            const r = t.ctx.rects.get(node.id) orelse continue;
            if (@abs(r.x - text.x) < 0.5 and r.y <= text.y and r.y + r.h >= text.y + text.h and r.h < 40) widest = @max(widest, r.w);
        }
        return widest;
    }
};

test "columns without a width share the room left by their flex" {
    var s: Shares = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&s, Shares.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // 400 less the padding (20), the scrollbar's gutter (10), Fixed (80)
    // and two gaps (20): 270, two thirds to Wide and one to Narrow.
    const wide = Shares.x(&t, "Narrow") - Shares.x(&t, "Wide") - 10;
    const narrow = Shares.x(&t, "Fixed") - Shares.x(&t, "Narrow") - 10;
    try std.testing.expectApproxEqAbs(@as(f32, 270.0 * 2.0 / 3.0), wide, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 270.0 / 3.0), narrow, 1);
    try std.testing.expectApproxEqAbs(Shares.x(&t, "Wide"), t.findText("w").?.x, 0.5);
    try std.testing.expectApproxEqAbs(Shares.x(&t, "Narrow"), t.findText("n").?.x, 0.5);
}

test "a column that shares the room keeps its min_width in a narrow window" {
    var s: Shares = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&s, Shares.view), .{ .width = 260, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // 130 left: a third would be 43, under Narrow's 60.
    const narrow = Shares.x(&t, "Fixed") - Shares.x(&t, "Narrow") - 10;
    try std.testing.expect(narrow >= 60 - 0.5);
}

test "dragging an edge resizes the column on its left, a flexible one from its width on screen, the edge following the pointer" {
    var s: Shares = .{ .resize = true };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&s, Shares.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // Every column starts at 0, its own width.
    try std.testing.expectEqual([3]f32{ 0, 0, 0 }, s.widths);
    const y = t.findText("Fixed").?.y + 4;
    // Narrow, 90 on screen, keeps the width it is dragged to, and Wide
    // the 180 it had, so the edge follows the pointer.
    const fixed = Shares.x(&t, "Fixed");
    t.drag(fixed - 5, y, fixed - 25, y);
    t.settle(1);
    try std.testing.expectApproxEqAbs(@as(f32, 70), s.widths[1], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 180), s.widths[0], 0.5);
    try std.testing.expectApproxEqAbs(fixed - 20, Shares.x(&t, "Fixed"), 1);
    try std.testing.expectApproxEqAbs(Shares.x(&t, "Fixed"), t.findText("f").?.x, 0.5);
    // Never narrower than its min_width.
    const edge = Shares.x(&t, "Fixed") - 5;
    t.drag(edge, y, edge - 300, y);
    t.settle(1);
    try std.testing.expectApproxEqAbs(@as(f32, 60), s.widths[1], 0.5);
}

test "without scroll_x, a drag stops at the room the other columns leave, and the last column takes what is left" {
    var s: Shares = .{ .resize = true, .widths = .{ 0, 70, 80 } };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&s, Shares.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const y = t.findText("Fixed").?.y + 4;
    // 370 between the padding, less Narrow, Fixed and two gaps: 200.
    const edge = Shares.x(&t, "Narrow") - 5;
    t.drag(edge, y, edge + 100, y);
    t.settle(1);
    try std.testing.expectApproxEqAbs(@as(f32, 200), s.widths[0], 0.5);
    // None shares the room now: Fixed, the last, takes what Wide leaves,
    // so the rows still span the grid.
    const edge2 = Shares.x(&t, "Narrow") - 5;
    t.drag(edge2, y, edge2 - 50, y);
    t.settle(1);
    try std.testing.expectApproxEqAbs(@as(f32, 150), s.widths[0], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 80), s.widths[2], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 380), Shares.x(&t, "Fixed") + Shares.w(&t, "Fixed"), 1);
}

test "with scroll_x, a drag widens a column past the grid, which scrolls" {
    var s: Shares = .{ .resize = true, .scroll = true };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&s, Shares.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const y = t.findText("Fixed").?.y + 4;
    const edge = Shares.x(&t, "Narrow") - 5;
    t.drag(edge, y, edge + 150, y);
    t.settle(1);
    try std.testing.expect(s.widths[0] > 320);
}

test "a hidden column keeps its width for when it shows again, and its room goes to the flexible columns" {
    var s: Shares = .{ .resize = true, .widths = .{ 0, 70, 80 } };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&s, Shares.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    s.hide_narrow = true;
    t.settle(1);
    try std.testing.expect(!t.hasText("Narrow"));
    // 370 less Fixed and a gap.
    try std.testing.expectApproxEqAbs(@as(f32, 280), Shares.x(&t, "Fixed") - Shares.x(&t, "Wide") - 10, 1);
    s.hide_narrow = false;
    t.settle(1);
    try std.testing.expectEqual([3]f32{ 0, 70, 80 }, s.widths);
    try std.testing.expectApproxEqAbs(@as(f32, 70), Shares.x(&t, "Fixed") - Shares.x(&t, "Narrow") - 10, 1);
    // With Wide sized and Narrow hidden, the last column takes the room.
    s.widths[0] = 100;
    s.hide_narrow = true;
    t.settle(1);
    try std.testing.expectApproxEqAbs(@as(f32, 380), Shares.x(&t, "Fixed") + Shares.w(&t, "Fixed"), 1);
}

test "an edge after a column with a width resizes that column" {
    const Two = struct {
        widths: [3]f32 = .{ 0, 0, 0 },
        const columns = [_]Column{
            .{ .title = "Kind", .width = 70 },
            .{ .title = "Size", .width = 80 },
            .{ .title = "Name" },
        };
        fn view(s: *@This(), c: *ui.Context) void {
            var g = grid(c, &columns, .{ .count = 0, .widths = &s.widths });
            g.end();
        }
    };
    var s: Two = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&s, Two.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const y = t.findText("Kind").?.y + 4;
    const edge = t.findText("Size").?.x - 5;
    t.drag(edge, y, edge + 30, y);
    t.settle(1);
    try std.testing.expectApproxEqAbs(@as(f32, 100), s.widths[0], 0.5);
    // The column after it, not resized, keeps its own.
    try std.testing.expectEqual(@as(f32, 0), s.widths[1]);
}

/// How many texts read `s` whole.
fn countText(t: *ui.Tester, s: []const u8) usize {
    var n: usize = 0;
    for (t.ctx.nodes.items) |node| switch (node.content) {
        .text => |tx| n += @intFromBool(std.mem.eql(u8, tx.str, s)),
        else => {},
    };
    return n;
}

/// A narrow column of sizes, whose widths the caller keeps.
const Sizes = struct {
    widths: [2]f32 = .{ 0, 0 },
    fit_all: bool = false,
    reset: bool = false,
    clickable: bool = true,
    const columns = [_]Column{
        .{ .title = "Name" },
        .{ .title = "Size", .width = 40, .alignment = .end },
    };
    const long = "1234567890 KB";
    fn view(s: *Sizes, c: *ui.Context) void {
        var g = grid(c, &columns, .{ .count = 3, .widths = &s.widths, .clickable = s.clickable });
        if (s.fit_all) g.fitAll();
        if (s.reset) g.resetWidths();
        s.fit_all = false;
        s.reset = false;
        while (g.next()) |row| {
            g.cell();
            ui.text(c, c.print("file {d}", .{row.index}), .{});
            g.cell();
            ui.text(c, if (row.index == 1) long else "1 KB", .{ .truncate = .ellipsis });
        }
        g.end();
    }
};

test "a double-click on an edge fits the column on its left to its widest title or cell" {
    var s: Sizes = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&s, Sizes.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expectEqual(@as(f32, 0), s.widths[1]);
    // Name's widest is under its min_width, 40.
    const want = @max(40, t.ctx.text.width("file 0", .{}), t.findText("Name").?.w);
    // The edge before Size, whose cells end at the padding and the
    // scrollbar's gutter: 400 - 10 - 10 - 40.
    const y = t.findText("Name").?.y + 4;
    t.doubleClick(340 - 5, y);
    t.settle(1);
    try std.testing.expect(s.widths[0] >= want and s.widths[0] <= want + 3);
    try std.testing.expectEqual(@as(f32, 0), s.widths[1]);
}

test "a click on an edge that doesn't move changes no width" {
    var s: Shares = .{ .resize = true };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&s, Shares.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const edge = Shares.x(&t, "Fixed") - 5;
    t.drag(edge, t.findText("Fixed").?.y + 4, edge, t.findText("Fixed").?.y + 4);
    t.settle(1);
    try std.testing.expectEqual([3]f32{ 0, 0, 0 }, s.widths);
}

test "a double-click past the last title, or fitAll, fits every column, and resetWidths goes back" {
    var s: Sizes = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&s, Sizes.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const long = t.ctx.text.width(Sizes.long, .{ .truncate = .ellipsis });
    const name = @max(40, t.ctx.text.width("file 0", .{}), t.findText("Name").?.w);
    // In the padding past Size's title, the grid's last 20 points.
    t.doubleClick(395, t.findText("Name").?.y + 4);
    t.settle(1);
    try std.testing.expect(s.widths[0] >= name and s.widths[0] <= name + 3);
    try std.testing.expect(s.widths[1] >= long and s.widths[1] <= long + 3);
    s.reset = true;
    t.settle(1);
    // Each goes back to its own: Size's width, and Name sharing the room.
    try std.testing.expectEqual([2]f32{ 0, 0 }, s.widths);
    s.fit_all = true;
    t.settle(1);
    try std.testing.expect(s.widths[0] >= name and s.widths[0] <= name + 3);
    try std.testing.expect(s.widths[1] >= long and s.widths[1] <= long + 3);
}

test "a cut-off cell shows its whole text on hover, and a whole one doesn't" {
    var s: Sizes = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&s, Sizes.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // A cut-off text is shortened where it is drawn ("1234…"), so its
    // whole text is read only in the tooltip.
    try std.testing.expectEqual(@as(usize, 0), countText(&t, Sizes.long));
    const row = t.findText("file 1").?;
    // In Size's cell: 400 - 10 - 10 - 40 to 380.
    t.moveTo(360, row.y + row.h / 2);
    t.advance(0.2);
    try std.testing.expectEqual(@as(usize, 0), countText(&t, Sizes.long));
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), countText(&t, Sizes.long));
    // A whole one shows none, and the cut one's goes.
    t.moveTo(row.x + 2, row.y + row.h / 2);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 0), countText(&t, Sizes.long));
    try std.testing.expectEqual(@as(usize, 1), countText(&t, "file 1"));
}

test "a grid whose rows aren't clickable shows its cut-off cells' tooltips too, without the hand" {
    var s: Sizes = .{ .clickable = false };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&s, Sizes.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const row = t.findText("file 1").?;
    t.moveTo(360, row.y + row.h / 2);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), countText(&t, Sizes.long));
    try std.testing.expect(!t.ctx.cursor_hand);
    t.moveTo(row.x + 2, row.y + row.h / 2);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 0), countText(&t, Sizes.long));
}

/// The fruit grid, whose columns' order the caller keeps.
const Ordered = struct {
    order: [3]usize = .{ 0, 1, 2 },
    sort: g_mod.Sort = .{},
    sorted: usize = 0,
    fn view(o: *Ordered, c: *ui.Context) void {
        var g = grid(c, &Fruit.columns, .{ .count = 3, .order = &o.order, .sort = &o.sort });
        if (g.sorted) o.sorted += 1;
        while (g.next()) |row| {
            g.cell();
            ui.text(c, Fruit.names[row.index], .{});
            g.cell();
            ui.text(c, c.print("{d}", .{row.index * 100}), .{});
            g.cell();
            ui.text(c, "ripe", .{});
        }
        g.end();
    }
};

test "dragging a title moves its column, and its cells with it, without sorting" {
    var o: Ordered = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&o, Ordered.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const y = t.findText("Fruit").?.y + 4;
    const note = t.findText("Note").?;
    t.drag(note.x + 4, y, t.findText("Fruit").?.x + 2, y);
    t.settle(1);
    try std.testing.expectEqual([3]usize{ 2, 0, 1 }, o.order);
    try std.testing.expect(t.findText("ripe").?.x < t.findText("apple").?.x);
    try std.testing.expectApproxEqAbs(t.findText("Note").?.x, t.findText("ripe").?.x, 0.5);
    // A sortable title dragged moves, and doesn't sort.
    const count = t.findText("Count").?;
    t.drag(count.x + count.w - 4, y, t.findText("Note").?.x + 2, y);
    t.settle(1);
    try std.testing.expectEqual([3]usize{ 1, 2, 0 }, o.order);
    try std.testing.expectEqual(@as(usize, 0), o.sorted);
    const hundred = t.findText("100").?;
    try std.testing.expect(hundred.x < t.findText("ripe").?.x);
    // A click still sorts.
    try t.clickText("Fruit");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), o.sorted);
}

/// Three wide columns in a narrow window, which scroll sideways.
const Wide = struct {
    freeze: bool = false,
    const columns = [_]Column{
        .{ .title = "A", .width = 150 },
        .{ .title = "B", .width = 150 },
        .{ .title = "C", .width = 150 },
    };
    fn view(w: *Wide, c: *ui.Context) void {
        var g = grid(c, &columns, .{ .count = 3, .scroll_x = true, .freeze_first = w.freeze });
        while (g.next()) |row| {
            g.cell();
            ui.text(c, c.print("a{d}", .{row.index}), .{});
            g.cell();
            ui.text(c, c.print("b{d}", .{row.index}), .{});
            g.cell();
            ui.text(c, c.print("c{d}", .{row.index}), .{});
        }
        g.end();
    }
};

test "columns that don't fit scroll sideways, the titles with them" {
    var w: Wide = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&w, Wide.view), .{ .width = 300, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const b = t.findText("b1").?.x;
    try std.testing.expectApproxEqAbs(b, t.findText("B").?.x, 0.5);
    t.hscroll(100, 60, -100);
    t.settle(1);
    try std.testing.expectApproxEqAbs(b - 100, t.findText("b1").?.x, 0.5);
    try std.testing.expectApproxEqAbs(b - 100, t.findText("B").?.x, 0.5);
    // No further than the last column's end: 490 wide in a view of 290.
    t.hscroll(100, 60, -1000);
    t.settle(1);
    try std.testing.expectApproxEqAbs(b - 200, t.findText("b1").?.x, 0.5);
}

test "the first column stays in place as the others scroll, and the bar scrolls them" {
    var w: Wide = .{ .freeze = true };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&w, Wide.view), .{ .width = 300, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const a = t.findText("a1").?.x;
    const b = t.findText("b1").?.x;
    t.hscroll(100, 60, -60);
    t.settle(1);
    try std.testing.expectApproxEqAbs(a, t.findText("a1").?.x, 0.5);
    try std.testing.expectApproxEqAbs(a, t.findText("A").?.x, 0.5);
    try std.testing.expectApproxEqAbs(b - 60, t.findText("b1").?.x, 0.5);
    try std.testing.expectApproxEqAbs(b - 60, t.findText("B").?.x, 0.5);
    // The bar under the rows: its thumb dragged back to the start.
    t.drag(40, 300 - 5, 0, 300 - 5);
    t.settle(1);
    try std.testing.expectApproxEqAbs(b, t.findText("b1").?.x, 0.5);
}

test "rows with lines between them meet, without a gap" {
    const Lined = struct {
        lines: bool = false,
        fn view(x: *@This(), c: *ui.Context) void {
            var g = grid(c, &Fruit.columns, .{ .count = 3, .row_lines = x.lines, .column_lines = x.lines });
            while (g.next()) |row| {
                g.cell();
                ui.text(c, Fruit.names[row.index], .{});
            }
            g.end();
        }
    };
    var x: Lined = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Lined.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expectApproxEqAbs(@as(f32, 28 + 2), t.findText("banana").?.y - t.findText("apple").?.y, 0.5);
    x.lines = true;
    t.settle(1);
    try std.testing.expectApproxEqAbs(@as(f32, 28), t.findText("banana").?.y - t.findText("apple").?.y, 0.5);
}

/// A column whose cells and title sit in its center.
const Centered = struct {
    const columns = [_]Column{
        .{ .title = "Name" },
        .{ .title = "Mid", .width = 120, .alignment = .center },
    };
    fn view(_: *Centered, c: *ui.Context) void {
        var g = grid(c, &columns, .{ .count = 2 });
        while (g.next()) |row| {
            g.cell();
            ui.text(c, c.print("file {d}", .{row.index}), .{});
            g.cell();
            ui.text(c, "x", .{});
        }
        g.end();
    }
};

test "a centered column's cells and title sit in its center" {
    var s: Centered = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&s, Centered.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // Mid ends at the padding and the scrollbar's gutter: from
    // 400 - 10 - 10 - 120 to 380, its center at 320.
    const cell = t.findText("x").?;
    const title = t.findText("Mid").?;
    try std.testing.expectApproxEqAbs(@as(f32, 320), cell.x + cell.w / 2, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 320), title.x + title.w / 2, 1);
}

test "fitting a sorted column makes room for its title and its arrow" {
    const T = struct {
        widths: [2]f32 = .{ 0, 0 },
        sort: g_mod.Sort = .{ .column = 0 },
        fit: bool = true,
        const columns = [_]Column{
            .{ .title = "Filename", .sortable = true },
            .{ .title = "Size", .width = 60 },
        };
        fn view(x: *@This(), c: *ui.Context) void {
            var g = grid(c, &columns, .{ .count = 1, .widths = &x.widths, .sort = &x.sort });
            if (x.fit) g.fitAll();
            x.fit = false;
            while (g.next()) |_| {
                g.cell();
                ui.text(c, "a", .{});
                g.cell();
                ui.text(c, "1", .{});
            }
            g.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 400, .height = 200 });
    defer t.deinit();
    t.settle(1);
    const title = t.ctx.text.width("Filename", .{ .size = 11, .weight = .semibold });
    // The title, the gap and the 8-point arrow.
    try std.testing.expect(x.widths[0] >= title + 8);
    try std.testing.expect(t.hasText("Filename"));
}
