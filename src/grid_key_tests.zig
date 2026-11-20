//! The grid's tests of a selection the caller keeps as a key
//! (`selected_key`): set from outside, moved by clicks, the keys and
//! `jump` and reported in `chosen`, through filters, re-sorts and folds,
//! and with rows selected together.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const grid_mod = @import("grid.zig");
const grid = grid_mod.grid;
const groups_mod = @import("grid_groups.zig");

const columns = [_]grid_mod.Column{.{ .title = "Name" }};

/// Forty rows keyed by their names, the selection kept as a name the
/// app copies in from `chosen`.
const Shelf = struct {
    names: [40][]const u8 = undefined,
    /// How many of `names` show, from the first: fewer is a filter.
    shown: usize = 40,
    drawn: bool = true,
    multi: bool = false,
    marked: [40]bool = @splat(false),
    /// The app's selection: its own copy of a row's key.
    buf: [16]u8 = undefined,
    key: ?[]const u8 = null,
    /// Asks the grid to `jump` to this row in the next frame.
    jump_to: ?usize = null,
    /// What the last frame drew: the selected row, drawn or not, and how
    /// often `chosen` had a key.
    row: ?usize = null,
    chosen: usize = 0,

    fn init(s: *Shelf, c: std.mem.Allocator) !void {
        for (&s.names, 0..) |*n, i| n.* = try std.fmt.allocPrint(c, "item-{d}", .{i});
    }

    fn deinit(s: *Shelf, c: std.mem.Allocator) void {
        for (s.names) |n| c.free(n);
    }

    fn choose(s: *Shelf, key: ?[]const u8) void {
        const k = key orelse {
            s.key = null;
            return;
        };
        @memcpy(s.buf[0..k.len], k);
        s.key = s.buf[0..k.len];
    }

    fn view(s: *Shelf, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        if (!s.drawn) return;
        const names = s.names[0..s.shown];
        var g = grid(c, &columns, .{ .count = names.len, .keys = names, .selected_key = &s.key, .selection = if (s.multi) s.marked[0..s.shown] else null });
        if (s.jump_to) |i| g.jump(i);
        s.jump_to = null;
        while (g.next()) |row| {
            g.cell();
            ui.text(c, names[row.index], .{});
        }
        s.row = for (0..names.len) |i| {
            if (g.isSelected(i)) break i;
        } else null;
        g.end();
        if (g.chosen) |k| {
            s.chosen += 1;
            s.choose(k);
        }
    }

    /// The row showing `name` is drawn, wholly in the window.
    fn inView(t: *ui.Tester, name: []const u8) bool {
        const r = t.findText(name) orelse return false;
        return r.y >= 0 and r.y + r.h <= t.ctx.size.h;
    }
};

fn start(t: *ui.Tester, s: *Shelf) !void {
    try s.init(std.testing.allocator);
    try t.init(std.testing.allocator, .init(s, Shelf.view), .{ .width = 300, .height = 300 });
    t.settle(1);
}

fn clickName(t: *ui.Tester, name: []const u8, shift: bool) void {
    const r = t.findText(name).?;
    t.setMods(.{ .shift = shift });
    t.click(r.x + 2, r.y + r.h / 2);
    t.setMods(.{});
    t.settle(1);
}

test "a key set from outside selects its row and scrolls it into view" {
    var s: Shelf = .{};
    var t: ui.Tester = undefined;
    try start(&t, &s);
    defer s.deinit(std.testing.allocator);
    defer t.deinit();
    try std.testing.expectEqual(@as(?usize, null), s.row);
    try std.testing.expect(!Shelf.inView(&t, "item-30"));
    s.choose("item-30");
    t.settle(2);
    try std.testing.expectEqual(@as(?usize, 30), s.row);
    try std.testing.expect(Shelf.inView(&t, "item-30"));
    // The grid didn't move it, so it reports nothing.
    try std.testing.expectEqual(@as(usize, 0), s.chosen);
    try std.testing.expectEqualStrings("item-30", s.key.?);
}

test "a click, the keys and jump are reported in chosen, which is null when nothing moved" {
    var s: Shelf = .{};
    var t: ui.Tester = undefined;
    try start(&t, &s);
    defer s.deinit(std.testing.allocator);
    defer t.deinit();
    clickName(&t, "item-2", false);
    try std.testing.expectEqualStrings("item-2", s.key.?);
    try std.testing.expectEqual(@as(usize, 1), s.chosen);
    t.settle(3);
    try std.testing.expectEqual(@as(usize, 1), s.chosen);
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqualStrings("item-3", s.key.?);
    try std.testing.expectEqual(@as(?usize, 3), s.row);
    s.jump_to = 25;
    t.settle(2);
    try std.testing.expectEqualStrings("item-25", s.key.?);
    try std.testing.expect(Shelf.inView(&t, "item-25"));
    try std.testing.expectEqual(@as(usize, 3), s.chosen);
}

