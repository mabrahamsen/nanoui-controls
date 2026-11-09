//! The sidebar's keys, while it has the keyboard: where they start, the
//! rows, branches and headings they move between, folding and choosing,
//! and scrolling the row they reach into view.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const focus = @import("focus.zig");
const Sidebar = @import("sidebar.zig").Sidebar;
const typing_mod = @import("grid_keys.zig");

/// The text typed to move to a row, kept by a key of its own: use it at
/// once.
fn typing(c: *ui.Context) *typing_mod.Typing {
    ui.key(c, "sidebar-typing");
    defer c.next_key = null;
    return c.state(typing_mod.Typing, "sidebar-typing");
}

/// Where typing moves the keys: to the first entry after them whose label
/// begins with the text typed, or with a letter typed again, the next
/// that begins with it. The characters are the sidebar's.
fn typed(c: *ui.Context, list: anytype, at: ?usize) ?usize {
    const chars = c.input.chars;
    if (chars.len == 0 or std.mem.eql(u8, chars, " ")) return null;
    const text = typing_mod.useTyping(c, true, typing(c), list.len) orelse return null;
    c.input.chars = "";
    const again = text.len > 1 and std.mem.allEqual(u8, text, text[0]);
    const from = if (at) |a| (if (text.len == 1 or again) a + 1 else a) else 0;
    return typedTo(list, from, if (again) text[0..1] else text);
}

/// The first entry from `from`, round to it again, whose label begins
/// `text`, ignoring case, as the grid's typing does.
fn typedTo(list: anytype, from: usize, text: []const u8) ?usize {
    for (0..list.len) |n| {
        const i = (from + n) % list.len;
        if (std.ascii.startsWithIgnoreCase(list[i].label, text)) return i;
    }
    return null;
}

/// Where the keys are among the entries drawn: the entry they moved
/// to, else the selected row, else none.
pub fn place(sb: *const Sidebar) ?usize {
    const list = sb.entries.items;
    if (sb.kept.cursor != 0) for (list, 0..) |e, i| if (e.hash == sb.kept.cursor) return i;
    const s = sb.selected orelse return null;
    for (list, 0..) |e, i| if (e.choosable and std.mem.eql(u8, e.key, s)) return i;
    return null;
}

/// The keys, while the sidebar has the keyboard: on the rows, branches
/// and headings drawn this frame. The keys it acts on are its own:
/// nothing after it sees them.
pub fn keys(sb: *Sidebar) void {
    const c = sb.c;
    const list = sb.entries.items;
    if (list.len == 0) return;
    const last = list.len - 1;
    const at = place(sb);
    // A cursor whose entry is gone follows the selection again.
    if (at == null or list[at.?].hash != sb.kept.cursor) sb.kept.cursor = 0;
    var to: ?usize = null;
    var enter = false;
    focus.keysOf(c, &.{ .down, .up, .home, .end, .enter, .left, .right });
    if (typed(c, list, at)) |i| {
        to = i;
    } else if (c.shortcut(.{ .key = ' ' })) {
        enter = true;
    } else if (c.input.key) |key| {
        switch (key) {
            .down => to = if (at) |a| @min(a + 1, last) else 0,
            .up => to = if (at) |a| a -| 1 else last,
            .home => to = 0,
            .end => to = last,
            .enter => enter = true,
            // Left folds what is open, else goes to what the entry is
            // in; Right opens what is folded, else goes to its first
            // row, as on a fixed branch.
            .left => if (at) |a| {
                const e = list[a];
                if (e.open != null and e.open.?.*) {
                    e.open.?.* = false;
                    c.changed = true;
                } else if (e.parent) |p| to = p;
            },
            .right => if (at) |a| {
                const e = list[a];
                if (e.open != null and !e.open.?.*) {
                    e.open.?.* = true;
                    c.changed = true;
                } else if (a + 1 < list.len and list[a + 1].parent == a) to = a + 1;
            },
            else => return,
        }
        c.input.key = null;
    }
    if (enter) if (at) |a| {
        const e = list[a];
        if (e.choosable) {
            if (!sb.isSelected(e.key)) sb.choose(e.key);
        } else if (e.open) |o| {
            o.* = !o.*;
            c.changed = true;
        }
        sb.kept.cursor = e.hash;
    };
    // Nothing to start from: the first row shows the ring until a key
    // moves.
    const start = at == null and to == null;
    if (start != sb.kept.start) c.changed = true;
    sb.kept.start = start;
    const i = to orelse return;
    const next = list[i];
    sb.kept.cursor = next.hash;
    c.changed = true;
    if (next.choosable and !sb.opts.choose_on_enter and !sb.isSelected(next.key)) sb.choose(next.key);
    reveal(sb, next.index);
}

/// Scrolls the sidebar so box `index`, as last laid out, is in view.
pub fn reveal(sb: *Sidebar, index: u32) void {
    const c = sb.c;
    const box_id = c.node(sb.outer.index).id;
    const view = c.rects.get(box_id) orelse return;
    const r = c.rects.get(c.node(index).id) orelse return;
    const offset = ui.scrollOffset(c, box_id, .y);
    if (r.y < view.y) {
        ui.setScrollOffset(c, box_id, .y, offset - (view.y - r.y));
    } else if (r.y + r.h > view.y + view.h) {
        ui.setScrollOffset(c, box_id, .y, offset + (r.y + r.h - view.y - view.h));
    }
}
