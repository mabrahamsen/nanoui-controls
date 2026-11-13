//! Chips: short values as pills. `chipInput` is a field of them to type
//! into (times, rules, extensions), each with a × to remove it; `chip` is
//! an option shown as a chip that is on or off.
//!
//! The caller keeps the values, and the text being typed:
//!
//!     const r = controls.chipInput(c, s.times.items, &s.time_field, .{ .placeholder = "9:00", .invalid = s.bad_times });
//!     for (r.added) |v| try s.addTime(v);
//!     if (r.removed) |i| s.removeTime(i);
//!
//!     if (controls.chip(c, "Grouped", &s.grouped, .{})) s.regroup();
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const focus = @import("focus.zig");
const measure = @import("measure.zig");
const parts = @import("parts.zig");
const pill_mod = @import("pill.zig");
const surface = @import("surface.zig");

pub const InputOptions = struct {
    /// One flag a chip, kept by the caller: a flagged chip doesn't read,
    /// and is drawn in the danger color. Shorter than the chips, the rest
    /// read.
    invalid: []const bool = &.{},
    /// What a tooltip and a screen reader say of a chip that doesn't read.
    invalid_text: []const u8 = "doesn't read",
    /// Values from elsewhere, before the chips: muted, without a ×.
    inherited: []const []const u8 = &.{},
    /// What an inherited chip is, in its tooltip and to a screen reader.
    inherited_note: []const u8 = "inherited",
    /// In the empty field while there are no chips, and once there are.
    placeholder: []const u8 = "",
    add_placeholder: []const u8 = "",
    /// A chip's × to a screen reader, `{}` standing for the chip:
    /// "Remove 9:00".
    remove_text: []const u8 = "Remove {}",
    /// Typed or pasted, each of these characters ends a chip; Enter and a
    /// line's end always do.
    separators: []const u8 = ",",
    /// The room the field keeps for typing, in points before `scale`: a
    /// line with less left starts a new one for it.
    field_width: f32 = 110,
    /// The parent's width by default; a width in points is multiplied by
    /// `scale`.
    width: ui.Length = .fill,
    /// The text's size, as the kit's; `text_size` in points, over it.
    size: kit.Size = .sm,
    text_size: ?f32 = null,
    mono: bool = false,
    /// Dimmed, its chips without their × and no field: values that can't
    /// change now.
    disabled: bool = false,
    scale: f32 = 1,
};

/// What the user did this frame, for the caller to apply to its values.
pub const InputResult = struct {
    /// The chips made this frame, trimmed, none empty, in the frame's
    /// memory: the caller adds them.
    added: []const []const u8 = &.{},
    /// The chip closed, by its × or by Backspace in the empty field: an
    /// index into the chips.
    removed: ?usize = null,
    /// The field has the keyboard.
    focused: bool = false,
};

/// `chips` as pills, each with a × that Tab reaches, then a field to type
/// the next into, `buffer` its text. A separator or Enter ends a chip;
/// pasting text with separators makes several; Backspace in the empty
/// field removes the last. The chips wrap where the width ends.
pub fn chipInput(c: *ui.Context, chips: []const []const u8, buffer: *ui.TextBuffer, opts: InputOptions) InputResult {
    const t = kit.tokens(c);
    const k = opts.scale;
    const style: ui.TextStyle = .{ .size = opts.text_size orelse opts.size.text(), .mono = opts.mono };
    var result: InputResult = .{};

    const pad: f32 = 8;
    var box = ui.div(c).column().px(pad * k).py(6 * k).gap(6 * k).rounded(t.radius * k).bg(t.surface).border(t.border);
    if (opts.disabled) box = box.opacity(focus.dimmed);
    c.node(box.index).style.width = surface.scaled(opts.width, k);
    defer box.end();
    // The room for chips: the box's width as the last frame laid it out,
    // or in its first, the window's.
    const width = (if (measure.lastSize(c, box.index)) |s| s.w else c.size.w) - 2 * pad * k;
    if (!opts.disabled and box.interaction().clicked) buffer.focus();

    var rows: Rows = .{ .c = c, .width = width, .gap = 6 * k };
    for (opts.inherited, 0..) |v, i| {
        rows.place(chipWidth(c, v, style, k, false));
        ui.key(c, c.print("inherited-{d}", .{i}));
        _ = chip_(c, v, .{ .style = style, .k = k, .color = t.muted, .closes = false, .tooltip = opts.inherited_note });
    }
    for (chips, 0..) |v, i| {
        rows.place(chipWidth(c, v, style, k, !opts.disabled));
        const ok = i >= opts.invalid.len or !opts.invalid[i];
        ui.key(c, c.print("chip-{d}", .{i}));
        // Its × goes with the chip: the field takes the keyboard, by a
        // click or by the keys alike.
        if (chip_(c, v, .{ .style = style, .k = k, .color = if (ok) t.foreground else t.danger, .closes = !opts.disabled, .tooltip = if (ok) "" else opts.invalid_text, .remove_text = opts.remove_text })) {
            result.removed = i;
            buffer.focus();
        }
    }
    if (opts.disabled) {
        rows.end();
        return result;
    }
    // The field, in what is left of the last line, or a line of its own.
    rows.place(opts.field_width * k);
    const empty_before = buffer.text().len == 0;
    {
        const f = ui.div(c).row().w(0).grow();
        defer f.end();
        const r = ui.textField(c, buffer, .{ .bare = true, .width = .fill, .size = style.size, .mono = opts.mono, .placeholder = if (chips.len == 0 and opts.inherited.len == 0) opts.placeholder else opts.add_placeholder });
        result.focused = r.focused;
        result.added = take(c, buffer, opts.separators, r.submitted);
    }
    rows.end();
    // Backspace with nothing typed takes the last chip back.
    if (result.focused and empty_before and chips.len > 0 and backspaced(c)) result.removed = chips.len - 1;
    // What the caller removes shows in this frame.
    if (result.removed != null) c.changed = true;
    if (result.focused) c.node(box.index).style.border = t.primary;
    return result;
}

