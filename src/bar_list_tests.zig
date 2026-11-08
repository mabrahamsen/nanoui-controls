//! The bar list's tests of richer rows: icons, badges, details, a scale
//! from a minimum, a ramp, and meters.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const chart = @import("chart.zig");
const shared = @import("chart_tests.zig");
const heights = shared.heights;
const red = shared.red;
const blue = shared.blue;
const bar_list = @import("bar_list.zig");

/// A list of levels: temperatures from 20 to 120.
const Levels = struct {
    style: bar_list.Style = .bar,
    const heat = [_]ui.Color{ .hex(0x22d3ee), .hex(0xfb7185) };
    const items = [_]bar_list.Item{
        .{ .label = "CPU", .value = 70, .value_text = "70 °C", .detail = "max 94", .badge = "P", .icon = "cpu" },
        .{ .label = "GPU", .value = 120, .value_text = "120 °C" },
    };

    fn view(x: *Levels, c: *ui.Context) void {
        const root = ui.div(c).column().w(400);
        defer root.end();
        _ = bar_list.barList(c, &items, .{ .min = 20, .max = 120, .ramp = &heat, .style = x.style, .segments = 10 });
    }
};

test "a bar list's rows lead with an icon or a badge, end with a detail, and their bars start at min in the ramp's color" {
    var x: Levels = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Levels.view), .{ .width = 500, .height = 200 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(t.hasText("P") and t.hasText("max 94"));
    // The second row has no icon, but its slot is kept: the labels' column
    // starts at the same place.
    try std.testing.expect(t.findText("GPU").?.x > 20);
    // CPU's bar is half full, in the ramp's middle color.
    const half = chart.rampColor(&Levels.heat, 0.5);
    var found = false;
    for (t.ctx.nodes.items) |node| if (node.style.background) |b| if (std.meta.eql(b, half)) {
        found = true;
    };
    try std.testing.expect(found);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqualStrings("70 °C, max 94", list.items[0].value);
}

test "a bar list as meters lights each row's segments to its level" {
    var x: Levels = .{ .style = .meter };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Levels.view), .{ .width = 500, .height = 200 });
    defer t.deinit();
    t.settle(1);
    // Two meters of ten segments: five lit, then ten.
    const track = chart.track(&t.ctx);
    var unlit: usize = 0;
    for (t.ctx.nodes.items) |node| if (node.style.background) |b| if (std.meta.eql(b, track) and node.style.height == .fill) {
        unlit += 1;
    };
    try std.testing.expectEqual(@as(usize, 5), unlit);
}
