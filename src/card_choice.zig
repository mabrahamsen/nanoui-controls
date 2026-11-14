//! A card choice: one choice out of several, as cards of one width that
//! run on to new rows where the width ends, each card's content the
//! caller's (a preview, a picture, lines of its own). `segmented` and
//! `tabStrip` choose among labels; this among what the caller draws.
//!
//! One stop for Tab, heard as radio buttons named by `labels`: while it
//! has the keyboard, Left and Right choose the card before and after, Up
//! and Down the one a row up or down, and Home and End the first and the
//! last, passing disabled cards. A click on a card chooses it and gives
//! the group the keyboard. The chosen card is tinted in the accent and
//! outlined in it.
//!
//!     var cc = controls.cardChoice(c, &names, &s.theme, .{ .cell_width = 132, .label = "Theme" });
//!     while (cc.next()) |i| {
//!         preview(c, themes[i]);
//!         ui.text(c, names[i], .{ .size = 12, .weight = .semibold });
//!     }
//!     if (cc.end()) s.save();
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const focus = @import("focus.zig");
const parts = @import("parts.zig");
const surface = @import("surface.zig");
const Surface = surface.Surface;
const flow_mod = @import("flow.zig");

pub const Options = struct {
    /// Each card's width, in points before `scale`; with `fill`, the
    /// narrowest a card gets as they share each row's width.
    cell_width: f32 = 160,
    fill: bool = false,
    /// Between the cards in a row, and between the rows, in points before
    /// `scale`.
    gap: f32 = 8,
    row_gap: f32 = 8,
    /// A card's look over its own: the theme's surface and border, 8
    /// points of padding and 6 between what is in it.
    card: Surface = .{},
    /// What the choice is, said by a screen reader after each card.
    label: []const u8 = "",
    /// Dimmed, it doesn't change or take the keyboard, and is said to be
    /// unavailable.
    disabled: bool = false,
    /// Cards that can't be chosen, one flag a card, or none: dimmed, not
    /// chosen by a click, and passed by the keys.
    disabled_cards: []const bool = &.{},
    scale: f32 = 1,
};

/// Where the choice is kept: a card's index, or one that may be none.
const Index = union(enum) {
    one: *usize,
    maybe: *?usize,

    fn get(i: Index) ?usize {
        return switch (i) {
            .one => |p| p.*,
            .maybe => |p| p.*,
        };
    }

    fn set(i: Index, v: usize) void {
        switch (i) {
            .one => |p| p.* = v,
            .maybe => |p| p.* = v,
        }
    }
};

/// The cards named `labels`, `index` the one chosen: a `*usize`, or a
/// `*?usize` for a choice that may be none. Draw each card's content
/// while `next` returns its index, then `end` it.
pub fn cardChoice(c: *ui.Context, labels: []const []const u8, index: anytype, opts: Options) CardChoice {
    const at: Index = switch (@TypeOf(index)) {
        *usize => .{ .one = index },
        *?usize => .{ .maybe = index },
        else => @compileError("cardChoice: `index` is a *usize or a *?usize"),
    };
    var box = ui.div(c).column().wFull();
    if (opts.disabled) box = box.opacity(focus.dimmed);
    var cc: CardChoice = .{ .c = c, .labels = labels, .opts = opts, .index = at, .box = box, .own = undefined, .flow = undefined };
    // An index past the last card moves to the last that can be chosen.
    if (at.get()) |i| if (labels.len > 0 and i >= labels.len) {
        const to = cc.seek(labels.len, -1) orelse labels.len - 1;
        if (to != i) cc.changed = true;
        at.set(to);
    };
    cc.own = focus.takeIf(c, box, !opts.disabled and cc.seek(null, 1) != null);
    cc.flow = flow_mod.flow(c, opts.cell_width, .{ .gap = opts.gap, .row_gap = opts.row_gap, .fill = opts.fill, .scale = opts.scale });
    cc.keys();
    return cc;
}

