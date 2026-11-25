//! A header: what a window or a pane is, at its top. An icon tile, a
//! title and a muted subtitle under it, left open after them for the
//! pane's own pills and buttons, which sit at its end. A screen reader
//! hears the title as a heading. In a narrow pane the title and the
//! subtitle are cut short with an ellipsis, whole in a tooltip, and what
//! is at the end keeps its room. Narrowed (`narrow`), as over a sidebar
//! narrowed to its icons, it is the tile alone.
//!
//!     const h = controls.header(c, .{ .icon = "externaldrive", .title = "Backups", .subtitle = "~/Documents", .subtitle_mono = true });
//!     controls.pill(c, "RUNNING", .{ .status = .success });
//!     h.end();
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const measure = @import("measure.zig");
const parts = @import("parts.zig");
const tile_mod = @import("icon_tile.zig");

pub const Options = struct {
    /// An SF Symbol in the tile; empty leaves the tile out.
    icon: []const u8 = "",
    /// The tile's look; its status and color, left neutral and null, are
    /// the header's.
    tile: tile_mod.Options = .{},
    title: []const u8,
    /// The title in the monospaced font, for an app's or a host's name.
    title_mono: bool = false,
    subtitle: []const u8 = "",
    /// The subtitle in the monospaced font, for a path or a host.
    subtitle_mono: bool = false,
    /// The tile's color, as the kit's statuses; neutral takes the theme's
    /// accent. `color` goes over it.
    status: kit.Status = .neutral,
    color: ?ui.Color = null,
    /// The title's size: the kit's text at `size` and two points;
    /// `text_size` in points, over it. The subtitle is three points under
    /// the title.
    size: kit.Size = .md,
    text_size: ?f32 = null,
    /// The title's level as a heading to a screen reader, 1 to 6: 1 for a
    /// window's or a pane's title, more for one under another heading.
    heading_level: u8 = 1,
    /// The room between the tile, the words and what is at the end, in
    /// points before `scale`.
    gap: f32 = 10,
    /// The tile alone, centered, for a header over a sidebar narrowed to
    /// its icons: the title shows in a tooltip, and is still heard as a
    /// heading; the subtitle is left out. What the caller adds goes after
    /// the tile.
    narrow: bool = false,
    scale: f32 = 1,
};

/// The header, as wide as its parent, left open after its words for what
/// goes at its end; the caller ends it.
pub fn header(c: *ui.Context, opts: Options) ui.Div {
    const k = opts.scale;
    const t = kit.tokens(c);
    const size = opts.text_size orelse opts.size.text() + 2;
    var bar = ui.div(c).row().wFull().itemsCenter().gap(opts.gap * k);
    var tile = opts.tile;
    if (tile.status == .neutral) tile.status = opts.status;
    tile.color = tile.color orelse opts.color;
    tile.scale = k;
    if (opts.narrow) {
        bar = bar.justifyCenter();
        // The tile names the header: its title in a tooltip, and a
        // heading to a screen reader.
        const box = ui.div(c).row();
        defer box.end();
        if (opts.icon.len > 0) tile_mod.iconTile(c, opts.icon, tile);
        kit.tooltip(c, parts.still(c, box), opts.title, .{ .placement = .right });
        ui.access.describe(c, box.index, .{ .role = .static_text, .label = opts.title, .header = true, .level = opts.heading_level });
        return bar;
    }
    if (opts.icon.len > 0) tile_mod.iconTile(c, opts.icon, tile);
    // The room the rest leaves, and no less than none: the words give way
    // to what is at the end.
    const words = ui.div(c).column().w(0).grow().gap(1 * k);
    defer words.end();
    line(c, opts.title, .{ .size = size, .weight = .bold, .mono = opts.title_mono, .color = t.foreground }, opts.heading_level);
    if (opts.subtitle.len > 0) line(c, opts.subtitle, .{ .size = size - 3, .mono = opts.subtitle_mono, .color = t.muted }, 0);
    return bar;
}

/// `text` on its own line, cut short with an ellipsis where the room
/// ends and then whole in a tooltip; a heading of `level` to a screen
/// reader, or plain text at 0.
fn line(c: *ui.Context, text: []const u8, style: ui.TextStyle, level: u8) void {
    var cut = style;
    cut.truncate = .ellipsis;
    const box = ui.div(c).row().wFull();
    defer box.end();
    ui.text(c, text, cut);
    if (measure.cutOff(c, text, cut)) kit.tooltip(c, parts.still(c, box), text, .{});
    ui.access.describe(c, box.index, .{ .role = .static_text, .label = text, .header = level > 0, .level = level });
}

