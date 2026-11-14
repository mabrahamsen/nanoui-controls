//! The grid's tests of a selection kept by key: through a re-sort, a
//! filter that hides its row and brings it back, groups that move and
//! fold, and rows selected together.
const std = @import("std");
const builtin = @import("builtin");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const grid_mod = @import("grid.zig");
const grid = grid_mod.grid;
const groups_mod = @import("grid_groups.zig");

const columns = [_]grid_mod.Column{.{ .title = "Name" }};

/// Fruit in an order the test changes, each row keyed by its name.
const Basket = struct {
    names: [5][]const u8 = .{ "apple", "banana", "cherry", "damson", "elder" },
    /// How many of `names` show, from the first: fewer is a filter.
    shown: usize = 5,
    selected: ?usize = null,
    marked: [5]bool = @splat(false),
    multi: bool = false,

    fn view(b: *Basket, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        const names = b.names[0..b.shown];
        var g = grid(c, &columns, .{ .count = names.len, .keys = names, .selected = &b.selected, .selection = if (b.multi) b.marked[0..b.shown] else null });
        while (g.next()) |row| {
            g.cell();
            ui.text(c, names[row.index], .{});
        }
        g.end();
    }

    fn reverse(b: *Basket) void {
        std.mem.reverse([]const u8, b.names[0..b.shown]);
    }

    /// Where `name` is now.
    fn at(b: *const Basket, name: []const u8) ?usize {
        for (b.names[0..b.shown], 0..) |x, i| if (std.mem.eql(u8, x, name)) return i;
        return null;
    }

    fn selectedName(b: *const Basket) ?[]const u8 {
        return if (b.selected) |i| b.names[i] else null;
    }
};

fn start(t: *ui.Tester, b: *Basket) !void {
    try t.init(std.testing.allocator, .init(b, Basket.view), .{ .width = 300, .height = 300 });
    t.settle(1);
}

/// Clicks the row showing `name`, with Cmd (Ctrl off the Mac) or Shift.
fn clickName(t: *ui.Tester, name: []const u8, mods: struct { adds: bool = false, shift: bool = false }) void {
    const r = t.findText(name).?;
    const mac = builtin.os.tag.isDarwin();
    t.setMods(.{ .cmd = mac and mods.adds, .ctrl = !mac and mods.adds, .shift = mods.shift });
    t.click(r.x + 2, r.y + r.h / 2);
    t.setMods(.{});
    t.settle(1);
}

test "with keys, the selection stays on its row as the rows re-sort" {
    var b: Basket = .{};
    var t: ui.Tester = undefined;
    try start(&t, &b);
    defer t.deinit();
    clickName(&t, "banana", .{});
    try std.testing.expectEqual(@as(?usize, 1), b.selected);
    b.reverse();
    t.settle(1);
    try std.testing.expectEqual(b.at("banana"), b.selected);
    try std.testing.expectEqualStrings("banana", b.selectedName().?);
}

test "a key whose row is filtered out selects nothing, and its row again when it comes back" {
    var b: Basket = .{};
    var t: ui.Tester = undefined;
    try start(&t, &b);
    defer t.deinit();
    clickName(&t, "elder", .{});
    b.shown = 3;
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, null), b.selected);
    // It stays remembered across frames while gone.
    t.settle(2);
    b.shown = 5;
    b.reverse();
    t.settle(1);
    try std.testing.expectEqualStrings("elder", b.selectedName().?);
}

test "the caller setting the selection replaces the key it follows" {
    var b: Basket = .{};
    var t: ui.Tester = undefined;
    try start(&t, &b);
    defer t.deinit();
    clickName(&t, "banana", .{});
    b.selected = 3;
    t.settle(1);
    b.reverse();
    t.settle(1);
    try std.testing.expectEqualStrings("damson", b.selectedName().?);
    // Its row gone, another row selected replaces it.
    b.shown = 1;
    t.settle(1);
    clickName(&t, "elder", .{});
    b.shown = 5;
    t.settle(1);
    try std.testing.expectEqualStrings("elder", b.selectedName().?);
}

test "rows selected together follow their keys as the rows re-sort, and the anchor with them" {
    var b: Basket = .{ .multi = true };
    var t: ui.Tester = undefined;
    try start(&t, &b);
    defer t.deinit();
    clickName(&t, "apple", .{});
    clickName(&t, "cherry", .{ .adds = true });
    b.reverse();
    t.settle(1);
    try std.testing.expect(b.marked[b.at("apple").?] and b.marked[b.at("cherry").?]);
    try std.testing.expect(!b.marked[b.at("banana").?]);
    try std.testing.expectEqualStrings("cherry", b.selectedName().?);
    // Shift-click runs from the anchor, cherry, where it is now.
    clickName(&t, "elder", .{ .shift = true });
    for (b.names, b.marked) |name, on| try std.testing.expectEqual(!std.mem.eql(u8, name, "apple") and !std.mem.eql(u8, name, "banana"), on);
}

test "rows selected together drop a row filtered out, and keep the caller's changes while the rows stay" {
    var b: Basket = .{ .multi = true };
    var t: ui.Tester = undefined;
    try start(&t, &b);
    defer t.deinit();
    clickName(&t, "banana", .{});
    clickName(&t, "elder", .{ .adds = true });
    b.shown = 4;
    t.settle(1);
    try std.testing.expect(b.marked[1]);
    for (b.marked[0..4], 0..) |on, i| try std.testing.expectEqual(i == 1, on);
    // The caller clears the selection: the same rows, so it stays clear.
    @memset(&b.marked, false);
    b.selected = null;
    t.settle(2);
    for (b.marked) |on| try std.testing.expect(!on);
}

/// Two groups of fruit whose order the test swaps, each heading and row
/// keyed.
const Orchard = struct {
    open: [2]bool = .{ true, true },
    swapped: bool = false,
    selected: ?usize = null,
    keys: [6][]const u8 = undefined,

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
        var g = grid(c, &columns, .{ .count = gs.count(), .groups = gs, .keys = o.keys[0..gs.count()], .selected = &o.selected });
        while (g.next()) |row| switch (gs.at(row.index)) {
            .heading => |h| g.heading(.{ .title = names[o.group(h.group)] }),
            .row => |r| {
                g.cell();
                ui.text(c, fruit[o.group(r.group)][r.index], .{});
            },
        };
        g.end();
    }
};

test "a selected heading is kept by its key as the groups move" {
    var o: Orchard = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&o, Orchard.view), .{ .width = 300, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // The heading of "stone", third in view.
    o.selected = 3;
    t.settle(1);
    o.swapped = true;
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 0), o.selected);
    try std.testing.expectEqualStrings("stone", o.keys[o.selected.?]);
}

test "with keys, a row in a group that folds selects its heading" {
    var o: Orchard = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&o, Orchard.view), .{ .width = 300, .height = 300 });
    defer t.deinit();
    t.settle(1);
    o.selected = 5;
    t.settle(1);
    try std.testing.expectEqualStrings("plum", o.keys[5]);
    o.open[1] = false;
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 3), o.selected);
    try std.testing.expectEqualStrings("stone", o.keys[o.selected.?]);
}
