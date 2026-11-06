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

    const columns = [_]Column{
        .{ .title = "Wide", .flex = 2 },
        .{ .title = "Narrow", .flex = 1, .min_width = 60 },
        .{ .title = "Fixed", .width = 80, .min_width = 50 },
    };

    fn view(s: *Shares, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        var g = grid(c, &columns, .{ .count = 1, .widths = if (s.resize) &s.widths else null });
        while (g.next()) |_| {
            g.cell();
            ui.text(c, "w", .{});
            g.cell();
            ui.text(c, "n", .{});
            g.cell();
            ui.text(c, "f", .{});
        }
        g.end();
    }

    /// Where column `title`'s cells start.
    fn x(t: *ui.Tester, title: []const u8) f32 {
        return t.findText(title).?.x;
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

test "dragging the edge between titles resizes the column with a width" {
    var s: Shares = .{ .resize = true };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&s, Shares.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // Columns with a width start at it; the others stay 0.
    try std.testing.expectEqual([3]f32{ 0, 0, 80 }, s.widths);
    const y = t.findText("Fixed").?.y + 4;
    // The edge between Narrow and Fixed, in the gap before Fixed: Fixed
    // is on its right, so it widens as the edge moves left.
    const edge = Shares.x(&t, "Fixed") - 5;
    t.drag(edge, y, edge - 40, y);
    t.settle(1);
    try std.testing.expectApproxEqAbs(@as(f32, 120), s.widths[2], 0.5);
    try std.testing.expectApproxEqAbs(edge - 40, Shares.x(&t, "Fixed") - 5, 1);
    try std.testing.expectApproxEqAbs(Shares.x(&t, "Fixed"), t.findText("f").?.x, 0.5);
    // Never narrower than its min_width.
    const edge2 = Shares.x(&t, "Fixed") - 5;
    t.drag(edge2, y, edge2 + 300, y);
    t.settle(1);
    try std.testing.expectApproxEqAbs(@as(f32, 50), s.widths[2], 0.5);
    // Between two columns without a width, there's nothing to resize.
    const between = Shares.x(&t, "Narrow") - 5;
    t.drag(between, y, between + 40, y);
    t.settle(1);
    try std.testing.expectEqual([3]f32{ 0, 0, 50 }, s.widths);
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
    try std.testing.expectApproxEqAbs(@as(f32, 80), s.widths[1], 0.5);
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
    const columns = [_]Column{
        .{ .title = "Name" },
        .{ .title = "Size", .width = 40, .alignment = .end },
    };
    const long = "1234567890 KB";
    fn view(s: *Sizes, c: *ui.Context) void {
        var g = grid(c, &columns, .{ .count = 3, .widths = &s.widths });
        while (g.next()) |row| {
            g.cell();
            ui.text(c, c.print("file {d}", .{row.index}), .{});
            g.cell();
            ui.text(c, if (row.index == 1) long else "1 KB", .{ .truncate = .ellipsis });
        }
        g.end();
    }
};

test "a double-click on an edge fits the column to its widest cell" {
    var s: Sizes = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&s, Sizes.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expectEqual(@as(f32, 40), s.widths[1]);
    // The edge before Size, whose cells end at the padding and the
    // scrollbar's gutter: 400 - 10 - 10 - 40.
    const y = t.findText("Name").?.y + 4;
    t.doubleClick(340 - 5, y);
    t.settle(1);
    const want = t.ctx.text.width(Sizes.long, .{ .truncate = .ellipsis });
    try std.testing.expect(s.widths[1] >= want and s.widths[1] <= want + 3);
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
