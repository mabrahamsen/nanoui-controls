//! A pill: a short label in a box tinted in its color, led by a glowing
//! dot or an icon if wanted. A capsule for a status ("● LIVE", "3
//! FAILED"); a box at least as wide as it is tall for a badge ("P",
//! "ROSETTA"). The kit's `tag` with a lead, a tooltip, a height, and the
//! tint's strength to set.
//!
//!     controls.pill(c, "LIVE", .{ .status = .success, .lead = .{ .dot = .{} } });
//!     controls.pill(c, "P", .{ .shape = .box, .tooltip = "Performance cores" });
//!     const p = controls.pillOpen(c, "BREACHES?", .{ .lead = .{ .icon = .{ .name = "network" } } });
//!     if (kit.button(c, "Check", .{ .size = .xs, .variant = .ghost }).clicked) check();
//!     p.end();
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const parts = @import("parts.zig");

/// What comes before the label.
pub const Lead = union(enum) {
    none,
    /// A dot that glows; `dim` draws it faint and without its glow, as the
    /// off beat of a blink. Its size, null, follows the pill's `size`.
    dot: struct { size: ?f32 = null, dim: bool = false },
    /// An SF Symbol; its size, null, follows the pill's `size`.
    icon: struct { name: []const u8, size: ?f32 = null },
};

pub const Shape = enum {
    /// Fully rounded ends: a status.
    capsule,
    /// Corners of `radius`, and at least square: a badge.
    box,
};

pub const Options = struct {
    /// The color, as the kit's statuses; neutral takes the theme's accent.
    status: kit.Status = .neutral,
    /// The label's, the tint's and the border's color, over the status's.
    /// A status's own color is the tint's and the border's, and the label
    /// takes a shade of it that reads (`text_contrast`).
    color: ?ui.Color = null,
    lead: Lead = .none,
    shape: Shape = .capsule,
    /// The label's size, as the kit's tag: a point under the kit's text at
    /// that size. Its padding, gap and corners follow it.
    size: kit.Size = .xs,
    /// The label's size in points, over `size`'s; the lengths still follow
    /// `size`.
    text_size: ?f32 = null,
    weight: ui.Weight = .semibold,
    /// The label in the monospaced font, so figures line up from pill to
    /// pill.
    mono: bool = false,
    /// The tint's and the border's opacity.
    fill: f32 = 0.08,
    edge: f32 = 0.4,
    /// Padding across and down, the gap after the lead, and a box's
    /// corners, in points before `scale`; null follows `size` (9, 4, 6 and
    /// 5 at `.xs`).
    px: ?f32 = null,
    py: ?f32 = null,
    gap: ?f32 = null,
    radius: ?f32 = null,
    /// A height of its own, which a box is at least as wide as, in points
    /// before `scale`; null takes its content's and padding's.
    height: ?f32 = null,
    /// The widest it gets, in points before `scale`: a longer label ends
    /// in "…" and shows whole in a tooltip. A screen reader hears it whole
    /// either way.
    max_width: ?f32 = null,
    /// What the pill means, for one too terse to say it ("P" for
    /// "Performance cores"): in a tooltip under the pointer, and said to a
    /// screen reader after the label.
    tooltip: []const u8 = "",
    /// What a screen reader hears in place of the label, for one that is
    /// a symbol or an abbreviation ("Recording" for "● REC").
    value_text: []const u8 = "",
    /// Multiplies every length but the label's size, for an app that
    /// zooms its layout along with `c.setZoom`.
    scale: f32 = 1,
};

/// A pill reading `label`.
pub fn pill(c: *ui.Context, label: []const u8, opts: Options) void {
    pillOpen(c, label, opts).end();
}

/// A pill reading `label`, left open after it for more, such as a button;
/// the caller ends it. A screen reader hears the label, then what was
/// added, as it is.
pub fn pillOpen(c: *ui.Context, label: []const u8, opts: Options) ui.Div {
    const k = opts.scale;
    const t = kit.tokens(c);
    const col = parts.statusColor(t, opts.status, opts.color, .accent);
    // The label in a shade that reads on the tint; a color the caller
    // gives, as it is.
    const ink = if (opts.color == null) parts.readable(t, col, opts.fill) else col;
    const l = lengths(opts);
    var p = ui.div(c).row().gap(l.gap * k).px(l.px * k).py(l.py * k).bg(col.alpha(opts.fill)).border(col.alpha(opts.edge));
    p = switch (opts.shape) {
        .capsule => p.itemsCenter().roundedFull(),
        .box => p.center().rounded(l.radius * k),
    };
    if (opts.height) |h| {
        p = p.h(h * k);
        if (opts.shape == .box) c.node(p.index).style.min_width = h * k;
    }
    if (opts.max_width) |mw| p = p.maxW(mw * k);
    switch (opts.lead) {
        .none => {},
        .dot => |d| parts.dot(c, if (d.dim) col.alpha(0.25) else col, l.dot * k, if (d.dim) 0 else 0.8),
        .icon => |i| ui.icon(c, i.name, .{ .size = l.icon * k, .color = col }),
    }
    // The label in a box of its own, which a screen reader hears: the pill
    // isn't one element, so a button in it is still reached.
    const text = ui.div(c).row();
    const style: ui.TextStyle = .{ .size = l.text, .weight = opts.weight, .mono = opts.mono, .color = ink, .truncate = if (opts.max_width != null) .ellipsis else .none };
    ui.text(c, label, style);
    text.end();
    ui.access.describe(c, text.index, .{ .role = .static_text, .label = if (opts.value_text.len > 0) opts.value_text else label, .hint = opts.tooltip });
    // Cut short as the last frame laid it out, it shows whole in the
    // tooltip, before what the tooltip says of it.
    const cut = opts.max_width != null and if (c.rects.get(c.node(text.index).id)) |r| r.w + 0.5 < c.text.width(label, style) else false;
    const tip = if (cut and opts.tooltip.len > 0) c.print("{s} — {s}", .{ label, opts.tooltip }) else if (cut) label else opts.tooltip;
    if (tip.len > 0) kit.tooltip(c, parts.still(c, p), tip, .{});
    return p;
}

/// A pill's lengths, in points before `scale`.
pub const Lengths = struct {
    text: f32,
    px: f32,
    py: f32,
    gap: f32,
    radius: f32,
    dot: f32,
    icon: f32,
};

/// The lengths a pill with `opts` is drawn at, each set in `opts` or
/// following its `size`, as the kit's tag's padding follows its text: to
/// measure a pill before drawing it.
pub fn lengths(opts: Options) Lengths {
    // 1 at `.xs`, the size the lengths were drawn for.
    const f = opts.size.text() / kit.Size.xs.text();
    return .{
        .text = opts.text_size orelse opts.size.text() - 1,
        .px = opts.px orelse 9 * f,
        .py = opts.py orelse 4 * f,
        .gap = opts.gap orelse 6 * f,
        .radius = opts.radius orelse 5 * f,
        .dot = switch (opts.lead) {
            .dot => |d| d.size orelse 7 * f,
            else => 7 * f,
        },
        .icon = switch (opts.lead) {
            .icon => |i| i.size orelse 10 * f,
            else => 10 * f,
        },
    };
}

test {
    _ = @import("pill_tests.zig");
}
