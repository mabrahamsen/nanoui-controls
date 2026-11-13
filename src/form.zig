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
const focus = @import("focus.zig");
const parts = @import("parts.zig");
const measure = @import("measure.zig");
const sections = @import("form_sections.zig");

/// Where a form's labels or controls sit in their room: at its start,
/// or at its end.
pub const Align = enum { start, end };

pub const Options = struct {
    /// The labels' size, and every row at least the height of the kit's
    /// controls at it, so selects, inputs and toggles keep one rhythm.
    size: kit.Size = .md,
    /// What a screen reader says of a row marked `required`, after its
    /// label, which names its control ("Name, required"): the "*" isn't
    /// said.
    required_text: []const u8 = "required",
    /// The labels' column, in points before `scale`; null takes the
    /// widest label's, as the form measured it, up to `max_label_width`.
    label_width: ?f32 = null,
    max_label_width: f32 = 220,
    /// Labels at the start of their column, or at its end, beside what
    /// they name.
    label_align: Align = .start,
    /// Controls and values after the labels' column, or at the row's end,
    /// as a settings window's cards have them.
    control_align: Align = .start,
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
    /// What a screen reader says of a folding heading, open or not.
    expanded_text: []const u8 = "expanded",
    collapsed_text: []const u8 = "collapsed",
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
    /// The title's color, and its card's border, as the kit's statuses:
    /// danger for a section of what can't be undone.
    status: kit.Status = .neutral,
};

