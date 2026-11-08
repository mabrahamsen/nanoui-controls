//! A gauge: a ring of ticks from the bottom left round to the bottom
//! right, lit up to a value, each lit tick in the ramp's color for its
//! place, with a figure in its middle and a caption under it, as the
//! donut has. A score, a level, a strength, read at a glance. Its ticks
//! keep to its size, and it eases to a new value as the donut does. Drawn
//! with `ui.canvas`.
//!
//!     controls.gauge(c, 0.62, .{ .ramp = &.{ red, amber, green }, .text = "B", .caption = "62 bits", .label = "Strength" });
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const chart = @import("chart.zig");

pub const Options = struct {
    /// Across, in points before `scale`.
    diameter: f32 = 116,
    /// How many ticks, from the first to the last.
    ticks: usize = 40,
    /// The ticks' length, in points before `scale`; null takes about a
    /// tenth of the diameter.
    thickness: ?f32 = null,
    /// Colors from the first tick to the last, blended between, as a
    /// trend's ramp; empty takes `color`.
    ramp: []const ui.Color = &.{},
    /// Every lit tick's color, without a ramp; null takes the theme's
    /// accent.
    color: ?ui.Color = null,
    /// Unlit ticks; null takes the track of the kit's progress bar.
    track: ?ui.Color = null,
    /// The opacity of a glow behind each lit tick, in its color; 0 draws
    /// none.
    glow: f32 = 0.16,
    /// A thin circle inside the ticks, in the theme's border color.
    inner_line: bool = true,
    /// A figure in the middle ("B"), in the value's color on the ramp, and
    /// a word under it ("62 bits").
    text: []const u8 = "",
    caption: []const u8 = "",
    /// What a screen reader calls the gauge, and says it shows; empty says
    /// the value as a percentage. Without a label, it is left out, as a
    /// decoration.
    label: []const u8 = "",
    value_text: []const u8 = "",
    /// Multiplies its lengths, but not its text, as the charts'.
    scale: f32 = 1,
};

/// Draws the gauge at `value`, 0 to 1. A value that is not a number
/// lights no ticks.
pub fn gauge(c: *ui.Context, value: f32, opts: Options) void {
    const t = kit.tokens(c);
    const k = opts.scale;
    const known = !std.math.isNan(value);
    const v = if (known) std.math.clamp(value, 0, 1) else 0;
    const size = opts.diameter * k;
    const box = ui.div(c).w(size).h(size).column().center();
    defer box.end();
    const said = if (opts.value_text.len > 0 or opts.label.len == 0 or !known) opts.value_text else c.print("{d}%", .{@round(v * 100)});
    chart.describe(c, box.index, opts.label, said, false, "");
    // Not a number, it goes dark at once.
    const eased = ui.motion.number(c, "gauge", v, .{ .tween = .{ .duration = 0.35 } });
    const shown = if (known) eased else 0;
    const cv = ui.canvas(c, .{ .absolute = true, .width = .fill, .height = .fill });
    // In its first frame it has no size: the canvas asks for the frame
    // that gives it one.
    // In proportion to the size: at 116 points, ticks 11 long and 2.5 wide
    // with a glow 7 wide, its round end touching the edge.
    const unit = @min(cv.size.w, cv.size.h) / 116;
    const outer = 58 * unit - 3.5 * unit;
    const inner = @max(0, outer - (if (opts.thickness) |th| th * k else 11 * unit));
    const mid: ui.Point = .{ .x = cv.size.w / 2, .y = cv.size.h / 2 };
    const n = @max(opts.ticks, 2);
    const last: f32 = @floatFromInt(n - 1);
    if (unit > 0) for (0..n) |i| {
        const at = @as(f32, @floatFromInt(i)) / last;
        // From 135° (the bottom left) round 270° to the bottom right.
        const a = (135 + 270 * at) * std.math.pi / 180;
        const dir: ui.Point = .{ .x = @cos(a), .y = @sin(a) };
        const p0: ui.Point = .{ .x = mid.x + dir.x * inner, .y = mid.y + dir.y * inner };
        const p1: ui.Point = .{ .x = mid.x + dir.x * outer, .y = mid.y + dir.y * outer };
        if (shown > 0 and at <= shown + 0.0001) {
            const col = colorAt(opts, t, at);
            if (opts.glow > 0) cv.line(p0, p1, .{ .width = 7 * unit, .color = col.alpha(opts.glow) });
            cv.line(p0, p1, .{ .width = 2.5 * unit, .color = col });
        } else cv.line(p0, p1, .{ .width = 2.5 * unit, .color = opts.track orelse chart.track(c) });
    };
    if (opts.inner_line and inner > 8 * unit) {
        const r = inner - 7 * unit;
        chart.arc(c, cv, mid, r + 0.5 * k, r - 0.5 * k, 0, std.math.tau, t.border);
    }
    if (opts.text.len > 0) ui.text(c, opts.text, .{ .size = @round(opts.diameter * 0.2), .weight = .semibold, .color = colorAt(opts, t, v) });
    if (opts.caption.len > 0) ui.text(c, opts.caption, .{ .size = @round(opts.diameter * 0.09), .color = t.muted });
}

