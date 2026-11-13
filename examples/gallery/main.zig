//! The gallery: each of the library's controls in an app, picked from a
//! sidebar, itself the library's. "Grid" is a grid of ten thousand files
//! with a pager (grid.zig), and under it "Grouped" pull requests in
//! groups that fold, as cards or rows of two lines, loading
//! (groups.zig); "Form" a settings pane in a form, with
//! swatches (form.zig); "Sidebar" the sidebar's own options, which the
//! sidebar takes as they change (sidebar.zig); under "Charts", "Monitor" is a system monitor
//! whose charts move with its readings, its alerts (readings over 80%) in
//! a pill, and "Every chart" each chart once, as figures it doesn't change
//! (charts.zig), a branch with the charts of histories and of parts under
//! it; "Status" a backup service at a glance, in pills, readings,
//! callouts, panels and notices (status.zig); "Choices" a backup's
//! history filtered by a segmented group, a tab strip and chips, its
//! times of day typed as chips, and toasts raised by buttons
//! (choices.zig). "More to come" is a row
//! that can't be chosen yet. The counts load
//! for a moment at launch.
//!
//! Drag the splitter beside the sidebar to resize it, or click it and use
//! Left and Right: narrower than 120 points, the sidebar shows only its
//! icons, the labels in tooltips. The sidebar takes the keyboard on a
//! click or Tab: Up and Down move between its rows, and Left and Right
//! fold the Charts group and the Every chart branch. A right-click on a row opens a menu for it.
const std = @import("std");
const nanoui = @import("nanoui");
const controls = @import("nanoui_controls");
const ui = nanoui.ui;
const kit = nanoui.kit;
const grid = @import("grid.zig");
const charts = @import("charts.zig");
const form = @import("form.zig");
const sidebar = @import("sidebar.zig");
const groups = @import("groups.zig");
const status = @import("status.zig");
const choices = @import("choices.zig");

const Gallery = struct {
    /// The key of the view shown, as the sidebar chose it.
    shown: []const u8 = "grid",
    charts_open: bool = true,
    every_open: bool = false,
    grid_open: bool = true,
    /// The sidebar's width as the splitter set it; below `narrow` it shows
    /// only its icons, `icons_width` wide.
    side_width: f32 = 210,
    /// The row a right-click opened the menu for, and where.
    menu_open: bool = false,
    menu_key: []const u8 = "",
    menu_at: ?ui.Rect = null,
    browser: grid.Browser,
    monitor: charts.Monitor,
    settings: form.Settings,
    tuning: sidebar.Tuning = .{},
    pulls: groups.Pulls = .{},
    backups: status.Backups = .{},
    history: choices.History = .{},
    /// When the first frame was drawn: the counts load for a moment after.
    launched: ?f64 = null,

    const narrow = 120;
    const icons_width = 52;
    /// How long the counts load at launch, in seconds.
    const launch_wait = 1.5;

    fn view(g: *Gallery, c: *ui.Context) void {
        const t = kit.tokens(c);
        const root = ui.div(c).row().sizeFull();
        defer root.end();
        const opts = g.tuning.options(c, g.side_width < narrow);
        const icons_only = opts.icons_only;
        {
            const side = ui.div(c).column().w(if (icons_only) icons_width else g.side_width).hFull().p(if (icons_only) 6 else 10).bg(t.surface);
            defer side.end();
            // The counts load for a moment at launch, as an app's would
            // while it asks for them.
            const launched = g.launched orelse c.time;
            g.launched = launched;
            const loading = g.tuning.loading or c.time - launched < launch_wait;
            if (c.time - launched < launch_wait) c.frameIn(0.1);
            var sb = controls.sidebar(c, "gallery", g.shown, opts);
            sb.heading("Controls");
            if (sb.branch("grid", "Grid", .{ .icon = "square.grid.3x3", .count = g.browser.shown_len, .loading = loading }, if (g.tuning.fixed) null else &g.grid_open)) |grids| {
                sb.item("grouped", "Grouped", .{ .icon = "list.bullet" });
                grids.end();
            }
            sb.item("form", "Form", .{ .icon = "slider.horizontal.3" });
            sb.item("sidebar", "Sidebar", .{ .icon = "sidebar.left" });
            if (sb.group("charts", "Charts", &g.charts_open)) |group| {
                sb.item("monitor", "Monitor", .{ .icon = "waveform.path.ecg", .count = g.monitor.alerts(), .count_style = if (g.tuning.pill) .pill else .plain, .loading = loading });
                if (sb.branch("every", "Every chart", .{ .icon = "chart.bar.xaxis" }, if (g.tuning.fixed) null else &g.every_open)) |every| {
                    sb.item("histories", "Histories", .{ .icon = "list.bullet" });
                    sb.item("parts", "Parts", .{ .icon = "gauge.with.dots.needle.33percent" });
                    every.end();
                }
                group.end();
            }
            sb.item("status", "Status", .{ .icon = "checklist" });
            sb.item("choices", "Choices", .{ .icon = "slider.horizontal.3" });
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
            charts.catalog(c, .all);
        } else if (std.mem.eql(u8, g.shown, "histories")) {
            charts.catalog(c, .histories);
        } else if (std.mem.eql(u8, g.shown, "parts")) {
            charts.catalog(c, .parts);
        } else if (std.mem.eql(u8, g.shown, "form")) {
            g.settings.view(c);
        } else if (std.mem.eql(u8, g.shown, "grouped")) {
            g.pulls.view(c);
        } else if (std.mem.eql(u8, g.shown, "choices")) {
            g.history.view(c);
        } else if (std.mem.eql(u8, g.shown, "status")) {
            g.backups.view(c);
        } else if (std.mem.eql(u8, g.shown, "sidebar")) {
            g.tuning.view(c);
        } else g.browser.view(c);
    }
};

pub fn main(init: std.process.Init) !void {
    const app = try nanoui.App.create(init, .{ .name = "Gallery" });
    defer app.destroy();
    // The controls' ring only while the keyboard is in use, as on a Mac.
    controls.setFocusRingShows(.keyboard);
    var state: Gallery = .{ .browser = try grid.init(init.arena.allocator()), .monitor = charts.init(), .settings = form.init() };
    defer state.browser.search.deinit();
    defer state.settings.name.deinit();
    defer state.history.field.deinit();
    _ = try app.newWindow(.{
        .title = "nanoui-controls",
        .width = 980,
        .height = 620,
        .content = .{ .view = .init(&state, Gallery.view) },
    });
    try app.run();
}
