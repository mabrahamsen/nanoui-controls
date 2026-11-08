//! A grid that is loading: with no rows yet, a spinner, its label and a
//! progress bar over rows sketched in its columns, so the list's shape
//! shows before its data; with rows in, a thin progress line under the
//! titles. Not a control of its own.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const grid_mod = @import("grid.zig");
const lay_mod = @import("grid_layout.zig");
const Column = grid_mod.Column;
const Options = grid_mod.Options;
const Layout = lay_mod.Layout;

/// How far along the loading is: null while nothing has answered yet,
/// which the bars show sweeping.
fn share(l: grid_mod.Loading) ?f32 {
    if (l.total == 0) return null;
    return @as(f32, @floatFromInt(@min(l.done, l.total))) / @as(f32, @floatFromInt(l.total));
}

/// A thin progress line where the titles end, over the rows rather than
/// pushing them down.
pub fn line(c: *ui.Context, opts: Options, l: grid_mod.Loading) void {
    const k = opts.scale;
    const holder = ui.div(c).wFull().h(0);
    defer holder.end();
    const bar = ui.div(c).absolute().offset(0, -1 * k).wFull().h(2 * k);
    defer bar.end();
    kit.progress(c, share(l), .{ .height = 2 * k });
}

/// The spinner, the label and the progress, then `rows` sketched rows in
/// the columns as laid out.
pub fn sketch(c: *ui.Context, columns: []const Column, opts: Options, lay: Layout, l: grid_mod.Loading, rows: usize) void {
    const t = kit.tokens(c);
    const k = opts.scale;
    {
        const head = ui.div(c).row().wFull().itemsCenter().gap(8 * k).px(opts.padding * k).py(8 * k);
        defer head.end();
        kit.spinner(c, .{ .size = 14 * k });
        ui.text(c, l.label, .{ .size = 13, .color = t.muted, .truncate = .ellipsis });
        ui.spacer(c);
        kit.progress(c, share(l), .{ .height = 4 * k, .width = .{ .px = 120 * k } });
        ui.access.describe(c, head.index, .{ .role = .static_text, .label = l.label });
    }
    const h = lay_mod.rowHeight(opts) * k;
    const bar_h = 10 * k;
    const list = ui.div(c).column().wFull().gap(lay_mod.rowGap(opts) * k);
    defer list.end();
    // A decoration: a screen reader hears the label above instead.
    ui.access.hide(c, list.index);
    for (0..rows) |r| {
        const row = ui.div(c).wFull().h(h);
        defer row.end();
        for (lay.order) |i| {
            if (lay.w[i] == 0) continue;
            // Lengths that vary from row to row and column to column, but
            // stay the same from frame to frame.
            const f = 0.35 + 0.5 * @as(f32, @floatFromInt((r * 7 + i * 13 + 3) % 10)) / 10;
            const w = lay.w[i] * f;
            const x = lay.at(i) + switch (columns[i].alignment) {
                .start => 0,
                .center => (lay.w[i] - w) / 2,
                .end => lay.w[i] - w,
            };
            const d = ui.div(c).absolute().offset(x, (h - bar_h) / 2).w(w).h(bar_h);
            defer d.end();
            kit.skeleton(c, .{ .height = bar_h, .radius = 4 * k });
        }
    }
}
