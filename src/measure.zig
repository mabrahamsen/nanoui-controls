//! Measuring a box: its size as the last frame laid it out, for what is
//! drawn to fit it (a chart's lines, a legend's wrapping, a flow's cells,
//! a form's stacking). Not a control of its own.
const nanoui = @import("nanoui");
const ui = nanoui.ui;

/// The size of box `index` as the last frame laid it out, or null in its
/// first frame. Then, or when it changed, another frame is drawn with the
/// new one, as the grid does with its width.
pub fn lastSize(c: *ui.Context, index: u32) ?ui.Size {
    const id = c.node(index).id;
    const r = c.rects.get(id) orelse {
        c.frameIn(0);
        return null;
    };
    // Kept by the box's own id, not by where the lookup happens.
    ui.key(c, c.print("chart-size-{x}", .{id}));
    defer c.next_key = null;
    const last = c.state(struct { w: f32 = 0, h: f32 = 0 }, "chart-size");
    if (last.w != r.w or last.h != r.h) {
        last.* = .{ .w = r.w, .h = r.h };
        c.frameIn(0);
    }
    return .{ .w = r.w, .h = r.h };
}
