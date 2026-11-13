//! A callout: an icon and text that wraps, in a box tinted in the icon's
//! color, in the flow of a page: a warning, a finding, a rule met or not.
//! The kit's `alert` with its title optional, the text in the theme's
//! text color, and the icon, the tint and the padding the caller's to set.
//!
//!     controls.callout(c, "That folder doesn't exist.", .{ .status = .warning });
//!     if (controls.callout(c, "The server stopped.", .{ .status = .danger, .closable = true })) dismissed = true;
//!
//!     const r = controls.calloutOpen(c, "Couldn't reach the server.", .{ .status = .danger });
//!     if (kit.button(c, "Retry", .{ .size = .sm }).clicked) retry();
//!     r.end();
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const parts = @import("parts.zig");
const buttons = @import("buttons.zig");
const surface = @import("surface.zig");

pub const Options = struct {
    /// The color and icon, as the kit's statuses; neutral takes the
    /// theme's accent and an info icon.
    status: kit.Status = .neutral,
    /// The icon's, the tint's and the border's color, over the status's.
    color: ?ui.Color = null,
    /// An SF Symbol, over the status's.
    icon: ?[]const u8 = null,
    /// A line above the text, in its weight.
    title: []const u8 = "",
    /// A close button at its end; `callout` returns true when it is
    /// clicked. `calloutOpen` draws none: its caller draws one after its
    /// own.
    closable: bool = false,
    /// The close button's tooltip, and its name to a screen reader.
    close_text: []const u8 = "Close",
    /// Said by a screen reader when it appears or its text changes, for
    /// one that comes up after something happened. Null says a danger or
    /// a warning callout, and not others.
    announce: ?bool = null,
    /// The parent's width by default; `.auto` takes its content's. A width
    /// in points is multiplied by `scale`.
    width: ui.Length = .fill,
    /// The text's color; null takes the theme's text.
    text_color: ?ui.Color = null,
    /// The icon by the text's first line (`top`), or its middle; null is
    /// the top with a title, else the middle.
    icon_align: ?enum { top, middle } = null,
    /// The text's size, as the kit's alert: the kit's text at that size.
    /// nanoui's zoom scales it; `scale` doesn't.
    size: kit.Size = .sm,
    /// The text's size in points, over `size`'s.
    text_size: ?f32 = null,
    /// The icon's size, in points before `scale`.
    icon_size: f32 = 13,
    /// No box: the icon and the text alone, without tint, border or
    /// padding, for a note among other content.
    plain: bool = false,
    /// The tint's and the border's opacity.
    fill: f32 = 0.06,
    edge: f32 = 0.25,
    /// Padding across and down, and the gap after the icon, in points
    /// before `scale`.
    px: f32 = 12,
    py: f32 = 8,
    gap: f32 = 10,
    /// Its corners; null takes the theme's radius.
    radius: ?f32 = null,
    /// Multiplies every length but the text's size, for an app that zooms
    /// its layout along with `c.setZoom`.
    scale: f32 = 1,
};

/// A callout saying `text`; true when its close button is clicked.
pub fn callout(c: *ui.Context, text: []const u8, opts: Options) bool {
    const r = calloutOpen(c, text, opts);
    defer r.end();
    return opts.closable and buttons.closeButton(c, opts.close_text).clicked;
}

/// A callout, left open after its text for more, such as a button at its
/// end; the caller ends it. The text takes the room the rest leaves.
pub fn calloutOpen(c: *ui.Context, text: []const u8, opts: Options) ui.Div {
    const k = opts.scale;
    const t = kit.tokens(c);
    const col = parts.statusColor(t, opts.status, opts.color, .accent);
    const icon = opts.icon orelse parts.statusIcon(opts.status);
    const size = opts.text_size orelse opts.size.text();
    const said = if (opts.title.len > 0) c.print("{s}. {s}", .{ opts.title, text }) else text;
    if (opts.announce orelse (opts.status == .danger or opts.status == .warning)) parts.announceOnce(c, said);
    var r = ui.div(c).row().gap(opts.gap * k);
    if (!opts.plain) r = r.px(opts.px * k).py(opts.py * k).rounded((opts.radius orelse t.radius) * k).bg(col.alpha(opts.fill)).border(col.alpha(opts.edge));
    c.node(r.index).style.width = surface.scaled(opts.width, k);
    // With a title, the icon stays by it, as the kit's alert's does.
    const top = if (opts.icon_align) |a| a == .top else opts.title.len > 0;
    r = if (top) r.itemsStart() else r.itemsCenter();
    ui.icon(c, icon, .{ .size = opts.icon_size * k, .color = col });
    // Growing, so the text takes the room and wraps within it. One element
    // to a screen reader: the title and the text.
    const body = ui.div(c).column().grow().gap(2 * k);
    if (opts.title.len > 0) ui.text(c, opts.title, .{ .size = size, .weight = .semibold, .color = t.foreground });
    ui.text(c, text, .{ .size = size, .wrap = true, .color = opts.text_color orelse t.foreground });
    body.end();
    ui.access.describe(c, body.index, .{ .role = .static_text, .label = said });
    return r;
}

test {
    _ = @import("callout_tests.zig");
}
