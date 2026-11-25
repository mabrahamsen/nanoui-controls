//! Measuring a box: its size as the last frame laid it out, for what is
//! drawn to fit it (a chart's lines, a legend's wrapping, a flow's cells,
//! a form's stacking). Not a control of its own.
const nanoui = @import("nanoui");
const ui = nanoui.ui;

/// The size of box `index` as the last frame laid it out, or null in its
/// first frame. The box is marked as drawn from its last size, so nanoui
/// draws another frame whenever its size changes, whatever changed it (a
/// window resized, or the app's own state), and in its first frame.
pub fn lastSize(c: *ui.Context, index: u32) ?ui.Size {
    const n = c.node(index);
    n.layout_dependent = true;
    const r = c.rects.get(n.id) orelse return null;
    return .{ .w = r.w, .h = r.h };
}

/// The text just drawn, `text` in `style`, was cut short where the last
/// frame laid it out: for showing it whole in a tooltip. Call it right
/// after `ui.text`.
pub fn cutOff(c: *ui.Context, text: []const u8, style: ui.TextStyle) bool {
    const index: u32 = @intCast(c.nodes.items.len - 1);
    const r = c.rects.get(c.node(index).id) orelse return false;
    return c.text.width(text, style) > r.w + 0.5;
}
