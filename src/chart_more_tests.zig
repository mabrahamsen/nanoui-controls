//! The charts' tests of bars in units with a scale that rises, short
//! histories, axes and texts under a chart, richer bar lists, stats with
//! units, details, loading and clicks, fitted legends and swatches, and
//! meters rounded at their ends or in zones.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const chart = @import("chart.zig");
const bars = @import("bars.zig").bars;
const line = @import("line.zig").line;
const bar_list = @import("bar_list.zig");
const stat_mod = @import("stat.zig");
const legend_mod = @import("legend.zig");
const meter = @import("meter.zig").meter;

const red: ui.Color = .hex(0xef4444);
const blue: ui.Color = .hex(0x3b82f6);

/// The heights of the boxes in `color`, in the order drawn.
fn heights(t: *ui.Tester, color: ui.Color, out: []f32) []f32 {
    var n: usize = 0;
    for (t.ctx.nodes.items) |node| if (node.style.background) |b| if (std.meta.eql(b, color)) {
        const r = t.ctx.rects.get(node.id) orelse continue;
        if (n < out.len) out[n] = r.h;
        n += 1;
    };
    return out[0..@min(n, out.len)];
}

/// Bars of `values` in units, 100 points tall.
const Units = struct {
    values: []const f32 = &.{ 40, 20 },
    min: f32 = 0,
    max: f32 = 100,
    fixed: bool = true,
    readings: ?usize = null,
    count: usize = 2,
    interactive: bool = false,
    slots: [16]?usize = @splat(null),
    built: usize = 0,
    current: ?usize = null,

    fn view(x: *Units, c: *ui.Context) void {
        const root = ui.div(c).column().w(200).p(10);
        defer root.end();
        var b = bars(c, .{ .count = x.count, .height = .{ .px = 100 }, .min = x.min, .max = x.max, .fixed_max = x.fixed, .readings = x.readings, .interactive = x.interactive });
        x.current = b.current;
        x.built = 0;
        while (b.next()) |slot| {
            x.slots[x.built] = slot.reading;
            x.built += 1;
            const v = x.values[slot.reading orelse slot.index];
            slot.bar(&.{.{ .value = v, .color = if (v < 0) red else blue }});
        }
        b.end();
    }
};

fn startUnits(x: *Units, t: *ui.Tester) !void {
    try t.init(std.testing.allocator, .init(x, Units.view), .{ .width = 300, .height = 200 });
    t.settle(1);
}

test "bars in units take their share of the scale" {
    var x: Units = .{};
    var t: ui.Tester = undefined;
    try startUnits(&x, &t);
    defer t.deinit();
    var buf: [4]f32 = undefined;
    const h = heights(&t, blue, &buf);
    try std.testing.expectApproxEqAbs(@as(f32, 40), h[0], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 20), h[1], 0.5);
}

test "a scale that isn't fixed rises to the tallest bar, and a fixed one squeezes it" {
    var x: Units = .{ .values = &.{ 200, 50 }, .fixed = false };
    var t: ui.Tester = undefined;
    try startUnits(&x, &t);
    defer t.deinit();
    var buf: [4]f32 = undefined;
    var h = heights(&t, blue, &buf);
    try std.testing.expectApproxEqAbs(@as(f32, 100), h[0], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 25), h[1], 0.5);
    x.fixed = true;
    t.settle(1);
    h = heights(&t, blue, &buf);
    try std.testing.expectApproxEqAbs(@as(f32, 100), h[0], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 50), h[1], 0.5);
}

test "a scale from below zero has room for negative bars, and one from above zero starts the bars there" {
    var x: Units = .{ .values = &.{ 25, -25 }, .min = -50, .max = 50 };
    var t: ui.Tester = undefined;
    try startUnits(&x, &t);
    defer t.deinit();
    var buf: [4]f32 = undefined;
    try std.testing.expectApproxEqAbs(@as(f32, 25), heights(&t, blue, &buf)[0], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 25), heights(&t, red, &buf)[0], 0.5);
    // Zero is halfway: the negative bar starts where the positive ends.
    var top_red: f32 = 0;
    var bottom_blue: f32 = 0;
    for (t.ctx.nodes.items) |node| if (node.style.background) |b| {
        const r = t.ctx.rects.get(node.id) orelse continue;
        if (std.meta.eql(b, red)) top_red = r.y;
        if (std.meta.eql(b, blue)) bottom_blue = r.y + r.h;
    };
    try std.testing.expectApproxEqAbs(bottom_blue, top_red, 0.5);
    x.values = &.{ 70, 20 };
    x.min = 20;
    x.max = 120;
    t.settle(1);
    const h = heights(&t, blue, &buf);
    try std.testing.expectApproxEqAbs(@as(f32, 50), h[0], 0.5);
    try std.testing.expectEqual(@as(usize, 1), h.len);
}

