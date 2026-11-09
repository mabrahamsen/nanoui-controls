//! The grid's keyboard: what takes it, the keys that move its selection,
//! and the text typed to jump to a row.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const focus = @import("focus.zig");
const builtin = @import("builtin");
const Grid = @import("grid.zig").Grid;

/// What takes the keyboard for a grid with a selection, as the pager
/// does: from a click in the grid (see `Grid.end`), or Tab (`focus.take`).
/// Without a selection: nothing takes it, id 0.
pub fn take(c: *ui.Context, box: ui.Div, selects: bool) ui.Interaction {
    if (!selects) return .{ .id = 0, .rect = null, .hovered = false, .pressed = false, .clicked = false, .focused = false };
    return focus.take(c, box);
}

/// What the keys did this frame (`useKeys`).
pub const Keys = struct {
    /// The row Enter opened.
    opened: ?usize = null,
    /// Shift was held as the selection moved, which extends it.
    extend: bool = false,
};

/// Moves the selection by the keys pressed this frame, while the grid has
/// the keyboard (`focused`), among `count` rows of which `page` fit in a
/// view.
pub fn useKeys(c: *ui.Context, focused: bool, selected: ?*?usize, count: usize, page: usize) Keys {
    const s = selected orelse return .{};
    if (!focused or count == 0) return .{};
    focus.keysOf(c, &.{ .down, .up, .page_down, .page_up, .home, .end, .enter });
    const last = count - 1;
    const i = s.*;
    const down = if (i) |n| @min(n + 1, last) else 0;
    const up = if (i) |n| n -| 1 else 0;
    var to: ?usize = null;
    var keys: Keys = .{};
    if (c.shortcut(.{ .key = ui.Shortcut.down, .shift = true })) {
        to = down;
        keys.extend = true;
    } else if (c.shortcut(.{ .key = ui.Shortcut.up, .shift = true })) {
        to = up;
        keys.extend = true;
    } else if (c.input.key) |key| {
        switch (key) {
            .down => to = down,
            .up => to = up,
            .page_down => to = if (i) |n| @min(n + page, last) else @min(page, last),
            .page_up => to = if (i) |n| n -| page else 0,
            .home => to = 0,
            .end => to = last,
            .enter => keys.opened = i,
            else => return .{},
        }
        keys.extend = c.input.shift;
        c.input.key = null;
        c.changed = true;
    }
    if (to) |n| s.* = n;
    return keys;
}

/// How long a pause in typing starts the text afresh, in seconds.
pub const type_pause = 1.0;

/// The text typed to jump to a row, kept across frames.
pub const Typing = struct {
    buf: [32]u8 = undefined,
    len: usize = 0,
    /// When the last of it was typed (`Context.time`).
    at: f64 = 0,
};

/// The text typed so far, with what was typed this frame, while the grid
/// has the keyboard (`focused`); null when nothing was typed this frame.
/// A pause of `type_pause` starts it afresh. The text is a copy in the
/// frame's memory: `typing` lives in nanoui's state, which can move.
pub fn useTyping(c: *ui.Context, focused: bool, typing: *Typing, count: usize) ?[]const u8 {
    const chars = c.input.chars;
    if (!focused or count == 0 or chars.len == 0 or c.input.cmd or c.input.ctrl) return null;
    if (c.time - typing.at > type_pause) typing.len = 0;
    const n = @min(chars.len, typing.buf.len - typing.len);
    @memcpy(typing.buf[typing.len..][0..n], chars[0..n]);
    typing.len += n;
    // A character cut in half where the text is full is dropped.
    while (typing.len > 0 and !std.unicode.utf8ValidateSlice(typing.buf[0..typing.len])) typing.len -= 1;
    typing.at = c.time;
    return c.alloc().dupe(u8, typing.buf[0..typing.len]) catch null;
}

/// Backspace or Cmd+Up (Alt+Up off the Mac), and Escape, while the
/// grid has the keyboard.
pub fn otherKeys(g: *Grid) void {
    if (!g.focused) return;
    const c = g.c;
    const mac = builtin.os.tag.isDarwin();
    if (c.shortcut(.{ .key = ui.Shortcut.up, .cmd = mac, .alt = !mac })) {
        g.back = true;
        return;
    }
    focus.keysOf(c, &.{ .backspace, .escape });
    const key = c.input.key orelse return;
    switch (key) {
        .backspace => g.back = true,
        .up => if (if (mac) c.input.cmd else c.input.alt) {
            g.back = true;
        } else return,
        .escape => g.escaped = true,
        else => return,
    }
    c.input.key = null;
    c.changed = true;
}
