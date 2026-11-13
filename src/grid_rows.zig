//! The grid's rows beyond their cells: a group's heading, open for the
//! caller's content or not, and its keys, folding and the fade as a group
//! opens, following the selection as groups fold, two lines in a cell,
//! and a status on a row's edge.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const focus = @import("focus.zig");
const grid_mod = @import("grid.zig");
const Grid = grid_mod.Grid;
const Options = grid_mod.Options;
const lay_mod = @import("grid_layout.zig");
const groups_mod = @import("grid_groups.zig");
const cells = @import("grid_cells.zig");

/// A heading's look (`Grid.heading`).
pub const Heading = struct {
    title: []const u8,
    /// Muted, after the title: "4 pull requests".
    detail: []const u8 = "",
    /// The title in the first column's cell, leaving the others for the
    /// caller's `cellAt`, for a group's totals; false spans the columns.
    cells: bool = false,
    /// What a screen reader hears of the heading, for one whose content
    /// (`headingOpen`) says more ("Inbox, 3 unread, 1 flagged"); empty
    /// takes the title and the detail.
    label: []const u8 = "",
};

/// A heading's row the caller draws in (`Grid.headingRow`).
pub const HeadingRow = struct {
    /// The row's box, open for the caller's chevron, title and the rest:
    /// across the columns stepped in by `depth`, or with `cells` the
    /// first column's cell. The caller ends it.
    box: ui.Div,
    /// The group is open, after this frame's click or key.
    open: bool,
    /// How many groups it is in: 0 at the top.
    depth: u8,
};

/// A cell's two lines (`Grid.twoLines`).
pub const TwoLines = struct {
    /// The title's size; the detail is a point and a half smaller.
    size: f32 = 13,
    /// Null takes the theme's muted text.
    detail_color: ?ui.Color = null,
    mono_detail: bool = false,
};

/// Keeps `selected` on the row it was on when the rows in view changed
/// under it, as a group above it folded or opened; on the nearest heading
/// over it when it was folded away. A caller that moved the selection
/// itself keeps its own.
pub fn follow(c: *ui.Context, opts: Options) void {
    const gs = opts.groups orelse return;
    const s = opts.selected orelse return;
    const i = s.* orelse return;
    const was = lay_mod.state(c, Follow).*;
    const item = was.item orelse return;
    if (was.at != i) return;
    if (i < gs.count() and gs.at(i).eql(item)) return;
    if (gs.locate(item)) |j| {
        s.* = j;
        c.changed = true;
    }
}

/// The selected row's place in its groups, and where it was in view, to
/// follow it when groups fold or open.
pub const Follow = struct { item: ?groups_mod.Item = null, at: usize = 0 };

/// The group opened last, and when, whose rows fade in.
pub const Opening = struct { group: ?usize = null, at: f64 = 0 };

/// How long a group's rows take to fade in as it opens, in seconds.
const fade_time = 0.2;

/// Draws the row being built as its group's heading: a chevron, the
/// title and the detail, across the columns, or with `cells` in the
/// first column's cell, the caller's `cellAt` filling the others. A
/// click on it folds or opens its group.
pub fn heading(g: *Grid, opts: Heading) void {
    if (draw(g, opts, false)) |box| box.end();
}

/// Draws the row being built as its group's heading, as `heading` does,
/// and leaves it open after the title and the detail for the caller's
/// content, such as tinted labels; the caller ends it. A click on the
/// content folds or opens the group, unless the content takes the click
/// itself, as a button does.
pub fn headingOpen(g: *Grid, opts: Heading) ui.Div {
    return draw(g, opts, true).?;
}

