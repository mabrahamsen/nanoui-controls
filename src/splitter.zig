//! A splitter: a handle between two panes side by side that resizes one
//! of them. Drag it, or give it the keyboard (a click or Tab) and move it
//! with Left and Right, Home and End; a screen reader hears a splitter
//! with the width as its value, and steps it. The caller keeps the width
//! and draws the panes.
//!
//!     const row = ui.div(c).row().sizeFull();
//!     const side = ui.div(c).w(width).hFull();
//!     sidebar(c);
//!     side.end();
//!     _ = controls.splitter(c, &width, .{ .min = 160, .max = 400, .label = "Sidebar width" });
//!     content(c);
//!     row.end();
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const focus = @import("focus.zig");

/// The pane a splitter resizes: the one before it, or the one after it.
pub const Pane = enum { start, end };

pub const Options = struct {
    /// The narrowest and widest the pane may be.
    min: f32 = 0,
    max: f32 = std.math.inf(f32),
    /// The pane it resizes: the one before it, at the start, which widens
    /// as the splitter moves toward the end; or the one after it, at the
    /// end, which narrows.
    pane: Pane = .start,
    /// How far Left and Right, and a screen reader's step, move it.
    step: f32 = 10,
    /// The handle's width, where the pointer can grab it.
    grab_width: f32 = 7,
    /// A line down the handle's middle, between the panes.
    center_line: bool = true,
    /// What a screen reader calls it ("Sidebar width").
    label: []const u8 = "",
    /// Multiplies its lengths, for an app that zooms its layout along with
    /// `c.setZoom`, as the grid's does: `width.*` is in points before it.
    scale: f32 = 1,
};

/// Draws the handle, as tall as its parent, and moves `width.*` (the
/// pane's, in points) as the user drags it or uses the keys; true when it
/// changed.
pub fn splitter(c: *ui.Context, width: *f32, opts: Options) bool {
    const t = kit.tokens(c);
    const k = opts.scale;
    const d = ui.div(c).w(opts.grab_width * k).hFull().row().justifyCenter();
    defer d.end();
    const it = c.interact(d.index, .{ .focusable = true });
    const drag = c.state(struct { on: bool = false, x: f32 = 0, width: f32 = 0 }, "splitter");
    const lit = it.hovered or it.pressed or drag.on;
    if (lit) c.cursor = .resize_left_right;
    if (opts.center_line or lit or it.focused) {
        const col = if (it.focused) focus.ring(c) else if (lit) t.muted else t.border;
        ui.div(c).w(if (lit or it.focused) 2 else 1).hFull().bg(col).end();
    }
    const way: f32 = if (opts.pane == .start) 1 else -1;
    const before = width.*;
    if (it.pressed) {
        if (!drag.on) {
            drag.* = .{ .on = true, .x = c.input.mouse.x, .width = width.* };
        } else width.* = drag.width + way * (c.input.mouse.x - drag.x) / k;
    } else drag.on = false;
    if (it.a11y_step != 0) width.* += @as(f32, @floatFromInt(it.a11y_step)) * opts.step;
    // The keys it moves by are its own: nothing after it sees them.
    if (it.focused) if (c.input.key) |key| {
        switch (key) {
            .left => width.* -= way * opts.step,
            .right => width.* += way * opts.step,
            // To a bound, when it has one.
            .home => width.* = bound(if (opts.pane == .start) opts.min else opts.max, width.*),
            .end => width.* = bound(if (opts.pane == .start) opts.max else opts.min, width.*),
            else => {},
        }
        if (key == .left or key == .right or key == .home or key == .end) c.input.key = null;
    };
    width.* = std.math.clamp(width.*, opts.min, @max(opts.min, opts.max));
    c.adjustable(d.index, .{ .role = .splitter, .label = opts.label, .value = c.print("{d:.0}", .{width.*}) });
    if (width.* != before) c.changed = true;
    return width.* != before;
}

/// `to`, or `at` when `to` is no bound (infinite).
fn bound(to: f32, at: f32) f32 {
    return if (std.math.isFinite(to)) to else at;
}

const Panes = struct {
    width: f32 = 200,
    changed: usize = 0,
    /// Keys left for the app after the splitter.
    leaked: usize = 0,
    fn view(p: *Panes, c: *ui.Context) void {
        const row = ui.div(c).row().sizeFull();
        defer row.end();
        ui.div(c).w(p.width).hFull().end();
        if (splitter(c, &p.width, .{ .min = 100, .max = 300, .label = "Sidebar width" })) p.changed += 1;
        if (c.input.key != null) p.leaked += 1;
        ui.div(c).wFull().hFull().end();
    }
};

test "dragging a splitter resizes its pane, within its bounds" {
    var p: Panes = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Panes.view), .{ .width = 500, .height = 200 });
    defer t.deinit();
    t.settle(1);
    // The handle is 7 points wide, after the 200-point pane.
    t.drag(203, 100, 243, 100);
    t.settle(1);
    try std.testing.expectEqual(@as(f32, 240), p.width);
    try std.testing.expect(p.changed > 0);
    t.drag(243, 100, 450, 100);
    t.settle(1);
    try std.testing.expectEqual(@as(f32, 300), p.width);
    t.drag(303, 100, 10, 100);
    t.settle(1);
    try std.testing.expectEqual(@as(f32, 100), p.width);
}

test "a splitter takes the keyboard, and the keys move it" {
    var p: Panes = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Panes.view), .{ .width = 500, .height = 200 });
    defer t.deinit();
    t.settle(1);
    t.key(.right);
    try std.testing.expectEqual(@as(f32, 200), p.width);
    t.key(.tab);
    t.settle(1);
    // Keys before it had the keyboard were the app's.
    p.leaked = 0;
    t.key(.right);
    try std.testing.expectEqual(@as(f32, 210), p.width);
    t.key(.left);
    t.key(.left);
    try std.testing.expectEqual(@as(f32, 190), p.width);
    t.key(.end);
    try std.testing.expectEqual(@as(f32, 300), p.width);
    t.key(.home);
    try std.testing.expectEqual(@as(f32, 100), p.width);
    // The keys it moves by are its own.
    try std.testing.expectEqual(@as(usize, 0), p.leaked);
}

test "a screen reader hears a splitter with its width, and steps it" {
    var p: Panes = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Panes.view), .{ .width = 500, .height = 200 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqual(ui.access.Role.splitter, list.items[0].role);
    try std.testing.expectEqualStrings("Sidebar width", list.items[0].label);
    try std.testing.expectEqualStrings("200", list.items[0].value);
    try std.testing.expect(list.items[0].adjustable);
    t.ctx.a11yStep(list.items[0].id, 1);
    t.settle(1);
    try std.testing.expectEqual(@as(f32, 210), p.width);
}

test "End on a splitter without a widest leaves the width as it is" {
    const T = struct {
        width: f32 = 200,
        fn view(x: *@This(), c: *ui.Context) void {
            const row = ui.div(c).row().sizeFull();
            defer row.end();
            ui.div(c).w(x.width).hFull().end();
            _ = splitter(c, &x.width, .{ .min = 100 });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 500, .height = 200 });
    defer t.deinit();
    t.settle(1);
    t.key(.tab);
    t.settle(1);
    t.key(.end);
    try std.testing.expectEqual(@as(f32, 200), x.width);
    t.key(.home);
    try std.testing.expectEqual(@as(f32, 100), x.width);
}
