//! The grid's cells: opening one in its column, ending it with its
//! tooltip when cut off, and the lines between rows and columns.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const Grid = @import("grid.zig").Grid;
const lay_mod = @import("grid_layout.zig");
const widths_mod = @import("grid_widths.zig");
const rows = @import("grid_rows.zig");

/// Opens the row's next cell, ending the one before: what is drawn
/// until the next `cell` goes in it. When columns hide, use `cellAt`,
/// as this panics on a hidden one.
pub fn cell(g: *Grid) void {
    if (!g.cellAt(g.column)) @panic("grid: `cell` opened a hidden column; use `cellAt`");
}

/// Opens column `i`'s cell, ending the one before, and returns true;
/// false when the column is hidden, with nothing to draw. Columns go
/// in order: `i` is past the cell before.
pub fn cellAt(g: *Grid, i: usize) bool {
    endCell(g);
    std.debug.assert(g.row != null and i >= g.column and i < g.columns.len);
    g.column = i + 1;
    if (!g.isShown(i)) return false;
    const c = g.c;
    const l = g.lay;
    const k = g.opts.scale;
    const h = lay_mod.rowHeight(g.opts) * k;
    // The frozen column's cell sits in the row; the others in a box
    // past it that cuts them off as they scroll.
    var origin: f32 = 0;
    if (l.frozen == i) {
        endCut(g);
    } else {
        if (g.cut == null) g.cut = ui.div(c).absolute().offset(l.clip_x, 0).w(@max(0, l.view - l.clip_x)).h(h).clip();
        origin = l.clip_x;
    }
    var d = ui.div(c).absolute().offset(l.at(i) - origin, 0).w(l.w[i]).h(h).row().itemsCenter().gap(g.opts.column_gap * k / 2);
    // The first column steps in for each level of groups the row is in.
    if (i == 0 and g.row_depth > 0) d = d.pl(@as(f32, @floatFromInt(g.row_depth)) * rows.indent_step * k);
    d = switch (g.columns[i].alignment) {
        .start => d,
        .center => d.justifyCenter(),
        .end => d.justifyEnd(),
    };
    g.cell_box = d;
    g.cell_column = i;
    return true;
}

/// Ends the cell, measuring it for a fit, and showing its whole text on
/// hover if it is cut off.
pub fn endCell(g: *Grid) void {
    const b = g.cell_box orelse return;
    const i = g.cell_column;
    widths_mod.measure(g, i, b.index);
    if (g.opts.tooltips) tooltip(g, b, i);
    b.end();
    g.cell_box = null;
}

/// The cell's whole text over it, while the pointer rests on it and
/// the text is cut off. Asked of every cut-off cell in view, under the
/// pointer or not, so its wait starts when the pointer comes.
pub fn tooltip(g: *Grid, b: ui.Div, i: usize) void {
    const c = g.c;
    const id = c.node(b.index).id;
    const rect = c.rects.get(id) orelse return;
    if (lay_mod.natural(c, b.index) <= g.lay.w[i] + 0.5) return;
    // Not where the frozen column covers it.
    const visible = g.lay.frozen == i or c.input.mouse.x >= g.lay.left + g.lay.clip_x;
    const over = g.row_hovered and visible and rect.contains(c.input.mouse);
    const text = ui.access.textOf(c, c.alloc(), b.index) catch return;
    kit.tooltip(c, .{ .id = id, .rect = rect, .hovered = over, .pressed = false, .clicked = false, .focused = false }, text, .{});
}

pub fn endCut(g: *Grid) void {
    if (g.cut) |d| d.end();
    g.cut = null;
}

pub fn endRow(g: *Grid) void {
    endCell(g);
    if (g.row != null) lines(g);
    endCut(g);
    if (g.row) |r| r.end();
    g.row = null;
}

/// The row's lines: down the gaps between its columns, the scrolled
/// ones' cut off past the frozen column, and along its bottom.
pub fn lines(g: *Grid) void {
    const c = g.c;
    const l = g.lay;
    const k = g.opts.scale;
    const h = lay_mod.rowHeight(g.opts) * k;
    const border = kit.tokens(c).border;
    const half = g.opts.column_gap * k / 2;
    if (g.opts.column_lines) {
        if (g.cut == null) g.cut = ui.div(c).absolute().offset(l.clip_x, 0).w(@max(0, l.view - l.clip_x)).h(h).clip();
        var last: ?usize = null;
        for (l.order) |i| if (l.w[i] > 0) {
            last = i;
        };
        for (l.order) |i| {
            if (l.w[i] == 0 or i == last or i == l.frozen) continue;
            ui.div(c).absolute().offset(l.at(i) + l.w[i] + half - l.clip_x, 0).w(1).h(h).bg(border).end();
        }
    }
    endCut(g);
    if (l.frozen) |f| if (g.opts.column_lines or l.sx > 0) {
        ui.div(c).absolute().offset(l.x[f] + l.w[f] + half, 0).w(1).h(h).bg(border).end();
    };
    if (g.opts.row_lines and g.opts.rows != .cards) ui.div(c).absolute().offset(0, h - 1).w(l.view).h(1).bg(border).end();
}