/// An open card choice: draw each card's content while `next` returns its
/// index, then `end` it.
pub const CardChoice = struct {
    c: *ui.Context,
    labels: []const []const u8,
    opts: Options,
    index: Index,
    box: ui.Div,
    own: ui.Interaction,
    flow: flow_mod.Flow,
    /// The next card's index.
    at: usize = 0,
    /// The card open: its cell, its box and its content's.
    cell: ?ui.Div = null,
    card: ?ui.Div = null,
    content: ?ui.Div = null,
    changed: bool = false,

    /// Ends the card open and opens the next, a column for its content,
    /// returning its index; null after the last.
    pub fn next(cc: *CardChoice) ?usize {
        cc.endCard();
        if (cc.at >= cc.labels.len) return null;
        const i = cc.at;
        cc.at += 1;
        const c = cc.c;
        const k = cc.opts.scale;
        const t = kit.tokens(c);
        const on = cc.isChosen(i);
        const off = cc.opts.disabled or cc.cardOff(i);
        // Keyed by place: labels may repeat.
        ui.keyInt(c, i);
        const cell = cc.flow.cell();
        var card = surface.open(c, cc.opts.card, .{ .fill = t.surface, .border = t.border, .px = 8, .py = 8, .gap = 6, .scale = k });
        if (on) card = card.bg((cc.opts.card.fill orelse t.surface).mix(t.primary, 0.1)).border(t.primary).borderW(2);
        if (cc.cardOff(i) and !cc.opts.disabled) card = card.opacity(focus.dimmed);
        // The ring on the card the keys are on: the chosen one, or the
        // first that can be chosen.
        const keys_on = cc.index.get() orelse cc.seek(null, 1);
        if (focus.showRing(c, cc.own.focused) and keys_on == i) card = card.border(focus.ring(c)).borderW(@max(2, focus.ringWidth(c)));
        const it = if (off) parts.still(c, card) else card.interaction();
        if (it.hovered and !off and !on) c.cursor_hand = true;
        if (it.clicked and !off) {
            if (c.focus != cc.own.id) c.changed = true;
            c.focus = cc.own.id;
            if (!on) {
                cc.index.set(i);
                cc.changed = true;
            }
        }
        ui.access.describe(c, card.index, .{ .role = .radio_button, .label = cc.labels[i], .hint = cc.opts.label, .selected = cc.isChosen(i), .enabled = !off });
        // The caller's content, heard as the card's name, not on its own.
        const content = ui.div(c).column().wFull().gap((cc.opts.card.gap orelse 6) * k);
        ui.access.hide(c, content.index);
        cc.cell = cell;
        cc.card = card;
        cc.content = content;
        return i;
    }

    /// Card `i` is the one chosen.
    pub fn isChosen(cc: *const CardChoice, i: usize) bool {
        return cc.index.get() == i;
    }

    /// Ends the cards; true when a click or a key changed the choice this
    /// frame.
    pub fn end(cc: *CardChoice) bool {
        cc.endCard();
        cc.flow.end();
        cc.box.end();
        if (cc.changed) cc.c.changed = true;
        return cc.changed;
    }

    fn endCard(cc: *CardChoice) void {
        if (cc.content) |d| d.end();
        if (cc.card) |d| d.end();
        if (cc.cell) |d| d.end();
        cc.content = null;
        cc.card = null;
        cc.cell = null;
    }

    /// Card `i` can't be chosen on its own.
    fn cardOff(cc: *const CardChoice, i: usize) bool {
        return i < cc.opts.disabled_cards.len and cc.opts.disabled_cards[i];
    }

    /// The first card that can be chosen from `from` (exclusive; null:
    /// before the first, `labels.len`: after the last), a step of `step`
    /// at a time.
    fn seek(cc: *const CardChoice, from: ?usize, step: isize) ?usize {
        var i: isize = if (from) |f| @as(isize, @intCast(f)) + step else if (step > 0) 0 else @as(isize, @intCast(cc.labels.len)) - 1;
        while (i >= 0 and i < cc.labels.len) : (i += step) {
            if (!cc.cardOff(@intCast(i))) return @intCast(i);
        }
        return null;
    }

    /// Moves the choice as the keys ask, while the group has the keyboard,
    /// before the cards are drawn for them to show it. The keys it moves
    /// by are used up, even at an end.
    fn keys(cc: *CardChoice) void {
        const c = cc.c;
        if (!cc.own.focused or cc.opts.disabled or cc.labels.len == 0) return;
        focus.keysOf(c, &.{ .left, .right, .up, .down, .home, .end });
        const key = c.input.key orelse return;
        const row: isize = @intCast(cc.flow.per_row);
        const now = cc.index.get();
        const to = switch (key) {
            .left => if (now) |i| cc.seek(i, -1) else cc.seek(null, 1),
            .right => if (now) |i| cc.seek(i, 1) else cc.seek(null, 1),
            .up => if (now) |i| cc.seek(i, -row) else cc.seek(null, 1),
            .down => if (now) |i| cc.seek(i, row) else cc.seek(null, 1),
            .home => cc.seek(null, 1),
            .end => cc.seek(cc.labels.len, -1),
            else => return,
        };
        c.input.key = null;
        const i = to orelse return;
        if (now == i) return;
        cc.index.set(i);
        cc.changed = true;
    }
};

test {
    _ = @import("card_choice_tests.zig");
}
