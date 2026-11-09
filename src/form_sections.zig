//! A form's sections: its headings, plain or folding, the cards a grouped
//! form puts their rows in, and notes under them. Part of `form.zig`, not
//! a control of its own.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const focus = @import("focus.zig");
const form_mod = @import("form.zig");
const Form = form_mod.Form;
const HeadingOptions = form_mod.HeadingOptions;

/// The rows of a folding heading's section: a box clipped to the share of
/// their height it is open, and the rows in it.
/// A folding heading's rows, while they show: the box eased to their
/// height, and the rows in it.
pub const Fold = struct {
    body: ui.Div,
    rows: ui.Div,
};

/// A heading over the rows after it (`Form.heading`).
pub fn heading(f: *Form, title: []const u8, opts: HeadingOptions) void {
    closeSection(f);
    head(f, title, opts, null);
}

/// A heading that folds the rows after it (`Form.foldingHeading`): true
/// while they show, eased open and closed.
pub fn foldingHeading(f: *Form, title: []const u8, open: *bool, opts: HeadingOptions) bool {
    const c = f.c;
    closeSection(f);
    head(f, title, opts, open);
    // How far open, easing, keyed by its title wherever it is in the form.
    ui.key(c, c.print("form-fold-{s}", .{title}));
    const shown = ui.motion.number(c, "fold", if (open.*) 1 else 0, .{ .tween = .{ .duration = 0.22, .ease = .ease_in_out } });
    c.next_key = null;
    if (!open.* and shown < 0.001) return false;
    ui.key(c, c.print("form-fold-body-{s}", .{title}));
    const body = ui.div(c).column().wFull().clip();
    // The rows' box, as the last frame laid it out: the body's only child.
    if (shown < 0.999) if (c.rects.get(c.peekId(null))) |r| {
        c.node(body.index).style.height = .{ .px = r.h * shown };
        c.node(body.index).style.opacity = shown;
    };
    const rows = ui.div(c).column().wFull().gap(f.opts.row_gap * f.opts.scale);
    f.fold = .{ .body = body, .rows = rows };
    return true;
}

/// Muted text under a section's rows (`Form.note`).
pub fn note(f: *Form, text: []const u8) void {
    const c = f.c;
    const k = f.opts.scale;
    closeCard(f);
    const n = ui.div(c).wFull().px(if (f.opts.grouped) cardPadding(f) else 0).pt(if (f.opts.grouped) 0 else 2 * k);
    defer n.end();
    ui.text(c, text, .{ .size = f.opts.size.text() - 1.5, .color = kit.tokens(c).muted, .wrap = true });
    // The rows after it start a card of their own, with no line above.
    f.any = false;
    f.started = true;
}

/// A heading's title, a chevron after it if it folds (`open`), and its
/// description under it.
fn head(f: *Form, title: []const u8, opts: HeadingOptions, open: ?*bool) void {
    const c = f.c;
    const k = f.opts.scale;
    const t = kit.tokens(c);
    const text = f.opts.size.text();
    const tint: ?ui.Color = if (opts.status == .neutral) null else kit.statusColor(t, opts.status);
    f.card_border = if (tint) |col| col.alpha(0.5) else null;
    if (open != null) ui.key(c, c.print("form-heading-{s}", .{title}));
    // Grouped, in line with the labels in the card under it.
    var h = ui.div(c).column().wFull().gap(2 * k).px(if (f.opts.grouped) cardPadding(f) else 0).pt(if (f.started) @round(text * 1.2) * k else 0).pb(@round(text * 0.25) * k);
    defer h.end();
    f.started = true;
    f.any = false;
    var hovered = false;
    if (open) |o| {
        const it = c.interact(h.index, .{ .focusable = true });
        hovered = it.hovered;
        if (it.hovered) c.cursor_hand = true;
        if (it.focused) h = h.border(focus.ring(c)).borderW(focus.ringWidth(c)).rounded(@max(0, t.radius - 2) * k);
        if (it.clicked) {
            o.* = !o.*;
            c.changed = true;
        }
        // One element: a button that says whether it is open, its
        // description read after it.
        ui.access.describe(c, h.index, .{ .role = .button, .label = title, .value = if (o.*) f.opts.expanded_text else f.opts.collapsed_text, .hint = opts.description, .header = true });
    }
    {
        const line = ui.div(c).row().wFull().itemsCenter().gap(6 * k);
        defer line.end();
        ui.text(c, title, .{ .size = text - 0.5, .weight = .semibold, .color = tint orelse t.foreground });
        if (open) |o| {
            ui.spacer(c);
            ui.icon(c, if (o.*) "chevron.down" else "chevron.right", .{ .size = text - 3.5, .color = if (hovered) t.foreground else t.muted });
        } else ui.access.describe(c, line.index, .{ .role = .static_text, .label = title, .header = true });
    }
    if (opts.description.len > 0) {
        const d = ui.div(c).wFull();
        defer d.end();
        ui.text(c, opts.description, .{ .size = text - 1.5, .color = t.muted, .wrap = true });
    }
}

/// Room inside a card, either side of its rows.
pub fn cardPadding(f: *const Form) f32 {
    return @round(f.opts.size.text() * 0.9) * f.opts.scale;
}

/// Opens a card for the rows to come, if the form is grouped and none is.
pub fn openCard(f: *Form) void {
    if (!f.opts.grouped or f.card != null) return;
    const k = f.opts.scale;
    const t = kit.tokens(f.c);
    f.card = ui.div(f.c).column().wFull().px(cardPadding(f)).py(4 * k).gap(f.opts.row_gap * k).bg(t.surface).border(f.card_border orelse t.border).rounded(t.radius * k);
}

/// Ends the open card, if any.
pub fn closeCard(f: *Form) void {
    if (f.card) |card| card.end();
    f.card = null;
}

/// Ends the open section: its card, and its fold.
pub fn closeSection(f: *Form) void {
    closeCard(f);
    if (f.fold) |fold| {
        fold.rows.end();
        fold.body.end();
    }
    f.fold = null;
}
