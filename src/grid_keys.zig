//! The grid's keyboard: the keys that move its selection, and the text
//! typed to jump to a row.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

/// What the keys did this frame (`useKeys`).
pub const Keys = struct {
    /// The row Enter opened.
    opened: ?usize = null,
    /// Shift was held as the selection moved, which extends it.
    extend: bool = false,
};

/// Moves the selection by the keys pressed this frame, while nothing else
/// has the keyboard, among `count` rows of which `page` fit in a view.
pub fn useKeys(c: *ui.Context, selected: ?*?usize, count: usize, page: usize) Keys {
    const s = selected orelse return .{};
    if (c.focus != 0 or count == 0) return .{};
    const last = count - 1;
    const i = s.*;
    const down = if (i) |n| @min(n + 1, last) else 0;
    const up = if (i) |n| n -| 1 else 0;
    var to: ?usize = null;
    var keys: Keys = .{};
    if (c.shortcut(.{ .key = ui.Shortcut.down })) {
        to = down;
    } else if (c.shortcut(.{ .key = ui.Shortcut.down, .shift = true })) {
        to = down;
        keys.extend = true;
    } else if (c.shortcut(.{ .key = ui.Shortcut.up })) {
        to = up;
    } else if (c.shortcut(.{ .key = ui.Shortcut.up, .shift = true })) {
        to = up;
        keys.extend = true;
    } else if (c.shortcut(.{ .key = ui.Shortcut.enter })) {
        keys.opened = i;
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

/// The text typed so far, with what was typed this frame, while nothing
/// else has the keyboard; null when nothing was typed this frame. A
/// pause of `type_pause` starts it afresh.
pub fn useTyping(c: *ui.Context, typing: *Typing, count: usize) ?[]const u8 {
    const chars = c.input.chars;
    if (c.focus != 0 or count == 0 or chars.len == 0 or c.input.cmd or c.input.ctrl) return null;
    if (c.time - typing.at > type_pause) typing.len = 0;
    const n = @min(chars.len, typing.buf.len - typing.len);
    @memcpy(typing.buf[typing.len..][0..n], chars[0..n]);
    typing.len += n;
    typing.at = c.time;
    return typing.buf[0..typing.len];
}