/// Makes the row being built its group's heading with nothing drawn in
/// it, for a heading that looks the caller's way: the caller draws its
/// chevron (the way `open` says), title and the rest in `box`, and ends
/// it. The grid keeps the rest of a heading: a click folds or opens it,
/// the keys, the selection, and what a screen reader hears of `opts`.
pub fn headingRow(g: *Grid, opts: Heading) HeadingRow {
    const at = place(g, opts);
    const c = g.c;
    // The cell is the grid's to end: the caller's content goes in a box of
    // its own in it.
    const box = if (at.in_cell) ui.div(c).row().wFull().itemsCenter().gap(g.opts.column_gap * g.opts.scale / 2) else at.box;
    return .{ .box = box, .open = at.open, .depth = at.depth };
}

/// A heading's row made ready: its group folded or opened by a click, its
/// description, and the box its content goes in.
const Place = struct { box: ui.Div, in_cell: bool, open: bool, depth: u8 };

fn place(g: *Grid, opts: Heading) Place {
    const gs = g.opts.groups orelse @panic("grid: `heading` needs `groups`");
    const item = gs.at(g.row_index);
    if (item != .heading) @panic("grid: `heading` on a row that isn't one");
    const group = item.heading.group;
    if (g.row_clicked) toggle(g, group);
    const open = gs.open[group];
    const c = g.c;
    const k = g.opts.scale;
    const label = if (opts.label.len > 0) opts.label else if (opts.detail.len > 0) c.print("{s}, {s}", .{ opts.title, opts.detail }) else opts.title;
    ui.access.describe(c, g.row.?.index, .{
        .role = .row,
        .label = label,
        .value = if (open) g.opts.expanded_text else g.opts.collapsed_text,
        .selected = g.isSelected(g.row_index),
    });
    // In the first column's cell, unless that column is hidden.
    const in_cell = opts.cells and g.cellAt(0);
    const box = if (in_cell) g.cell_box.? else blk: {
        const x = (g.opts.padding + @as(f32, @floatFromInt(item.heading.depth)) * g.opts.indent_step) * k;
        break :blk ui.div(c).absolute().offset(x, 0).w(@max(0, g.lay.view - x - g.opts.padding * k)).h(lay_mod.rowHeight(g.opts) * k).row().itemsCenter().gap(g.opts.column_gap * k / 2);
    };
    return .{ .box = box, .in_cell = in_cell, .open = open, .depth = item.heading.depth };
}

/// Draws a heading, returning its box left open with `open`, or else the
/// box the caller ends: null in the first column's cell, which the grid
/// ends.
fn draw(g: *Grid, opts: Heading, open_for_caller: bool) ?ui.Div {
    const at = place(g, opts);
    const c = g.c;
    const t = kit.tokens(c);
    const k = g.opts.scale;
    const gap = g.opts.column_gap * k / 2;
    const in_cell = at.in_cell;
    const box = at.box;
    const open = at.open;
    {
        const slot = ui.div(c).w(@max(0, g.opts.indent_step - g.opts.column_gap / 2) * k).h(12 * k).center();
        defer slot.end();
        ui.icon(c, if (open) "chevron.down" else "chevron.right", .{ .size = 9.5 * k, .color = t.muted });
    }
    ui.text(c, opts.title, .{ .size = 13, .weight = .semibold, .truncate = .ellipsis });
    if (opts.detail.len > 0) ui.text(c, opts.detail, .{ .size = 12, .color = t.muted, .truncate = .ellipsis });
    if (!in_cell) return box;
    // The cell is the grid's to end: the caller's content goes in a box of
    // its own in it.
    return if (open_for_caller) ui.div(c).row().itemsCenter().gap(gap) else null;
}

/// Draws a title over a muted detail in the cell open, each cut short
/// with an ellipsis, and whole in the cell's tooltip. Give the grid
/// `lines = 2` for the room.
pub fn twoLines(g: *Grid, title: []const u8, detail: []const u8, opts: TwoLines) void {
    std.debug.assert(g.cell_box != null);
    const c = g.c;
    const col = ui.div(c).column().wFull().gap(1 * g.opts.scale);
    defer col.end();
    ui.text(c, title, .{ .size = opts.size, .truncate = .ellipsis });
    ui.text(c, detail, .{ .size = opts.size - 1.5, .color = opts.detail_color orelse kit.tokens(c).muted, .mono = opts.mono_detail, .truncate = .ellipsis });
}

