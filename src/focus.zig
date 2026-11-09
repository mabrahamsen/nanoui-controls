//! Taking the keyboard for a control whose own box mustn't take clicks,
//! shared by the grid, the sidebar and the swatches; and the look every
//! control gives the keyboard's ring and something disabled. Not a
//! control of its own.
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
/// what follows it keeps its place.
pub fn takeIf(c: *ui.Context, box: ui.Div, wants: bool) ui.Interaction {
    const taker = ui.div(c).absolute().w(0).h(0);
    // The control takes Enter and Space itself, and draws its own ring, as
    // a text field does: nanoui is not to click it with them.
    var own = c.interact(taker.index, .{ .focusable = wants, .text = true });
    taker.end();
    if (wants and c.focus == c.node(box.index).id) {
        c.focus = own.id;
        own.focused = true;
    }
    return own;
}
