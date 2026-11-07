//! The gallery: each of the library's controls in an app, a view each,
//! picked from a sidebar. "Grid" is a grid of ten thousand files with a
//! pager (grid.zig), and "Charts" a system monitor whose charts move with
//! its readings (charts.zig).
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const grid = @import("grid.zig");
const charts = @import("charts.zig");

const Gallery = struct {
    shown: Section = .grid,
    browser: grid.Browser,
    monitor: charts.Monitor,

    const Section = enum { grid, charts };

    fn view(g: *Gallery, c: *ui.Context) void {
        const t = kit.tokens(c);
        const root = ui.div(c).row().sizeFull();
        defer root.end();
        {
            const side = ui.div(c).column().w(200).hFull().p(10).gap(2).bg(t.surface);
            defer side.end();
            ui.div(c).h(4).end();
            {
                const head = ui.div(c).row().wFull().px(10).pb(6);
                defer head.end();
                ui.text(c, "CONTROLS", .{ .size = 10, .weight = .semibold, .color = t.muted });
            }
            if (item(c, "tablecells", "Grid", g.browser.shown_len, g.shown == .grid)) g.shown = .grid;
            if (item(c, "chart.bar.fill", "Charts", null, g.shown == .charts)) g.shown = .charts;
        }
        ui.div(c).w(1).hFull().bg(t.border).end();
        const pane = ui.div(c).column().wFull().hFull();
        defer pane.end();
        switch (g.shown) {
            .grid => g.browser.view(c),
            .charts => g.monitor.view(c),
        }
    }
};

/// One of the sidebar's items: an icon in a slot of its own, so labels
/// line up whatever the icons' widths, its label, and a count at the end;
/// tinted when it is the one shown. True when clicked.
fn item(c: *ui.Context, icon: []const u8, label: []const u8, count: ?usize, selected: bool) bool {
    const t = kit.tokens(c);
    var row = ui.div(c).row().wFull().itemsCenter().gap(8).px(10).py(7).rounded(t.radius);
    const it = row.interaction();
    if (selected) {
        row = row.bg(t.primary.alpha(0.12));
    } else if (it.hovered) row = row.bg(t.surface_hover);
    defer row.end();
    if (it.hovered) c.cursor_hand = true;
    {
        const slot = ui.div(c).w(16).center();
        defer slot.end();
        ui.icon(c, icon, .{ .size = 12, .color = if (selected) t.primary else t.muted });
    }
    ui.text(c, label, .{ .size = 12.5, .weight = if (selected) .semibold else .regular, .truncate = .ellipsis });
    ui.spacer(c);
    if (count) |n| ui.textf(c, .{ .size = 10.5, .mono = true, .color = t.muted }, "{d}", .{n});
    ui.access.describe(c, row.index, .{ .role = .tab, .label = label, .selected = selected });
    return it.clicked;
}

pub fn main(init: std.process.Init) !void {
    const app = try nanoui.App.create(init, .{ .name = "Gallery" });
    defer app.destroy();
    var state: Gallery = .{ .browser = try grid.init(init.arena.allocator()), .monitor = charts.init() };
    defer state.browser.search.deinit();
    _ = try app.newWindow(.{
        .title = "nanoui-controls",
        .width = 980,
        .height = 620,
        .content = .{ .view = .init(&state, Gallery.view) },
    });
    try app.run();
}
