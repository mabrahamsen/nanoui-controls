//! A panel: a rounded box with a border that groups what is in it, headed
//! by a caption if it has a title. A status colors its border and
//! caption; with `open`, its head folds it.
//!
//!     const p = controls.panel(c, .{ .title = "RETENTION" });
//!     defer p.end();
//!
//!     const adv = controls.panel(c, .{ .title = "ADVANCED", .open = &s.advanced });
//!     defer adv.end();
//!     if (s.advanced) advanced(c, s);
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const focus = @import("focus.zig");
const parts = @import("parts.zig");
const surface = @import("surface.zig");
const Surface = surface.Surface;
const caption_mod = @import("caption.zig");

pub const Options = struct {
    /// A caption at its top, drawn as `caption` draws with `caption`'s
    /// options; empty draws none.
    title: []const u8 = "",
    caption: caption_mod.Options = .{},
    /// Whether it is open, for a panel that folds: its head is then one
    /// button, the caption and a chevron, that Tab reaches and a click,
    /// Space or Enter flips. The caller draws what it holds only while it
    /// is open. Null doesn't fold.
    open: ?*bool = null,
    /// What a screen reader says of a folding panel that is open, and
    /// folded.
    expanded_text: []const u8 = "expanded",
    collapsed_text: []const u8 = "collapsed",
    /// As the kit's statuses: other than neutral colors the border and the
    /// caption, as the form's danger heading does its card. The card's
    /// `border` and the caption's `color` go over it.
    status: kit.Status = .neutral,
    /// The box: the theme's surface, border and radius, 14 points of
    /// padding and 10 between what is in it, as wide as its parent, unless
    /// it says. A glow takes the status's color, or the accent.
    card: Surface = .{},
    /// Multiplies every length but text sizes, for an app that zooms its
    /// layout along with `c.setZoom`.
    scale: f32 = 1,
};

/// A panel, open for its content; the caller ends it. The panel isn't an
/// element to a screen reader, so what is in it is reached as it is.
pub fn panel(c: *ui.Context, opts: Options) ui.Div {
    const t = kit.tokens(c);
    const tint: ?ui.Color = if (opts.status == .neutral) null else parts.statusColor(t, opts.status, null, .muted);
    const p = surface.open(c, opts.card, .{
        .fill = t.surface,
        .border = if (tint) |col| col.alpha(0.5) else t.border,
        .px = 14,
        .py = 14,
        .gap = 10,
        .color = tint,
        .scale = opts.scale,
    });
    var cap = opts.caption;
    cap.color = cap.color orelse if (tint) |col| parts.readable(t, col, 0) else null;
    cap.scale = opts.scale;
    if (opts.open) |open| {
        foldingHead(c, opts.title, open, cap, opts);
    } else if (opts.title.len > 0) caption_mod.caption(c, opts.title, cap);
    return p;
}

/// A folding panel's head: the caption and a chevron at the line's end,
/// one button that flips `open`.
fn foldingHead(c: *ui.Context, title: []const u8, open: *bool, cap: caption_mod.Options, opts: Options) void {
    const t = kit.tokens(c);
    const k = opts.scale;
    ui.key(c, c.print("panel-head-{s}", .{title}));
    var h = ui.div(c).row().wFull().itemsCenter().gap(6 * k).rounded(@max(0, t.radius - 2) * k);
    defer h.end();
    const it = focus.button(c, h.index, true);
    if (it.hovered) c.cursor_hand = true;
    if (focus.showRing(c, it.focused)) h = h.border(focus.ring(c)).borderW(focus.ringWidth(c));
    if (it.clicked) {
        open.* = !open.*;
        c.changed = true;
    }
    // One element: a button that says whether it is open.
    ui.access.describe(c, h.index, .{ .role = .button, .label = title, .value = if (open.*) opts.expanded_text else opts.collapsed_text, .header = true });
    var plain = cap;
    plain.heading = false;
    caption_mod.caption(c, title, plain);
    ui.spacer(c);
    const size = cap.text_size orelse cap.size.text() - 1;
    ui.icon(c, if (open.*) "chevron.down" else "chevron.right", .{ .size = size * k, .color = if (it.hovered) t.foreground else cap.color orelse t.muted });
}

test {
    _ = @import("panel_tests.zig");
}
