//! The grid's columns sized by hand, given `widths`: which columns have a
//! width and which share the room, how far a drag on an edge can go,
//! fitting columns to their contents, and going back to the columns' own
//! widths.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const grid_mod = @import("grid.zig");
const Grid = grid_mod.Grid;
const Column = grid_mod.Column;
const Options = grid_mod.Options;
const lay_mod = @import("grid_layout.zig");
const Layout = lay_mod.Layout;

/// Column `i`'s width in points before `scale`: the caller's in `widths`,
/// or its own; null for a column that shares the room by its `flex`.
pub fn sized(columns: []const Column, opts: Options, i: usize) ?f32 {
    if (opts.widths) |ws| if (ws[i] > 0) return ws[i];
    return columns[i].width;
}

/// The widest column `a` can be dragged to, scaled, without `scroll_x`:
/// the room the other columns leave at their widths, or the flexible ones
/// at their `min_width`. Null with `scroll_x`, where the grid scrolls.
pub fn maxWidth(c: *const ui.Context, columns: []const Column, opts: Options, l: Layout, a: usize) ?f32 {
    if (opts.scroll_x) return null;
    const k = opts.scale;
    var room = l.view - 2 * opts.padding * k;
    var n: f32 = 0;
    for (l.order) |j| {
        if (!lay_mod.shown(c, columns, opts, j, l.grid_w)) continue;
        n += 1;
        if (j == a) continue;
        room -= (sized(columns, opts, j) orelse columns[j].min_width) * k;
    }
    return room - @max(0, n - 1) * opts.column_gap * k;
}

/// Not being fitted, in a fit's widths.
const not_fitted: f32 = -1;

/// The widths a fit measures, one a column: `only`'s, or with null every
/// shown column's, starting at their titles' (`titles`, the header's
/// boxes); `not_fitted` for the others. Null without `widths`.
pub fn fits(c: *ui.Context, columns: []const Column, opts: Options, l: Layout, titles: ?[]const u32, only: ?usize) ?[]f32 {
    if (opts.widths == null) return null;
    const out = c.alloc().alloc(f32, columns.len) catch return null;
    for (out, 0..) |*w, i| {
        const wanted = if (only) |o| o == i else lay_mod.shown(c, columns, opts, i, l.grid_w);
        w.* = if (!wanted) not_fitted else if (titles) |ts| (if (ts[i] != no_title) lay_mod.natural(c, ts[i]) else 0) else 0;
    }
    return out;
}

/// A column without a title box this frame, in the header's list of them.
pub const no_title = std.math.maxInt(u32);

/// Widens column `i`'s fit to the cell `index` just built.
pub fn measure(g: *Grid, i: usize, index: u32) void {
    const f = g.fit orelse return;
    if (f[i] != not_fitted) f[i] = @max(f[i], lay_mod.natural(g.c, index));
}

/// Writes the fit measured this frame into `widths`.
pub fn apply(g: *Grid) void {
    const f = g.fit orelse return;
    const widths = g.opts.widths orelse return;
    for (f, widths, g.columns) |w, *out, col| {
        if (w == not_fitted) continue;
        const fitted = @max(col.min_width, @ceil(w / g.opts.scale) + 1);
        if (fitted != out.*) {
            out.* = fitted;
            g.c.changed = true;
        }
    }
}

/// Fits every column in view to its widest title or cell in view, as a
/// double click past the last title does. Call it before the rows, so
/// their cells are measured. Without `widths`, it does nothing.
pub fn fitAll(g: *Grid) void {
    g.fit = fits(g.c, g.columns, g.opts, g.lay, g.titles, null);
}

/// Writes 0s back to `widths`, so every column goes back to its own
/// `width`, or to sharing the room by its `flex`, from the next frame.
pub fn resetWidths(g: *Grid) void {
    const widths = g.opts.widths orelse return;
    for (widths) |*w| if (w.* != 0) {
        w.* = 0;
        g.c.changed = true;
    };
}
