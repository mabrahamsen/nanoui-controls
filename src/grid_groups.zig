//! A grid's rows in groups under headings that fold: which row in view is
//! a heading and which is a row of which group, as the grid builds only
//! the rows in view and needs to know.
//!
//!     // The groups in order, each its rows' number; kept by the caller,
//!     // with whether each is open.
//!     const groups = controls.GridGroups.init(c, &.{ .{ .size = 4 }, .{ .size = 2 } }, &open, .{});
//!     var g = controls.grid(c, &columns, .{ .count = groups.count(), .groups = groups, .selected = &sel });
//!     while (g.next()) |row| switch (groups.at(row.index)) {
//!         .heading => |h| g.heading(.{ .title = repos[h.group].name, .detail = "4 pull requests" }),
//!         .row => |r| { g.cell(); ui.text(c, pulls[r.group][r.index].title, .{}); },
//!     };
//!     g.end();
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

/// A group: how many rows it has, and how deep it is. A group one deeper
/// than the one before it is in that one, under its rows.
pub const Group = struct {
    size: usize,
    depth: u8 = 0,
};

/// What a row in view is: a group's heading, or one of its rows.
pub const Item = union(enum) {
    heading: struct { group: usize, depth: u8 },
    row: struct { group: usize, index: usize, depth: u8 },

    /// How many steps in it is drawn.
    pub fn depth(it: Item) u8 {
        return switch (it) {
            .heading => |h| h.depth,
            .row => |r| r.depth,
        };
    }

    pub fn group(it: Item) usize {
        return switch (it) {
            .heading => |h| h.group,
            .row => |r| r.group,
        };
    }

    pub fn eql(a: Item, b: Item) bool {
        return switch (a) {
            .heading => |h| b == .heading and b.heading.group == h.group,
            .row => |r| b == .row and b.row.group == r.group and b.row.index == r.index,
        };
    }
};

pub const Options = struct {
    /// A group of one row, with no groups in it, shows a heading over
    /// its row; false shows the row alone, where the heading would be.
    singles: bool = true,
};

pub const Groups = struct {
    groups: []const Group,
    /// Whether each group is open, kept by the caller: the grid changes
    /// it as the user folds and opens groups.
    open: []bool,
    /// The rows in view, in order: what each is.
    items: []const Item,

    /// The groups' rows in view, as `open` says, in the frame's arena.
    pub fn init(c: *ui.Context, groups: []const Group, open: []bool, opts: Options) Groups {
        if (open.len != groups.len) @panic("grid groups: `open` needs one flag a group");
        var items: std.ArrayList(Item) = .empty;
        // Groups deeper than this are in a folded one, and don't show.
        var folded: ?u8 = null;
        for (groups, 0..) |gr, i| {
            if (folded) |d| {
                if (gr.depth > d) continue;
                folded = null;
            }
            const has_groups = i + 1 < groups.len and groups[i + 1].depth > gr.depth;
            if (!opts.singles and gr.size == 1 and !has_groups) {
                items.append(c.alloc(), .{ .row = .{ .group = i, .index = 0, .depth = gr.depth } }) catch @panic("grid groups: out of memory");
                continue;
            }
            items.append(c.alloc(), .{ .heading = .{ .group = i, .depth = gr.depth } }) catch @panic("grid groups: out of memory");
            if (!open[i]) {
                folded = gr.depth;
                continue;
            }
            for (0..gr.size) |j| items.append(c.alloc(), .{ .row = .{ .group = i, .index = j, .depth = gr.depth + 1 } }) catch @panic("grid groups: out of memory");
        }
        return .{ .groups = groups, .open = open, .items = items.items };
    }

    /// How many rows show: the grid's `count`.
    pub fn count(gs: Groups) usize {
        return gs.items.len;
    }

    /// What row `i` in view is.
    pub fn at(gs: Groups, i: usize) Item {
        return gs.items[i];
    }

    /// The group `g` is in, if any: the nearest before it that is less deep.
    pub fn parent(gs: Groups, g: usize) ?usize {
        var i = g;
        while (i > 0) {
            i -= 1;
            if (gs.groups[i].depth < gs.groups[g].depth) return i;
        }
        return null;
    }

    /// Group `inner` is `outer`, or in it, however deep.
    pub fn within(gs: Groups, inner: usize, outer: usize) bool {
        var g: ?usize = inner;
        while (g) |x| : (g = gs.parent(x)) if (x == outer) return true;
        return false;
    }

    /// Where `item` is in view; when it is folded away, where the nearest
    /// heading over it is, as the selection moves there. Null when neither
    /// shows, or the group is gone.
    pub fn locate(gs: Groups, item: Item) ?usize {
        if (item.group() >= gs.groups.len) return null;
        for (gs.items, 0..) |it, i| if (it.eql(item)) return i;
        // Its group's first row in view (its heading, or its row alone
        // when it is a group of one), else the nearest group over it.
        var g: ?usize = item.group();
        while (g) |x| : (g = gs.parent(x)) {
            for (gs.items, 0..) |it, i| if (it.group() == x) return i;
        }
        return null;
    }
};

test {
    _ = @import("grid_groups_tests.zig");
}
