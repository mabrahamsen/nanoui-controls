//! A sidebar: rows to pick what a window shows, under headings and in
//! groups that fold. One row is selected, by a key the caller keeps, never
//! by position: rows come and go as data changes, and a position would
//! then point at another row.
//!
//! It moves as the kit does: the selection slides from row to row as
//! `kit.tabs`' marker does, a row eases into a wash under the pointer, and
//! a group opens to its rows' height and closes back as `kit.collapsible`
//! does. It takes the keyboard as the grid does, from a click or Tab:
//! Up and Down move between rows and group headings, Home and End go to
//! the ends, Left folds a group and Right opens it, and Enter or Space
//! chooses. The keys choose a row as they reach it, or, with
//! `choose_on_enter`, only on Enter or Space.
//!
//!     var sb = controls.sidebar(c, "nav", selected, .{});
//!     sb.heading("Mailboxes");
//!     sb.item("inbox", "Inbox", .{ .icon = "doc.text", .count = unread });
//!     if (sb.group("folders", "Folders", &folders_open)) |g| {
//!         for (folders) |f| sb.item(f.id, f.name, .{ .icon = "folder" });
//!         g.end();
//!     }
//!     if (sb.end()) |key| selected = key;
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const motion = ui.motion;
const focus = @import("focus.zig");

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
    /// that folds it, and counts dots.
    icons_only: bool = false,
    /// Between the rows.
    gap: f32 = 2,
    /// What a screen reader says of a group's heading while its rows show,
    /// and while they are folded away.
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
};

