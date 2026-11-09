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
    /// The text typed, copied: `g.typed` lasts only for its frame.
    typed: ?[]const u8 = null,
    typed_buf: [32]u8 = undefined,
    field: bool = false,
    search: ui.TextBuffer = .{},
    first: usize = 0,
    last: usize = 0,
    /// The grid was given the keyboard, in the first frame.
    started: bool = false,

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
        if (!n.started) c.focusNext(false);
        n.started = true;
        var g = grid(c, &columns, .{ .count = count, .selected = &n.selected });
        if (g.typed) |text| {
            @memcpy(n.typed_buf[0..text.len], text);
            n.typed = n.typed_buf[0..text.len];
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

test "the keys a grid moves by are its own when offered first as shortcuts, as the Mac offers them" {
    var n: Names = .{};
    var t: ui.Tester = undefined;
    try start(&t, &n);
    defer t.deinit();
    try std.testing.expect(t.shortcut(.{ .key = ui.Shortcut.end }));
    try std.testing.expectEqual(@as(?usize, 1004), n.selected);
    try std.testing.expect(t.shortcut(.{ .key = ui.Shortcut.home }));
    try std.testing.expect(t.shortcut(.{ .key = ui.Shortcut.down }));
    try std.testing.expectEqual(@as(?usize, 1), n.selected);
    // Not with Cmd: that is the app's.
    try std.testing.expect(!t.shortcut(.{ .key = ui.Shortcut.end, .cmd = true }));
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
    t.setMods(.{ .cmd = true });
    t.typeText("c");
    t.setMods(.{});
    t.settle(0.1);
    try std.testing.expectEqual(@as(?usize, 0), n.selected);
    t.typeText("c");
    t.settle(0.1);
    try std.testing.expectEqual(@as(?usize, 4), n.selected);
}

/// Two grids side by side, as a folder list and its files, under a
/// search field.
const Two = struct {
    left: ?usize = null,
    right: ?usize = null,
    typed: [2]usize = .{ 0, 0 },
    search: ui.TextBuffer = .{},

    const columns = [_]Column{.{ .title = "Name" }};

    fn view(w: *Two, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        _ = ui.textField(c, &w.search, .{ .placeholder = "Search" });
        const panes = ui.div(c).row().wFull().grow();
        defer panes.end();
        for ([_]*?usize{ &w.left, &w.right }, 0..) |sel, side| {
            const pane = ui.div(c).column().w(200).hFull();
            defer pane.end();
            var g = grid(c, &columns, .{ .count = 100, .selected = sel });
            if (g.typed != null) w.typed[side] += 1;
            while (g.next()) |row| {
                g.cell();
                ui.text(c, c.print("{s} {d}", .{ if (side == 0) "folder" else "file", row.index }), .{});
            }
            g.end();
        }
    }
};

test "of two grids, only the one with the keyboard takes the keys" {
    var w: Two = .{};
    defer w.search.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&w, Two.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // Neither has the keyboard yet: the keys are no grid's.
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, null), w.left);
    try std.testing.expectEqual(@as(?usize, null), w.right);
    // A click on a file gives its grid the keyboard.
    try t.clickText("file 3");
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 3), w.right);
    t.key(.down);
    t.settle(1);
    t.typeText("f");
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, null), w.left);
    try std.testing.expectEqual(@as(?usize, 4), w.right);
    try std.testing.expectEqual([2]usize{ 0, 1 }, w.typed);
    // A click on a folder moves it there.
    try t.clickText("folder 1");
    t.settle(1);
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 2), w.left);
    try std.testing.expectEqual(@as(?usize, 4), w.right);
    // The search field takes it from both.
    try t.clickText("Search");
    t.settle(1);
    t.key(.down);
    t.typeText("f");
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 2), w.left);
    try std.testing.expectEqual(@as(?usize, 4), w.right);
    try std.testing.expectEqual([2]usize{ 0, 1 }, w.typed);
}

test "Tab gives the grids the keyboard in turn, after the field" {
    var w: Two = .{};
    defer w.search.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&w, Two.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    for ([_]?usize{ null, 0, 0 }, [_]?usize{ null, null, 0 }) |left, right| {
        // As the window does with Tab, whatever has the keyboard: the
        // Tester only does when nothing has.
        t.ctx.focusCycle(false);
        t.settle(1);
        t.key(.down);
        t.settle(1);
        try std.testing.expectEqual(left, w.left);
        try std.testing.expectEqual(right, w.right);
    }
}

test "a press on a grid's empty room or its title gives it the keyboard" {
    var w: Two = .{};
    defer w.search.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&w, Two.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    try t.clickText("Search");
    t.settle(1);
    // The right grid's title, then the left's.
    t.click(300, t.findText("Name").?.y + 4);
    t.settle(1);
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 0), w.right);
    t.click(100, t.findText("Name").?.y + 4);
    t.settle(1);
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 0), w.left);
}
