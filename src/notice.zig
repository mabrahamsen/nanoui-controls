//! A notice: a panel with a large icon, a title and a description,
//! centered: what a pane shows in place of its content when it is empty,
//! stopped or waiting. The kit's `empty`, in a panel, with a status, a
//! spinner while loading, and room for a button.
//!
//!     controls.notice(c, .{ .icon = "tray", .title = "No snapshots yet", .description = "They show here once the first backup runs." });
//!
//!     const n = controls.noticeOpen(c, .{ .icon = "power", .title = "Server stopped", .status = .warning });
//!     if (kit.button(c, "Start", .{ .variant = .primary }).clicked) start();
//!     n.end();
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const parts = @import("parts.zig");
const Surface = @import("surface.zig").Surface;
const panel = @import("panel.zig").panel;

pub const Options = struct {
    /// An SF Symbol, over the status's.
    icon: ?[]const u8 = null,
    /// A spinner in place of the icon, for a pane waiting on something.
    loading: bool = false,
    /// A short title, heard as a heading.
    title: []const u8 = "",
    /// The title in the monospaced font, for one in capitals.
    mono: bool = false,
    /// A sentence or two, centered, wrapped into lines of about one
    /// length.
    description: []const u8 = "",
    /// The title's and the icon's color, as the kit's statuses; neutral
    /// takes the theme's accent and an info icon.
    status: kit.Status = .neutral,
    /// The title's and the icon's color, over the status's.
    color: ?ui.Color = null,
    /// The icon's color, over `color`.
    icon_color: ?ui.Color = null,
    /// The title's and the description's size, as the kit's: its text at
    /// that size; `text_size` in points, over it.
    size: kit.Size = .sm,
    text_size: ?f32 = null,
    /// The icon's size, in points before `scale`.
    icon_size: f32 = 26,
    /// The panel: a panel's (the theme's surface, border and radius, as
    /// wide as its parent), with 32 points of room above and below what
    /// is in it, unless it says.
    card: Surface = .{},
    /// Said by a screen reader when it appears or changes (its title and
    /// description), for a pane that turns into it after something
    /// happened.
    announce: bool = false,
    /// Multiplies every length but the texts' sizes, for an app that zooms
    /// its layout along with `c.setZoom`.
    scale: f32 = 1,
};

/// A notice.
pub fn notice(c: *ui.Context, opts: Options) void {
    noticeOpen(c, opts).end();
}

/// A notice, left open after its description for more, such as a button
/// or a checkbox; the caller ends it.
pub fn noticeOpen(c: *ui.Context, opts: Options) ui.Div {
    const t = kit.tokens(c);
    const k = opts.scale;
    const col = parts.statusColor(t, opts.status, opts.color, .accent);
    const icon = opts.icon orelse parts.statusIcon(opts.status);
    const size = opts.text_size orelse opts.size.text();
    if (opts.announce) parts.announceOnce(c, if (opts.title.len > 0 and opts.description.len > 0) c.print("{s}. {s}", .{ opts.title, opts.description }) else if (opts.title.len > 0) opts.title else opts.description);
    const p = panel(c, .{ .card = opts.card.over(.{ .py = 32 }), .scale = k }).itemsCenter();
    if (opts.loading) {
        // Over the icon, drawn clear, so the title doesn't move when it
        // goes.
        const slot = ui.div(c);
        defer slot.end();
        ui.icon(c, icon, .{ .size = opts.icon_size * k, .color = col.alpha(0) });
        const over = ui.div(c).absolute().offset(0, 0).wFull().hFull().center();
        defer over.end();
        kit.spinner(c, .{ .size = @round(opts.icon_size * 0.8 * k), .color = opts.icon_color orelse col });
    } else ui.icon(c, icon, .{ .size = opts.icon_size * k, .color = opts.icon_color orelse col });
    if (opts.title.len > 0) {
        const line = ui.div(c).row();
        ui.text(c, opts.title, .{ .size = size + 1, .weight = .semibold, .mono = opts.mono, .color = if (opts.color == null) parts.readable(t, col, 0) else col });
        line.end();
        ui.access.describe(c, line.index, .{ .role = .static_text, .label = opts.title, .header = true });
    }
    if (opts.description.len > 0) parts.centeredText(c, opts.description, .{ .size = size, .color = t.muted });
    return p;
}

test {
    _ = @import("notice_tests.zig");
}
