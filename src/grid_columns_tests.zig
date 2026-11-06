//! The grid's tests of its columns: sharing the room left, keeping
//! their minimum widths, resizing by their edges, and the text of an
//! empty grid under them.
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