const Pane = struct {
    width: f32 = 400,
    opts: Options = .{ .icon = "externaldrive", .title = "Backups", .subtitle = "~/Documents/Projects" },
    tile: u32 = 0,
    /// Text at its end.
    end: bool = true,

    fn view(x: *Pane, c: *ui.Context) void {
        const root = ui.div(c).column().w(x.width).p(8);
        defer root.end();
        x.tile = @intCast(c.nodes.items.len + 1);
        const h = header(c, x.opts);
        if (x.end) ui.text(c, "RUNNING", .{ .size = 10 });
        h.end();
    }
};

test "a header's tile, title and subtitle lead, and what the caller adds sits at its end" {
    var x: Pane = .{ .opts = .{ .icon = "externaldrive", .title = "Backups", .subtitle = "~/Documents", .status = .success } };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Pane.view), .{ .width = 420, .height = 80 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expectEqual(kit.tokens(&t.ctx).success.alpha(0.12), t.ctx.nodes.items[x.tile].style.background.?);
    const title = t.findText("Backups").?;
    const sub = t.findText("~/Documents").?;
    try std.testing.expect(title.x > 40 and sub.y > title.y);
    const end = t.findText("RUNNING").?;
    try std.testing.expectApproxEqAbs(@as(f32, 400), end.x + end.w + 8, 1);
}

test "a screen reader hears the title as a heading, then the subtitle" {
    var x: Pane = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Pane.view), .{ .width = 420, .height = 80 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqualStrings("Backups", list.items[0].label);
    try std.testing.expect(list.items[0].header);
    try std.testing.expectEqual(@as(u8, 1), list.items[0].level);
    try std.testing.expectEqualStrings("~/Documents/Projects", list.items[1].label);
    try std.testing.expect(!list.items[1].header);
    try std.testing.expectEqual(@as(u8, 0), list.items[1].level);
    // Under another heading, the caller's level.
    x.opts.heading_level = 3;
    t.settle(1);
    list.clearRetainingCapacity();
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(@as(u8, 3), list.items[0].level);
}

test "a mono title is in the monospaced font" {
    var x: Pane = .{ .opts = .{ .icon = "externaldrive", .title = "Backups", .title_mono = true } };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Pane.view), .{ .width = 420, .height = 80 });
    defer t.deinit();
    t.settle(1);
    for (t.ctx.nodes.items) |n| switch (n.content) {
        .text => |tx| if (std.mem.eql(u8, tx.str, "Backups")) try std.testing.expect(tx.style.mono),
        else => {},
    };
}

test "narrowed, the header is its tile alone, centered, its title in a tooltip and heard as a heading" {
    var x: Pane = .{ .width = 48, .opts = .{ .icon = "externaldrive", .title = "Backups", .subtitle = "~/Documents", .narrow = true }, .end = false };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Pane.view), .{ .width = 100, .height = 80 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(!t.hasText("Backups") and !t.hasText("~/Documents"));
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    var heading: ?ui.Rect = null;
    for (list.items) |e| if (std.mem.eql(u8, e.label, "Backups") and e.header) {
        heading = e.rect;
    };
    // Centered in the pane, between its padding.
    const r = heading.?;
    try std.testing.expectApproxEqAbs(@as(f32, 8 + 16), r.x + r.w / 2, 1.5);
    t.moveTo(r.x + r.w / 2, r.y + r.h / 2);
    t.advance(1.5);
    try std.testing.expect(t.hasText("Backups"));
}

test "in a narrow pane the words are cut short, whole in a tooltip, and what is at the end stays" {
    var x: Pane = .{ .width = 150, .opts = .{ .title = "Backups of every folder", .subtitle = "~/Documents/Projects/a-long-name" } };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Pane.view), .{ .width = 200, .height = 80 });
    defer t.deinit();
    t.settle(1);
    for (0..2) |_| t.frame();
    const end = t.findText("RUNNING").?;
    try std.testing.expectApproxEqAbs(@as(f32, 150), end.x + end.w + 8, 1);
    // Cut short, the title's words aren't all drawn, however many the
    // fonts leave; its box is where a screen reader finds it.
    try std.testing.expect(!t.hasText("Backups of every folder"));
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    var title: ?ui.Rect = null;
    for (list.items) |e| if (std.mem.eql(u8, e.label, "Backups of every folder")) {
        title = e.rect;
    };
    t.moveTo(title.?.x + 4, title.?.y + title.?.h / 2);
    t.advance(1.5);
    // Whole in its tooltip.
    try std.testing.expect(t.hasText("Backups of every folder"));
}
