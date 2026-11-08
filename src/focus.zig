//! Taking the keyboard for a control whose own box mustn't take clicks,
//! shared by the grid, the sidebar and the swatches; and the look every
//! control gives the keyboard's ring and something disabled. Not a
//! control of its own.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;

/// The ring around a control that has the keyboard, in the theme's
/// accent.
pub fn ring(c: *ui.Context) ui.Color {
    return ringIn(kit.tokens(c).primary);
}

/// The ring in `color`, for a control tinted its own way.
pub fn ringIn(color: ui.Color) ui.Color {
    return color.alpha(0.6);
}

/// The opacity of something disabled: there, but not now.
pub const dimmed = 0.45;

/// A box of no size, made in the open `box`, that takes the keyboard for
/// it: from Tab, from a click the control passes on (`c.focus = own.id`),
/// or from `c.focusNext` just before `box` was made, which names `box`
/// and is moved to it. It has no size, as `box` taking clicks would take
/// them from what is in it, such as a scrollbar.
pub fn take(c: *ui.Context, box: ui.Div) ui.Interaction {
    const taker = ui.div(c).absolute().w(0).h(0);
    var own = c.interact(taker.index, .{ .focusable = true });
    taker.end();
    if (c.focus == c.node(box.index).id) {
        c.focus = own.id;
        own.focused = true;
    }
    return own;
}
