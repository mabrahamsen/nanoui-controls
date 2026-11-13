//! A surface: the look of a box a control draws itself in (a panel, a
//! notice, a stat's tile). Each of those takes one as its `card`, so a
//! look an app gives one, kept as a preset, is the same on all of them.
//!
//!     const card: controls.Surface = .{ .radius = 12, .fill = cardFill(c) };
//!     const p = controls.panel(c, .{ .title = "RETENTION", .card = card });
//!     defer p.end();
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;

/// A box's look, as its caller sets it. A field left null takes the
/// control's own: most often the theme's surface, border and radius, and
/// the control's padding and gap.
pub const Surface = struct {
    fill: ?ui.Color = null,
    border: ?ui.Color = null,
    /// The border's width, in points.
    border_width: ?f32 = null,
    /// The corners' radius, in points before `scale`.
    radius: ?f32 = null,
    /// Padding across and down, and the gap between what is in it, in
    /// points before `scale`.
    px: ?f32 = null,
    py: ?f32 = null,
    gap: ?f32 = null,
    /// Its width and height; a length in points is multiplied by `scale`.
    /// A width of `.auto` takes its content's, for boxes side by side.
    width: ?ui.Length = null,
    height: ?ui.Length = null,
    /// A glow around it, for a box that stands out (a result).
    glow: ?Glow = null,

    /// `s`, the fields it leaves null taken from `under`: one look over
    /// another, as an app's change over its preset.
    pub fn over(s: Surface, under: Surface) Surface {
        var out = s;
        inline for (@typeInfo(Surface).@"struct".field_names) |n| {
            if (@field(out, n) == null) @field(out, n) = @field(under, n);
        }
        return out;
    }
};

/// A glow around a box.
pub const Glow = struct {
    /// Null takes the control's color: its status's, or the accent.
    color: ?ui.Color = null,
    opacity: f32 = 0.3,
    /// How far it spreads, in points before `scale`.
    blur: f32 = 30,
};

/// What a control's box is where its caller's `Surface` leaves a field
/// null: a fill and a border (null for none), corners (null: the
/// theme's), and lengths in points before `scale`.
pub const Own = struct {
    fill: ?ui.Color = null,
    border: ?ui.Color = null,
    border_width: f32 = 1,
    radius: ?f32 = null,
    px: f32 = 0,
    py: f32 = 0,
    gap: f32 = 0,
    width: ui.Length = .fill,
    /// What a glow is in when the caller's names no color.
    color: ?ui.Color = null,
    scale: f32 = 1,
};

/// The box `s` describes over the control's `own`, a column open for
/// what goes in it; the caller ends it.
pub fn open(c: *ui.Context, s: Surface, own: Own) ui.Div {
    const t = kit.tokens(c);
    const k = own.scale;
    var d = ui.div(c).column().px((s.px orelse own.px) * k).py((s.py orelse own.py) * k).gap((s.gap orelse own.gap) * k)
        .rounded((s.radius orelse own.radius orelse t.radius) * k);
    if (s.fill orelse own.fill) |f| d = d.bg(f);
    if (s.border orelse own.border) |b| d = d.border(b).borderW(s.border_width orelse own.border_width);
    if (s.glow) |g| {
        const col = g.color orelse own.color orelse t.primary;
        d = d.shadow(.{ .color = col.alpha(g.opacity), .blur = g.blur * k, .y = 0 });
    }
    const n = c.node(d.index);
    n.style.width = scaled(s.width orelse own.width, k);
    if (s.height) |h| n.style.height = scaled(h, k);
    return d;
}

/// A length with `scale` applied: one in points zooms; one relative to
/// the parent doesn't.
pub fn scaled(length: ui.Length, k: f32) ui.Length {
    return switch (length) {
        .px => |w| .{ .px = w * k },
        else => length,
    };
}

const std = @import("std");

test "a look over another takes the other's fields where it leaves them null" {
    const preset: Surface = .{ .radius = 12, .px = 20, .fill = .hex(0x101010) };
    const s = (Surface{ .px = 8 }).over(preset);
    try std.testing.expectEqual(@as(?f32, 8), s.px);
    try std.testing.expectEqual(@as(?f32, 12), s.radius);
    try std.testing.expect(s.fill != null);
    try std.testing.expectEqual(@as(?f32, null), s.py);
}

test "a box takes the control's own look where the caller's leaves it, and its lengths follow scale" {
    const T = struct {
        card: Surface = .{},
        index: u32 = 0,
        fn view(x: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(300);
            defer root.end();
            const d = open(c, x.card, .{ .fill = kit.tokens(c).surface, .border = kit.tokens(c).border, .px = 10, .py = 6, .width = .{ .px = 100 }, .scale = 2 });
            x.index = d.index;
            ui.text(c, "in", .{});
            d.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 400, .height = 200 });
    defer t.deinit();
    t.settle(1);
    var n = t.ctx.nodes.items[x.index];
    try std.testing.expectEqual(@as(f32, 20), n.style.padding.left);
    try std.testing.expectEqual(@as(f32, 12), n.style.padding.top);
    try std.testing.expectEqual(ui.Length{ .px = 200 }, n.style.width);
    try std.testing.expect(n.style.shadow == null);
    // The caller's fields go over the control's, and a glow takes the
    // accent when neither names a color.
    x.card = .{ .px = 4, .width = .auto, .glow = .{} };
    t.settle(1);
    n = t.ctx.nodes.items[x.index];
    try std.testing.expectEqual(@as(f32, 8), n.style.padding.left);
    try std.testing.expectEqual(ui.Length.auto, n.style.width);
    try std.testing.expect(n.style.shadow != null);
}
