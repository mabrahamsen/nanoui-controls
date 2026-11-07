//! A split: a bar across, split into colored parts from the left. A total
//! by kind, as memory in use, with what is left empty; a whole split by
//! source, as traffic by app (`whole`); or one part as a level against a
//! maximum, as a fan's speed.
//!
//!     controls.split(c, &.{ .{ .value = app, .color = cyan }, .{ .value = wired, .color = violet } }, .{ .label = "Memory", .value = "15 of 24 GB" });
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const bars_mod = @import("bars.zig");

pub const Options = struct {
    /// The parent's width by default; in a row, the room the rest leaves.
    width: ui.Length = .fill,
    height: f32 = 6,
    /// The bar's corner radius; null rounds its ends.
    radius: ?f32 = null,
    /// Between the parts; null keeps a hairline of one point at any scale,
    /// and 0 none.
    gap: ?f32 = null,
    /// Where no part is; null takes the track of the kit's progress bar.
    track: ?ui.Color = null,
    /// The parts are the whole: each takes its share of their sum, and
    /// none of the bar is left. Otherwise each is `value` of the bar (0 to
    /// 1), and what they leave stays empty.
    whole: bool = false,
    /// Each part's corner radius, for a level's rounded end.
    part_radius: f32 = 0,
    /// The opacity of a glow around each part, in its color; 0 draws none.
    /// A glowing bar doesn't clip its parts, so the glow shows around it:
    /// give the parts a `part_radius` to keep their ends round.
    glow: f32 = 0,
    /// What a screen reader calls the bar ("Memory") and says it shows
    /// ("15 of 24 GB"); empty leaves it out, as a decoration.
    label: []const u8 = "",
    value: []const u8 = "",
    /// Multiplies the bar's lengths, as `bars`.
    scale: f32 = 1,
};

/// Draws the bar of `parts`. A part that is negative or not a number
/// counts as 0; parts that add up to more than the bar are squeezed to
/// fit, each keeping its share.
pub fn split(c: *ui.Context, parts: []const bars_mod.Part, opts: Options) void {
    const k = opts.scale;
    const h = opts.height * k;
    var r = ui.div(c).row().h(h).rounded(if (opts.radius) |rad| rad * k else h / 2).bg(opts.track orelse track(c));
    c.node(r.index).style.width = bars_mod.scaled(opts.width, k);
    if (opts.glow == 0) r = r.clip();
    // Without gaps, the parts overlap by a point, as a meter's segments.
    r = r.gap(if (opts.gap) |g| (if (g > 0) g * k else -1) else 1);
    if (opts.label.len > 0) ui.access.describe(c, r.index, .{ .role = .image, .label = opts.label, .value = opts.value });
    defer r.end();
    var used: f32 = 0;
    for (parts) |p| {
        const v = bars_mod.partShare(p.value);
        used += v;
        var d = ui.div(c).hFull();
        if (opts.part_radius > 0) d = d.rounded(opts.part_radius * k);
        d = d.bg(p.color);
        if (opts.glow > 0) d = d.shadow(.{ .color = p.color.alpha(opts.glow), .blur = 6 * k, .y = 0 });
        bars_mod.weighted(d, v).end();
    }
    if (!opts.whole) bars_mod.weighted(ui.div(c).hFull(), 1 - @min(1, used)).end();
}

/// The track of the kit's progress bar, for where no part is.
pub fn track(c: *ui.Context) ui.Color {
    const t = kit.tokens(c);
    return t.surface_hover.mix(t.border, 0.5);
}

const Color = ui.Color;
const cyan: Color = .hex(0x22d3ee);
const violet: Color = .hex(0xa78bfa);

/// Where each part of a split 200 points wide starts and how wide it is.
fn widths(parts: []const bars_mod.Part, opts: Options) ![3]f32 {
    const T = struct {
        var ps: []const bars_mod.Part = &.{};
        var o: Options = .{};
        fn view(_: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(200);
            defer root.end();
            split(c, ps, o);
        }
    };
    T.ps = parts;
    T.o = opts;
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 40 });
    defer t.deinit();
    t.settle(1);
    var out: [3]f32 = @splat(0);
    var n: usize = 0;
    // The first box is the window's.
    for (t.ctx.nodes.items[1..]) |node| {
        if (node.style.background == null or node.style.height != .fill) continue;
        if (n < out.len) out[n] = t.ctx.rects.get(node.id).?.w;
        n += 1;
    }
    return out;
}

test "a split's parts take their share of the bar, and leave the rest" {
    // Two parts and a hairline between each: 198 points to share.
    const w = try widths(&.{ .{ .value = 0.5, .color = cyan }, .{ .value = 0.25, .color = violet } }, .{});
    try std.testing.expectApproxEqAbs(@as(f32, 99), w[0], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 49.5), w[1], 0.5);
}

test "a whole split shares the bar by the parts' sum" {
    // Without a gap, the parts overlap by a point.
    const w = try widths(&.{ .{ .value = 3, .color = cyan }, .{ .value = 1, .color = violet } }, .{ .whole = true, .gap = 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 150.75), w[0], 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 50.25), w[1], 0.01);
}

test "a split counts bad parts as nothing, and squeezes parts over the bar" {
    const nan = std.math.nan(f32);
    const bad = try widths(&.{ .{ .value = nan, .color = cyan }, .{ .value = -1, .color = violet }, .{ .value = 0.5, .color = cyan } }, .{ .gap = 2 });
    try std.testing.expectEqualSlices(f32, &.{ 0, 0, 97 }, &bad);
    const over = try widths(&.{ .{ .value = 0.9, .color = cyan }, .{ .value = 0.9, .color = violet } }, .{ .gap = 2 });
    try std.testing.expectApproxEqAbs(@as(f32, 98), over[0], 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 98), over[1], 0.01);
}

test "a split with a label is one image to a screen reader, with its value" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            split(c, &.{.{ .value = 0.6, .color = cyan }}, .{ .label = "Memory", .value = "15 of 24 GB" });
            split(c, &.{.{ .value = 0.6, .color = cyan }}, .{});
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 60 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqual(ui.access.Role.image, list.items[0].role);
    try std.testing.expectEqualStrings("Memory", list.items[0].label);
    try std.testing.expectEqualStrings("15 of 24 GB", list.items[0].value);
}