/// Folds or opens `group`; its rows fade in as it opens.
pub fn toggle(g: *Grid, group: usize) void {
    const gs = g.opts.groups orelse return;
    gs.open[group] = !gs.open[group];
    if (gs.open[group]) g.opened_group = group;
    g.c.changed = true;
}

/// Where the rows of the group opened last are in fading in.
pub fn fadeFrom(g: *Grid, o: Opening) void {
    const group = o.group orelse return;
    if (g.opts.groups == null or !g.opts.fade_in) return;
    const c = g.c;
    const u: f32 = if (c.reduced_motion) 1 else @floatCast(std.math.clamp((c.time - o.at) / fade_time, 0, 1));
    if (u >= 1) return;
    g.fade_group = group;
    g.fade = ui.motion.Easing.sample(.ease_out, u)[0];
    c.animationFrame();
}

/// The row's edge in `s`'s color (`Row.status`).
pub fn rowStatus(g: *Grid, s: kit.Status) void {
    const r = g.row orelse return;
    const c = g.c;
    const t = kit.tokens(c);
    const k = g.opts.scale;
    const color = if (s == .neutral) t.primary else kit.statusColor(t, s);
    if (g.opts.rows == .cards) {
        _ = r.border(color);
        return;
    }
    cells.endCell(g);
    cells.endCut(g);
    const h = lay_mod.rowHeight(g.opts) * k;
    ui.div(c).absolute().offset(2 * k, 5 * k).w(3 * k).h(@max(0, h - 10 * k)).roundedFull().bg(color).end();
}

/// The keys on groups, while the grid has the keyboard: Left folds a
/// heading or goes from a row to its heading, Right opens a heading or
/// goes to its first row, and Enter or Space folds or opens one.
pub fn groupKeys(g: *Grid) void {
    const gs = g.opts.groups orelse return;
    const s = g.opts.selected orelse return;
    const i = s.* orelse return;
    if (!g.focused or i >= gs.count()) return;
    const c = g.c;
    switch (gs.at(i)) {
        .heading => |h| {
            const open = gs.open[h.group];
            if (c.shortcut(.{ .key = ui.Shortcut.enter }) or c.shortcut(.{ .key = ' ' })) return toggle(g, h.group);
            if (std.mem.eql(u8, c.input.chars, " ")) {
                c.input.chars = "";
                return toggle(g, h.group);
            }
            focus.keysOf(c, &.{ .enter, .left, .right });
            const key = c.input.key orelse return;
            switch (key) {
                .enter => toggle(g, h.group),
                .left => if (open) {
                    toggle(g, h.group);
                } else if (gs.parent(h.group)) |p| {
                    if (gs.locate(.{ .heading = .{ .group = p, .depth = 0 } })) |j| g.pick(j, .only);
                },
                .right => if (!open) {
                    toggle(g, h.group);
                } else if (i + 1 < gs.count() and gs.within(gs.at(i + 1).group(), h.group)) {
                    g.pick(i + 1, .only);
                },
                else => return,
            }
            c.input.key = null;
            c.changed = true;
        },
        .row => |r| {
            focus.keysOf(c, &.{.left});
            if (c.input.key != .left) return;
            // Its group's heading; a group of one shown as its row goes
            // to the heading over it.
            var to = gs.locate(.{ .heading = .{ .group = r.group, .depth = 0 } });
            if (to == i) to = if (gs.parent(r.group)) |p| gs.locate(.{ .heading = .{ .group = p, .depth = 0 } }) else null;
            if (to) |j| g.pick(j, .only);
            c.input.key = null;
            c.changed = true;
        },
    }
}
