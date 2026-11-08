//! A sidebar: rows to pick what a window shows, under headings, in groups
//! that fold, and in branches: rows with rows under them, to any depth.
//! One row is selected, by a key the caller keeps, never by position: rows
//! come and go as data changes, and a position would then point at another
//! row.
//!
//! It moves as the kit does: the selection slides from row to row as
//! `kit.tabs`' marker does, a row eases into a wash under the pointer, and
//! a group opens to its rows' height and closes back as `kit.collapsible`
//! does. It takes the keyboard as the grid does, from a click or Tab:
//! Up and Down move between rows, branches and group headings, Home and
//! End go to the ends, Left folds a group or branch and Right opens it,
//! and Enter or Space chooses. The keys choose a row as they reach it, or, with
//! `choose_on_enter`, only on Enter or Space.
//!
//!     var sb = controls.sidebar(c, "nav", selected, .{});
//!     sb.heading("Mailboxes");
//!     sb.item("inbox", "Inbox", .{ .icon = "doc.text", .count = unread });
//!     if (sb.group("folders", "Folders", &folders_open)) |g| {
//!         for (folders) |f| sb.item(f.id, f.name, .{ .icon = "folder" });
//!         g.end();
//!     }
//!     if (sb.branch("archive", "Archive", .{ .icon = "folder" }, &archive_open)) |g| {
//!         for (years) |y| sb.item(y.id, y.name, .{});
//!         g.end();
//!     }
//!     if (sb.end()) |key| selected = key;
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const motion = ui.motion;
const focus = @import("focus.zig");
const measure = @import("measure.zig");
const keys_mod = @import("sidebar_keys.zig");

pub const Options = struct {
    /// The rows' height and text, as the kit's controls at this size.
    size: kit.Size = .sm,
    /// The selection's tint; null takes the theme's accent.
    color: ?ui.Color = null,
    /// Behind each row not selected; none by default.
    background: ?ui.Color = null,
    /// The keys move a highlight, and only Enter or Space chooses its
    /// row: for an app where showing another view is slow.
    choose_on_enter: bool = false,
    /// Rows show only their icon, centered, for a sidebar narrowed to a
    /// strip: the label shows in a tooltip and is still what a screen
    /// reader says. Headings become lines, a group's heading a chevron
    /// that folds it, and counts dots; a branch's rows aren't indented,
    /// and only the keys fold it.
    icons_only: bool = false,
    /// Between the rows, in points before `scale`.
    gap: f32 = 2,
    /// What a screen reader says of a group's heading or a branch while
    /// its rows show, and while they are folded away.
    expanded_text: []const u8 = "expanded",
    collapsed_text: []const u8 = "collapsed",
    /// Multiplies the sidebar's lengths, for an app that zooms its layout
    /// along with `c.setZoom`, which zooms text, as the grid's does.
    scale: f32 = 1,
};

/// One row's look besides its label.
pub const Item = struct {
    /// A symbol before the label, in a slot of its own, so labels line up
    /// whatever the icons' widths.
    icon: ?[]const u8 = null,
    /// A number at the end: how many there are.
    count: ?usize = null,
    /// The count's color; null takes the theme's muted text, or with
    /// `.pill`, the selection's tint.
    count_color: ?ui.Color = null,
    /// The count as muted text, or as a filled pill that stands out, for
    /// what waits to be seen (unread mail).
    count_style: CountStyle = .plain,
    /// Shown dimmed, it can't be chosen, and the keys pass it by: a place
    /// that is there but not now (an account offline).
    disabled: bool = false,

    pub const CountStyle = enum { plain, pill };
};

/// What a sidebar keeps between frames: where its selected row was, for
/// the marker, and the row or heading the keys are on.
const Kept = struct {
    y: f32 = 0,
    h: f32 = 0,
    known: bool = false,
    /// What the keys are on (`entryHash`); 0 while they follow the
    /// selection.
    cursor: u64 = 0,
    /// The keys have nothing to start from (nothing selected, or it is
    /// folded away): the first row shows the ring, and the first key goes
    /// to it.
    start: bool = false,
};

/// What a branch keeps between frames: the selected row it last showed
/// among its rows, by `entryHash`, or 0. Folded, it shows the selection
/// is in it.
const Held = struct {
    of: u64 = 0,
};

