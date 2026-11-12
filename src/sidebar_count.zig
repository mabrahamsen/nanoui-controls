//! A sidebar row's count: a number at the row's end, as muted text or a
//! pill, a dot at its icon's corner when the sidebar is narrowed, or a
//! spinner in either place while it is loading. Not a control of its own.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const Item = @import("sidebar.zig").Item;

/// Draws the count of a row whose text is `text` points at the end of
/// the row, in `color`: right-aligned where the count goes, so a spinner
/// becoming a count doesn't move the label.
pub fn count(c: *ui.Context, opts: Item, text: f32, k: f32, color: ui.Color) void {
    if (opts.loading) {
        kit.spinner(c, .{ .size = @round(text - 2) * k, .color = color });
        return;
    }
    const n = opts.count orelse return;
    if (opts.count_style == .pill) {
        const p = ui.div(c).h(@round(text * 1.25) * k).px(@round(text * 0.45) * k).roundedFull().bg(color).center();
        defer p.end();
        ui.textf(c, .{ .size = text - 2, .weight = .semibold, .color = kit.tokens(c).primary_foreground }, "{d}", .{n});
    } else ui.textf(c, .{ .size = text - 2, .mono = true, .color = color }, "{d}", .{n});
}

/// Draws the count of a narrowed row at its icon's corner, in `color`: a
/// dot when there are any, or a small spinner while it is loading. Call
/// it in the icon's slot.
pub fn badge(c: *ui.Context, opts: Item, text: f32, k: f32, color: ui.Color) void {
    const slot = @round(text * 1.3) * k;
    if (opts.loading) {
        const size = @round(text * 0.6) * k;
        const at = ui.div(c).absolute().offset(slot - size * 0.7, -size * 0.4).w(size).h(size);
        defer at.end();
        kit.spinner(c, .{ .size = size, .color = color });
        return;
    }
    const n = opts.count orelse return;
    if (n == 0) return;
    const dot = @round(text * 0.45) * k;
    ui.div(c).absolute().offset(slot - dot * 0.6, -dot * 0.3).w(dot).h(dot).roundedFull().bg(color).end();
}

/// What a screen reader says of the row's count: the number, or
/// `loading_text` while it is loading; empty without one.
pub fn said(c: *ui.Context, opts: Item, loading_text: []const u8) []const u8 {
    if (opts.loading) return loading_text;
    const n = opts.count orelse return "";
    return c.print("{d}", .{n});
}