test "a key no row has selects nothing, and its row again when it comes back" {
    var s: Shelf = .{};
    var t: ui.Tester = undefined;
    try start(&t, &s);
    defer s.deinit(std.testing.allocator);
    defer t.deinit();
    s.choose("item-30");
    t.settle(1);
    s.shown = 10;
    t.settle(2);
    try std.testing.expectEqual(@as(?usize, null), s.row);
    try std.testing.expectEqualStrings("item-30", s.key.?);
    try std.testing.expectEqual(@as(usize, 0), s.chosen);
    s.shown = 40;
    t.settle(2);
    try std.testing.expectEqual(@as(?usize, 30), s.row);
    try std.testing.expectEqual(@as(usize, 0), s.chosen);
}

test "re-sorted rows keep the selection on its key, and the scroll where it was" {
    var s: Shelf = .{};
    var t: ui.Tester = undefined;
    try start(&t, &s);
    defer s.deinit(std.testing.allocator);
    defer t.deinit();
    clickName(&t, "item-1", false);
    std.mem.reverse([]const u8, &s.names);
    t.settle(2);
    try std.testing.expectEqual(@as(?usize, 38), s.row);
    try std.testing.expect(!Shelf.inView(&t, "item-1"));
    try std.testing.expectEqualStrings("item-1", s.key.?);
    try std.testing.expectEqual(@as(usize, 1), s.chosen);
    // Scrolled to the end, it is the row selected there.
    t.key(.end);
    t.settle(1);
    try std.testing.expectEqualStrings("item-0", s.key.?);
}

test "a grid not drawn for some frames shows the caller's key again when it comes back" {
    var s: Shelf = .{};
    var t: ui.Tester = undefined;
    try start(&t, &s);
    defer s.deinit(std.testing.allocator);
    defer t.deinit();
    clickName(&t, "item-4", false);
    s.drawn = false;
    t.settle(3);
    // Set elsewhere while the grid was away.
    s.choose("item-33");
    s.drawn = true;
    t.settle(2);
    try std.testing.expectEqual(@as(?usize, 33), s.row);
    try std.testing.expect(Shelf.inView(&t, "item-33"));
}

test "with rows selected together, Shift selects from the caller's key's row" {
    var s: Shelf = .{ .multi = true };
    var t: ui.Tester = undefined;
    try start(&t, &s);
    defer s.deinit(std.testing.allocator);
    defer t.deinit();
    clickName(&t, "item-1", false);
    try std.testing.expect(s.marked[1]);
    // The app selects another row: the key and its flag.
    s.choose("item-3");
    @memset(&s.marked, false);
    s.marked[3] = true;
    t.settle(1);
    clickName(&t, "item-5", true);
    for (s.marked, 0..) |on, i| try std.testing.expectEqual(i >= 3 and i <= 5, on);
    try std.testing.expectEqualStrings("item-5", s.key.?);
}

/// Two groups of fruit whose order the test swaps, each heading and row
/// keyed, the selection kept as a key.
const Orchard = struct {
    open: [2]bool = .{ true, true },
    swapped: bool = false,
    key: ?[]const u8 = null,
    keys: [6][]const u8 = undefined,
    chosen: usize = 0,
    row: ?usize = null,

    const names = [2][]const u8{ "pome", "stone" };
    const fruit = [2][2][]const u8{ .{ "apple", "pear" }, .{ "cherry", "plum" } };

    fn group(o: *const Orchard, g: usize) usize {
        return if (o.swapped) 1 - g else g;
    }

    fn view(o: *Orchard, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        const gs = groups_mod.Groups.init(c, &.{ .{ .size = 2 }, .{ .size = 2 } }, &o.open, .{});
        for (0..gs.count()) |i| o.keys[i] = switch (gs.at(i)) {
            .heading => |h| names[o.group(h.group)],
            .row => |r| fruit[o.group(r.group)][r.index],
        };
        var g = grid(c, &columns, .{ .count = gs.count(), .groups = gs, .keys = o.keys[0..gs.count()], .selected_key = &o.key });
        o.row = null;
        while (g.next()) |row| {
            if (row.selected) o.row = row.index;
            switch (gs.at(row.index)) {
                .heading => |h| g.heading(.{ .title = names[o.group(h.group)] }),
                .row => |r| {
                    g.cell();
                    ui.text(c, fruit[o.group(r.group)][r.index], .{});
                },
            }
        }
        g.end();
        // The keys are the app's constants, so it keeps them as they are.
        if (g.chosen) |k| {
            o.chosen += 1;
            o.key = k;
        }
    }
};

test "a heading's key keeps the heading chosen as the groups move, and a fold chooses its heading's key" {
    var o: Orchard = .{ .key = "stone" };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&o, Orchard.view), .{ .width = 300, .height = 300 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 3), o.row);
    o.swapped = true;
    t.settle(2);
    try std.testing.expectEqual(@as(?usize, 0), o.row);
    try std.testing.expectEqualStrings("stone", o.key.?);
    try std.testing.expectEqual(@as(usize, 0), o.chosen);
    o.key = "plum";
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 2), o.row);
    // "plum" is in the first group now; folding it chooses its heading.
    o.open[0] = false;
    t.settle(2);
    try std.testing.expectEqualStrings("stone", o.key.?);
    try std.testing.expectEqual(@as(?usize, 0), o.row);
    try std.testing.expectEqual(@as(usize, 1), o.chosen);
}
