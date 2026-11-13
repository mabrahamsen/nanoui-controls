//! An input box: nanoui's text field in a frame of its own, as a search
//! box or a password field has it. An icon leads; while the field has the
//! keyboard the frame takes the accent and glows. A clear button comes
//! with text, a Paste button if asked, and with `shown` the text is hidden
//! as dots until an eye shows it. Each button is named to a screen
//! reader, which isn't told a hidden secret's text.
//!
//! The caller keeps the text and does what the buttons ask: empties the
//! buffer on `cleared`, reads the clipboard on `pasted`.
//!
//!     const r = controls.inputBox(c, &s.search, .{ .icon = "magnifyingglass", .placeholder = "Search" });
//!     if (r.cleared) s.search.set("");
//!
//!     _ = controls.inputBox(c, &s.password, .{ .icon = "lock", .label = "Password", .shown = &s.show });
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const focus = @import("focus.zig");
const parts = @import("parts.zig");
const buttons = @import("buttons.zig");
const surface = @import("surface.zig");
const Surface = surface.Surface;

pub const Options = struct {
    /// An SF Symbol before the field; empty for none.
    icon: []const u8 = "",
    placeholder: []const u8 = "",
    /// What a screen reader calls the field; empty takes the placeholder.
    label: []const u8 = "",
    /// A secret: its text shows as dots until the eye, which turns this,
    /// shows it. Null for a plain field, with no eye.
    shown: ?*bool = null,
    /// A clear button: null shows it while there is text, unless the field
    /// is a secret; true always, false never.
    clearable: ?bool = null,
    /// A Paste button.
    paste: bool = false,
    mono: bool = false,
    /// The text's size, as the kit's; `text_size` in points, over it.
    size: kit.Size = .md,
    text_size: ?f32 = null,
    /// The frame's, the icon's and the caret's color while the field has
    /// the keyboard; null takes the theme's accent.
    color: ?ui.Color = null,
    /// The glow's opacity while the field has the keyboard; 0 for none.
    glow: f32 = 0.22,
    /// The frame: the theme's surface, border and radius, 12 points of
    /// padding across, 8 down and 8 between its parts, as wide as its
    /// parent, unless it says. A width in points is multiplied by `scale`.
    card: Surface = .{},
    /// The buttons' words: their tooltips, and their names to a screen
    /// reader.
    show_text: []const u8 = "Show",
    hide_text: []const u8 = "Hide",
    clear_text: []const u8 = "Clear",
    paste_text: []const u8 = "Paste",
    /// Dimmed, its text shown (a hidden secret's as dots) without the
    /// field or the buttons, said to be unavailable.
    disabled: bool = false,
    scale: f32 = 1,
};

/// What happened this frame: the field's, and the buttons clicked.
pub const Result = struct {
    /// nanoui's: `changed`, `submitted` (Return), `focused`.
    field: ui.TextFieldResult = .{},
    /// The clear button was pressed: empty the buffer.
    cleared: bool = false,
    /// The Paste button was pressed: read the clipboard into the buffer.
    pasted: bool = false,
};

/// `buffer` in a framed field.
pub fn inputBox(c: *ui.Context, buffer: *ui.TextBuffer, opts: Options) Result {
    const t = kit.tokens(c);
    const k = opts.scale;
    const col = opts.color orelse t.primary;
    // Whether the field had the keyboard, as the last frame left it: the
    // frame and the icon are drawn before the field says. Kept under the
    // frame's own id, so each box glows for its own field.
    const had = c.state(struct { on: bool = false }, "input-box");
    const lit = had.on and !opts.disabled;
    var frame = surface.open(c, opts.card, .{ .fill = t.surface, .border = t.border, .px = 12, .py = 8, .gap = 8, .scale = k }).row().itemsCenter();
    if (lit) frame = frame.border(col.alpha(0.7));
    if (lit and opts.glow > 0) frame = frame.shadow(.{ .color = col.alpha(opts.glow), .blur = 20 * k, .y = 0 });
    if (opts.disabled) frame = frame.opacity(focus.dimmed);
    defer frame.end();
    if (opts.icon.len > 0) ui.icon(c, opts.icon, .{ .size = 14 * k, .color = if (lit) col else t.muted });
    const size = opts.text_size orelse opts.size.text();
    const hidden = if (opts.shown) |s| !s.* else false;
    const name = if (opts.label.len > 0) opts.label else opts.placeholder;
    if (opts.disabled) {
        had.on = false;
        const text = buffer.text();
        const words = if (text.len == 0) opts.placeholder else if (hidden) parts.dots(c, text) else text;
        const at = parts.oneLine(c, words, .{ .size = size, .mono = opts.mono, .color = if (text.len == 0) t.muted else t.foreground });
        ui.access.describe(c, at, .{ .role = .text_field, .label = name, .value = if (hidden) "" else text, .enabled = false });
        return .{};
    }
    // The field is the next box: its index, to name it.
    const at: u32 = @intCast(c.nodes.items.len);
    const field = ui.textField(c, buffer, .{ .placeholder = opts.placeholder, .width = .fill, .size = size, .mono = opts.mono, .password = hidden, .bare = true, .caret_color = col });
    // nanoui names a field by its placeholder and tells a password's text.
    if (at < c.nodes.items.len and (opts.label.len > 0 or hidden)) parts.redescribe(c, at, opts.label, if (hidden) "" else buffer.text());
    if (field.focused != had.on) {
        had.on = field.focused;
        c.frameIn(0);
    }
    var r: Result = .{ .field = field };
    // A click on a button gives the field the keyboard back, so typing
    // goes on; the keys leave it on the button.
    if (opts.shown) |s| {
        ui.key(c, "input-box-eye");
        // The eye says how the secret stands: crossed out while hidden,
        // which nanoui draws everywhere.
        const hit = buttons.iconButton(c, if (s.*) "eye" else "eye.slash", .{ .size = .xs, .tooltip = if (s.*) opts.hide_text else opts.show_text, .keep_keyboard = true });
        if (hit.clicked) {
            s.* = !s.*;
            if (!hit.focused) buffer.focus();
        }
    }
    if (opts.clearable orelse (buffer.text().len > 0 and opts.shown == null)) {
        ui.key(c, "input-box-clear");
        if (buttons.iconButton(c, "xmark", .{ .size = .xs, .tooltip = opts.clear_text, .keep_keyboard = true }).clicked) {
            r.cleared = true;
            buffer.focus();
        }
    }
    if (opts.paste) {
        ui.key(c, "input-box-paste");
        const hit = buttons.button(c, opts.paste_text, .{ .variant = .ghost, .size = .xs, .keep_keyboard = true });
        if (hit.clicked) {
            r.pasted = true;
            if (!hit.focused) buffer.focus();
        }
    }
    return r;
}

test {
    _ = @import("input_box_tests.zig");
}
