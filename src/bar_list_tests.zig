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

test "a bar list's max rises to its largest item, unless fixed" {
    const T = struct {
        fixed: bool = false,
        fn view(x: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(400);
            defer root.end();
            _ = bar_list.barList(c, &.{
                .{ .label = "a", .value = 20, .color = blue },
                .{ .label = "b", .value = 10, .color = red },
            }, .{ .max = 10, .fixed_max = x.fixed });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 500, .height = 200 });
    defer t.deinit();
    t.settle(1);
    var b: [2]f32 = undefined;
    var r: [2]f32 = undefined;
    // Widths: the largest full, the other half.
    const wa = widths(&t, blue, &b);
    const wb = widths(&t, red, &r);
    try std.testing.expectApproxEqAbs(wa[0] / 2, wb[0], 1);
    x.fixed = true;
    t.settle(1);
    // Fixed at 10: both full.
    try std.testing.expectApproxEqAbs(widths(&t, blue, &b)[0], widths(&t, red, &r)[0], 1);
}

/// The widths of the boxes in `color`, in the order drawn.
fn widths(t: *ui.Tester, color: ui.Color, out: []f32) []f32 {
    var n: usize = 0;
    for (t.ctx.nodes.items) |node| if (node.style.background) |bg| if (std.meta.eql(bg, color)) {
        const rect = t.ctx.rects.get(node.id) orelse continue;
        if (n < out.len) out[n] = rect.w;
        n += 1;
    };
    return out[0..@min(n, out.len)];
}

test "a bar list's rows keyed by item keep the keyboard on their item as the list re-sorts" {
    const T = struct {
        swapped: bool = false,
        clicked: ?usize = null,
        fn view(x: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(400);
            defer root.end();
            const a: bar_list.Item = .{ .key = "a", .label = "Alpha", .value = 2 };
            const b: bar_list.Item = .{ .key = "b", .label = "Beta", .value = 1 };
            const items = if (x.swapped) [_]bar_list.Item{ b, a } else [_]bar_list.Item{ a, b };
            if (bar_list.barList(c, &items, .{ .clickable = true })) |i| x.clicked = i;
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 500, .height = 200 });
    defer t.deinit();
    t.settle(1);
    // The keyboard on Alpha, then the list re-sorts: Enter is still
    // Alpha's, now the second row.
    t.ctx.focusCycle(false);
    t.settle(1);
    x.swapped = true;
    t.settle(1);
    t.key(.enter);
    try std.testing.expectEqual(@as(?usize, 1), x.clicked);
}
