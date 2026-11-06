//! The grid's tests of typing to jump to a row.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const g_mod = @import("grid.zig");
const grid = g_mod.grid;
const Column = g_mod.Column;
const type_pause = @import("grid_keys.zig").type_pause;

/// A long grid of names in order, which jumps to the first name the typed
/// text begins, as an app would, under a search field.
const Names = struct {
    selected: ?usize = null,
    typed: ?[]const u8 = null,
    field: bool = false,
    search: ui.TextBuffer = .{},
    first: usize = 0,
    last: usize = 0,

    const columns = [_]Column{.{ .title = "Name" }};
    const words = [_][]const u8{ "apple", "apricot", "banana", "blueberry", "cherry" };

    /// Five fruit, then a thousand numbered rows.
    fn name(c: *ui.Context, i: usize) []const u8 {
        return if (i < words.len) words[i] else c.print("row {d:0>4}", .{i - words.len});
    }

    fn view(n: *Names, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        if (n.field) _ = ui.textField(c, &n.search, .{ .placeholder = "Search" });
        const count = words.len + 1000;
        var g = grid(c, &columns, .{ .count = count, .selected = &n.selected });
        if (g.typed) |text| {
            n.typed = text;
            for (0..count) |i| if (std.ascii.startsWithIgnoreCase(name(c, i), text)) {
                g.jump(i);
                break;
            };
        }
        n.first = g.first;
        n.last = g.last;
        while (g.next()) |row| {
            g.cell();
            ui.text(c, name(c, row.index), .{});
        }
        g.end();
    }
};

fn start(t: *ui.Tester, n: *Names) !void {
    try t.init(std.testing.allocator, .init(n, Names.view), .{ .width = 400, .height = 300 });
    t.settle(1);
}

test "typing jumps to the first row it begins, and more typing narrows it" {
    var n: Names = .{};
    defer n.search.deinit();
    var t: ui.Tester = undefined;
    try start(&t, &n);
    defer t.deinit();
    t.typeText("b");
    t.settle(0.1);
    try std.testing.expectEqualStrings("b", n.typed.?);
    try std.testing.expectEqual(@as(?usize, 2), n.selected);
    t.typeText("l");
    t.settle(0.1);
    try std.testing.expectEqualStrings("bl", n.typed.?);
    try std.testing.expectEqual(@as(?usize, 3), n.selected);
    // Text no row begins: the selection stays.
    t.typeText("x");
    t.settle(0.1);
    try std.testing.expectEqual(@as(?usize, 3), n.selected);
}

test "a pause in typing starts the text afresh" {
    var n: Names = .{};
    defer n.search.deinit();
    var t: ui.Tester = undefined;
    try start(&t, &n);
    defer t.deinit();
    t.typeText("b");
    t.advance(type_pause + 0.5);
    t.typeText("C");
    t.settle(0.1);
    try std.testing.expectEqualStrings("C", n.typed.?);
    try std.testing.expectEqual(@as(?usize, 4), n.selected);
}

test "typing jumps to a row out of view and scrolls to it" {
    var n: Names = .{};
    defer n.search.deinit();
    var t: ui.Tester = undefined;
    try start(&t, &n);
    defer t.deinit();
    t.typeText("row 07");
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 5 + 700), n.selected);
    try std.testing.expect(n.first <= 705 and 705 < n.last);
    try std.testing.expect(t.findText("row 0700") != null);
}

test "typing goes to a focused text field, and not with Cmd or Ctrl held" {
    var n: Names = .{ .field = true };
    defer n.search.deinit();
    var t: ui.Tester = undefined;
    try start(&t, &n);
    defer t.deinit();
    try t.clickText("Search");
    t.settle(0.1);
    t.typeText("b");
    t.settle(0.1);
    try std.testing.expectEqual(@as(?[]const u8, null), n.typed);
    try std.testing.expectEqual(@as(?usize, null), n.selected);
    // A click on a row takes the keyboard back; Cmd held is a shortcut.
    try t.clickText("apple");
    t.settle(0.1);
    t.ctx.input.cmd = true;
    t.typeText("c");
    t.ctx.input.cmd = false;
    t.settle(0.1);
    try std.testing.expectEqual(@as(?usize, 0), n.selected);
    t.typeText("c");
    t.settle(0.1);
    try std.testing.expectEqual(@as(?usize, 4), n.selected);
}
