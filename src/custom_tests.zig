//! The tests of the parts for building controls, used from outside as an
//! app would: a tile that is a button in a surface, a list that takes the
//! keyboard for its rows and moves with the arrows, and a label that
//! measures itself.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const controls = @import("controls.zig");
const custom = controls.custom;

/// The app's ring, a color nothing else is drawn in.
const ring: ui.Color = .hex(0xff00ff);

/// A tile of the app's own: a button in a surface, its ring drawn when
/// the controls' would be, dimmed when disabled.
const Tile = struct {
    card: controls.Surface = .{},
    disabled: bool = false,
    clicks: usize = 0,
    focused: bool = false,
    box: u32 = 0,

    fn view(x: *Tile, c: *ui.Context) void {
        const root = ui.div(c).column().w(240).p(8).gap(8);
        defer root.end();
        _ = kit.button(c, "Before", .{});
        var box = custom.surface(c, x.card, .{ .fill = kit.tokens(c).surface, .px = 10, .py = 8, .width = .{ .px = 120 } });
        defer box.end();
        x.box = box.index;
        if (x.disabled) box = box.opacity(custom.dimmed);
        const it = custom.button(c, box.index, !x.disabled);
        x.focused = it.focused;
        if (custom.showRing(c, it.focused)) box = box.border(custom.ring(c)).borderW(custom.ringWidth(c));
        if (it.clicked and !x.disabled) x.clicks += 1;
        ui.text(c, "Tile", .{});
    }
};

fn startTile(x: *Tile, t: *ui.Tester) !void {
    try t.init(std.testing.allocator, .init(x, Tile.view), .{ .width = 300, .height = 200 });
    t.ctx.focus_ring = .{ .color = ring, .width = 3 };
    t.settle(1);
}

test "a box made a button in a surface: Tab reaches it, Enter clicks it, and its ring is the app's" {
    var x: Tile = .{ .card = .{ .px = 14 } };
    var t: ui.Tester = undefined;
    try startTile(&x, &t);
    defer t.deinit();
    // The caller's surface over the control's own, its lengths as given.
    const n = t.ctx.nodes.items[x.box];
    try std.testing.expectEqual(@as(f32, 14), n.style.padding.left);
    try std.testing.expectEqual(@as(f32, 8), n.style.padding.top);
    try std.testing.expectEqual(ui.Length{ .px = 120 }, n.style.width);
    t.key(.tab);
    t.key(.tab);
    t.settle(1);
    try std.testing.expect(x.focused);
    try std.testing.expectEqual(ring, t.ctx.nodes.items[x.box].style.border.?);
    try std.testing.expectEqual(@as(f32, 3), t.ctx.nodes.items[x.box].style.border_width);
    t.key(.enter);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.clicks);
    try t.clickText("Tile");
    try std.testing.expectEqual(@as(usize, 2), x.clicks);
}

test "with rings for the keyboard only, a click on the box acts and leaves the keyboard where it was" {
    controls.setFocusRingShows(.keyboard);
    defer controls.setFocusRingShows(.focused);
    var x: Tile = .{};
    var t: ui.Tester = undefined;
    try startTile(&x, &t);
    defer t.deinit();
    try t.clickText("Tile");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.clicks);
    try std.testing.expect(!x.focused);
    try std.testing.expect(t.ctx.nodes.items[x.box].style.border == null);
}

test "a disabled box is dimmed as the controls dim, passed by Tab and takes no click" {
    var x: Tile = .{ .disabled = true };
    var t: ui.Tester = undefined;
    try startTile(&x, &t);
    defer t.deinit();
    try std.testing.expectEqual(custom.dimmed, t.ctx.nodes.items[x.box].style.opacity);
    t.key(.tab);
    t.key(.tab);
    t.settle(1);
    try std.testing.expect(!x.focused);
    try t.clickText("Tile");
    try std.testing.expectEqual(@as(usize, 0), x.clicks);
}

/// A list of the app's own: a stop for Tab whose clicks go to its rows,
/// moving with Up and Down, its keys taken before the app's shortcuts.
const List = struct {
    chosen: usize = 0,
    wants: bool = true,
    focused: bool = false,

    fn view(x: *List, c: *ui.Context) void {
        const box = ui.div(c).column().w(200).p(4);
        defer box.end();
        const own = custom.takeIf(c, box, x.wants);
        x.focused = own.focused;
        if (own.focused) {
            custom.keysOf(c, &.{ .up, .down });
            if (c.input.key) |k| switch (k) {
                .up => x.chosen -|= 1,
                .down => x.chosen = @min(x.chosen + 1, 2),
                else => {},
            };
        }
        for (0..3) |i| {
            ui.keyInt(c, i);
            const row = ui.div(c).row().p(4).control();
            if (row.clicked()) {
                x.chosen = i;
                c.focus = own.id;
            }
            ui.text(c, c.print("Row {d}", .{i}), .{});
            row.end();
        }
    }
};

test "a box that takes the keyboard for its rows, its keys its own before the app's shortcuts" {
    var x: List = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, List.view), .{ .width = 300, .height = 200 });
    defer t.deinit();
    t.settle(1);
    // Without the keyboard, Down is the app's shortcut.
    try std.testing.expect(!t.shortcut(.{ .key = ui.Shortcut.down }));
    try t.clickText("Row 1");
    t.settle(1);
    try std.testing.expect(x.focused);
    try std.testing.expectEqual(@as(usize, 1), x.chosen);
    try std.testing.expect(t.shortcut(.{ .key = ui.Shortcut.down }));
    try std.testing.expectEqual(@as(usize, 2), x.chosen);
    t.key(.up);
    try std.testing.expectEqual(@as(usize, 1), x.chosen);
    // Not wanting the keyboard, it gives it up and Tab passes it.
    x.wants = false;
    t.settle(1);
    try std.testing.expect(!x.focused);
}

/// A label that knows its box's width from the last frame, and whether
/// its text was cut short.
const Measured = struct {
    width: f32 = 300,
    room: ?f32 = null,
    cut: bool = false,

    fn view(x: *Measured, c: *ui.Context) void {
        const root = ui.div(c).column().w(x.width);
        defer root.end();
        const box = ui.div(c).row().wFull();
        defer box.end();
        x.room = if (custom.lastSize(c, box.index)) |s| s.w else null;
        const style: ui.TextStyle = .{ .truncate = .ellipsis };
        ui.text(c, "A label long enough to be cut short", style);
        x.cut = custom.cutOff(c, "A label long enough to be cut short", style);
    }
};

test "a box's size from the last frame, a frame drawn at once when it changes, and text cut short" {
    var x: Measured = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Measured.view), .{ .width = 400, .height = 100 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expectEqual(@as(?f32, 300), x.room);
    try std.testing.expect(!x.cut);
    // Narrowed: the frame that lays it out still reads the old width, and
    // the size it leaves asks for the next frame, which reads the new.
    x.width = 80;
    t.frame();
    try std.testing.expectEqual(@as(?f32, 300), x.room);
    t.settle(1);
    try std.testing.expectEqual(@as(?f32, 80), x.room);
    try std.testing.expect(x.cut);
}

test "a length in points takes scale, one relative to the parent doesn't" {
    try std.testing.expectEqual(ui.Length{ .px = 24 }, custom.scaled(.{ .px = 12 }, 2));
    try std.testing.expectEqual(ui.Length.fill, custom.scaled(.fill, 2));
}
