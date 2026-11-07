//! A form: rows with a label beside a control or a value, the labels in
//! one column, so what follows them lines up row under row. For a
//! settings pane or an inspector; the kit's `field` puts its label above
//! the control, which suits a dialog of a few fields.
//!
//!     var f = controls.form(c, .{ .row_lines = true });
//!     f.heading("Snapshots", .{ .description = "How often, and how many to keep." });
//!     {
//!         const r = f.row("Keep latest", .{ .hint = "Snapshots to keep, newest first." });
//!         _ = kit.numberInput(c, &keep, .{});
//!         r.end();
//!     }
//!     f.property("Hostname", host, .{ .mono = true });
//!     f.end();
//!
//! A row's label names its control to a screen reader, as nanoui names a
//! control by the text just before it on its line.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const chart = @import("chart.zig");

pub const Options = struct {
    /// The labels' size, and every row at least the height of the kit's
    /// controls at it, so selects, inputs and toggles keep one rhythm.
    size: kit.Size = .md,
    /// The labels' column, in points before `scale`; null takes the
    /// widest label's, as the form measured it, up to `max_label_width`.
    label_width: ?f32 = null,
    max_label_width: f32 = 220,
    /// Labels at the start of their column, or at its end, beside what
    /// they name.
    label_align: enum { start, end } = .start,
    /// The labels' color; null takes the theme's muted text.
    label_color: ?ui.Color = null,
    /// The gap after the labels, and between rows, in points before
    /// `scale`.
    gap: f32 = 12,
    row_gap: f32 = 4,
    /// A line between rows, in the theme's border color.
    row_lines: bool = false,
    /// The rows under each heading in a card of their own, the heading
    /// above it, as a settings window groups them: the theme's surface,
    /// border and corners. Rows before the first heading have a card too.
    grouped: bool = false,
    /// Below this width, in points before `scale`, the labels go above
    /// what they name, as the kit's field has them, for a form in a narrow
    /// pane; null keeps them beside it at any width.
    stack_below: ?f32 = null,
    /// Multiplies its lengths, but not its text, for an app that zooms its
    /// layout along with `c.setZoom`, as the grid's does.
    scale: f32 = 1,
};

pub const RowOptions = struct {
    /// Under the control, muted; `err` takes its place, in the theme's
    /// danger color, as the kit's field has them.
    hint: []const u8 = "",
    err: []const u8 = "",
    /// A "*" after the label, in the theme's danger color, as the kit's
    /// field marks one that must be filled in.
    required: bool = false,
    /// The label at the top of the row, beside a control taller than a
    /// line; otherwise they are centered on each other.
    label_top: bool = false,
    /// More than a hint should say, in a tooltip on an ⓘ after the label,
    /// and to a screen reader as the label's hint.
    info: []const u8 = "",
    /// The label and the hint dimmed, beside a control the caller
    /// disables, as the kit's controls dim.
    disabled: bool = false,
};

pub const HeadingOptions = struct {
    /// What the rows under it are for, muted under the title, wrapping.
    description: []const u8 = "",
};

pub const PropertyOptions = struct {
    /// The value in the monospaced font, for names, numbers and paths.
    mono: bool = false,
    /// The value can be selected with the pointer and copied.
    selectable: bool = false,
    /// A value too long for its line wraps; off, it ends in "…" and says
    /// itself whole in a tooltip.
    wrap: bool = true,
};

/// Opens a form as wide as its parent: add its `row`s, `property`s and
/// `heading`s, then `end` it.
pub fn form(c: *ui.Context, opts: Options) Form {
    const box = ui.div(c).column().wFull().gap(opts.row_gap * opts.scale);
    // Its width as the last frame laid it out, only when it matters.
    const stacked = if (opts.stack_below) |below| if (chart.lastSize(c, box.index)) |s| s.w < below * opts.scale else false else false;
    return .{ .stacked = stacked, .c = c, .opts = opts, .box = box, .measured = state(c).width };
}

/// What a form keeps between frames: its widest label.
const Kept = struct { width: f32 = 0 };

/// The form's `Kept`, found by a key of its own in its box: the same at
/// its start and in `end`, whatever its rows draw between. The pointer
/// lasts only until the next state is made, which a control in a row may
/// do, so it isn't kept: use it at once.
fn state(c: *ui.Context) *Kept {
    ui.key(c, "form-state");
    // Looking a state up doesn't take the key, as a new box would.
    defer c.next_key = null;
    return c.state(Kept, "form");
}