test "a history shorter than the slots sits at the right, and only its slots can be pointed at" {
    var x: Units = .{ .values = &.{ 10, 20, 30 }, .count = 8, .readings = 3, .interactive = true };
    var t: ui.Tester = undefined;
    try startUnits(&x, &t);
    defer t.deinit();
    try std.testing.expectEqual(@as(usize, 3), x.built);
    try std.testing.expectEqual(@as(?usize, 0), x.slots[0]);
    try std.testing.expectEqual(@as(?usize, 2), x.slots[2]);
    // The bars sit in the last three of eight slots, 180 points wide.
    var first_x: f32 = 1000;
    for (t.ctx.nodes.items) |node| if (node.style.background) |b| if (std.meta.eql(b, blue)) {
        first_x = @min(first_x, t.ctx.rects.get(node.id).?.x);
    };
    try std.testing.expect(first_x > 10 + 180 * 5 / 8 - 2);
    // On the empty slots, nothing is current; on the last, its reading.
    t.moveTo(30, 60);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, null), x.current);
    t.moveTo(185, 60);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 2), x.current);
    // The keys stop at the first reading.
    t.moveTo(500, 500);
    t.ctx.focusCycle(false);
    t.settle(1);
    t.key(.home);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 0), x.current);
    t.key(.left);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 0), x.current);
}

/// A chart with an axis and texts under it: bars or a line.
const Framed = struct {
    axis: chart.Axis = .start,
    use_line: bool = false,
    close: bool = false,
    box: u32 = 0,

    fn view(x: *Framed, c: *ui.Context) void {
        const root = ui.div(c).column().w(300).p(10);
        defer root.end();
        const lines = [_]chart.ValueLine{ .{ .value = 100, .label = "100" }, .{ .value = 50, .label = "50" }, .{ .value = if (x.close) 52 else 0, .label = "near" } };
        if (x.use_line) {
            var l = line(c, &.{.{ .values = &.{ 20, 60, 80 } }}, .{ .capacity = 3, .max = 100, .fixed_max = true, .height = .{ .px = 100 }, .value_lines = &lines, .axis = x.axis, .start_text = "-60 s", .end_text = "now" });
            x.box = l.box.index;
            l.end();
            return;
        }
        var b = bars(c, .{ .count = 3, .max = 100, .fixed_max = true, .height = .{ .px = 100 }, .value_lines = &lines, .axis = x.axis, .start_text = "-60 s", .end_text = "now" });
        x.box = b.row.index;
        while (b.next()) |slot| slot.bar(&.{.{ .value = 40, .color = blue }});
        b.end();
    }
};

fn chartRect(t: *ui.Tester, x: *const Framed) ui.Rect {
    return t.ctx.rects.get(t.ctx.node(x.box).id).?;
}

test "an axis puts the value lines' labels beside the chart, level with them, and texts go under it" {
    var x: Framed = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Framed.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const r = chartRect(&t, &x);
    const fifty = t.findText("50").?;
    try std.testing.expect(fifty.x + fifty.w <= r.x + 0.5);
    try std.testing.expectApproxEqAbs(r.y + 50, fifty.y + fifty.h / 2, 2);
    try std.testing.expect(t.findText("-60 s").?.y >= r.y + r.h);
    try std.testing.expectApproxEqAbs(r.x, t.findText("-60 s").?.x, 0.5);
    try std.testing.expectApproxEqAbs(r.x + r.w, t.findText("now").?.x + t.findText("now").?.w, 1);
    // At the end, past the chart.
    x.axis = .end;
    t.settle(1);
    try std.testing.expect(t.findText("50").?.x >= chartRect(&t, &x).x + chartRect(&t, &x).w - 0.5);
}

