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

/// Rows drawn plain: a list of levels as a monitor draws them, its labels
/// left out or not.
const Plain = struct {
    opts: bar_list.Options = .{ .padded = false, .show_labels = false, .label_width = 34, .text_size = 13, .min = 20, .max = 110, .fixed_max = true },
    items: []const bar_list.Item = &.{
        .{ .label = "CPU temperature", .value = 65, .value_text = "65 °C", .badge = "CPU", .value_weight = .semibold, .value_color = .hex(0xfb7185) },
        .{ .label = "Fan", .value = 40, .value_text = "1200 rpm", .icon = "gauge.with.dots.needle.33percent", .icon_color = .hex(0x22d3ee) },
    },

    fn view(x: *Plain, c: *ui.Context) void {
        const root = ui.div(c).column().w(400);
        defer root.end();
        _ = bar_list.barList(c, x.items, x.opts);
    }
};

fn startPlain(x: *Plain, t: *ui.Tester) !void {
    try t.init(std.testing.allocator, .init(x, Plain.view), .{ .width = 500, .height = 200 });
    t.settle(1);
}

/// The style of the first text that reads `s`.
fn styleOf(t: *ui.Tester, s: []const u8) ?ui.TextStyle {
    for (t.ctx.nodes.items) |n| switch (n.content) {
        .text => |tx| if (std.mem.eql(u8, tx.str, s)) return tx.style,
        else => {},
    };
    return null;
}

test "a bar list without labels shows its badges in their column, and its labels still name the rows" {
    var x: Plain = .{};
    var t: ui.Tester = undefined;
    try startPlain(&x, &t);
    defer t.deinit();
    try std.testing.expect(!t.hasText("CPU temperature") and t.hasText("CPU"));
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    // One element a row: the badge isn't heard on its own.
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqualStrings("CPU temperature", list.items[0].label);
    try std.testing.expectEqualStrings("Fan", list.items[1].label);
}

test "unpadded, a bar list's rows run to its edges, at the caller's text size, figures in their weight and icons in their color" {
    var x: Plain = .{};
    var t: ui.Tester = undefined;
    try startPlain(&x, &t);
    defer t.deinit();
    const fan = t.findText("1200 rpm").?;
    try std.testing.expectApproxEqAbs(@as(f32, 400), fan.x + fan.w, 0.5);
    // Figures a point under the text, the first semibold.
    const hot = styleOf(&t, "65 °C").?;
    try std.testing.expectEqual(@as(f32, 12), hot.size);
    try std.testing.expectEqual(ui.Weight.semibold, hot.weight);
    try std.testing.expectEqual(ui.Weight.regular, styleOf(&t, "1200 rpm").?.weight);
    var cyan = false;
    for (t.ctx.nodes.items) |n| switch (n.content) {
        .icon => |ic| cyan = cyan or std.meta.eql(ic.color, ui.Color.hex(0x22d3ee)),
        else => {},
    };
    try std.testing.expect(cyan);
    // The padded rows start their content further in.
    const plain_x = t.findText("CPU").?.x;
    x.opts.padded = true;
    t.settle(1);
    try std.testing.expect(t.findText("CPU").?.x > plain_x);
}

test "a label width of 0 leaves the label column and its gap out" {
    var x: Plain = .{ .items = &.{.{ .label = "Neural Engine", .value = 50, .value_text = "50%" }} };
    x.opts.label_width = 0;
    var t: ui.Tester = undefined;
    try startPlain(&x, &t);
    defer t.deinit();
    // Its bar starts at the list's start.
    var track: ?ui.Rect = null;
    for (t.ctx.nodes.items) |n| if (n.style.background != null) if (t.ctx.rects.get(n.id)) |r| if (r.h <= 6.5 and track == null) {
        track = r;
    };
    try std.testing.expectApproxEqAbs(@as(f32, 0), track.?.x, 0.5);
}

test "a bar's level rounds its ends without a glow, as its track does" {
    var x: Plain = .{};
    var t: ui.Tester = undefined;
    try startPlain(&x, &t);
    defer t.deinit();
    var rounded: usize = 0;
    for (t.ctx.nodes.items) |n| if (n.style.background != null and n.style.height == .fill and n.style.radius > 0) {
        rounded += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), rounded);
}
