//! A tab strip: tabs that read as tabs, each a name with a count in a
//! badge, the chosen one in full text with an accent bar under it, all on
//! a rule. The kit's `tabs`, with the keyboard (one stop for Tab, the
//! arrows choosing), counts, a spinner while a count loads, and an alert.
//!
//!     const tabs = [_]controls.Choice{
//!         .{ .label = "Reviews", .count = 3 },
//!         .{ .label = "Failed runs", .count = 1, .alert = true },
//!         .{ .label = "Work", .loading = true },
//!     };
//!     if (controls.tabStrip(c, &tabs, &s.tab, .{})) s.scrollToTop();
//!
//! `tabStripOf` keeps the chosen tab as a value of an enum, and
//! `tabStripOpen` leaves the tabs' line open for a button at its end.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const focus = @import("focus.zig");
const choices_mod = @import("choices.zig");
const Choice = choices_mod.Choice;

pub const Options = struct {
    /// The names' size, as the kit's; `text_size` in points, over it. The
    /// badges' text is the kit's at `.xs`.
    size: kit.Size = .sm,
    text_size: ?f32 = null,
    /// A count past it shows as "999+".
    max_count: usize = 999,
    /// What a screen reader says of a tab still loading its count.
    loading_text: []const u8 = "loading",
    /// Dimmed, it doesn't change or take the keyboard, and is said to be
    /// unavailable.
    disabled: bool = false,
    scale: f32 = 1,
};

/// `tabs`, `index` the one chosen; true when a click or a key changed it.
pub fn tabStrip(c: *ui.Context, tabs: []const Choice, index: *usize, opts: Options) bool {
    var strip = tabStripOpen(c, tabs, index, opts);
    return strip.end();
}

/// As `tabStrip`, the chosen tab kept as `value`, a value of the enum `E`:
/// `tabs` has one for each of its values, in their order. True when a
/// click or a key changed `value`.
pub fn tabStripOf(c: *ui.Context, comptime E: type, value: *E, tabs: *const [choices_mod.Typed(E).count]Choice, opts: Options) bool {
    const T = choices_mod.Typed(E);
    var at = T.index(value.*);
    if (!tabStrip(c, tabs, &at, opts)) return false;
    value.* = T.all[at];
    return true;
}

/// A tab strip left open after its tabs, on their line, for what goes at
/// its end (a button); `end` draws the rule under both and says whether a
/// click or a key changed the tab.
pub const TabStripOpen = struct {
    // The strip's own: callers use `end`.
    c: *ui.Context,
    strip: ui.Div,
    row: ui.Div,
    group: choices_mod.Group,

    pub fn end(t: *TabStripOpen) bool {
        t.row.end();
        ui.div(t.c).wFull().h(1).bg(kit.tokens(t.c).border).end();
        t.strip.end();
        return t.group.end(t.c);
    }
};

/// The tabs, open after them for the caller's own at the line's end; the
/// caller `end`s it.
pub fn tabStripOpen(c: *ui.Context, tabs: []const Choice, index: *usize, opts: Options) TabStripOpen {
    const k = opts.scale;
    const t = kit.tokens(c);
    const size = opts.text_size orelse opts.size.text();
    var strip = ui.div(c).column().wFull();
    if (opts.disabled) strip = strip.opacity(focus.dimmed);
    // One stop for Tab: the arrows, Home and End choose a tab; a click
    // gives it the keyboard too. The chosen tab shows the ring.
    var g = choices_mod.Group.take(c, strip, index, tabs, opts.disabled);
    g.keys(c);
    const row = ui.div(c).row().wFull().gap(2 * k).itemsCenter();
    for (tabs, 0..) |tab, i| {
        const on = index.* == i;
        const off = opts.disabled or tab.disabled;
        // Keyed by place: labels may repeat, or be empty.
        ui.keyInt(c, i);
        const col = ui.div(c).column();
        defer col.end();
        var head = ui.div(c).row().itemsCenter().gap(7 * k).px(12 * k).py(7 * k).rounded(7 * k).control();
        if (!on and !off) head = head.hover(t.surface_hover);
        if (tab.disabled and !opts.disabled) head = head.opacity(focus.dimmed);
        const hit = g.interact(c, head, i);
        if (on and g.ringed(c)) head = head.border(focus.ring(c)).borderW(focus.ringWidth(c));
        {
            defer head.end();
            const ink = if (on) t.foreground else t.muted;
            if (tab.icon.len > 0) ui.icon(c, tab.icon, .{ .size = size * k, .color = ink });
            ui.text(c, tab.label, .{ .size = size, .weight = if (on) .semibold else .medium, .color = ink });
            if (tab.count != null or tab.loading) choices_mod.badge(c, tab, on, opts.max_count, k);
        }
        const bar = ui.div(c).wFull().h(2 * k).rounded(1 * k);
        (if (on) bar.bg(t.primary) else bar).end();
        ui.access.describe(c, head.index, .{ .role = .tab, .label = tab.label, .value = choices_mod.countText(c, tab, opts.loading_text), .selected = on, .enabled = !off });
        g.click(c, i, hit);
    }
    ui.spacer(c);
    return .{ .c = c, .strip = strip, .row = row, .group = g };
}

test {
    _ = @import("tab_strip_tests.zig");
}