/// A lit tick's color at `at`, 0 to 1.
fn colorAt(opts: Options, t: kit.Tokens, at: f32) ui.Color {
    return if (opts.ramp.len > 0) chart.rampColor(opts.ramp, at) else opts.color orelse t.primary;
}

const red: ui.Color = .hex(0xef4444);

const Dial = struct {
    value: f32 = 0.5,
    opts: Options = .{ .color = red, .glow = 0, .inner_line = false },
    fn view(d: *Dial, c: *ui.Context) void {
        gauge(c, d.value, d.opts);
    }
    /// The ticks drawn in the lit color, of all drawn.
    fn lit(t: *ui.Tester) struct { usize, usize } {
        var n: usize = 0;
        var all: usize = 0;
        const want = [4]f32{ red.r, red.g, red.b, red.a };
        for (t.ctx.nodes.items) |node| switch (node.content) {
            .canvas => |cv| for (cv.shapes.items) |shape| {
                all += 1;
                if (std.meta.eql(want, shape.color)) n += 1;
            },
            else => {},
        };
        return .{ n, all };
    }
};

fn startDial(d: *Dial, t: *ui.Tester) !void {
    try t.init(std.testing.allocator, .init(d, Dial.view), .{ .width = 200, .height = 200 });
    t.settle(2);
}

test "a gauge lights its ticks up to its value" {
    var d: Dial = .{};
    var t: ui.Tester = undefined;
    try startDial(&d, &t);
    defer t.deinit();
    // Ticks 0 to 19 of 40 are at or under a half.
    try std.testing.expectEqual(@as(usize, 20), Dial.lit(&t)[0]);
    try std.testing.expectEqual(@as(usize, 40), Dial.lit(&t)[1]);
    d.value = 1;
    t.settle(2);
    try std.testing.expectEqual(@as(usize, 40), Dial.lit(&t)[0]);
    // Not a number: dark at once.
    d.value = std.math.nan(f32);
    t.frame();
    try std.testing.expectEqual(@as(usize, 0), Dial.lit(&t)[0]);
}

test "a gauge eases to a new value, and moves at once with reduced motion" {
    var d: Dial = .{ .value = 0 };
    var t: ui.Tester = undefined;
    try startDial(&d, &t);
    defer t.deinit();
    d.value = 1;
    t.frame();
    t.frame();
    const moving = Dial.lit(&t)[0];
    try std.testing.expect(moving > 0 and moving < 40);
    t.settle(2);
    try std.testing.expectEqual(@as(usize, 40), Dial.lit(&t)[0]);
    t.ctx.reduce_motion = true;
    d.value = 0;
    t.frame();
    try std.testing.expectEqual(@as(usize, 0), Dial.lit(&t)[0]);
}

test "a gauge draws nothing outside its box" {
    var d: Dial = .{ .value = 1, .opts = .{ .diameter = 40, .color = red, .inner_line = false } };
    var t: ui.Tester = undefined;
    try startDial(&d, &t);
    defer t.deinit();
    for (t.ctx.nodes.items) |node| switch (node.content) {
        // A line's ends, and its width round them.
        .canvas => |cv| for (cv.shapes.items) |shape| {
            const half = shape.border_width / 2;
            for ([_]f32{ shape.uv[0], shape.uv[2] }) |x| try std.testing.expect(x - half >= 0 and x + half <= 40);
            for ([_]f32{ shape.uv[1], shape.uv[3] }) |y| try std.testing.expect(y - half >= 0 and y + half <= 40);
        },
        else => {},
    };
}

test "a screen reader hears a gauge's label and value, and nothing without a label" {
    var d: Dial = .{ .value = 0.62, .opts = .{ .label = "Strength" } };
    var t: ui.Tester = undefined;
    try startDial(&d, &t);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings("Strength", list.items[0].label);
    try std.testing.expectEqualStrings("62%", list.items[0].value);
    d.opts = .{ .label = "Strength", .value_text = "Good", .text = "B" };
    t.settle(1);
    list.clearRetainingCapacity();
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqualStrings("Good", list.items[0].value);
    // Not a number, it says no value.
    d.value = std.math.nan(f32);
    d.opts = .{ .label = "Strength" };
    t.settle(1);
    list.clearRetainingCapacity();
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqualStrings("", list.items[0].value);
    d.opts = .{ .text = "B" };
    t.settle(1);
    list.clearRetainingCapacity();
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(@as(usize, 0), list.items.len);
}
