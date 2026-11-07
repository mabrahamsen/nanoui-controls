//! The gallery: each of the library's controls in an app, picked from a
//! sidebar, itself the library's. "Grid" is a grid of ten thousand files
//! with a pager (grid.zig); under "Charts", "Monitor" is a system monitor
//! whose charts move with its readings, and "Every chart" each chart once,
//! as figures it doesn't change (charts.zig). The sidebar takes the
//! keyboard on a click or Tab: Up and Down move between its rows, and
//! Left and Right fold the Charts group.
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
    browser: grid.Browser,
    monitor: charts.Monitor,

    fn view(g: *Gallery, c: *ui.Context) void {
        const t = kit.tokens(c);
        const root = ui.div(c).row().sizeFull();
        defer root.end();
        {
            const side = ui.div(c).column().w(200).hFull().p(10).bg(t.surface);
            defer side.end();
            var sb = controls.sidebar(c, "gallery", g.shown, .{});
            sb.heading("Controls");
            sb.item("grid", "Grid", .{ .icon = "square.grid.3x3", .count = g.browser.shown_len });
            if (sb.group("charts", "Charts", &g.charts_open)) |group| {
                sb.item("monitor", "Monitor", .{ .icon = "waveform.path.ecg", .count = g.monitor.load.len });
                sb.item("every", "Every chart", .{ .icon = "chart.bar.xaxis" });
                group.end();
            }
            if (sb.end()) |key| g.shown = key;
        }
        ui.div(c).w(1).hFull().bg(t.border).end();
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
