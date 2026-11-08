//! The grid's selection: a row picked alone, added, or a run of rows
//! from where the selection started, by clicks and the keys; jumping to
//! a row; and a row held and moved to drag the selection out.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const Grid = @import("grid.zig").Grid;
const keys = @import("grid_keys.zig");
const lay_mod = @import("grid_layout.zig");

/// Follows row `i` held down: true once it has moved far enough to
/// drag, when the row is selected unless it is already.
pub fn pressDrags(g: *Grid, i: usize) bool {
    const m = g.c.input.mouse;
    if (g.press.row != i) {
        g.press = .{ .row = i, .x = m.x, .y = m.y };
        return false;
    }
    if (g.press.dragging or @abs(m.x - g.press.x) + @abs(m.y - g.press.y) < 4 * g.opts.scale) return false;
    g.press.dragging = true;
    if (!g.isSelected(i)) g.pick(i, .only);
    g.c.changed = true;
    return true;
}

/// Starts dragging `text` out of the grid, with the row being built as
/// what is seen dragged: in the frame `Row.drag_started` says so.
pub fn dragOut(g: *Grid, text: []const u8) void {
    const r = g.row orelse return;
    g.c.startDrag(r.index, text);
}

/// Selects row `i` alone, if rows select, and scrolls it into view:
/// where `typed` leads. The grid is drawn again to show it.
pub fn jump(g: *Grid, i: usize) void {
    if (i >= lay_mod.rowsShown(g.opts)) return;
    g.pick(i, .only);
    g.jump_to = i;
    g.c.changed = true;
}

/// Row `i` is selected: among `selection`'s, or `selected` without it.
pub fn isSelected(g: *const Grid, i: usize) bool {
    if (g.opts.selection) |m| return m[i];
    return if (g.opts.selected) |s| s.* == i else false;
}

pub const Pick = enum { only, toggle, extend };

/// Makes row `i` the selected one, and changes `selection` as `how` says:
/// `i` alone, `i` added or taken away, or every row from the anchor
/// to `i`.
pub fn pick(g: *Grid, i: usize, how: Pick) void {
    const s = g.opts.selected orelse return;
    s.* = i;
    const m = g.opts.selection orelse return;
    switch (how) {
        .only => {
            @memset(m, false);
            m[i] = true;
            g.anchor = i;
        },
        .toggle => {
            m[i] = !m[i];
            g.anchor = i;
        },
        .extend => {
            const from = g.anchor orelse i;
            g.anchor = from;
            @memset(m, false);
            @memset(m[@min(from, i) .. @max(from, i) + 1], true);
        },
    }
}

/// Follows the keys with `selection`: the row they moved to alone, or with
/// Shift the rows from the anchor to it.
pub fn useKeys(g: *Grid, before: ?usize, k: keys.Keys) void {
    g.opened = k.opened;
    const s = g.opts.selected orelse return;
    const i = s.* orelse return;
    if (i != before) g.pick(i, if (k.extend) .extend else .only);
}
