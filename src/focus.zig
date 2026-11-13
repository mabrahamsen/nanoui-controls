//! Taking the keyboard for a control whose own box mustn't take clicks,
//! shared by the grid, the sidebar and the swatches; a box that is a
//! button; and the look every control gives the keyboard's ring, when it
//! shows, and something disabled. Not a control of its own.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;

/// The ring around a control that has the keyboard: the app's
/// (`c.focus_ring`), so every focusable box shows the keyboard alike, or
/// else the theme's accent.
pub fn ring(c: *ui.Context) ui.Color {
    return ringIn(c, kit.tokens(c).primary.alpha(0.6));
}

/// The ring for a control tinted its own way: the app's, or else `color`.
pub fn ringIn(c: *const ui.Context, color: ui.Color) ui.Color {
    return if (c.focus_ring) |r| r.color else color;
}

/// The ring's width: the app's, or a point.
pub fn ringWidth(c: *const ui.Context) f32 {
    return if (c.focus_ring) |r| r.width else 1;
}

/// When a control's ring shows.
pub const RingShows = enum {
    /// Whenever the control has the keyboard, as nanoui rings a focusable
    /// box.
    focused,
    /// Only while the keyboard is in use (`c.keyboard_modality`: a key
    /// shows it, the pointer hides it), as on a Mac; and a click on a
    /// control that is a button leaves the keyboard where it was.
    keyboard,
};

/// When every control's ring shows: the app's, set once with
/// `setRingShows`.
var ring_shows: RingShows = .focused;

/// Sets when every control's ring shows, once, as the app sets
/// `c.focus_ring`.
pub fn setRingShows(shows: RingShows) void {
    ring_shows = shows;
}

/// A control that has the keyboard (`focused`) shows its ring now.
pub fn showRing(c: *const ui.Context, focused: bool) bool {
    return focused and (ring_shows == .focused or c.keyboard_modality);
}

/// Interacts with a box that is a button, `focusable` or not, as
/// `c.interact` does: Tab reaches it, and Enter or Space clicks it. With
/// `.keyboard`, a click on it leaves the keyboard where it was, and the
/// ring nanoui draws round it (the app's `c.focus_ring`) comes off while
/// the pointer is in use; the control draws its own ring when
/// `showRing` says.
pub fn button(c: *ui.Context, index: u32, focusable: bool) ui.Interaction {
    const style = c.node(index).style;
    const was = c.focus;
    var it = c.interact(index, .{ .focusable = focusable });
    if (ring_shows == .focused) return it;
    if (c.input.pressed and was != it.id and c.focus == it.id) {
        c.focus = was;
        it.focused = false;
    }
    if (!showRing(c, it.focused)) {
        const n = c.node(index);
        n.style.border = style.border;
        n.style.border_width = style.border_width;
    }
    return it;
}

/// A key, as `c.input.key` has it.
pub const Key = @typeInfo(@FieldType(@FieldType(ui.Context, "input"), "key")).optional.child;

/// Takes the shortcut nanoui offers for a key in `keys` before the key
/// itself (on the Mac, every key, while no text field has the keyboard),
/// and makes it that key, for a control with the keyboard to
/// handle as it does the key: its keys are then its own, and the app's
/// shortcuts don't see them first. Not with ⌘, ⌃ or ⌥, nor with a Shift
/// that `c.input.shift` doesn't say, so the control reads the key as it
/// was pressed.
pub fn keysOf(c: *ui.Context, keys: []const Key) void {
    const s = c.input.shortcut orelse return;
    if (s.cmd or s.ctrl or s.alt or s.shift != c.input.shift) return;
    const S = ui.Shortcut;
    const key: Key = switch (s.key) {
        S.up => .up,
        S.down => .down,
        S.left => .left,
        S.right => .right,
        S.home => .home,
        S.end => .end,
        S.page_up => .page_up,
        S.page_down => .page_down,
        S.enter => .enter,
        S.escape => .escape,
        S.backspace => .backspace,
        else => return,
    };
    if (std.mem.indexOfScalar(Key, keys, key) == null or !c.shortcut(s)) return;
    c.input.key = key;
}

/// The opacity of something disabled: there, but not now.
pub const dimmed = 0.45;

/// A box of no size, made in the open `box`, that takes the keyboard for
/// it: from Tab, from a click the control passes on (`c.focus = own.id`),
/// or from `c.focusNext` just before `box` was made, which names `box`
/// and is moved to it. It has no size, as `box` taking clicks would take
/// them from what is in it, such as a scrollbar.
pub fn take(c: *ui.Context, box: ui.Div) ui.Interaction {
    return takeIf(c, box, true);
}

/// As `take`, when the control `wants` the keyboard: one that is disabled
/// or has nothing in it doesn't take Tab. The box is made either way, so
/// what follows it keeps its place. It is focused only while it wants the
/// keyboard: disabled with it, it takes no key in that frame.
pub fn takeIf(c: *ui.Context, box: ui.Div, wants: bool) ui.Interaction {
    const taker = ui.div(c).absolute().w(0).h(0);
    // The control takes Enter and Space itself, and draws its own ring, as
    // a text field does: nanoui is not to click it with them.
    var own = c.interact(taker.index, .{ .focusable = wants, .text = true });
    taker.end();
    // nanoui says a box is focused while the keyboard is on it, until the
    // frame ends, whether it still takes the keyboard or not.
    if (!wants) own.focused = false;
    if (wants and c.focus == c.node(box.index).id) {
        c.focus = own.id;
        own.focused = true;
    }
    return own;
}

test {
    _ = @import("focus_tests.zig");
}