/// A row or a group's heading, as the keys move between them.
const Entry = struct {
    hash: u64,
    key: []const u8,
    /// A heading's group, open or not; null for a row.
    open: ?*bool = null,
    /// The heading of the group a row is in.
    group: ?usize = null,
    /// The box, to keep it in view.
    index: u32,
};

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
    const own = focus.take(c, outer);
    ui.key(c, id);
    const inner = ui.div(c).column().wFull().gap(opts.gap * k);
    const kept = c.state(Kept, "sidebar");
    if (!own.focused) kept.cursor = 0;
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
    kept: *Kept,
    own: u64,
    /// The rows and headings drawn this frame, in order, for the keys.
    entries: std.ArrayList(Entry),
    /// The marker is drawn: the selected row leaves its tint to it.
    marked: bool = false,
    /// The selected row was drawn this frame.
    found: bool = false,
    /// The group whose rows are being drawn, by its heading's entry.
    group_at: ?usize = null,
    /// The group being drawn is folding away: its rows can't be reached.
    folding: bool = false,
    /// A row chosen this frame.
    chosen: ?[]const u8 = null,

    /// A row keyed `key`, reading `label`.
    pub fn item(sb: *Sidebar, key: []const u8, label: []const u8, opts: Item) void {
        const c = sb.c;
        const k = sb.opts.scale;
        const t = kit.tokens(c);
        const size = sb.opts.size;
        const text = size.text();
        const narrow = sb.opts.icons_only;
        const on = if (sb.selected) |s| std.mem.eql(u8, s, key) else false;
        const hash = entryHash(false, key);
        const at_cursor = sb.focused and !opts.disabled and sb.cursorIs(hash, on);
        const tint = sb.opts.color orelse t.primary;
        ui.key(c, key);
        var row = ui.div(c).row().wFull().itemsCenter().gap(@round(text * 0.6) * k).px(@round(text * @as(f32, if (narrow) 0.3 else 0.8)) * k).h(size.height() * k).rounded(radius(c, k));
        if (narrow) row = row.justifyCenter();
        // A disabled row still shows its tooltip, but takes no clicks.
        var it = row.interaction();
        if (opts.disabled) {
            it.clicked = false;
            it.secondary_clicked = false;
        } else if (it.hovered) c.cursor_hand = true;
        if (!sb.folding and !opts.disabled) sb.entries.append(c.alloc(), .{ .hash = hash, .key = key, .group = sb.group_at, .index = row.index }) catch {};
        // A wash eases in under the pointer, and on the row the keys are on
        // when they don't choose as they move.
        const wash = motion.number(c, "wash", if (!on and !opts.disabled and (it.hovered or (at_cursor and sb.opts.choose_on_enter))) 1 else 0, .{ .tween = .{ .duration = 0.12 } });
        if (on and !sb.marked) {
            row = row.bg(tint.alpha(0.12));
        } else if (wash > 0.001) {
            const base = sb.opts.background orelse t.foreground.alpha(0);
            row = row.bg(base.mix(t.foreground.alpha(0.07), wash));
        } else if (sb.opts.background) |bg| row = row.bg(bg);
        if (at_cursor) row = row.border(tint.alpha(0.45));
        if (opts.disabled) c.node(row.index).style.opacity = 0.45;
        defer row.end();
        const pill = opts.count_style == .pill;
        const count_col = opts.count_color orelse if (pill) tint else t.muted;
        {
            const slot = ui.div(c).w(@round(text * 1.3) * k).h(text * k).center();
            defer slot.end();
            if (opts.icon) |name| ui.icon(c, name, .{ .size = text - 0.5, .color = if (on) tint else t.muted.mix(t.foreground, wash * 0.5) });
            // Narrowed, a count is a dot at the icon's corner.
            if (narrow) if (opts.count) |n| if (n > 0) {
                const dot = @round(text * 0.45) * k;
                ui.div(c).absolute().offset(@round(text * 1.3) * k - dot * 0.6, -dot * 0.3).w(dot).h(dot).roundedFull().bg(count_col).end();
            };
        }
        if (narrow) {
            kit.tooltip(c, it, label, .{ .placement = .right });
        } else {
            ui.text(c, label, .{
                .size = text,
                .weight = if (on) .semibold else .regular,
                .color = if (on) t.foreground else t.foreground.alpha(0.85).mix(t.foreground, wash),
                .truncate = .ellipsis,
            });
            ui.spacer(c);
            if (opts.count) |n| if (pill) {
                const p = ui.div(c).h(@round(text * 1.25) * k).px(@round(text * 0.45) * k).roundedFull().bg(count_col).center();
                defer p.end();
                ui.textf(c, .{ .size = text - 2, .weight = .semibold, .color = t.primary_foreground }, "{d}", .{n});
            } else ui.textf(c, .{ .size = text - 2, .mono = true, .color = count_col }, "{d}", .{n});
        }
        ui.access.describe(c, row.index, .{
            .role = .tab,
            .label = label,
            .value = if (opts.count) |n| c.print("{d}", .{n}) else "",
            .selected = on,
            .enabled = !opts.disabled,
        });
        if (it.clicked) {
            c.focus = sb.own;
            sb.kept.cursor = hash;
            if (!on) sb.choose(key);
        }
        if (it.secondary_clicked) sb.secondary_clicked = key;
        if (on and !sb.folding) {
            sb.found = true;
            if (it.rect) |r| if (sb.inner_rect) |br| {
                sb.kept.* = .{ .y = r.y - br.y, .h = r.h, .known = true, .cursor = sb.kept.cursor };
                // The marker is drawn from the next frame: ask for it.
                if (!sb.marked) c.animationFrame();
            };
        }
    }

    /// A heading over the rows that follow ("Mailboxes"): text, which takes
    /// no clicks.
    pub fn heading(sb: *Sidebar, title: []const u8) void {
        const c = sb.c;
        const k = sb.opts.scale;
        const t = kit.tokens(c);
        const text = sb.opts.size.text();
        const h = ui.div(c).row().wFull().px(@round(text * 0.8) * k).pt(@round(text * 0.7) * k).pb(@round(text * 0.2) * k);
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
        const at_cursor = sb.focused and sb.cursorIs(hash, false);
        ui.key(c, key);
        const wrap = ui.div(c).column().wFull().gap(sb.opts.gap * k);
        {
            const head = ui.div(c).row().wFull().itemsCenter().gap(6 * k).px(@round(text * 0.8) * k).pt(@round(text * 0.7) * k).pb(@round(text * 0.2) * k).rounded(radius(c, k));
            defer head.end();
            const it = head.interaction();
            if (it.hovered) c.cursor_hand = true;
            if (at_cursor) _ = head.border((sb.opts.color orelse t.primary).alpha(0.45));
            if (it.clicked) {
                open.* = !open.*;
                c.changed = true;
                c.focus = sb.own;
                sb.kept.cursor = hash;
            }
            sb.entries.append(c.alloc(), .{ .hash = hash, .key = key, .open = open, .index = head.index }) catch {};
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
            ui.access.describe(c, head.index, .{ .role = .button, .label = title, .value = if (open.*) sb.opts.expanded_text else sb.opts.collapsed_text });
        }
        // How far open, easing: the rows' box is that share of their height.
        const shown = motion.number(c, "fold", if (open.*) 1 else 0, .{ .tween = .{ .duration = 0.22, .ease = .ease_in_out } });
        if (!open.* and shown < 0.001) {
            wrap.end();
            return null;
        }
        const body = ui.div(c).column().wFull().clip();
        // The rows' box, as the last frame laid it out: the body's only child.
        if (shown < 0.999) if (c.rects.get(c.peekId(null))) |r| {
            c.node(body.index).style.height = .{ .px = r.h * shown };
            c.node(body.index).style.opacity = shown;
        };
        const rows = ui.div(c).column().wFull().gap(sb.opts.gap * k);
        sb.group_at = sb.entries.items.len - 1;
        sb.folding = !open.*;
        return .{ .sb = sb, .wrap = wrap, .body = body, .rows = rows };
    }

    /// Ends the sidebar: the key of a row chosen this frame, by a click or
    /// the keys, if one was.
    pub fn end(sb: *Sidebar) ?[]const u8 {
        // A selected row folded away, or gone: no marker until it shows.
        if (!sb.found) sb.kept.known = false;
        if (sb.focused) sb.keys();
        sb.inner.end();
        sb.outer.end();
        return sb.chosen;
    }

    /// Whether the keys are on `hash`: the entry they moved to, or, while
    /// they follow the selection, the selected row.
    fn cursorIs(sb: *const Sidebar, hash: u64, on: bool) bool {
        if (sb.kept.cursor != 0) return sb.kept.cursor == hash;
        return on;
    }

    fn choose(sb: *Sidebar, key: []const u8) void {
        sb.chosen = key;
        sb.c.changed = true;
    }

    /// The keys, while the sidebar has the keyboard: on the rows and
    /// headings drawn this frame.
    fn keys(sb: *Sidebar) void {
        const c = sb.c;
        const list = sb.entries.items;
        if (list.len == 0) return;
        // Where the keys are: the entry they moved to, else the selected
        // row, else the first.
        var at: usize = 0;
        for (list, 0..) |e, i| {
            if (sb.kept.cursor != 0 and e.hash == sb.kept.cursor) {
                at = i;
                break;
            }
            if (sb.kept.cursor == 0 and e.open == null and sb.selected != null and std.mem.eql(u8, e.key, sb.selected.?)) at = i;
        }
        const e = list[at];
        var to: ?usize = null;
        var enter = false;
        if (c.shortcut(.{ .key = ui.Shortcut.down })) {
            to = @min(at + 1, list.len - 1);
        } else if (c.shortcut(.{ .key = ui.Shortcut.up })) {
            to = at -| 1;
        } else if (c.shortcut(.{ .key = ' ' })) {
            enter = true;
        } else if (c.input.key) |key| switch (key) {
            .down => to = @min(at + 1, list.len - 1),
            .up => to = at -| 1,
            .home => to = 0,
            .end => to = list.len - 1,
            .enter => enter = true,
            .left => if (e.open) |o| {
                if (o.*) o.* = false;
                c.changed = true;
            } else if (e.group) |g| {
                to = g;
            },
            .right => if (e.open) |o| {
                if (!o.*) o.* = true;
                c.changed = true;
            },
            else => {},
        };
        if (enter) {
            if (e.open) |o| {
                o.* = !o.*;
                c.changed = true;
            } else if (!sb.isSelected(e.key)) sb.choose(e.key);
            sb.kept.cursor = e.hash;
        }
        const i = to orelse return;
        const next = list[i];
        sb.kept.cursor = next.hash;
        c.changed = true;
        if (next.open == null and !sb.opts.choose_on_enter and !sb.isSelected(next.key)) sb.choose(next.key);
        sb.reveal(next.index);
    }

    fn isSelected(sb: *const Sidebar, key: []const u8) bool {
        return if (sb.selected) |s| std.mem.eql(u8, s, key) else false;
    }

    /// Scrolls the sidebar so box `index`, as last laid out, is in view.
    fn reveal(sb: *Sidebar, index: u32) void {
        const c = sb.c;
        const box_id = c.node(sb.outer.index).id;
        const view = c.rects.get(box_id) orelse return;
        const r = c.rects.get(c.node(index).id) orelse return;
        const offset = c.scroll.get(box_id) orelse 0;
        if (r.y < view.y) {
            c.scroll.put(c.gpa, box_id, @max(0, offset - (view.y - r.y))) catch {};
        } else if (r.y + r.h > view.y + view.h) {
            c.scroll.put(c.gpa, box_id, offset + (r.y + r.h - view.y - view.h)) catch {};
        }
    }
};

/// A group's rows, while it returns one: draw them, then `end` it.
pub const Group = struct {
    sb: *Sidebar,
    wrap: ui.Div,
    body: ui.Div,
    rows: ui.Div,

    pub fn end(g: Group) void {
        g.sb.group_at = null;
        g.sb.folding = false;
        g.rows.end();
        g.body.end();
        g.wrap.end();
    }
};

test {
    _ = @import("sidebar_tests.zig");
}