pub const LinkOptions = struct {
    /// Dimmed, and takes no click.
    disabled: bool = false,
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

/// Opens a form as wide as its parent: add its `row`s, `property`s,
/// `link`s, `heading`s and `note`s, then `end` it.
pub fn form(c: *ui.Context, opts: Options) Form {
    const box = ui.div(c).column().wFull().gap(opts.row_gap * opts.scale);
    // Its width as the last frame laid it out, only when it matters.
    const stacked = if (opts.stack_below) |below| if (measure.lastSize(c, box.index)) |s| s.w < below * opts.scale else false else false;
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
    /// Anything has been drawn: a heading after it has room above.
    started: bool = false,
    /// The card the rows go in, while one is open, and its border.
    card: ?ui.Div = null,
    card_border: ?ui.Color = null,
    /// The rows of a folding heading, while its section is open.
    fold: ?sections.Fold = null,

    /// A row with `label` in the form's column, open after it for a
    /// control: draw it, then `end` the row.
    pub fn row(f: *Form, label: []const u8, opts: RowOptions) Row {
        const c = f.c;
        const k = f.opts.scale;
        f.before(label, opts.required, opts.info.len > 0);
        const r = f.openRow(!opts.label_top);
        const label_box = f.drawLabel(label, .{ .required = opts.required, .info = opts.info, .disabled = opts.disabled, .names = true });
        const at_end = f.atEnd();
        if (at_end) ui.spacer(c);
        return .{ .c = c, .row = r, .opts = opts, .size = f.opts.size, .indent = if (f.stacked) 0 else f.columnWidth() + f.opts.gap * k, .at_end = at_end, .label_box = label_box };
    }

    /// `label` in the form's column, then `value`, wrapping within the
    /// room left, the label beside its first line. A screen reader hears
    /// them as one: "Hostname, studio.local".
    pub fn property(f: *Form, label: []const u8, value: []const u8, opts: PropertyOptions) void {
        const c = f.c;
        f.before(label, false, false);
        const r = f.openRow(false);
        defer r.end();
        ui.access.describe(c, r.index, .{ .role = .static_text, .label = label, .value = value });
        const style: ui.TextStyle = .{ .size = f.opts.size.text(), .mono = opts.mono, .color = kit.tokens(c).foreground };
        _ = f.drawLabel(label, .{ .top = f.firstLine(.{ .size = style.size }) });
        var v = ui.div(c).wFull().pt(f.firstLine(style));
        if (f.atEnd()) v = v.row().justifyEnd();
        if (opts.selectable) c.node(v.index).style.selectable = true;
        defer v.end();
        if (opts.wrap) {
            var s = style;
            s.wrap = true;
            return endText(c, value, s, f.atEnd(), v.index, 0);
        }
        var s = style;
        s.truncate = .ellipsis;
        ui.text(c, value, s);
        // Whole in a tooltip, when the last frame cut it short.
        var it = parts.still(c, v);
        it.hovered = it.hovered and if (c.rects.get(c.node(v.index).id)) |rect| c.text.width(value, style) > rect.w + 0.5 else false;
        kit.tooltip(c, it, value, .{});
    }

    /// A row that leads somewhere, such as another pane: its label, its
    /// value muted at its end and a chevron, clicked as a whole or with
    /// Enter or Space once Tab reaches it; true when it is.
    pub fn link(f: *Form, label: []const u8, value: []const u8, opts: LinkOptions) bool {
        const c = f.c;
        const k = f.opts.scale;
        const t = kit.tokens(c);
        f.before(label, false, false);
        // Keyed by its label, so a row appearing above it doesn't take its
        // keyboard.
        ui.key(c, c.print("form-link-{s}", .{label}));
        var r = f.openRow(true);
        defer r.end();
        const it = focus.button(c, r.index, !opts.disabled);
        const live = !opts.disabled;
        if (live and it.hovered) c.cursor_hand = true;
        if (focus.showRing(c, it.focused)) r = r.border(focus.ring(c)).borderW(focus.ringWidth(c)).rounded(@max(0, t.radius - 2) * k);
        ui.access.describe(c, r.index, .{ .role = .button, .label = label, .value = value, .enabled = live });
        _ = f.drawLabel(label, .{ .disabled = opts.disabled });
        {
            var v = ui.div(c).wFull().row().itemsCenter().justifyEnd().gap(4 * k);
            if (opts.disabled) v = v.opacity(focus.dimmed);
            defer v.end();
            const col = if (live and it.hovered) t.foreground else t.muted;
            const style: ui.TextStyle = .{ .size = f.opts.size.text(), .color = col, .truncate = .ellipsis };
            ui.text(c, value, style);
            // Whole in a tooltip, when the last frame cut it short.
            var tip = it;
            tip.hovered = it.hovered and measure.cutOff(c, value, style);
            kit.tooltip(c, tip, value, .{});
            ui.icon(c, "chevron.right", .{ .size = f.opts.size.text() - 3, .color = col });
        }
        return live and it.clicked;
    }

    /// A heading over the rows after it, its title in the theme's text and
    /// a description under it if it has one, with room above it after
    /// rows. Grouped, its rows go in a card under it.
    pub fn heading(f: *Form, title: []const u8, opts: HeadingOptions) void {
        sections.heading(f, title, opts);
    }

    /// A heading that folds the rows after it and opens them again, eased:
    /// a click on it, or Enter or Space once Tab reaches it, turns
    /// `open.*`, which the caller keeps. True while its rows show: draw
    /// them only then. It is known by its title, so give each its own.
    pub fn foldingHeading(f: *Form, title: []const u8, open: *bool, opts: HeadingOptions) bool {
        return sections.foldingHeading(f, title, open, opts);
    }

    /// A note under the rows before it, muted, wrapping: under their card,
    /// when grouped. Rows after it start a card of their own.
    pub fn note(f: *Form, text: []const u8) void {
        sections.note(f, text);
    }

    /// Ends the form, keeping its widest label for the next frame's column.
    pub fn end(f: *Form) void {
        // Its state is in its own box, out of the last card.
        sections.closeSection(f);
        const widest = @min(f.widest, f.opts.max_label_width * f.opts.scale);
        const kept = state(f.c);
        if (f.opts.label_width == null and kept.width != widest) {
            kept.width = widest;
            f.c.frameIn(0);
        }
        f.box.end();
    }

    /// Controls and values go at the row's end.
    fn atEnd(f: *const Form) bool {
        return f.opts.control_align == .end and !f.stacked;
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
    fn openRow(f: *const Form, centered: bool) ui.Div {
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
    /// its required mark and its ⓘ; returns its box.
    fn drawLabel(f: *const Form, text: []const u8, l: Label) u32 {
        const c = f.c;
        const k = f.opts.scale;
        const t = kit.tokens(c);
        const size = f.opts.size.text();
        var col = ui.div(c).row().itemsCenter().gap(2 * k).clip().pt(l.top);
        col = if (f.stacked) col.wFull() else col.w(f.columnWidth());
        if (f.opts.label_align == .end and !f.stacked) col = col.justifyEnd();
        if (l.disabled) col = col.opacity(focus.dimmed);
        defer col.end();
        // One element, so the mark isn't what names the control.
        if (l.names) {
            if (text.len > 0) {
                // The label names the control, which takes only the label's
                // text: "Name, required".
                const said = if (l.required) c.print("{s}, {s}", .{ text, f.opts.required_text }) else text;
                ui.access.describe(c, col.index, .{ .role = .static_text, .label = said, .hint = l.info, .enabled = !l.disabled });
            } else ui.access.hide(c, col.index);
        }
        // A label too long for the column ends in "…".
        ui.text(c, text, .{ .size = size, .color = f.opts.label_color orelse t.muted, .truncate = .ellipsis });
        if (l.required) ui.text(c, "*", .{ .size = size, .color = t.danger });
        if (l.info.len > 0) {
            const i = ui.div(c).pl(2 * k).w(infoWidth(size, k)).center();
            defer i.end();
            ui.icon(c, "info.circle", .{ .size = size - 1, .color = t.muted });
            kit.tooltip(c, parts.still(c, i), l.info, .{});
        }
        return col.index;
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
        sections.openCard(f);
        if (f.opts.row_lines and f.any) ui.div(c).wFull().h(1 * k).bg(kit.tokens(c).border).end();
        f.any = true;
        f.started = true;
    }
};

/// Wrapping `text` in the open row `holder`, at its end when `at_end`: in
/// a box as wide as the text, or as the room the row had last frame
/// (after `inset`) when that is less, as wrapping text takes all the room
/// it is given and a row's end can't move it.
fn endText(c: *ui.Context, text: []const u8, style: ui.TextStyle, at_end: bool, holder: u32, inset: f32) void {
    if (!at_end) return ui.text(c, text, style);
    var w = @ceil(c.text.width(text, style)) + 1;
    if (c.rects.get(c.node(holder).id)) |r| w = @min(w, @max(0, r.w - inset));
    const box = ui.div(c).w(w);
    defer box.end();
    ui.text(c, text, style);
}

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
    /// The control is at the row's end, and its hint under it there.
    at_end: bool,
    /// The label's box, which names the control.
    label_box: u32,

    /// Ends the row, then puts its hint or error under the control.
    pub fn end(r: Row) void {
        nameControl(r.c, r.label_box);
        r.row.end();
        const msg = if (r.opts.err.len > 0) r.opts.err else r.opts.hint;
        if (msg.len == 0) return;
        const t = kit.tokens(r.c);
        var under = ui.div(r.c).row().wFull().pl(r.indent);
        if (r.at_end) under = under.justifyEnd();
        if (r.opts.disabled) under = under.opacity(focus.dimmed);
        defer under.end();
        endText(r.c, msg, .{ .size = r.size.text() - 1, .color = if (r.opts.err.len > 0) t.danger else t.muted, .wrap = true }, r.at_end, under.index, r.indent);
    }
};

/// Gives the first control after the label in box `label_box` that has no
/// name of its own the label's description ("Notify, required", and the
/// ⓘ's text as its hint), and leaves the label out, so it isn't read
/// twice. nanoui would name it from the label only while the label is
/// just before it on its line, and without the hint.
fn nameControl(c: *ui.Context, label_box: u32) void {
    const items = c.a11y_items.items;
    const from = for (items, 0..) |it, i| {
        if (it.node_index == label_box) break i;
    } else return;
    const label = &items[from];
    if (label.hidden or label.label.len == 0) return;
    for (items[from + 1 ..]) |*it| {
        if (it.hidden) continue;
        switch (it.role) {
            .static_text, .group, .list, .row, .image, .popover => continue,
            else => {},
        }
        if (it.label.len > 0) return;
        const text = ui.access.textOf(c, c.alloc(), it.node_index) catch return;
        if (text.len > 0) return;
        it.label = label.label;
        if (it.hint.len == 0) it.hint = label.hint;
        label.hidden = true;
        return;
    }
}

test {
    _ = @import("form_tests.zig");
    _ = @import("form_sections_tests.zig");
}
