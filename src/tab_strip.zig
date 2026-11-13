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
//!
//! Tabs too many for the strip scroll sideways, by the wheel either way
//! and the trackpad, between chevrons at its ends that page through them;
//! the chosen tab is scrolled into view as it changes.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const focus = @import("focus.zig");
const measure = @import("measure.zig");
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
    const kept = c.state(Kept, "tab-strip");
    // Whether the frame last laid out had chevrons, which its sizes leave
    // out of the tabs' room.
    if (kept.frame != c.frame) {
        kept.laid = kept.over;
        kept.frame = c.frame;
    }
    // The tabs in a box that scrolls sideways, taking the room the line
    // leaves; too many for it, between chevrons that page through them.
    const back = kept.over and chevron(c, "chevron.left", kept.offset > 0.5, size, k);
    // Keyed, so the chevron before it doesn't make it another box.
    ui.key(c, "tab-strip-tabs");
    var view = ui.div(c).row().w(0).grow();
    c.node(view.index).style.scroll_x = true;
    c.node(view.index).style.scroll_bar = false;
    if (kept.over) view = view.wheel();
    const view_id = c.node(view.index).id;
    const offset = c.scroll_x.get(view_id) orelse 0;
    const tabs_row = ui.div(c).row().gap(2 * k).itemsCenter();
    var chosen: ?ui.Rect = null;
    for (tabs, 0..) |tab, i| {
        const on = index.* == i;
        const off = opts.disabled or tab.disabled;
        // Keyed by place: labels may repeat, or be empty.
        ui.keyInt(c, i);
        const col = ui.div(c).column();
        defer col.end();
        if (on) chosen = c.rects.get(c.node(col.index).id);
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
    // Where the tabs start, and how wide they and their room are, as the
    // last frame laid them out.
    const tabs_at = c.rects.get(c.node(tabs_row.index).id);
    const tabs_size = measure.lastSize(c, tabs_row.index);
    tabs_row.end();
    const room = measure.lastSize(c, view.index);
    // The wheel pans the tabs, across or down, while the pointer is over
    // them, rather than a page they are in.
    if (kept.over and view.hovered()) {
        c.wants_wheel = true;
        const d = c.input.scroll.x + c.input.scroll.y;
        if (d != 0) c.setScroll(view_id, .x, offset - d);
    }
    view.end();
    var forward = false;
    if (tabs_size) |ts| if (room) |last| {
        // The room without chevrons, and with them if the tabs overflow it.
        const chevrons = 2 * (chevron_w + 2) * k;
        const whole = last.w + if (kept.laid) chevrons else 0;
        const was = kept.over;
        kept.over = ts.w > whole + 0.5;
        // The chevrons come or go in this frame, built again.
        if (kept.over != was) c.changed = true;
        const r: ui.Size = .{ .w = whole - if (kept.over) chevrons else 0, .h = last.h };
        const most = @max(0, ts.w - r.w);
        if (kept.over) forward = chevron(c, "chevron.right", offset < most - 0.5, size, k);
        // A page, less a little, so a tab cut at the edge shows whole.
        const page = r.w * 0.8;
        if (back) c.setScroll(view_id, .x, offset - page);
        if (forward) c.setScroll(view_id, .x, @min(most, offset + page));
        // The chosen tab into view each time it changes, or the tabs come
        // to overflow, until it is: the room narrows as the chevrons come.
        if (!kept.over) kept.revealed = null else if (kept.revealed != index.*) if (chosen) |ch| if (tabs_at) |at| {
            const x = ch.x - at.x;
            if (x < offset - 0.5) {
                c.setScroll(view_id, .x, x);
                c.changed = true;
            } else if (x + ch.w > offset + r.w + 0.5) {
                c.setScroll(view_id, .x, x + ch.w - r.w);
                c.changed = true;
            } else kept.revealed = index.*;
        };
        kept.offset = c.scroll_x.get(view_id) orelse 0;
    };
    return .{ .c = c, .strip = strip, .row = row, .group = g };
}

/// What a tab strip keeps between frames.
const Kept = struct {
    /// The tabs are wider than their room, and have chevrons.
    over: bool = false,
    /// They had them in the frame last laid out, `frame`.
    laid: bool = false,
    frame: u64 = 0,
    /// How far they are scrolled.
    offset: f32 = 0,
    /// The tab last scrolled into view.
    revealed: ?usize = null,
};

/// A chevron's width and height, in points before `scale`.
const chevron_w: f32 = 20;

/// A chevron at an end of tabs that overflow, which pages through them
/// that way while there is more; clicked, it leaves the keyboard where it
/// was. Left out for a screen reader, which reaches each tab.
fn chevron(c: *ui.Context, icon: []const u8, more: bool, size: f32, k: f32) bool {
    const t = kit.tokens(c);
    var b = ui.div(c).w(chevron_w * k).h(chevron_w * k).center().rounded(5 * k);
    defer b.end();
    const was = c.focus;
    const it = c.interact(b.index, .{});
    c.focus = was;
    if (more and it.hovered) {
        c.cursor_hand = true;
        b = b.bg(t.surface_hover);
    }
    ui.access.hide(c, b.index);
    ui.icon(c, icon, .{ .size = (size - 2) * k, .color = if (more) t.muted else t.muted.alpha(0.35) });
    return more and it.clicked;
}

test {
    _ = @import("tab_strip_tests.zig");
}
