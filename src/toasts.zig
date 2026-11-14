//! Toasts: short messages that come and go in a corner of the window, over
//! everything else: "Saved", "Restored 120 files" with "Show in Finder",
//! "The server didn't answer". Each slides in, goes after a few seconds
//! (not while the pointer rests on it) or stays until closed, and slides
//! out, the rest gliding into its place; with reduced motion they come and
//! go at once. A screen reader hears each as it comes. The stack keeps
//! within the window's height: a toast that doesn't fit waits, its time
//! not running, until those before it go.
//!
//! The app keeps the toasts (`Toasts`) and draws them once a frame, last,
//! so they are over what the frame drew:
//!
//!     _ = s.toasts.show("Restored 120 files", .{ .status = .success, .action = "Show in Finder", .tag = show_files });
//!     ...
//!     if (controls.toasts(c, &s.toasts, .{})) |hit| if (hit.tag == show_files) s.showInFinder();
//!
//! The kit's `Toaster` allocates and has no action; these keep up to
//! `max` in fixed buffers, with an action, a tag and a payload to tell
//! them apart, and the same message shown twice shown once.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const parts = @import("parts.zig");
const buttons = @import("buttons.zig");
const measure = @import("measure.zig");

/// The most toasts kept at once: one more pushes out the oldest.
pub const max = 6;
/// The most bytes of a title, a text and an action kept; past them, a
/// toast's texts are cut short at a character's start.
pub const max_title = 64;
pub const max_text = 200;
pub const max_action = 32;

/// What `Toasts.show` takes.
pub const Show = struct {
    /// Its icon's and its edge's color, as the kit's statuses; neutral has
    /// no icon, and the border's edge.
    status: kit.Status = .neutral,
    /// A line above the text, in its weight ("Backup failed").
    title: []const u8 = "",
    /// A button's words in it ("Undo", "Show in Finder"); `toasts` says
    /// when it is clicked.
    action: []const u8 = "",
    /// How long it stays, in seconds; 0 stays until it is closed.
    seconds: f32 = 4,
    /// The caller's own numbers: which kind of toast it is, and which
    /// thing it is about (an index, an id), given back with its action.
    tag: u32 = 0,
    payload: u64 = 0,
};

/// A toast kept: its texts are copies.
pub const Toast = struct {
    id: u32,
    tag: u32,
    payload: u64,
    status: kit.Status,
    seconds: f32,

    // The rest is the toast's own: callers read the texts with the
    // methods.
    /// When its time is up, on the frame's clock (`c.time`): null until it
    /// is drawn, and while the pointer rests on it.
    ends: ?f64 = null,
    /// The seconds it has left from when `ends` is set again.
    left: f32 = 0,
    announced: bool = false,
    /// Closed, and sliding out: gone once it has.
    leaving: bool = false,
    /// Its height as the last frame laid it out; 0 until it has been.
    height: f32 = 0,
    title_buf: [max_title]u8 = undefined,
    title_len: u8 = 0,
    text_buf: [max_text]u8 = undefined,
    text_len: u8 = 0,
    action_buf: [max_action]u8 = undefined,
    action_len: u8 = 0,

    pub fn title(t: *const Toast) []const u8 {
        return t.title_buf[0..t.title_len];
    }

    pub fn text(t: *const Toast) []const u8 {
        return t.text_buf[0..t.text_len];
    }

    pub fn action(t: *const Toast) []const u8 {
        return t.action_buf[0..t.action_len];
    }
};

