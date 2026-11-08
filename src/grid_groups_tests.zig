//! GridGroups' tests: which rows show as groups fold and open, nested
//! groups, groups of one, and where a row folded away goes.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const groups_mod = @import("grid_groups.zig");
const Groups = groups_mod.Groups;
const Item = groups_mod.Item;

fn nothing(_: *u8, _: *ui.Context) void {}

/// A context to make groups in, outside a view.
fn context(t: *ui.Tester) !*ui.Context {
    var x: u8 = 0;
    try t.init(std.testing.allocator, .init(&x, nothing), .{});
    return &t.ctx;
}

fn heading(g: usize) Item {
    return .{ .heading = .{ .group = g, .depth = 0 } };
}

fn row(g: usize, i: usize) Item {
    return .{ .row = .{ .group = g, .index = i, .depth = 0 } };
}

test "groups show a heading, then their rows while open" {
    var t: ui.Tester = undefined;
    const c = try context(&t);
    defer t.deinit();
    var open = [_]bool{ true, true, false };
    const gs = Groups.init(c, &.{ .{ .size = 2 }, .{ .size = 0 }, .{ .size = 3 } }, &open, .{});
    try std.testing.expectEqual(@as(usize, 5), gs.count());
    try std.testing.expect(gs.at(0).eql(heading(0)));
    try std.testing.expect(gs.at(1).eql(row(0, 0)));
    try std.testing.expect(gs.at(2).eql(row(0, 1)));
    try std.testing.expect(gs.at(3).eql(heading(1)));
    try std.testing.expect(gs.at(4).eql(heading(2)));
    try std.testing.expectEqual(@as(u8, 0), gs.at(0).depth());
    try std.testing.expectEqual(@as(u8, 1), gs.at(1).depth());
}

test "a group in a group shows under its rows, and folds with it" {
    var t: ui.Tester = undefined;
    const c = try context(&t);
    defer t.deinit();
    const groups = [_]groups_mod.Group{ .{ .size = 1 }, .{ .size = 2, .depth = 1 }, .{ .size = 1 } };
    var open = [_]bool{ true, true, true };
    var gs = Groups.init(c, &groups, &open, .{});
    // Outer, its row, inner, its two rows, the last, its row.
    try std.testing.expectEqual(@as(usize, 7), gs.count());
    try std.testing.expectEqual(@as(u8, 1), gs.at(2).depth());
    try std.testing.expectEqual(@as(u8, 2), gs.at(3).depth());
    try std.testing.expectEqual(@as(?usize, 0), gs.parent(1));
    try std.testing.expect(gs.within(1, 0) and !gs.within(2, 0));
    open[0] = false;
    gs = Groups.init(c, &groups, &open, .{});
    try std.testing.expectEqual(@as(usize, 3), gs.count());
    try std.testing.expect(gs.at(1).eql(heading(2)));
}

test "without singles, a group of one shows its row alone" {
    var t: ui.Tester = undefined;
    const c = try context(&t);
    defer t.deinit();
    var open = [_]bool{ true, true };
    const gs = Groups.init(c, &.{ .{ .size = 1 }, .{ .size = 2 } }, &open, .{ .singles = false });
    try std.testing.expectEqual(@as(usize, 4), gs.count());
    try std.testing.expect(gs.at(0).eql(row(0, 0)));
    try std.testing.expectEqual(@as(u8, 0), gs.at(0).depth());
    try std.testing.expect(gs.at(1).eql(heading(1)));
}

test "a row folded away is found at the nearest heading over it" {
    var t: ui.Tester = undefined;
    const c = try context(&t);
    defer t.deinit();
    const groups = [_]groups_mod.Group{ .{ .size = 1 }, .{ .size = 2, .depth = 1 }, .{ .size = 1 } };
    var open = [_]bool{ true, false, true };
    var gs = Groups.init(c, &groups, &open, .{});
    try std.testing.expectEqual(@as(?usize, 2), gs.locate(row(1, 1)));
    try std.testing.expectEqual(@as(?usize, 4), gs.locate(row(2, 0)));
    open[0] = false;
    gs = Groups.init(c, &groups, &open, .{});
    try std.testing.expectEqual(@as(?usize, 0), gs.locate(row(1, 1)));
    // A group that is gone is found nowhere.
    try std.testing.expectEqual(@as(?usize, null), gs.locate(row(7, 0)));
}

test "every row in view is what a plain listing of the groups says, however they fold" {
    var t: ui.Tester = undefined;
    const c = try context(&t);
    defer t.deinit();
    const groups = [_]groups_mod.Group{ .{ .size = 2 }, .{ .size = 3, .depth = 1 }, .{ .size = 1, .depth = 2 }, .{ .size = 1 }, .{ .size = 0 }, .{ .size = 4, .depth = 1 } };
    var open: [groups.len]bool = undefined;
    // Every way of folding them, with and without singles.
    for (0..(1 << groups.len)) |mask| for ([_]bool{ true, false }) |singles| {
        for (&open, 0..) |*o, i| o.* = mask & (@as(usize, 1) << @intCast(i)) != 0;
        const gs = Groups.init(c, &groups, &open, .{ .singles = singles });
        // The listing, built the plain way: a heading, then its rows
        // while open, skipping groups in a folded one.
        var want: [64]Item = undefined;
        var n: usize = 0;
        var folded: ?u8 = null;
        for (groups, 0..) |gr, i| {
            if (folded) |d| {
                if (gr.depth > d) continue;
                folded = null;
            }
            const inner = i + 1 < groups.len and groups[i + 1].depth > gr.depth;
            if (!singles and gr.size == 1 and !inner) {
                want[n] = .{ .row = .{ .group = i, .index = 0, .depth = gr.depth } };
                n += 1;
                continue;
            }
            want[n] = .{ .heading = .{ .group = i, .depth = gr.depth } };
            n += 1;
            if (!open[i]) {
                folded = gr.depth;
                continue;
            }
            for (0..gr.size) |j| {
                want[n] = .{ .row = .{ .group = i, .index = j, .depth = gr.depth + 1 } };
                n += 1;
            }
        }
        try std.testing.expectEqual(n, gs.count());
        for (want[0..n], 0..) |w, i| {
            const got = gs.at(i);
            try std.testing.expect(got.eql(w));
            try std.testing.expectEqual(w.depth(), got.depth());
            try std.testing.expectEqual(@as(?usize, i), gs.locate(w));
        }
    };
}