/// A row, a branch or a group's heading, as the keys move between them.
const Entry = struct {
    hash: u64,
    key: []const u8,
    /// What it reads, for typing to move to it.
    label: []const u8,
    /// A branch or a group's heading, open or not; null for a row or a
    /// fixed branch.
    open: ?*bool = null,
    /// A row or a branch, which the keys choose; not a group's heading,
    /// nor a disabled branch, which they only fold.
    choosable: bool = true,
    /// The branch or group heading it is in.
    parent: ?usize = null,
    /// The box, to keep it in view.
    index: u32,
};

/// The sidebar's `Kept`, found by a key of its own in its inner box: the
/// same at its start and in `end`, whatever rows are drawn between. The
/// pointer lasts only until the next state is made, which a row's tooltip
/// may do, so it isn't kept: use it at once.
fn state(c: *ui.Context) *Kept {
    ui.key(c, "sidebar-state");
    // Looking a state up doesn't take the key, as a new box would.
    defer c.next_key = null;
    return c.state(Kept, "sidebar");
}

/// A branch's `Held`, found by a key of its own in the branch's box. Use
/// it at once, as `state`'s.
fn held(c: *ui.Context) *Held {
    ui.key(c, "sidebar-held");
    defer c.next_key = null;
    return c.state(Held, "held");
}

/// Whether the sidebar had rows the last frame, found by a key of its own
/// in its outer box. Use it at once, as `state`'s.
fn hadRows(c: *ui.Context) *HadRows {
    ui.key(c, "sidebar-rows");
    defer c.next_key = null;
    return c.state(HadRows, "sidebar-rows");
}

const HadRows = struct { rows: bool = true };

fn entryHash(heading: bool, key: []const u8) u64 {
    return std.hash.Wyhash.hash(@intFromBool(heading), key);
}

/// Opens a sidebar keyed `id`, `selected` the key of the row shown: add
/// its rows and headings, then `end` it. It takes the room left in its
/// parent, and scrolls when its rows need more.
pub fn sidebar(c: *ui.Context, id: []const u8, selected: ?[]const u8, opts: Options) Sidebar {
    const k = opts.scale;
    const t = kit.tokens(c);
    // Unkeyed, so `c.focusNext` just before names it.
    const outer = ui.div(c).column().wFull().grow().scrollY();
    c.node(outer.index).style.min_height = 0;
    // One that had no rows the last frame doesn't take Tab.
    const own = focus.takeIf(c, outer, hadRows(c).rows);
    ui.key(c, id);
    const inner = ui.div(c).column().wFull().gap(opts.gap * k);
    var kept = state(c).*;
    if (!own.focused) {
        kept.cursor = 0;
        kept.start = false;
    }
    var sb: Sidebar = .{
        .focused = own.focused,
        .c = c,
        .opts = opts,
        .selected = selected,
        .outer = outer,
        .inner = inner,
        .inner_rect = c.rects.get(c.node(inner.index).id),
        .kept = kept,
        .own = own.id,
        .entries = .empty,
    };
    // The marker first, so the rows draw over it: behind the selected row,
    // where it was laid out last frame.
    if (kept.known) {
        ui.key(c, "marker");
        const f = motion.frame(c, .{ .target = .{ .y = kept.y, .height = kept.h }, .transition = .{ .spring = motion.Spring.snappy } });
        const tint = opts.color orelse t.primary;
        ui.div(c).absolute().wFull().rounded(radius(c, k)).bg(tint.alpha(0.12)).motion(f).end();
        sb.marked = true;
    }
    return sb;
}

fn radius(c: *ui.Context, k: f32) f32 {
    return @max(0, kit.tokens(c).radius - 2) * k;
}