/// The toasts shown, oldest first, kept by the app.
pub const Toasts = struct {
    list: [max]Toast = undefined,
    n: usize = 0,
    next_id: u32 = 1,

    /// Shows `message`, returning its id, for `close` and `dismiss`. The
    /// same toast shown already (the same status, title, text, action, tag
    /// and payload: a request failing each time it is retried) starts
    /// `seconds` again instead of showing twice, comes back if it was
    /// leaving, and is said again.
    pub fn show(t: *Toasts, message: []const u8, opts: Show) u32 {
        const text = cut(message, max_text);
        const title = cut(opts.title, max_title);
        const act = cut(opts.action, max_action);
        for (t.list[0..t.n]) |*x| if (x.status == opts.status and x.tag == opts.tag and x.payload == opts.payload and
            std.mem.eql(u8, x.text(), text) and std.mem.eql(u8, x.title(), title) and std.mem.eql(u8, x.action(), act))
        {
            x.seconds = opts.seconds;
            x.ends = null;
            x.left = opts.seconds;
            x.leaving = false;
            x.announced = false;
            return x.id;
        };
        if (t.n == max) {
            std.mem.copyForwards(Toast, t.list[0 .. max - 1], t.list[1..max]);
            t.n -= 1;
        }
        var x: Toast = .{ .id = t.next_id, .tag = opts.tag, .payload = opts.payload, .status = opts.status, .seconds = opts.seconds, .left = opts.seconds };
        t.next_id +%= 1;
        x.title_len = @intCast(title.len);
        @memcpy(x.title_buf[0..x.title_len], title);
        x.text_len = @intCast(text.len);
        @memcpy(x.text_buf[0..x.text_len], text);
        x.action_len = @intCast(act.len);
        @memcpy(x.action_buf[0..x.action_len], act);
        t.list[t.n] = x;
        t.n += 1;
        return x.id;
    }

    /// Closes toast `id`: it slides out, and is gone once it has.
    pub fn close(t: *Toasts, id: u32) void {
        for (t.list[0..t.n]) |*x| if (x.id == id) {
            x.leaving = true;
        };
    }

    /// Removes toast `id` at once, without sliding out.
    pub fn dismiss(t: *Toasts, id: u32) void {
        for (t.list[0..t.n], 0..) |x, i| if (x.id == id) {
            std.mem.copyForwards(Toast, t.list[i .. t.n - 1], t.list[i + 1 .. t.n]);
            t.n -= 1;
            return;
        };
    }

    /// The toasts, those leaving too, oldest first.
    pub fn items(t: *const Toasts) []const Toast {
        return t.list[0..t.n];
    }
};

/// `s` cut to at most `n` bytes, at a character's start.
fn cut(s: []const u8, n: usize) []const u8 {
    if (s.len <= n) return s;
    var at = n;
    while (at > 0 and s[at] & 0xC0 == 0x80) at -= 1;
    return s[0..at];
}

/// Where the toasts stack.
pub const Corner = enum { bottom_right, bottom_center, bottom_left, top_right, top_center, top_left };

pub const Options = struct {
    corner: Corner = .bottom_right,
    /// A toast's width, and the room left to the window's edges, in points
    /// before `scale`. A window narrower than the width and its margins
    /// narrows the toasts to fit.
    width: f32 = 340,
    margin: f32 = 16,
    /// The text's size: the kit's text at `size` and half a point;
    /// `text_size` in points, over it. The title is the text's size, in
    /// its weight.
    size: kit.Size = .sm,
    text_size: ?f32 = null,
    /// The close button's tooltip, and its name to a screen reader.
    close_text: []const u8 = "Close",
    /// Over popovers, under tooltips (the kit layers them 20 and 30).
    layer: u8 = 25,
    scale: f32 = 1,
};

/// A toast's action was clicked; it is closing.
pub const Hit = struct {
    id: u32,
    tag: u32,
    payload: u64,
};