/// An open form: add its rows, properties and headings, then `end` it.
pub const Form = struct {
    /// Its labels are above what they name: the form is narrower than
    /// `stack_below`.
    stacked: bool,

    // The rest is the form's own.
    c: *ui.Context,
    opts: Options,
    box: ui.Div,
    /// The widest label the last frame measured, in points.
    measured: f32,
    /// The widest label drawn this frame, in points.
    widest: f32 = 0,
    /// A row has been drawn since the form or its last heading began.
    any: bool = false,
    /// The card the rows go in, while one is open.
    card: ?ui.Div = null,

    /// A row with `label` in the form's column, open after it for a
    /// control: draw it, then `end` the row.
    pub fn row(f: *Form, label: []const u8, opts: RowOptions) Row {
        const c = f.c;
        const k = f.opts.scale;
        f.before(label, opts.required, opts.info.len > 0);
        const r = f.open(!opts.label_top);
        f.drawLabel(label, .{ .required = opts.required, .info = opts.info, .disabled = opts.disabled, .names = true });
        return .{ .c = c, .row = r, .opts = opts, .size = f.opts.size, .indent = if (f.stacked) 0 else f.columnWidth() + f.opts.gap * k };
    }

    /// `label` in the form's column, then `value`, wrapping within the
    /// room left, the label beside its first line. A screen reader hears
    /// them as one: "Hostname, studio.local".
    pub fn property(f: *Form, label: []const u8, value: []const u8, opts: PropertyOptions) void {
        const c = f.c;
        f.before(label, false, false);
        const r = f.open(false);
        defer r.end();
        ui.access.describe(c, r.index, .{ .role = .static_text, .label = label, .value = value });
        const style: ui.TextStyle = .{ .size = f.opts.size.text(), .mono = opts.mono, .color = kit.tokens(c).foreground };
        f.drawLabel(label, .{ .top = f.firstLine(.{ .size = style.size }) });
        var v = ui.div(c).wFull().pt(f.firstLine(style));
        if (opts.selectable) c.node(v.index).style.selectable = true;
        defer v.end();
        if (opts.wrap) {
            var s = style;
            s.wrap = true;
            return ui.text(c, value, s);
        }
        var s = style;
        s.truncate = .ellipsis;
        ui.text(c, value, s);
        // Whole in a tooltip, when the last frame cut it short.
        var it = v.interaction();
        it.hovered = it.hovered and if (c.rects.get(c.node(v.index).id)) |rect| c.text.width(value, style) > rect.w + 0.5 else false;
        kit.tooltip(c, it, value, .{});
    }

    /// A heading over the rows after it, its title in the theme's text and
    /// a description under it if it has one, with room above it after
    /// rows. Grouped, its rows go in a card under it.
    pub fn heading(f: *Form, title: []const u8, opts: HeadingOptions) void {
        const c = f.c;
        const k = f.opts.scale;
        const t = kit.tokens(c);
        const text = f.opts.size.text();
        f.closeCard();
        // Grouped, in line with the labels in the card under it.
        const h = ui.div(c).column().wFull().gap(2 * k).px(if (f.opts.grouped) f.cardPadding() else 0).pt(if (f.any) @round(text * 1.2) * k else 0).pb(@round(text * 0.25) * k);
        defer h.end();
        {
            const head = ui.div(c).wFull();
            defer head.end();
            ui.text(c, title, .{ .size = text - 0.5, .weight = .semibold, .color = t.foreground });
            ui.access.describe(c, head.index, .{ .role = .static_text, .label = title, .header = true });
        }
        if (opts.description.len > 0) {
            const d = ui.div(c).wFull();
            defer d.end();
            ui.text(c, opts.description, .{ .size = text - 1.5, .color = t.muted, .wrap = true });
        }
        f.any = false;
    }

    /// Ends the form, keeping its widest label for the next frame's column.
    pub fn end(f: *Form) void {
        // Its state is in its own box, out of the last card.
        f.closeCard();
        const widest = @min(f.widest, f.opts.max_label_width * f.opts.scale);
        const kept = state(f.c);
        if (f.opts.label_width == null and kept.width != widest) {
            kept.width = widest;
            f.c.frameIn(0);
        }
        f.box.end();
    }

    /// Room inside a card, either side of its rows.
    fn cardPadding(f: *const Form) f32 {
        return @round(f.opts.size.text() * 0.9) * f.opts.scale;
    }

    fn closeCard(f: *Form) void {
        if (f.card) |card| card.end();
        f.card = null;
    }

    /// The labels' column, in points.
    fn columnWidth(f: *const Form) f32 {
        const k = f.opts.scale;
        if (f.opts.label_width) |w| return w * k;
        const max = f.opts.max_label_width * k;
        return if (f.measured > 0) @min(f.measured, max) else max / 2;
    }

    /// Opens a row: the label beside what it names, at least the kit's
    /// height and `centered` on it, or stacked above it.
    fn open(f: *const Form, centered: bool) ui.Div {
        const c = f.c;
        const k = f.opts.scale;
        if (f.stacked) return ui.div(c).column().wFull().gap(4 * k);
        var r = ui.div(c).row().wFull().gap(f.opts.gap * k);
        if (centered) r = r.itemsCenter();
        c.node(r.index).style.min_height = f.opts.size.height() * k;
        return r;
    }

    const Label = struct {
        required: bool = false,
        info: []const u8 = "",
        disabled: bool = false,
        /// The label is an element of its own, naming the control after it.
        names: bool = false,
        /// Room above it, to sit beside a first line.
        top: f32 = 0,
    };

    /// Room above a line of text in `style`, so it sits in the middle of a
    /// row of the kit's height; none when stacked.
    fn firstLine(f: *const Form, style: ui.TextStyle) f32 {
        if (f.stacked) return 0;
        return @max(0, @round((f.opts.size.height() * f.opts.scale - f.c.text.lineHeight(style)) / 2));
    }

    /// `text` in the labels' column, or across the row when stacked, with
    /// its required mark and its ⓘ.
    fn drawLabel(f: *const Form, text: []const u8, l: Label) void {
        const c = f.c;
        const k = f.opts.scale;
        const t = kit.tokens(c);
        const size = f.opts.size.text();
        var col = ui.div(c).row().itemsCenter().gap(2 * k).clip().pt(l.top);
        col = if (f.stacked) col.wFull() else col.w(f.columnWidth());
        if (f.opts.label_align == .end and !f.stacked) col = col.justifyEnd();
        if (l.disabled) col = col.opacity(0.45);
        defer col.end();
        // One element, so the mark isn't what names the control.
        if (l.names) {
            if (text.len > 0) {
                ui.access.describe(c, col.index, .{ .role = .static_text, .label = text, .hint = l.info, .enabled = !l.disabled });
            } else ui.access.hide(c, col.index);
        }
        // A label too long for the column ends in "…".
        ui.text(c, text, .{ .size = size, .color = f.opts.label_color orelse t.muted, .truncate = .ellipsis });
        if (l.required) ui.text(c, "*", .{ .size = size, .color = t.danger });
        if (l.info.len > 0) {
            const i = ui.div(c).pl(2 * k).w(infoWidth(size, k)).center();
            defer i.end();
            ui.icon(c, "info.circle", .{ .size = size - 1, .color = t.muted });
            kit.tooltip(c, i.interaction(), l.info, .{});
        }
    }

    /// Measures `label` for the column, unless it is set, and draws the
    /// line above its row.
    fn before(f: *Form, label_text: []const u8, required: bool, info: bool) void {
        const c = f.c;
        const k = f.opts.scale;
        if (f.opts.label_width == null) {
            const size = f.opts.size.text();
            var w = @ceil(c.text.width(label_text, .{ .size = size }));
            if (required) w += @ceil(c.text.width("*", .{ .size = size })) + 2 * k;
            // The ⓘ's box, and the gap before it.
            if (info) w += infoWidth(size, k) + 2 * k;
            f.widest = @max(f.widest, w);
        }
        if (f.opts.grouped and f.card == null) {
            const t = kit.tokens(c);
            f.card = ui.div(c).column().wFull().px(f.cardPadding()).py(4 * k).gap(f.opts.row_gap * k).bg(t.surface).border(t.border).rounded(t.radius * k);
        }
        if (f.opts.row_lines and f.any) ui.div(c).wFull().h(1 * k).bg(kit.tokens(c).border).end();
        f.any = true;
    }
};

/// The ⓘ's box beside a label of `size`: the icon, a point under the
/// text, is drawn a point wider either side, after a gap of 2.
fn infoWidth(size: f32, k: f32) f32 {
    return size + 1 + 2 * k;
}

/// A form's row, open for its control: draw it, then `end` it.
pub const Row = struct {
    c: *ui.Context,
    row: ui.Div,
    opts: RowOptions,
    size: kit.Size,
    /// Where the control starts, for the hint under it.
    indent: f32,

    /// Ends the row, then puts its hint or error under the control.
    pub fn end(r: Row) void {
        r.row.end();
        const msg = if (r.opts.err.len > 0) r.opts.err else r.opts.hint;
        if (msg.len == 0) return;
        const t = kit.tokens(r.c);
        var under = ui.div(r.c).row().wFull().pl(r.indent);
        if (r.opts.disabled) under = under.opacity(0.45);
        defer under.end();
        ui.text(r.c, msg, .{ .size = r.size.text() - 1, .color = if (r.opts.err.len > 0) t.danger else t.muted, .wrap = true });
    }
};

test {
    _ = @import("form_tests.zig");
}