/// Backspace was pressed this frame, as a key or as a text field's command
/// (as the Mac's text system sends it).
fn backspaced(c: *ui.Context) bool {
    if (c.input.key == .backspace) return true;
    for (c.input.ops) |op| switch (op) {
        .command => |cmd| if (cmd == .delete_backward) return true,
        else => {},
    };
    return false;
}

/// The chips typed into `buffer`: those ended by a separator or a line's
/// end, and with Enter (`submitted`) the rest; what follows the last
/// separator stays. Separators are whole characters, any of `separators`.
fn take(c: *ui.Context, buffer: *ui.TextBuffer, separators: []const u8, submitted: bool) []const []const u8 {
    const text = buffer.text();
    var out: std.ArrayList([]const u8) = .empty;
    var start: usize = 0;
    var ended = false;
    var i: usize = 0;
    while (i < text.len) {
        const n = @min(text.len - i, std.unicode.utf8ByteSequenceLength(text[i]) catch 1);
        const ch = text[i .. i + n];
        if (isSeparator(ch, separators)) {
            add(c, &out, text[start..i]);
            start = i + n;
            ended = true;
        }
        i += n;
    }
    if (submitted) {
        add(c, &out, text[start..]);
        start = text.len;
    } else if (!ended) return &.{};
    buffer.set(c.print("{s}", .{std.mem.trimStart(u8, text[start..], " ")}));
    return out.items;
}

/// `ch`, one character, ends a chip: a line's end, or one of `separators`.
fn isSeparator(ch: []const u8, separators: []const u8) bool {
    if (std.mem.eql(u8, ch, "\n") or std.mem.eql(u8, ch, "\r")) return true;
    var i: usize = 0;
    while (i < separators.len) {
        const n = @min(separators.len - i, std.unicode.utf8ByteSequenceLength(separators[i]) catch 1);
        if (std.mem.eql(u8, ch, separators[i .. i + n])) return true;
        i += n;
    }
    return false;
}

/// Adds `piece`, trimmed, to the chips made, unless it is empty.
fn add(c: *ui.Context, out: *std.ArrayList([]const u8), piece: []const u8) void {
    const v = std.mem.trim(u8, piece, " \t");
    if (v.len > 0) out.append(c.alloc(), c.print("{s}", .{v})) catch {};
}

/// Boxes placed in lines that run on to a new one where `width` ends:
/// `place` each box's width just before making it, then `end`.
const Rows = struct {
    c: *ui.Context,
    width: f32,
    gap: f32,
    row: ?ui.Div = null,
    used: f32 = 0,

    fn place(r: *Rows, w: f32) void {
        // A point to spare: text measured and laid out may round apart.
        if (r.row == null or (r.used > 0 and r.used + r.gap + w > r.width - 1)) {
            if (r.row) |row| row.end();
            r.row = ui.div(r.c).row().wFull().itemsCenter().gap(r.gap);
            r.used = 0;
        }
        r.used += (if (r.used > 0) r.gap else 0) + w;
    }

    fn end(r: *Rows) void {
        if (r.row) |row| row.end();
        r.row = null;
    }
};