/// Draws the toasts, ages them, closes those whose time is up and drops
/// those that have slid out; returns the one whose action was clicked, if
/// one was.
pub fn toasts(c: *ui.Context, list: *Toasts, opts: Options) ?Hit {
    if (list.n == 0) return null;
    const t = kit.tokens(c);
    const k = opts.scale;
    const m = opts.margin * k;
    const w = @max(0, @min(opts.width * k, c.size.w - 2 * m));
    const size = opts.text_size orelse opts.size.text() + 0.5;
    const top = opts.corner == .top_right or opts.corner == .top_center or opts.corner == .top_left;
    // They come from the side they sit at, or from below or above when
    // centered.
    const from: ui.motion.Target = switch (opts.corner) {
        .bottom_right, .top_right => .{ .x = 40 * k, .opacity = 0 },
        .bottom_left, .top_left => .{ .x = -40 * k, .opacity = 0 },
        .bottom_center => .{ .y = 24 * k, .opacity = 0 },
        .top_center => .{ .y = -24 * k, .opacity = 0 },
    };
    // A layer over the window that takes no pointer itself, the toasts at
    // the corner's edge of it.
    var layer = ui.div(c).fixed().offset(0, 0).w(c.size.w).h(c.size.h).layer(opts.layer).column().p(m);
    layer = if (top) layer else layer.justifyEnd();
    layer = switch (opts.corner) {
        .bottom_right, .top_right => layer.itemsEnd(),
        .bottom_center, .top_center => layer.itemsCenter(),
        .bottom_left, .top_left => layer.itemsStart(),
    };
    defer layer.end();
    const stack = ui.div(c).column().w(w).gap(8 * k);
    defer stack.end();

    var hit: ?Hit = null;
    var gone: ?u32 = null;
    var soonest: f32 = std.math.inf(f32);
    // The room down the window, and what the toasts shown take of it.
    const room = c.size.h - 2 * m;
    const gap = 8 * k;
    var used: f32 = 0;
    var full = false;
    for (list.list[0..list.n]) |*toast| {
        // The oldest show first; one that doesn't fit after them waits,
        // and those after it, its time kept. One after others is measured
        // as it is first drawn, unseen, and said and timed once it is
        // shown; the first always fits.
        if (!full and used > 0 and toast.height > 0 and used + gap + toast.height > room) full = true;
        if (full) {
            if (toast.leaving) gone = gone orelse toast.id;
            if (toast.ends) |e| toast.left = @floatCast(@max(0, e - c.time));
            toast.ends = null;
            continue;
        }
        const shown = toast.height > 0 or used == 0;
        if (shown) used += (if (used > 0) gap else 0) + @max(toast.height, 1);
        const f = ui.motion.present(c, c.print("toast-{d}", .{toast.id}), !toast.leaving, .{
            .initial = from,
            .exit = from,
            .layout = true,
            .transition = .{ .spring = ui.motion.Spring.snappy },
        }) orelse {
            gone = gone orelse toast.id;
            continue;
        };
        const col = parts.statusColor(t, toast.status, null, .border);
        ui.key(c, c.print("toast-box-{d}", .{toast.id}));
        const box = ui.div(c).row().wFull().itemsCenter().gap(10 * k).px(12 * k).py(10 * k).rounded((t.radius + 2) * k)
            .bg(t.popover).border(if (toast.status == .neutral) t.border else col.alpha(0.55))
            .shadow(.{ .color = t.shadow.alpha(0.9), .blur = 24 * k, .y = 8 * k }).motion(f);
        const it = parts.still(c, box);
        defer box.end();
        if (measure.lastSize(c, box.index)) |s| toast.height = s.h;
        if (!shown) {
            c.node(box.index).style.opacity = 0;
            ui.access.hide(c, box.index);
        }
        const said = if (toast.title_len > 0) c.print("{s}. {s}", .{ toast.title(), toast.text() }) else toast.text();
        if (shown and !toast.announced) {
            ui.access.announce(c, said);
            toast.announced = true;
        }
        if (toast.status != .neutral) ui.icon(c, parts.statusIcon(toast.status), .{ .size = 14 * k, .color = col });
        {
            // Growing, as a callout's: the text takes the room, and wraps.
            // One element to a screen reader.
            const words = ui.div(c).column().grow().gap(2 * k);
            defer words.end();
            if (toast.title_len > 0) ui.text(c, toast.title(), .{ .size = size, .weight = .semibold, .color = t.foreground, .wrap = true });
            ui.text(c, toast.text(), .{ .size = size, .color = t.foreground, .wrap = true });
            ui.access.describe(c, words.index, .{ .role = .static_text, .label = said });
        }
        if (toast.leaving) continue;
        // A click on its buttons leaves the keyboard where it was: the
        // toast goes as it is pressed.
        var keyed = false;
        if (toast.action_len > 0) {
            ui.key(c, c.print("toast-action-{d}", .{toast.id}));
            const act = buttons.button(c, toast.action(), .{ .variant = .ghost, .size = .xs, .keep_keyboard = true });
            keyed = act.focused;
            if (act.clicked) {
                hit = .{ .id = toast.id, .tag = toast.tag, .payload = toast.payload };
                toast.leaving = true;
            }
        }
        ui.key(c, c.print("toast-close-{d}", .{toast.id}));
        const close = buttons.closeButton(c, opts.close_text, true);
        keyed = keyed or close.focused;
        if (close.clicked) toast.leaving = true;
        // Its time passes on the clock while neither the pointer nor the
        // keyboard is on it, not by the frames drawn: a window that draws
        // nothing else wakes only when it is up.
        if (shown and toast.seconds > 0 and !toast.leaving) {
            if (it.hovered or keyed) {
                if (toast.ends) |e| toast.left = @floatCast(@max(0, e - c.time));
                toast.ends = null;
            } else {
                const e = toast.ends orelse c.time + toast.left;
                toast.ends = e;
                if (c.time >= e) toast.leaving = true else soonest = @min(soonest, @as(f32, @floatCast(e - c.time)));
            }
        }
        if (toast.leaving) c.changed = true;
    }
    // One gone a frame is plenty.
    if (gone) |id| {
        list.dismiss(id);
        c.changed = true;
    }
    if (std.math.isFinite(soonest)) c.frameIn(soonest);
    return hit;
}

test {
    _ = @import("toasts_tests.zig");
}
