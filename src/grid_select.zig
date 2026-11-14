//! The grid's selection: a row picked alone, added, or a run of rows
//! from where the selection started, by clicks and the keys; jumping to
//! a row; a row held and moved to drag the selection out; and the
//! selection kept on its rows' keys as the rows change.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const grid_mod = @import("grid.zig");
const Grid = grid_mod.Grid;
const Options = grid_mod.Options;
const keys = @import("grid_keys.zig");
const lay_mod = @import("grid_layout.zig");
const groups_mod = @import("grid_groups.zig");
const Follow = @import("grid_rows.zig").Follow;

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
    // Enter opens the row the keys are on while it is selected: not one
    // Cmd-click (Ctrl-click) took out of the selection.
    g.opened = if (k.opened) |i| (if (g.isSelected(i)) i else null) else null;
    const s = g.opts.selected orelse return;
    const i = s.* orelse return;
    if (i != before) g.pick(i, if (k.extend) .extend else .only);
}

/// What the grid keeps between frames to follow its selection by key
/// (`Options.keys`): the selected row's key and where it was, and with
/// `selection`, the anchor's key, the keys' print and how many rows were
/// selected, their keys kept in `Marked`s.
const KeyFollow = struct {
    key: u64 = 0,
    at: ?usize = null,
    anchor: u64 = 0,
    print: u64 = 0,
    marked: u32 = 0,
};

/// The keys of six rows selected together, as many as a state holds.
const Marked = struct { keys: [per_marked]u64 = @splat(0) };
const per_marked = 6;

/// A key as the grid keeps it: never 0, which is none.
fn keyHash(key: []const u8) u64 {
    return std.hash.Wyhash.hash(0, key) | 1;
}

/// The keys in order, as one number: it changes when the rows do.
fn keysPrint(ks: []const []const u8) u64 {
    var h = std.hash.Wyhash.init(0);
    for (ks) |key| {
        h.update(std.mem.asBytes(&key.len));
        h.update(key);
    }
    return h.final() | 1;
}

fn find(ks: []const []const u8, key: u64) ?usize {
    for (ks, 0..) |x, i| if (keyHash(x) == key) return i;
    return null;
}

/// What following the keys found: the key of a selected row that is
/// gone, the keys' print, and where the anchor went when the rows changed.
pub const Followed = struct {
    lost: u64 = 0,
    print: u64 = 0,
    anchor: ??usize = null,
};

/// Keeps the selection on its rows' keys when the rows changed under it
/// (`Options.keys`), at the start of the grid. A caller that moved the
/// selection itself keeps its own.
pub fn followKeys(c: *ui.Context, opts: Options) Followed {
    const ks = opts.keys orelse return .{};
    const s = opts.selected orelse return .{};
    const was = lay_mod.state(c, KeyFollow).*;
    if (opts.selection) |m| return followMarked(c, ks, s, m, was);
    if (s.* != was.at or was.key == 0) return .{};
    if (s.*) |i| if (i < ks.len and keyHash(ks[i]) == was.key) return .{};
    if (find(ks, was.key)) |j| {
        s.* = j;
        c.changed = true;
        return .{};
    }
    // Gone. A group folded over it selects its heading, as without keys.
    if (opts.groups) |gs| if (lay_mod.state(c, Follow).item) |item| if (foldedAway(gs, item)) if (gs.locate(item)) |j| {
        s.* = j;
        c.changed = true;
        return .{};
    };
    if (s.* != null) c.changed = true;
    s.* = null;
    return .{ .lost = was.key };
}

/// `item` doesn't show because a group over it is folded.
fn foldedAway(gs: groups_mod.Groups, item: groups_mod.Item) bool {
    const g = item.group();
    if (g >= gs.groups.len) return false;
    const p = gs.place[g] orelse return true;
    const sh = gs.shown[p];
    return item == .row and !sh.single and sh.len == 1;
}

/// Follows `selection` and `selected` by key, when the rows changed: each
/// row selected before is selected again where it is now, and one that is
/// gone is dropped.
fn followMarked(c: *ui.Context, ks: []const []const u8, s: *?usize, m: []bool, was: KeyFollow) Followed {
    const print = keysPrint(ks);
    if (was.print == 0 or print == was.print) return .{ .print = print };
    var at: std.AutoHashMapUnmanaged(u64, usize) = .empty;
    const a = c.alloc();
    at.ensureTotalCapacity(a, @intCast(ks.len)) catch @panic("grid: out of memory");
    for (ks, 0..) |key, i| at.putAssumeCapacity(keyHash(key), i);
    @memset(m, false);
    var n: usize = 0;
    while (n < was.marked) : (n += 1) {
        const chunk = lay_mod.stateAt(c, Marked, n / per_marked).*;
        if (at.get(chunk.keys[n % per_marked])) |i| m[i] = true;
    }
    if (s.* == was.at) s.* = if (was.key != 0) at.get(was.key) else null;
    c.changed = true;
    return .{ .print = print, .anchor = if (was.anchor != 0) at.get(was.anchor) else null };
}

/// Keeps the selected rows' keys for the next frame, in `Grid.end`.
pub fn keepKeys(g: *Grid) void {
    const ks = g.opts.keys orelse return;
    const s = g.opts.selected orelse return;
    const c = g.c;
    var kept: KeyFollow = .{ .at = s.*, .print = g.print };
    kept.key = if (s.*) |i| (if (i < ks.len) keyHash(ks[i]) else 0) else g.lost;
    if (g.opts.selection) |m| {
        if (g.anchor) |i| if (i < ks.len) {
            kept.anchor = keyHash(ks[i]);
        };
        var n: usize = 0;
        var chunk: Marked = .{};
        for (m, 0..) |on, i| {
            if (!on) continue;
            chunk.keys[n % per_marked] = keyHash(ks[i]);
            n += 1;
            if (n % per_marked == 0) lay_mod.stateAt(c, Marked, n / per_marked - 1).* = chunk;
        }
        if (n % per_marked != 0) lay_mod.stateAt(c, Marked, n / per_marked).* = chunk;
        kept.marked = @intCast(n);
    }
    lay_mod.state(c, KeyFollow).* = kept;
}
