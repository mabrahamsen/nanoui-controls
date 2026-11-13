//! What the pills, panels, captions, callouts and notices draw with: a
//! status's color and a shade of it that reads as text, a glowing dot, a box that listens only for its
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

/// The contrast text needs over what is behind it, as WCAG asks of text
/// at the kit's sizes.
pub const text_contrast: f32 = 4.5;

/// `col` for text, or a shade of it toward the theme's text, enough to
/// read at `text_contrast` over the background and over a surface, each
/// tinted with `col` at `tint`'s opacity: a status's color reads faint as
/// text in the light theme, a success's green above all. The dot, icon,
/// tint and border beside it keep `col`.
pub fn readable(t: kit.Tokens, col: ui.Color, tint: f32) ui.Color {
    const unders = [_]ui.Color{ t.background.mix(col, tint), t.surface.mix(col, tint) };
    var ink = col;
    var step: f32 = 0;
    while (step < 1) : (step += 0.05) {
        ink = col.mix(t.foreground, step);
        var least: f32 = std.math.inf(f32);
        for (unders) |u| least = @min(least, contrast(ink, u));
        if (least >= text_contrast) return ink;
    }
    return t.foreground;
}

/// The contrast of two opaque colors, from 1 to 21, as WCAG measures it.
pub fn contrast(a: ui.Color, b: ui.Color) f32 {
    const la = luminance(a);
    const lb = luminance(b);
    return (@max(la, lb) + 0.05) / (@min(la, lb) + 0.05);
}

/// A color's relative luminance, its channels taken out of sRGB.
fn luminance(col: ui.Color) f32 {
    const ch = struct {
        fn lin(v: f32) f32 {
            return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
        }
    };
    return 0.2126 * ch.lin(col.r) + 0.7152 * ch.lin(col.g) + 0.0722 * ch.lin(col.b);
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

/// `box`'s interaction without the pointing hand, and without a click on
/// it taking the keyboard from where it was: for a box that listens only
/// for its tooltip, or is disabled.
pub fn still(c: *ui.Context, box: ui.Div) ui.Interaction {
    const hand = c.hand_cursor;
    const was = c.focus;
    c.hand_cursor = false;
    defer c.hand_cursor = hand;
    const it = box.interaction();
    c.focus = was;
    return it;
}

/// Says `text` to a screen reader once, when it appears or changes, rather
/// than every frame: for a message that comes and goes in place. Gone for
/// a frame and back, it is said again. Call it just before the message's
/// box is made.
pub fn announceOnce(c: *ui.Context, text: []const u8) void {
    const said = c.state(struct { hash: u64 = 0, frame: u64 = 0 }, "announced");
    const h = std.hash.Wyhash.hash(0, text);
    // nanoui remembers a box's state a while after it goes: drawn in the
    // last frame, or this one again, it is still there.
    const there = said.frame + 1 >= c.frame;
    said.frame = c.frame;
    if (said.hash == h and there) return;
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

test "status text reads at 4.5:1 on its tint in the light and dark themes, a success's green darkened in the light" {
    const T = struct {
        fn view(_: *@This(), _: *ui.Context) void {}
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 100, .height = 100 });
    defer t.deinit();
    for ([_]ui.Theme{ ui.Theme.light, ui.Theme.dark_theme }) |theme| {
        t.ctx.theme = theme;
        const tk = kit.tokens(&t.ctx);
        for ([_]kit.Status{ .neutral, .info, .success, .warning, .danger }) |s| {
            const col = statusColor(tk, s, null, .accent);
            const ink = readable(tk, col, 0.08);
            try std.testing.expect(contrast(ink, tk.background.mix(col, 0.08)) >= text_contrast);
            try std.testing.expect(contrast(ink, tk.surface.mix(col, 0.08)) >= text_contrast);
        }
        // Where it reads already, it is as it is.
        try std.testing.expectEqual(tk.foreground, readable(tk, tk.foreground, 0));
    }
    t.ctx.theme = ui.Theme.light;
    const tk = kit.tokens(&t.ctx);
    // About 2:1 on white, as nanoui's light theme has it.
    try std.testing.expect(contrast(tk.success, tk.surface) < 3);
    try std.testing.expect(!std.meta.eql(tk.success, readable(tk, tk.success, 0.08)));
}
