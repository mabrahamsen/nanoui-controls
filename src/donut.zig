//! A donut: a ring split into colored parts, clockwise from the top, with
//! a figure in its middle. Disk use by kind, time by project, a share of
//! a budget. Its parts ease to new values, as a breakdown's do. Drawn with
//! `ui.canvas`.
//!
//!     controls.donut(c, &.{ .{ .value = apps, .color = t.primary }, .{ .value = docs, .color = t.success } }, .{
//!         .text = "71%",
//!         .caption = "used",
//!         .label = "Disk",
//!         .value_text = "71% used",
//!     });
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const chart = @import("chart.zig");

pub const Options = struct {
    /// Across, in points.
    size: f32 = 96,
    /// The ring's thickness.
    thickness: f32 = 12,
    /// Between the parts, at the ring's middle.
    gap: f32 = 2,
    /// Where no part is; null takes the track of the kit's progress bar.
    track: ?ui.Color = null,
    /// The parts are the whole ring, each its share of their sum, as a
    /// breakdown's; otherwise each is `value` of the ring (0 to 1).
    whole: bool = false,
    /// A figure in the middle ("71%"), and a word under it ("used").
    text: []const u8 = "",
    caption: []const u8 = "",
    /// What a screen reader calls the donut, and says it shows; without a
    /// label, it is left out, as a decoration.
    label: []const u8 = "",
    value_text: []const u8 = "",
    /// Multiplies its lengths, but not its text, as the charts'.
    scale: f32 = 1,
};

/// Draws the donut of `parts`. A part that is negative or not a number
/// counts as nothing; parts that add up to more than the ring are
/// squeezed to fit.
pub fn donut(c: *ui.Context, parts: []const chart.Part, opts: Options) void {
    const t = kit.tokens(c);
    const k = opts.scale;
    const size = opts.size * k;
    const box = ui.div(c).w(size).h(size).column().center();
    defer box.end();
    chart.describe(c, box.index, opts.label, opts.value_text, false, "");
    const cv = ui.canvas(c, .{ .absolute = true, .width = .fill, .height = .fill });
    // In its first frame it has no size: the canvas asks for the frame
    // that gives it one.
    const r_out = @min(cv.size.w, cv.size.h) / 2;
    const thick = @min(opts.thickness * k, r_out);
    if (r_out > 0) {
        const center: ui.Point = .{ .x = cv.size.w / 2, .y = cv.size.h / 2 };
        const r_in = r_out - thick;
        var eased: [chart.max_eased]f32 = undefined;
        const sum = chart.easeParts(c, parts, &eased);
        const whole = if (opts.whole) sum else @max(sum, 1);
        const gap = opts.gap * k / (r_out - thick / 2);
        var from: f32 = 0;
        var drawn: usize = 0;
        if (whole > 0) for (parts, 0..) |p, i| {
            const sweep = chart.eased(parts, &eased, i) / whole * std.math.tau;
            defer from += sweep;
            if (sweep <= gap) continue;
            drawn += 1;
            chart.arc(c, cv, center, r_out, r_in, from + gap / 2, from + sweep - gap / 2, p.color);
        };
        // The track, where no part is.
        const track = opts.track orelse chart.track(c);
        if (drawn == 0) {
            chart.arc(c, cv, center, r_out, r_in, 0, std.math.tau, track);
        } else if (std.math.tau - from > gap) {
            chart.arc(c, cv, center, r_out, r_in, from + gap / 2, std.math.tau - gap / 2, track);
        }
    }
    if (opts.text.len > 0) ui.text(c, opts.text, .{ .size = @round(opts.size * 0.2), .weight = .semibold, .color = t.foreground });
    if (opts.caption.len > 0) ui.text(c, opts.caption, .{ .size = @round(opts.size * 0.11), .color = t.muted });
}

const cyan: ui.Color = .hex(0x22d3ee);
const violet: ui.Color = .hex(0xa78bfa);

/// How many colors the donut's canvas drew in: the track's, and each
/// part's.
fn colors(parts: []const chart.Part, opts: Options) !usize {
    const T = struct {
        var ps: []const chart.Part = &.{};
        var o: Options = .{};
        fn view(_: *@This(), c: *ui.Context) void {
            donut(c, ps, o);
        }
    };
    T.ps = parts;
    T.o = opts;
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 200, .height = 200 });
    defer t.deinit();
    t.settle(1);
    var seen: [8][4]f32 = undefined;
    var n: usize = 0;
    for (t.ctx.nodes.items) |node| switch (node.content) {
        .canvas => |cv| for (cv.shapes.items) |shape| {
            for (seen[0..n]) |col| {
                if (std.meta.eql(col, shape.color)) break;
            } else {
                seen[n] = shape.color;
                n += 1;
            }
        },
        else => {},
    };
    return n;
}

test "a donut draws its track, and a part for each share" {
    try std.testing.expectEqual(@as(usize, 1), try colors(&.{}, .{}));
    try std.testing.expectEqual(@as(usize, 2), try colors(&.{.{ .value = 0.5, .color = cyan }}, .{}));
    try std.testing.expectEqual(@as(usize, 3), try colors(&.{ .{ .value = 0.5, .color = cyan }, .{ .value = 0.25, .color = violet } }, .{}));
    // A whole ring of parts leaves no track, whatever they add up to.
    try std.testing.expectEqual(@as(usize, 2), try colors(&.{ .{ .value = 0.3, .color = cyan }, .{ .value = 0.1, .color = violet } }, .{ .whole = true }));
}

test "a donut leaves out parts that are nothing, negative or not a number" {
    const one = try colors(&.{.{ .value = 0.5, .color = cyan }}, .{});
    const bad = try colors(&.{ .{ .value = 0.5, .color = cyan }, .{ .value = -1, .color = violet }, .{ .value = std.math.nan(f32), .color = violet }, .{ .value = 0, .color = violet } }, .{});
    try std.testing.expectEqual(one, bad);
}

test "a donut says its figure, and is one image to a screen reader" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            donut(c, &.{.{ .value = 0.71, .color = cyan }}, .{ .text = "71%", .caption = "used", .label = "Disk", .value_text = "71% used" });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 200, .height = 200 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(t.hasText("71%") and t.hasText("used"));
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqual(ui.access.Role.image, list.items[0].role);
    try std.testing.expectEqualStrings("71% used", list.items[0].value);
}

test "a donut without a label is left out of what a screen reader hears" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            donut(c, &.{.{ .value = 0.71, .color = cyan }}, .{ .text = "71%", .caption = "used" });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 200, .height = 200 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(@as(usize, 0), list.items.len);
}