test "an axis leaves out a label that would overlap the one above it" {
    var x: Framed = .{ .close = true };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Framed.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // The higher of the two keeps its label.
    try std.testing.expect(t.hasText("near"));
    try std.testing.expect(!t.hasText("50"));
    try std.testing.expect(t.hasText("100"));
}

test "a line chart takes an axis and texts under it, as bars do" {
    var x: Framed = .{ .use_line = true, .axis = .end };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Framed.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const r = chartRect(&t, &x);
    try std.testing.expect(t.findText("100").?.x >= r.x + r.w - 0.5);
    try std.testing.expect(t.findText("now").?.y >= r.y + r.h);
}

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

/// Stats: with a unit and a detail, loading, and one to click.
const Stats = struct {
    loading: bool = false,
    clicks: usize = 0,

    fn view(x: *Stats, c: *ui.Context) void {
        const root = ui.div(c).column().w(240).gap(8);
        defer root.end();
        stat_mod.stat(c, "Peak", "87", .{ .unit = "%", .detail = "over the last hour", .loading = x.loading });
        if (stat_mod.statButton(c, "Alerts", "3", .{}).clicked) x.clicks += 1;
    }
};

test "a stat shows its unit after its figure, a detail under it, and a spinner while loading" {
    var x: Stats = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Stats.view), .{ .width = 300, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const fig = t.findText("87").?;
    const unit = t.findText("%").?;
    try std.testing.expect(unit.x > fig.x + fig.w - 0.5 and unit.h < fig.h);
    try std.testing.expect(t.findText("over the last hour").?.y > fig.y);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqualStrings("87 %", list.items[0].value);
    x.loading = true;
    t.settle(1);
    try std.testing.expect(!t.hasText("87"));
    try std.testing.expect(t.hasText("Peak"));
    list = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqualStrings("loading", list.items[0].value);
}

test "a stat button is clicked by the pointer and the keys, and is a button to a screen reader" {
    var x: Stats = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Stats.view), .{ .width = 300, .height = 300 });
    defer t.deinit();
    t.settle(1);
    try t.clickText("Alerts");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.clicks);
    t.key(.enter);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 2), x.clicks);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(ui.access.Role.button, list.items[1].role);
}

/// A fitted legend beside a title, in a box `width` wide.
const Fitted = struct {
    width: f32 = 400,
    box: u32 = 0,

    fn view(x: *Fitted, c: *ui.Context) void {
        const root = ui.div(c).column().w(x.width);
        defer root.end();
        var l = legend_mod.legend(c, .{ .width = .fit });
        x.box = l.box.index;
        l.item(blue, "Read");
        l.item(red, "Write");
        l.item(blue, "Other things");
        l.end();
        legend_mod.swatch(c, red, .{ .shape = .dot });
        legend_mod.swatch(c, red, .{ .shape = .line });
    }
};

test "a fitted legend is as wide as its items, and still wraps where its parent ends" {
    var x: Fitted = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Fitted.view), .{ .width = 500, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const r = t.ctx.rects.get(t.ctx.node(x.box).id).?;
    try std.testing.expect(r.w < 300);
    try std.testing.expectApproxEqAbs(t.findText("Read").?.y, t.findText("Other things").?.y, 0.5);
    // As a resize would, the width changes and frames follow.
    x.width = 120;
    t.frame();
    t.settle(1);
    try std.testing.expect(t.findText("Other things").?.y > t.findText("Read").?.y);
}

test "a swatch on its own is a dot or a line, as a legend draws one" {
    var x: Fitted = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Fitted.view), .{ .width = 500, .height = 300 });
    defer t.deinit();
    t.settle(1);
    var reds: [4]f32 = undefined;
    const h = heights(&t, red, &reds);
    // The legend's square, then the dot as tall, then the line thinner.
    try std.testing.expectEqual(@as(usize, 3), h.len);
    try std.testing.expectEqual(h[0], h[1]);
    try std.testing.expect(h[2] < h[1]);
}