pub const Sidebar = struct {
    /// It has the keyboard.
    focused: bool,
    /// The key of a row right-clicked (or Control-clicked on the Mac) this
    /// frame, as `end` returns: open a menu for it, such as the kit's. It
    /// doesn't choose the row.
    secondary_clicked: ?[]const u8 = null,

    // The rest is the sidebar's own.
    c: *ui.Context,
    opts: Options,
    selected: ?[]const u8,
    outer: ui.Div,
    inner: ui.Div,
    inner_rect: ?ui.Rect,
    /// Its `Kept`, read at the start and written back at the end.
    kept: Kept,
    own: u64,
    /// The rows and headings drawn this frame, in order, for the keys.
    entries: std.ArrayList(Entry),
    /// The marker is drawn: the selected row leaves its tint to it.
    marked: bool = false,
    /// The selected row was drawn this frame.
    found: bool = false,
    /// The selected row was drawn this frame, or a folded branch it is in:
    /// what a branch around them keeps it holds.
    seen: bool = false,
    /// The branch or group whose rows are being drawn, by its entry.
    parent: ?usize = null,
    /// The rows being drawn are folding away: they can't be reached.
    folding: bool = false,
    /// How many branches the rows being drawn are in, for their indent.
    depth: u8 = 0,
    /// A row chosen this frame.
    chosen: ?[]const u8 = null,

    /// A row keyed `key`, reading `label`.
    pub fn item(sb: *Sidebar, key: []const u8, label: []const u8, opts: Item) void {
        ui.key(sb.c, key);
        _ = sb.row(key, label, opts, null, false);
    }

    /// A branch: a row keyed `key`, reading `label`, with rows under it,
    /// as `group` has. Draw them, then `end` the group, while it returns
    /// one; they are indented a step, and can be branches in turn.
    /// `open.*`, kept by the caller, says whether they show. The chevron
    /// at its end folds and opens it; a click elsewhere on it chooses it,
    /// and opens it if folded. A disabled branch isn't chosen, but still
    /// folds.
    ///
    /// With `open` null, the branch is fixed: its rows always show, it has
    /// no chevron, and it doesn't fold. A tree that doesn't fold is all
    /// fixed branches; it always returns a group.
    pub fn branch(sb: *Sidebar, key: []const u8, label: []const u8, opts: Item, open: ?*bool) ?Group {
        const c = sb.c;
        ui.key(c, key);
        const wrap = ui.div(c).column().wFull().gap(sb.opts.gap * sb.opts.scale);
        const o = open orelse {
            const at = sb.row(key, label, opts, null, false);
            return sb.fold(wrap, true, at, true);
        };
        // Folded, it shows the selected row is in it, if it was when open.
        const s = sb.selected;
        const holds = !o.* and s != null and !std.mem.eql(u8, s.?, key) and held(c).of == entryHash(false, s.?);
        const at = sb.row(key, label, opts, o, holds);
        return sb.fold(wrap, o.*, at, true);
    }

    /// The left of a row or heading, indented a step for each branch it
    /// is in: an icon's slot and the gap after it, so a row's icon sits
    /// under its branch's label.
    fn inset(sb: *const Sidebar) f32 {
        const k = sb.opts.scale;
        const text = sb.opts.size.text();
        const pad = @round(text * 0.8) * k;
        if (sb.opts.icons_only) return pad;
        return pad + @as(f32, @floatFromInt(sb.depth)) * (@round(text * 1.3) + @round(text * 0.6)) * k;
    }

    /// Draws a row, or with `open` a branch's, and adds it for the keys:
    /// its entry, if it has one. `holds`: a folded branch the selected row
    /// is in, which shows it in the selection's tint.
    fn row(sb: *Sidebar, key: []const u8, label: []const u8, opts: Item, open: ?*bool, holds: bool) ?usize {
        const c = sb.c;
        const k = sb.opts.scale;
        const t = kit.tokens(c);
        const size = sb.opts.size;
        const text = size.text();
        const narrow = sb.opts.icons_only;
        const on = if (sb.selected) |s| std.mem.eql(u8, s, key) else false;
        const hash = entryHash(false, key);
        // A disabled branch is still reached by the keys, to fold it.
        const reached = !opts.disabled or open != null;
        const at_cursor = sb.focused and reached and (sb.cursorIs(hash, on) or sb.isStart());
        const tint = sb.opts.color orelse t.primary;
        const pad = @round(text * @as(f32, if (narrow) 0.3 else 0.8)) * k;
        var row_box = ui.div(c).row().wFull().itemsCenter().gap(@round(text * 0.6) * k).px(pad).pl(if (narrow) pad else sb.inset()).h(size.height() * k).rounded(radius(c, k));
        if (narrow) row_box = row_box.justifyCenter();
        // A disabled row still shows its tooltip, but takes no clicks.
        var it = row_box.interaction();
        if (opts.disabled) {
            it.clicked = false;
            it.secondary_clicked = false;
        } else if (it.hovered) c.cursor_hand = true;
        var at: ?usize = null;
        if (!sb.folding and reached) {
            // A row that can't be added is left out for the keys.
            if (sb.entries.append(c.alloc(), .{ .hash = hash, .key = key, .label = label, .open = open, .choosable = !opts.disabled, .parent = sb.parent, .index = row_box.index })) |_| {
                at = sb.entries.items.len - 1;
            } else |_| {}
        }
        // A wash eases in under the pointer, and on the row the keys are on
        // when they don't choose as they move.
        const wash = motion.number(c, "wash", if (!on and !opts.disabled and (it.hovered or (at_cursor and sb.opts.choose_on_enter))) 1 else 0, .{ .tween = .{ .duration = 0.12 } });
        if (on and !sb.marked) {
            row_box = row_box.bg(tint.alpha(0.12));
        } else if (wash > 0.001) {
            const base = sb.opts.background orelse t.foreground.alpha(0);
            row_box = row_box.bg(base.mix(t.foreground.alpha(0.07), wash));
        } else if (sb.opts.background) |bg| row_box = row_box.bg(bg);
        if (at_cursor) row_box = row_box.border(focus.ringIn(tint));
        if (opts.disabled) c.node(row_box.index).style.opacity = focus.dimmed;
        defer row_box.end();
        if (holds) sb.seen = true;
        const pill = opts.count_style == .pill;
        const count_col = opts.count_color orelse if (pill) tint else t.muted;
        {
            const slot = ui.div(c).w(@round(text * 1.3) * k).h(text * k).center();
            defer slot.end();
            if (opts.icon) |name| ui.icon(c, name, .{ .size = text - 0.5, .color = if (on or holds) tint else t.muted.mix(t.foreground, wash * 0.5) });
            // Narrowed, a count is a dot at the icon's corner.
            if (narrow) if (opts.count) |n| if (n > 0) {
                const dot = @round(text * 0.45) * k;
                ui.div(c).absolute().offset(@round(text * 1.3) * k - dot * 0.6, -dot * 0.3).w(dot).h(dot).roundedFull().bg(count_col).end();
            };
        }
        if (narrow) {
            kit.tooltip(c, it, label, .{ .placement = .right });
        } else {
            const style: ui.TextStyle = .{
                .size = text,
                .weight = if (on) .semibold else .regular,
                .color = if (on) t.foreground else if (holds) tint else t.foreground.alpha(0.85).mix(t.foreground, wash),
                .truncate = .ellipsis,
            };
            ui.text(c, label, style);
            // Whole in a tooltip, when the last frame cut it short.
            var tip = it;
            tip.hovered = it.hovered and measure.cutOff(c, label, style);
            kit.tooltip(c, tip, label, .{ .placement = .right });
            ui.spacer(c);
            if (opts.count) |n| if (pill) {
                const p = ui.div(c).h(@round(text * 1.25) * k).px(@round(text * 0.45) * k).roundedFull().bg(count_col).center();
                defer p.end();
                ui.textf(c, .{ .size = text - 2, .weight = .semibold, .color = t.primary_foreground }, "{d}", .{n});
            } else ui.textf(c, .{ .size = text - 2, .mono = true, .color = count_col }, "{d}", .{n});
            // A branch's chevron, which folds and opens it: a box of its
            // own, so its click isn't the row's.
            if (open) |o| {
                // Its icon at the row's end, as a group heading's is.
                const chev = ui.div(c).row().w(@round(text * 1.1) * k).h(text * k).itemsCenter().justifyEnd();
                defer chev.end();
                const ci = chev.interaction();
                if (ci.hovered) c.cursor_hand = true;
                ui.icon(c, if (o.*) "chevron.down" else "chevron.right", .{ .size = text - 3.5, .color = if (ci.hovered) t.foreground else t.muted });
                ui.access.hide(c, chev.index);
                if (ci.clicked) {
                    o.* = !o.*;
                    c.changed = true;
                    c.focus = sb.own;
                    sb.kept.cursor = hash;
                }
            }
        }
        const value = if (open) |o| blk: {
            const state_text = if (o.*) sb.opts.expanded_text else sb.opts.collapsed_text;
            break :blk if (opts.count) |n| c.print("{d}, {s}", .{ n, state_text }) else state_text;
        } else if (opts.count) |n| c.print("{d}", .{n}) else "";
        ui.access.describe(c, row_box.index, .{
            .role = .tab,
            .label = label,
            .value = value,
            .selected = on,
            .enabled = !opts.disabled,
        });
        if (it.clicked) {
            c.focus = sb.own;
            sb.kept.cursor = hash;
            if (!on) sb.choose(key);
            if (open) |o| if (!o.*) {
                o.* = true;
                c.changed = true;
            };
        }
        if (it.secondary_clicked) sb.secondary_clicked = key;
        if (on and !sb.folding) {
            sb.found = true;
            sb.seen = true;
            if (it.rect) |r| if (sb.inner_rect) |br| {
                sb.kept.y = r.y - br.y;
                sb.kept.h = r.h;
                sb.kept.known = true;
                // The marker is drawn from the next frame: ask for it.
                if (!sb.marked) c.animationFrame();
            };
        }
        return at;
    }

    /// A heading over the rows that follow ("Mailboxes"): text, which takes
    /// no clicks.
    pub fn heading(sb: *Sidebar, title: []const u8) void {
        const c = sb.c;
        const k = sb.opts.scale;
        const t = kit.tokens(c);
        const text = sb.opts.size.text();
        const h = ui.div(c).row().wFull().px(@round(text * 0.8) * k).pl(sb.inset()).pt(@round(text * 0.7) * k).pb(@round(text * 0.2) * k);
        defer h.end();
        // Narrowed, a line where the heading was.
        if (sb.opts.icons_only) {
            ui.div(c).wFull().h(1).bg(t.border).end();
        } else ui.text(c, title, .{ .size = text - 1.5, .weight = .semibold, .color = t.muted });
        ui.access.describe(c, h.index, .{ .role = .static_text, .label = title, .header = true });
    }

    /// A heading that folds the rows under it: draw them, then `end` the
    /// group, while it returns one. `open.*`, kept by the caller, says
    /// whether they show; clicking the heading, or Left and Right on it,
    /// folds and opens it. The rows ease closed, drawn until they are.
    pub fn group(sb: *Sidebar, key: []const u8, title: []const u8, open: *bool) ?Group {
        const c = sb.c;
        const k = sb.opts.scale;
        const t = kit.tokens(c);
        const text = sb.opts.size.text();
        const hash = entryHash(true, key);
        const at_cursor = sb.focused and (sb.cursorIs(hash, false) or sb.isStart());
        ui.key(c, key);
        const wrap = ui.div(c).column().wFull().gap(sb.opts.gap * k);
        var at: ?usize = null;
        {
            const head = ui.div(c).row().wFull().itemsCenter().gap(6 * k).px(@round(text * 0.8) * k).pl(sb.inset()).pt(@round(text * 0.7) * k).pb(@round(text * 0.2) * k).rounded(radius(c, k));
            defer head.end();
            const it = head.interaction();
            if (it.hovered) c.cursor_hand = true;
            if (at_cursor) _ = head.border(focus.ringIn(sb.opts.color orelse t.primary));
            if (it.clicked) {
                open.* = !open.*;
                c.changed = true;
                c.focus = sb.own;
                sb.kept.cursor = hash;
            }
            if (!sb.folding) {
                if (sb.entries.append(c.alloc(), .{ .hash = hash, .key = key, .label = title, .open = open, .choosable = false, .parent = sb.parent, .index = head.index })) |_| {
                    at = sb.entries.items.len - 1;
                } else |_| {}
            }
            const col = if (it.hovered) t.foreground else t.muted;
            // Narrowed, the chevron alone, centered, its title in a tooltip.
            if (sb.opts.icons_only) {
                _ = head.justifyCenter();
                kit.tooltip(c, it, title, .{ .placement = .right });
            } else {
                ui.text(c, title, .{ .size = text - 1.5, .weight = .semibold, .color = col });
                ui.spacer(c);
            }
            ui.icon(c, if (open.*) "chevron.down" else "chevron.right", .{ .size = text - 3.5, .color = col });
            ui.access.describe(c, head.index, .{ .role = .button, .label = title, .value = if (open.*) sb.opts.expanded_text else sb.opts.collapsed_text, .header = true });
        }
        return sb.fold(wrap, open.*, at, false);
    }

    /// The rows under a group's heading or a branch, in `wrap` after it:
    /// a box that is the share of their height the fold has eased to.
    /// `at` is the heading's or branch's entry; `indent` steps the rows in.
    fn fold(sb: *Sidebar, wrap: ui.Div, open: bool, at: ?usize, indent: bool) ?Group {
        const c = sb.c;
        // How far open, easing: the rows' box is that share of their height.
        const shown = motion.number(c, "fold", if (open) 1 else 0, .{ .tween = .{ .duration = 0.22, .ease = .ease_in_out } });
        if (!open and shown < 0.001) {
            wrap.end();
            return null;
        }
        const body = ui.div(c).column().wFull().clip();
        // The rows' box, as the last frame laid it out: the body's only child.
        if (shown < 0.999) if (c.rects.get(c.peekId(null))) |r| {
            c.node(body.index).style.height = .{ .px = r.h * shown };
            c.node(body.index).style.opacity = shown;
        };
        const rows = ui.div(c).column().wFull().gap(sb.opts.gap * sb.opts.scale);
        const g: Group = .{ .sb = sb, .wrap = wrap, .body = body, .rows = rows, .parent = sb.parent, .folding = sb.folding, .depth = sb.depth, .branch = indent, .seen = sb.seen };
        if (at) |i| sb.parent = i;
        sb.folding = sb.folding or !open;
        if (indent) sb.depth +|= 1;
        return g;
    }

    /// Ends the sidebar: the key of a row chosen this frame, by a click or
    /// the keys, if one was.
    pub fn end(sb: *Sidebar) ?[]const u8 {
        // A selected row folded away, or gone: no marker until it shows.
        if (!sb.found) sb.kept.known = false;
        if (sb.focused) keys_mod.keys(sb);
        state(sb.c).* = sb.kept;
        sb.inner.end();
        const rows = sb.entries.items.len > 0;
        const had = hadRows(sb.c);
        if (had.rows != rows) sb.c.changed = true;
        had.rows = rows;
        sb.outer.end();
        return sb.chosen;
    }

    /// Whether the keys have nothing to start from and the entry about to
    /// be added is the first: it shows the ring.
    fn isStart(sb: *const Sidebar) bool {
        return sb.kept.start and !sb.folding and sb.entries.items.len == 0;
    }

    /// Whether the keys are on `hash`: the entry they moved to, or, while
    /// they follow the selection, the selected row.
    fn cursorIs(sb: *const Sidebar, hash: u64, on: bool) bool {
        if (sb.kept.cursor != 0) return sb.kept.cursor == hash;
        return on;
    }

    pub fn choose(sb: *Sidebar, key: []const u8) void {
        sb.chosen = key;
        sb.c.changed = true;
    }

    pub fn isSelected(sb: *const Sidebar, key: []const u8) bool {
        return if (sb.selected) |s| std.mem.eql(u8, s, key) else false;
    }
};

/// A group's or a branch's rows, while it returns one: draw them, then
/// `end` it.
pub const Group = struct {
    sb: *Sidebar,
    wrap: ui.Div,
    body: ui.Div,
    rows: ui.Div,
    /// The sidebar's, as they were before: what `end` puts back.
    parent: ?usize,
    folding: bool,
    depth: u8,
    /// A branch's rows, not a group's.
    branch: bool,
    /// The selected row, or a folded branch it is in, was drawn before
    /// these rows.
    seen: bool,

    /// Ends the group's or branch's rows, and puts back what the sidebar
    /// had before them.
    pub fn end(g: Group) void {
        const sb = g.sb;
        const shown = !sb.folding;
        const holds = !g.seen and sb.seen;
        sb.parent = g.parent;
        sb.folding = g.folding;
        sb.depth = g.depth;
        g.rows.end();
        g.body.end();
        // Open, a branch keeps whether the selected row is among its rows.
        if (g.branch and shown) held(sb.c).of = if (holds) entryHash(false, sb.selected.?) else 0;
        g.wrap.end();
    }
};

test {
    _ = @import("sidebar_tests.zig");
}
