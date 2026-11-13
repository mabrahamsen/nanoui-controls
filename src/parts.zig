//! What the pills, panels, captions, callouts and notices draw with: a
//! status's color, a glowing dot, a box that listens only for its
//! tooltip, a message said once, one line cut short, and a paragraph
//! centered under a title. Not a control of its own.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const measure = @import("measure.zig");

/// What a neutral status is drawn in, which each control names: the
/// accent, for what is tinted in it (a pill, a callout, a notice); the
/// muted text, for a word that says how something stands; the text, for
/// a value; or the border, for a box's edge.
pub const Neutral = enum { accent, muted, text, border };

/// The color a control in `status` is drawn in: `color` if set, else the
/// status's, and for neutral the one the control names.
pub fn statusColor(t: kit.Tokens, status: kit.Status, color: ?ui.Color, neutral: Neutral) ui.Color {
    if (color) |col| return col;
    if (status != .neutral) return kit.statusColor(t, status);
    return switch (neutral) {
        .accent => t.primary,
        .muted => t.muted,
        .text => t.foreground,
        .border => t.border,
    };
}

/// A status's icon, named as nanoui draws it everywhere: its own icons,
/// where there are no SF Symbols, have no filled info or danger symbol,
/// which `kit.statusIcon` names.
pub fn statusIcon(status: kit.Status) []const u8 {
    return switch (status) {
        .neutral, .info => "info.circle",
        .success => "checkmark.circle.fill",
        .warning => "exclamationmark.triangle.fill",
        .danger => "xmark.octagon",
    };
}

/// A round dot `diameter` points wide in `color`, glowing at `glow`'s
/// opacity (0 for none).
pub fn dot(c: *ui.Context, color: ui.Color, diameter: f32, glow: f32) void {
    var d = ui.div(c).w(diameter).h(diameter).roundedFull().bg(color);
    if (glow > 0) d = d.shadow(.{ .color = color.alpha(glow), .blur = diameter + 1, .y = 0 });
    d.end();
}

/// Gives box `index`, which nanoui described already, `label` (if not
/// empty) and `value` to a screen reader instead: nanoui keeps a box's
/// first description, and its text field is named by its placeholder and
/// tells a password's text. It reads nanoui's list of described boxes, as
/// the pager reads its boxes, and goes once the text field takes a name
/// and keeps a password to itself.
pub fn redescribe(c: *ui.Context, index: u32, label: []const u8, value: []const u8) void {
    var i = c.a11y_items.items.len;
    while (i > 0) {
        i -= 1;
        const item = &c.a11y_items.items[i];
        if (item.node_index != index) continue;
        if (label.len > 0) item.label = c.alloc().dupe(u8, label) catch label;
        item.value = c.alloc().dupe(u8, value) catch value;
        return;
    }
}

/// A dot for each character of `text`, at most 32, for a secret shown
/// hidden.
pub fn dots(c: *ui.Context, text: []const u8) []const u8 {
    const n = @min(std.unicode.utf8CountCodepoints(text) catch text.len, 32);
    const out = c.alloc().alloc(u8, n * 3) catch return "";
    for (0..n) |i| @memcpy(out[i * 3 ..][0..3], "•");
    return out;
}

/// `box`'s interaction without the pointing hand, for a box that listens
/// only for its tooltip.
pub fn still(c: *ui.Context, box: ui.Div) ui.Interaction {
    const hand = c.hand_cursor;
    c.hand_cursor = false;
    defer c.hand_cursor = hand;
    return box.interaction();
}

/// Says `text` to a screen reader once, when it differs from what was
/// said here last, rather than every frame: for a message that appears or
/// changes in place. Call it just before the message's box is made.
pub fn announceOnce(c: *ui.Context, text: []const u8) void {
    const said = c.state(struct { hash: u64 = 0 }, "announced");
    const h = std.hash.Wyhash.hash(0, text);
    if (said.hash == h) return;
    said.hash = h;
    ui.access.announce(c, text);
}

/// `text` on one line in the room its row leaves, cut short with an
/// ellipsis where the room ends, so it gives way to what is beside it.
/// Returns the box it is in, to describe it.
pub fn oneLine(c: *ui.Context, text: []const u8, style: ui.TextStyle) u32 {
    const room = ui.div(c).column().w(0).grow();
    defer room.end();
    const line = ui.div(c).row().wFull();
    defer line.end();
    var cut = style;
    cut.truncate = .ellipsis;
    ui.text(c, text, cut);
    return room.index;
}

/// `text` centered: on one line when it fits its parent, else wrapped
/// into as few lines as it needs, of about one length, so a paragraph
/// under a centered title neither sits at the left nor leaves its last
/// word alone on a line.
pub fn centeredText(c: *ui.Context, text: []const u8, style: ui.TextStyle) void {
    const outer = ui.div(c).column().wFull().itemsCenter();
    defer outer.end();
    const full = @ceil(c.text.width(text, style)) + 1;
    // The room as the last frame laid it out; in the first, the text's own.
    const space = if (measure.lastSize(c, outer.index)) |s| s.w else full;
    const lines = @max(1, @ceil(full / @max(space, 1)));
    // Words don't break evenly: a little over an even share each.
    const width = if (lines == 1) full else @min(space, full / lines * 1.12 + 1);
    var wrapped = style;
    wrapped.wrap = true;
    const box = ui.div(c).column().w(width);
    defer box.end();
    ui.text(c, text, wrapped);
}
