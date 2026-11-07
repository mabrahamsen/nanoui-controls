//! The gallery: each of the library's controls in an app, picked from a
//! sidebar, itself the library's. "Grid" is a grid of ten thousand files
//! with a pager (grid.zig); under "Charts", "Monitor" is a system monitor
//! whose charts move with its readings, its alerts (readings over 80%) in
//! a pill, and "Every chart" each chart once, as figures it doesn't change
//! (charts.zig). "More to come" is a row that can't be chosen yet.
//!
//! Drag the splitter beside the sidebar to resize it, or click it and use
//! Left and Right: narrower than 120 points, the sidebar shows only its
//! icons, the labels in tooltips. The sidebar takes the keyboard on a
//! click or Tab: Up and Down move between its rows, and Left and Right
//! fold the Charts group. A right-click on a row opens a menu for it.
const std = @import("std");
const nanoui = @import("nanoui");
const controls = @import("nanoui_controls");
const ui = nanoui.ui;
const kit = nanoui.kit;
const grid = @import("grid.zig");
const charts = @import("charts.zig");

const Gallery = struct {
    /// The key of the view shown, as the sidebar chose it.
    shown: []const u8 = "grid",
    charts_open: bool = true,
    /// The sidebar's width as the splitter set it; below `narrow` it shows
    /// only its icons, `icons_width` wide.
    side_width: f32 = 210,
    /// The row a right-click opened the menu for, and where.
    menu_open: bool = false,
    menu_key: []const u8 = "",
    menu_at: ?ui.Rect = null,
    browser: grid.Browser,
    monitor: charts.Monitor,

    const narrow = 120;
    const icons_width = 52;

    fn view(g: *Gallery, c: *ui.Context) void {
        const t = kit.tokens(c);
        const root = ui.div(c).row().sizeFull();
        defer root.end();
        const icons_only = g.side_width < narrow;
        {
            const side = ui.div(c).column().w(if (icons_only) icons_width else g.side_width).hFull().p(if (icons_only) 6 else 10).bg(t.surface);
            defer side.end();
            var sb = controls.sidebar(c, "gallery", g.shown, .{ .icons_only = icons_only });
            sb.heading("Controls");
            sb.item("grid", "Grid", .{ .icon = "square.grid.3x3", .count = g.browser.shown_len });
            if (sb.group("charts", "Charts", &g.charts_open)) |group| {
                sb.item("monitor", "Monitor", .{ .icon = "waveform.path.ecg", .count = g.monitor.alerts(), .count_style = .pill });
                sb.item("every", "Every chart", .{ .icon = "chart.bar.xaxis" });
                group.end();
            }
            sb.item("more", "More to come", .{ .icon = "sparkles", .disabled = true });
            if (sb.end()) |key| g.shown = key;
            if (sb.secondary_clicked) |key| {
                g.menu_key = key;
                g.menu_open = true;
                g.menu_at = .{ .x = c.input.mouse.x, .y = c.input.mouse.y, .w = 1, .h = 1 };
            }
        }
        // Narrowed to icons, the splitter still takes the width the drag
        // gives, so dragging back out widens it again.
        _ = controls.splitter(c, &g.side_width, .{ .min = 60, .max = 360, .label = "Sidebar width" });
        if (kit.menu(c, "sidebar-menu", &g.menu_open, g.menu_at, &.{
            .{ .label = "Show", .icon = "arrow.right" },
            .{ .separator = true },
            .{ .label = if (g.charts_open) "Fold Charts" else "Open Charts" },
        }, .{})) |choice| switch (choice) {
            0 => g.shown = g.menu_key,
            2 => g.charts_open = !g.charts_open,
            else => {},
        };
        const pane = ui.div(c).column().wFull().hFull();
        defer pane.end();
        if (std.mem.eql(u8, g.shown, "monitor")) {
            g.monitor.view(c);
        } else if (std.mem.eql(u8, g.shown, "every")) {
            charts.catalog(c);
        } else g.browser.view(c);
    }
};

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
