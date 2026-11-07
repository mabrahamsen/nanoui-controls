//! Taking the keyboard for a control whose own box mustn't take clicks,
//! shared by the grid and the sidebar. Not a control of its own.
const nanoui = @import("nanoui");
const ui = nanoui.ui;

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