const chip_px: f32 = 8;
const close_w: f32 = 14;
const close_gap: f32 = 3;

fn chipWidth(c: *ui.Context, v: []const u8, style: ui.TextStyle, k: f32, closes: bool) f32 {
    return @ceil(c.text.width(v, style)) + 2 * chip_px * k + if (closes) (close_gap + close_w) * k else 0;
}

const ChipLook = struct {
    style: ui.TextStyle,
    k: f32,
    color: ui.Color,
    closes: bool,
    tooltip: []const u8,
    remove_text: []const u8 = "",
};

/// A value as a pill, with a × after it that Tab reaches and Space or
/// Enter presses; true when it was.
fn chip_(c: *ui.Context, v: []const u8, s: ChipLook) bool {
    const t = kit.tokens(c);
    const k = s.k;
    const box = pill_mod.pillOpen(c, v, .{
        .color = s.color,
        .text_size = s.style.size,
        .mono = s.style.mono,
        .weight = .regular,
        .fill = 0.12,
        .edge = 0.35,
        .px = chip_px,
        .py = 2,
        .gap = close_gap,
        .tooltip = s.tooltip,
        .scale = k,
    });
    defer box.end();
    if (!s.closes) return false;
    var x = ui.div(c).w(close_w * k).h(close_w * k).center().roundedFull().control();
    const xi = focus.button(c, x.index, true);
    if (xi.hovered) x = x.bg(t.muted.alpha(0.25));
    if (focus.showRing(c, xi.focused)) x = x.border(focus.ring(c)).borderW(focus.ringWidth(c));
    defer x.end();
    const at = std.mem.indexOf(u8, s.remove_text, "{}");
    const name = if (at) |a| c.print("{s}{s}{s}", .{ s.remove_text[0..a], v, s.remove_text[a + 2 ..] }) else c.print("{s} {s}", .{ s.remove_text, v });
    ui.access.describe(c, x.index, .{ .role = .button, .label = name });
    ui.icon(c, "xmark", .{ .size = 8 * k, .color = t.muted });
    return xi.clicked;
}

pub const Options = struct {
    /// A dot of this color before the label, for a filter by color or a
    /// preset.
    swatch: ?ui.Color = null,
    /// The label's size, as the kit's; `text_size` in points, over it.
    size: kit.Size = .sm,
    text_size: ?f32 = null,
    /// What a screen reader says it is, on and off.
    on_text: []const u8 = "on",
    off_text: []const u8 = "off",
    /// Dimmed, it doesn't turn or take the keyboard, and is said to be
    /// unavailable.
    disabled: bool = false,
    scale: f32 = 1,
};

/// `label` as a chip that is on or off as `on` holds: on, it is outlined
/// and tinted in the accent with a ✓; off, it is plain. A click, or Space
/// or Enter once Tab reaches it, turns it; true when it did. A checkbox to
/// a screen reader.
pub fn chip(c: *ui.Context, label: []const u8, on: *bool, opts: Options) bool {
    const k = opts.scale;
    const t = kit.tokens(c);
    const size = opts.text_size orelse opts.size.text();
    var box = ui.div(c).row().itemsCenter().gap(6 * k).px(10 * k).py(5 * k).roundedFull().border(if (on.*) t.primary else t.border).control();
    if (on.*) box = box.bg(t.primary.alpha(0.1)) else if (!opts.disabled) box = box.hover(t.surface_hover);
    if (opts.disabled) box = box.opacity(focus.dimmed);
    const hit = if (opts.disabled) parts.still(c, box) else focus.button(c, box.index, true);
    if (focus.showRing(c, hit.focused)) box = box.border(focus.ring(c)).borderW(focus.ringWidth(c));
    {
        defer box.end();
        if (on.*) ui.icon(c, "checkmark", .{ .size = (size - 1.5) * k, .color = t.primary });
        if (opts.swatch) |col| parts.dot(c, col, 8 * k, 0);
        ui.text(c, label, .{ .size = size, .weight = if (on.*) .semibold else .regular, .color = if (on.*) t.foreground else t.muted });
    }
    ui.access.describe(c, box.index, .{ .role = .checkbox, .label = label, .value = if (on.*) opts.on_text else opts.off_text, .selected = on.*, .enabled = !opts.disabled });
    if (opts.disabled or !hit.clicked) return false;
    on.* = !on.*;
    // What it turns shows in this frame.
    c.changed = true;
    return true;
}

test {
    _ = @import("chips_tests.zig");
}
