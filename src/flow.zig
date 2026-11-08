//! A flow: cells of one width, as many to a row as fit, so a list of cells
//! wraps onto more rows instead of running off its parent, as nanoui's
//! rows would. It takes its parent's width as the last frame laid it out,
//! as the legend does, so it wraps anew when the window is resized.
//!
//!     var f = controls.flow(c, 180, .{ .gap = 16 });
//!     for (readings) |r| {
//!         const cell = f.cell();
//!         controls.stat(c, r.label, r.value, .{});
//!         cell.end();
//!     }
//!     f.end();
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const measure = @import("measure.zig");

pub const Options = struct {
    /// Between the cells in a row, and between the rows, in points before
    /// `scale`.
    gap: f32 = 10,
    row_gap: f32 = 10,
    /// The cells stretch to share each row's width, `cell_width` the
    /// narrowest they get, for cards that span their pane. A last row of
    /// fewer cells keeps their width, so the columns line up.
    fill: bool = false,
    /// Multiplies its lengths, the cells' width among them, for an app
    /// that zooms its layout along with `c.setZoom`, as the grid's does.
    scale: f32 = 1,
};

/// Opens a flow, as wide as its parent, of cells `cell_width` points wide
/// before `scale`: add them with `cell`, then `end` it.
pub fn flow(c: *ui.Context, cell_width: f32, opts: Options) Flow {
    const k = opts.scale;
    const box = ui.div(c).column().wFull().gap(opts.row_gap * k);
    // The width as the last frame laid it out; until then, the window's.
    const width = if (measure.lastSize(c, box.index)) |s| s.w else c.size.w;
    // A cell and its gap take at least a point, so a row holds a finite
    // number of them.
    const fit = @floor(@max(0, width + opts.gap * k) / @max(1, (cell_width + opts.gap) * k));
    const per_row: usize = @intFromFloat(@max(1, fit));
    const n: f32 = @floatFromInt(per_row);
    const shared = (width - opts.gap * k * (n - 1)) / n;
    const cell_px = if (opts.fill) @max(cell_width * k, shared) else cell_width * k;
    return .{ .c = c, .box = box, .opts = opts, .cell_px = cell_px, .per_row = per_row };
}

/// An open flow: add its cells, then `end` it.
pub const Flow = struct {
    /// How many cells fit in a row.
    per_row: usize,
    /// How many rows the cells took, so far.
    rows: usize = 0,

    // The rest is the flow's own.
    c: *ui.Context,
    box: ui.Div,
    opts: Options,
    /// Each cell's width, in points as drawn.
    cell_px: f32,
    row: ?ui.Div = null,
    /// Cells in the row being filled.
    in_row: usize = 0,

    /// The next cell's box, a column: draw in it, then end it.
    pub fn cell(f: *Flow) ui.Div {
        if (f.row == null or f.in_row == f.per_row) {
            if (f.row) |r| r.end();
            f.row = ui.div(f.c).row().wFull().itemsStart().gap(f.opts.gap * f.opts.scale);
            f.rows += 1;
            f.in_row = 0;
        }
        f.in_row += 1;
        return ui.div(f.c).column().w(f.cell_px).clip();
    }

    /// Starts the next cell on a new row.
    pub fn breakRow(f: *Flow) void {
        if (f.row != null) f.in_row = f.per_row;
    }

    /// Ends the flow.
    pub fn end(f: *Flow) void {
        if (f.row) |r| r.end();
        f.box.end();
    }
};

const Cells = struct {
    width: f32 = 400,
    break_at: ?usize = null,
    rows: usize = 0,
    fn view(x: *Cells, c: *ui.Context) void {
        const box = ui.div(c).column().w(x.width);
        defer box.end();
        var f = flow(c, 120, .{ .gap = 20 });
        for ([_][]const u8{ "one", "two", "three", "four" }, 0..) |s, i| {
            if (x.break_at == i) f.breakRow();
            const cell = f.cell();
            ui.text(c, s, .{});
            cell.end();
        }
        x.rows = f.rows;
        f.end();
    }
};

test "with fill, cells share each row's width, a last short row keeping it" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            const box = ui.div(c).column().w(460);
            defer box.end();
            var f = flow(c, 120, .{ .gap = 20, .fill = true });
            for ([_][]const u8{ "one", "two", "three", "four" }) |s| {
                const cell = f.cell();
                ui.text(c, s, .{});
                cell.end();
            }
            f.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 900, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // Three to a row, stretched from 120 to (460 - 2 * 20) / 3 = 140 wide:
    // 160 apart with the gap.
    try std.testing.expectApproxEqAbs(@as(f32, 160), t.findText("two").?.x - t.findText("one").?.x, 0.5);
    try std.testing.expectApproxEqAbs(t.findText("one").?.x, t.findText("four").?.x, 0.5);
}

test "cells wrap onto rows of as many as fit the parent, and wrap anew when it changes" {
    var x: Cells = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Cells.view), .{ .width = 900, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // (400 + 20) / (120 + 20): three to a row, though four would fit the
    // window.
    const one = t.findText("one").?;
    const three = t.findText("three").?;
    const four = t.findText("four").?;
    try std.testing.expectEqual(one.y, three.y);
    try std.testing.expectEqual(@as(f32, 280), three.x - one.x);
    try std.testing.expectEqual(one.x, four.x);
    try std.testing.expect(four.y > one.y);
    try std.testing.expectEqual(@as(usize, 2), x.rows);
    x.width = 600;
    // A frame to lay out the new width, and one to wrap to it.
    for (0..2) |_| t.frame();
    try std.testing.expectEqual(t.findText("one").?.y, t.findText("four").?.y);
    try std.testing.expectEqual(@as(usize, 1), x.rows);
}

test "cells of no width and no gap make a row of many, not a crash" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            var f = flow(c, 0, .{ .gap = 0 });
            for (0..3) |_| f.cell().end();
            f.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 100 });
    defer t.deinit();
    t.settle(1);
}

test "breakRow starts the next cell on a new row" {
    var x: Cells = .{ .width = 900, .break_at = 1 };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Cells.view), .{ .width = 900, .height = 300 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expectEqual(t.findText("one").?.x, t.findText("two").?.x);
    try std.testing.expectEqual(t.findText("two").?.y, t.findText("four").?.y);
    try std.testing.expectEqual(@as(usize, 2), x.rows);
}