test "a meter without gaps rounds only its ends, and zones label runs of its segments" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(300).gap(10);
            defer root.end();
            meter(c, 1, .{ .gap = 0, .radius = 4, .segments = 6, .color = blue });
            meter(c, 0.5, .{ .segments = 10, .zones = &.{ "<20", "<40", "<60", "<80", "80+" }, .color = red });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 400, .height = 200 });
    defer t.deinit();
    t.settle(1);
    var rounded_rows: usize = 0;
    for (t.ctx.nodes.items) |node| {
        if (node.style.background) |b| if (std.meta.eql(b, blue)) try std.testing.expectEqual(@as(f32, 0), node.style.radius);
        if (node.style.clip and node.style.radius == 4) rounded_rows += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), rounded_rows);
    try std.testing.expect(t.hasText("<20") and t.hasText("80+"));
    // Each label sits under its run: "<20" left of "<40", centered on a
    // fifth of the width.
    try std.testing.expectApproxEqAbs(@as(f32, 30), t.findText("<20").?.x + t.findText("<20").?.w / 2, 3);
}

test "a donut and a gauge with no room don't ask for frame after frame" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(300);
            defer root.end();
            @import("donut.zig").donut(c, &.{.{ .value = 0.5, .color = blue }}, .{ .size = 0 });
            @import("gauge.zig").gauge(c, 0.5, .{ .size = 0 });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 400, .height = 200 });
    defer t.deinit();
    t.settle(1);
    t.frame();
    try std.testing.expectEqual(@as(?f32, null), t.ctx.frame_in);
}

/// A line of three readings in eight slots.
const Short = struct {
    current: ?usize = null,
    read: ?f32 = null,

    fn view(x: *Short, c: *ui.Context) void {
        const root = ui.div(c).column().w(200).p(10);
        defer root.end();
        var l = line(c, &.{.{ .values = &.{ 0.2, 0.5, 0.8 } }}, .{ .capacity = 8, .interactive = true });
        x.current = l.current;
        x.read = if (l.current) |i| l.reading(0, i) else null;
        l.end();
    }
};

test "an interactive line with a short history stops only on its readings, and says each" {
    var x: Short = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Short.view), .{ .width = 300, .height = 200 });
    defer t.deinit();
    t.settle(1);
    t.ctx.focusCycle(false);
    t.settle(1);
    t.key(.home);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 5), x.current);
    try std.testing.expectEqual(@as(?f32, 0.2), x.read);
    t.key(.left);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 5), x.current);
    t.key(.end);
    t.settle(1);
    try std.testing.expectEqual(@as(?f32, 0.8), x.read);
}

test "a box's measured size is kept by the box, not by where it is looked up" {
    const T = struct {
        extra: bool = false,
        fn view(x: *@This(), c: *ui.Context) void {
            const box = ui.div(c).column().w(120).h(40);
            defer box.end();
            // A child before the lookup, from some frame on, as a caller's
            // content changes.
            if (x.extra) ui.div(c).h(4).end();
            _ = chart.lastSize(c, box.index);
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 200 });
    defer t.deinit();
    t.settle(1);
    // The box's size hasn't changed: no frame is asked for.
    x.extra = true;
    t.frame();
    try std.testing.expectEqual(@as(?f32, null), t.ctx.frame_in);
}

test "bars on a fixed scale don't ask for a frame when their tallest bar changes" {
    var x: Units = .{};
    var t: ui.Tester = undefined;
    try startUnits(&x, &t);
    defer t.deinit();
    x.values = &.{ 90, 10 };
    t.frame();
    try std.testing.expectEqual(@as(?f32, null), t.ctx.frame_in);
}

test "a meter's zones keep its segments one width when they don't divide evenly, and no value says nothing" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(300);
            defer root.end();
            meter(c, 1, .{ .segments = 7, .gap = 2, .zone_gap = 2, .zones = &.{ "a", "b", "c" }, .color = blue });
            meter(c, std.math.nan(f32), .{ .label = "Load" });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 400, .height = 200 });
    defer t.deinit();
    t.settle(1);
    var lo: f32 = 1000;
    var hi: f32 = 0;
    for (t.ctx.nodes.items) |node| if (node.style.background) |b| if (std.meta.eql(b, blue)) {
        const w = t.ctx.rects.get(node.id).?.w;
        lo = @min(lo, w);
        hi = @max(hi, w);
    };
    try std.testing.expect(hi - lo < 1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    for (list.items) |e| if (std.mem.eql(u8, e.label, "Load")) try std.testing.expectEqualStrings("", e.value);
}
