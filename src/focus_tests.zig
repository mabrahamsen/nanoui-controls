//! The tests of when the controls' ring shows: whenever a control has the
//! keyboard, or only while the keyboard is in use, with a click on a
//! button leaving the keyboard where it was.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const focus = @import("focus.zig");
const stat_mod = @import("stat.zig");
const swatches_mod = @import("swatches.zig");

/// The app's ring, a color nothing else is drawn in.
const ring: ui.Color = .hex(0xff00ff);

/// A text field, a stat button and swatches: a field to type in, a
/// button, and a control that takes keys of its own.
const Pane = struct {
    field: ui.TextBuffer = .{},
    chosen: ?usize = 0,
    clicks: usize = 0,
    field_focused: bool = false,

    const colors = [_]swatches_mod.Swatch{
        .{ .color = .hex(0x2060ff), .label = "Blue" },
        .{ .color = .hex(0x20c040), .label = "Green" },
    };

    fn view(x: *Pane, c: *ui.Context) void {
        const root = ui.div(c).column().w(240).gap(8);
        defer root.end();
        x.field_focused = ui.textField(c, &x.field, .{}).focused;
        if (stat_mod.statButton(c, "Alerts", "3", .{}).clicked) x.clicks += 1;
        _ = swatches_mod.swatches(c, &colors, &x.chosen, .{});
    }
};

fn start(x: *Pane, t: *ui.Tester) !void {
    try t.init(std.testing.allocator, .init(x, Pane.view), .{ .width = 300, .height = 300 });
    t.ctx.focus_ring = .{ .color = ring, .width = 3 };
    t.settle(1);
}

/// How many boxes are drawn in the app's ring.
fn ringed(t: *ui.Tester) usize {
    var n: usize = 0;
    for (t.ctx.nodes.items) |node| if (node.style.border) |b| if (std.meta.eql(b, ring)) {
        n += 1;
    };
    return n;
}

/// The middle of the chosen swatch, ringed two points wide.
fn swatchAt(t: *ui.Tester) struct { x: f32, y: f32 } {
    for (t.ctx.nodes.items) |node| if (node.style.border_width == 2) if (t.ctx.rects.get(node.id)) |r| {
        return .{ .x = r.x + r.w / 2, .y = r.y + r.h / 2 };
    };
    return .{ .x = 0, .y = 0 };
}

test "by default, a control rings whenever it has the keyboard, and a click on a button takes it" {
    var x: Pane = .{};
    defer x.field.deinit();
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    try t.clickText("Alerts");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.clicks);
    try std.testing.expect(!x.field_focused);
    try std.testing.expect(ringed(&t) >= 1);
}

test "with .keyboard, a click on a button acts and leaves the keyboard where it was, without a ring" {
    focus.setRingShows(.keyboard);
    defer focus.setRingShows(.focused);
    var x: Pane = .{};
    defer x.field.deinit();
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    t.key(.tab);
    t.settle(1);
    try std.testing.expect(x.field_focused);
    try t.clickText("Alerts");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.clicks);
    try std.testing.expect(x.field_focused);
    try std.testing.expectEqual(@as(usize, 0), ringed(&t));
}

test "with .keyboard, Tab rings a button, a key clicks it, and the pointer takes the ring off" {
    focus.setRingShows(.keyboard);
    defer focus.setRingShows(.focused);
    var x: Pane = .{};
    defer x.field.deinit();
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    t.key(.tab);
    t.key(.tab);
    t.settle(1);
    try std.testing.expect(!x.field_focused);
    try std.testing.expect(ringed(&t) >= 1);
    t.key(.enter);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.clicks);
    // Moving the pointer hides it, nanoui's ring and the stat's; the stat
    // keeps the keyboard.
    t.moveTo(290, 290);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 0), ringed(&t));
    t.key(.enter);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 2), x.clicks);
    try std.testing.expect(ringed(&t) >= 1);
}

test "with .keyboard, a control with keys of its own takes the keyboard on a click, ringed only once a key is used" {
    focus.setRingShows(.keyboard);
    defer focus.setRingShows(.focused);
    var x: Pane = .{};
    defer x.field.deinit();
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const at = swatchAt(&t);
    try std.testing.expect(at.y > 0);
    t.click(at.x, at.y);
    t.settle(1);
    try std.testing.expect(!x.field_focused);
    try std.testing.expectEqual(@as(usize, 0), ringed(&t));
    // Its keys are its own, and now the ring shows.
    t.key(.right);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 1), x.chosen);
    try std.testing.expectEqual(@as(usize, 1), ringed(&t));
}

test "a click on what only shows a tooltip, or is disabled, leaves the keyboard where it was, without a hand" {
    const form_mod = @import("form.zig");
    const T = struct {
        field: ui.TextBuffer = .{},
        chosen: ?usize = 0,
        field_focused: bool = false,
        fn view(x: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(300).gap(8);
            defer root.end();
            x.field_focused = ui.textField(c, &x.field, .{}).focused;
            _ = swatches_mod.swatches(c, &Pane.colors, &x.chosen, .{ .disabled = true });
            var f = form_mod.form(c, .{});
            const r = f.row("Port", .{ .info = "The port the server listens on." });
            ui.text(c, "8080", .{});
            r.end();
            f.end();
        }
    };
    var x: T = .{};
    defer x.field.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 320, .height = 200 });
    defer t.deinit();
    t.settle(1);
    t.key(.tab);
    t.settle(1);
    try std.testing.expect(x.field_focused);
    const at = swatchAt(&t);
    t.moveTo(at.x, at.y);
    try std.testing.expect(!t.ctx.cursor_hand);
    t.click(at.x, at.y);
    t.settle(1);
    try std.testing.expect(x.field_focused);
    // The ⓘ after the label.
    const port = t.findText("Port").?;
    t.moveTo(port.x + port.w + 8, port.y + port.h / 2);
    try std.testing.expect(!t.ctx.cursor_hand);
    t.click(port.x + port.w + 8, port.y + port.h / 2);
    t.settle(1);
    try std.testing.expect(x.field_focused);
}
