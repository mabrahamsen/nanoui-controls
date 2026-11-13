//! An icon tile: an SF Symbol in a rounded square tinted in its color, for
//! a device, an app or a kind of thing, and the lead of a `header`. Unlit,
//! it is the theme's surface with a muted icon, for something off.
//!
//!     controls.iconTile(c, "lightbulb", .{ .color = yellow, .lit = on, .label = "Light, on" });
//!
//! `iconTileOpen` leaves the tile open for an icon of the app's own, drawn
//! at the size and in the color it says.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const parts = @import("parts.zig");

pub const Options = struct {
    /// The tint, its border and the icon's color, as the kit's statuses;
    /// neutral takes the theme's accent.
    status: kit.Status = .neutral,
    /// The color, over the status's.
    color: ?ui.Color = null,
    /// Off, the tile is the theme's surface and border, its icon muted or
    /// `icon_color`.
    lit: bool = true,
    /// An unlit tile's icon color; null takes the theme's muted text.
    icon_color: ?ui.Color = null,
    /// Its side, in points before `scale`.
    size: f32 = 32,
    /// Its corners' radius; null takes 28% of its side.
    radius: ?f32 = null,
    /// The icon's size; null takes 45% of its side.
    icon_size: ?f32 = null,
    /// The tint's and the border's opacity.
    fill: f32 = 0.12,
    edge: f32 = 0.45,
    /// A glow of the color around a lit tile, this opaque (0 for none),
    /// `glow_blur` wide.
    glow: f32 = 0,
    glow_blur: f32 = 14,
    /// What a screen reader calls it, as an image ("Light, on"); empty
    /// leaves it out, as a decoration.
    label: []const u8 = "",
    /// Multiplies every length, for an app that zooms its layout along
    /// with `c.setZoom`.
    scale: f32 = 1,
};

/// The tile, with `icon` in its middle.
pub fn iconTile(c: *ui.Context, icon: []const u8, opts: Options) void {
    const tile = iconTileOpen(c, opts);
    defer tile.end();
    ui.icon(c, icon, .{ .size = tile.icon_size, .color = tile.icon_color });
}

/// A tile open for its icon, centered in it: draw the icon `icon_size`
/// points across in `icon_color`, then `end` it.
pub const IconTileOpen = struct {
    icon_size: f32,
    /// The tile's color, lit; muted or the caller's `icon_color`, off.
    icon_color: ui.Color,

    // The tile's own: callers end it.
    box: ui.Div,

    pub fn end(t: IconTileOpen) void {
        t.box.end();
    }
};

/// The tile, open for an icon the caller draws.
pub fn iconTileOpen(c: *ui.Context, opts: Options) IconTileOpen {
    const k = opts.scale;
    const t = kit.tokens(c);
    const col = parts.statusColor(t, opts.status, opts.color, .accent);
    const size = opts.size * k;
    var tile = ui.div(c).w(size).h(size).rounded((opts.radius orelse opts.size * 0.28) * k).center()
        .bg(if (opts.lit) col.alpha(opts.fill) else t.surface)
        .border(if (opts.lit) col.alpha(opts.edge) else t.border);
    if (opts.lit and opts.glow > 0) tile = tile.shadow(.{ .color = col.alpha(opts.glow), .blur = opts.glow_blur * k, .y = 0 });
    if (opts.label.len > 0) ui.access.describe(c, tile.index, .{ .role = .image, .label = opts.label }) else ui.access.hide(c, tile.index);
    return .{ .box = tile, .icon_size = (opts.icon_size orelse opts.size * 0.45) * k, .icon_color = if (opts.lit) col else opts.icon_color orelse t.muted };
}

const Tiles = struct {
    lit: bool = true,
    opts: Options = .{ .status = .warning, .label = "Light, on" },
    tile: u32 = 0,

    fn view(x: *Tiles, c: *ui.Context) void {
        const row = ui.div(c).row().gap(10).p(10);
        defer row.end();
        var o = x.opts;
        o.lit = x.lit;
        x.tile = @intCast(c.nodes.items.len);
        iconTile(c, "sun.max", o);
        const open = iconTileOpen(c, o);
        defer open.end();
        ui.text(c, "drawn", .{ .size = 8, .color = open.icon_color });
    }
};

fn iconOf(t: *ui.Tester) @TypeOf(t.ctx.nodes.items[0].content.icon) {
    for (t.ctx.nodes.items) |n| switch (n.content) {
        .icon => |i| return i,
        else => {},
    };
    unreachable;
}

test "a lit tile is tinted in its status's color, and unlit the surface with a muted icon or the caller's" {
    var x: Tiles = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Tiles.view), .{ .width = 200, .height = 80 });
    defer t.deinit();
    t.settle(1);
    const tk = kit.tokens(&t.ctx);
    var n = t.ctx.nodes.items[x.tile];
    try std.testing.expectEqual(tk.warning.alpha(0.12), n.style.background.?);
    try std.testing.expectEqual(tk.warning, iconOf(&t).color);
    try std.testing.expectEqual(@as(f32, 32 * 0.45), iconOf(&t).size);
    x.lit = false;
    t.settle(1);
    n = t.ctx.nodes.items[x.tile];
    try std.testing.expectEqual(tk.surface, n.style.background.?);
    try std.testing.expectEqual(tk.muted, iconOf(&t).color);
    x.opts.icon_color = .hex(0x22c55e);
    t.settle(1);
    try std.testing.expectEqual(ui.Color.hex(0x22c55e), iconOf(&t).color);
}

test "a glowing tile has a shadow in its color, and its lengths follow scale" {
    var x: Tiles = .{ .opts = .{ .color = .hex(0x22d3ee), .glow = 0.45, .scale = 2 } };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Tiles.view), .{ .width = 300, .height = 120 });
    defer t.deinit();
    t.settle(1);
    const n = t.ctx.nodes.items[x.tile];
    try std.testing.expectEqual(ui.Color.hex(0x22d3ee).alpha(0.45), n.style.shadow.?.color);
    try std.testing.expectEqual(@as(f32, 64), t.ctx.rects.get(n.id).?.w);
}

test "an open tile is the same tile, the caller's icon in its middle and color" {
    var x: Tiles = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Tiles.view), .{ .width = 200, .height = 80 });
    defer t.deinit();
    t.settle(1);
    const drawn = t.findText("drawn").?;
    // In the second tile's middle: 10 + 32 + 10 + 16 from the left.
    try std.testing.expectApproxEqAbs(@as(f32, 68), drawn.x + drawn.w / 2, 1);
}

test "a tile is an image named by its label, and without one a decoration" {
    var x: Tiles = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Tiles.view), .{ .width = 200, .height = 80 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(ui.access.Role.image, list.items[0].role);
    try std.testing.expectEqualStrings("Light, on", list.items[0].label);
    x.opts.label = "";
    t.settle(1);
    list = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(@as(usize, 0), list.items.len);
}
