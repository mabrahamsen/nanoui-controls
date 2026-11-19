//! Tests of a form row's error as a screen reader hears it: in its
//! control's hint, and said once as it appears while the control has the
//! keyboard.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const form = @import("form.zig").form;

/// A row whose toggle may have an error, an ⓘ and a name of its own, and
/// a row after it without an error.
const Checked = struct {
    on: bool = true,
    err: []const u8 = "",
    name: []const u8 = "",
    fn view(x: *Checked, c: *ui.Context) void {
        const root = ui.div(c).column().w(400);
        defer root.end();
        var f = form(c, .{});
        {
            const r = f.row("Notify", .{ .err = x.err, .info = "When a backup ends." });
            _ = ui.toggle(c, x.name, &x.on);
            r.end();
        }
        {
            const r = f.row("Sound", .{});
            _ = ui.toggle(c, "", &x.on);
            r.end();
        }
        f.end();
    }
};

/// Two rows of text fields, the first of which may have an error.
const Typed = struct {
    email: ui.TextBuffer = .{},
    name: ui.TextBuffer = .{},
    err: []const u8 = "",
    fn view(x: *Typed, c: *ui.Context) void {
        const root = ui.div(c).column().w(400);
        defer root.end();
        var f = form(c, .{});
        {
            const r = f.row("Email", .{ .err = x.err });
            _ = ui.textField(c, &x.email, .{ .width = .fill });
            r.end();
        }
        {
            const r = f.row("Name", .{});
            _ = ui.textField(c, &x.name, .{ .width = .fill });
            r.end();
        }
        f.end();
    }
};

fn elements(t: *ui.Tester, arena: std.mem.Allocator) ![]const ui.access.Element {
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena, &list);
    return list.items;
}

fn announced(t: *ui.Tester) []const u8 {
    return t.ctx.access.announcement[0..t.ctx.access.announcement_len];
}

test "a row's error comes first in its control's hint, before the ⓘ's text, and goes with it" {
    var x: Checked = .{ .err = "Needs an email address first." };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Checked.view), .{ .width = 420, .height = 300 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("Needs an email address first., When a backup ends.", (try toggle(&t, arena.allocator(), "Notify")).hint);
    // The row without one keeps its hint empty.
    try std.testing.expectEqualStrings("", (try toggle(&t, arena.allocator(), "Sound")).hint);
    x.err = "";
    t.settle(1);
    try std.testing.expectEqualStrings("When a backup ends.", (try toggle(&t, arena.allocator(), "Notify")).hint);
}

/// The toggle a screen reader hears as `label`.
fn toggle(t: *ui.Tester, arena: std.mem.Allocator, label: []const u8) !ui.access.Element {
    for (try elements(t, arena)) |e| if (e.role == .switch_toggle and std.mem.eql(u8, e.label, label)) return e;
    return error.NotFound;
}

test "a control with a name of its own still hears its row's error" {
    var x: Checked = .{ .err = "Needs an email address first.", .name = "Email me" };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Checked.view), .{ .width = 420, .height = 300 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const list = try elements(&t, arena.allocator());
    var heard = false;
    for (list) |e| heard = heard or (std.mem.eql(u8, e.label, "Email me") and std.mem.startsWith(u8, e.hint, "Needs an email address first."));
    try std.testing.expect(heard);
}

test "an error is said once as it appears or changes on the control with the keyboard, and not on another" {
    var x: Typed = .{};
    defer x.email.deinit();
    defer x.name.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Typed.view), .{ .width = 420, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // The keyboard in the other field: it isn't said, but heard when the
    // field with it is reached.
    const name = t.findText("Name").?;
    t.click(300, name.y + name.h / 2);
    t.settle(1);
    x.err = "Needs an @.";
    t.settle(1);
    try std.testing.expectEqualStrings("", announced(&t));
    // In its own field: said as it appears.
    x.err = "";
    const email = t.findText("Email").?;
    t.click(300, email.y + email.h / 2);
    t.settle(1);
    x.err = "Needs an @.";
    t.frame();
    try std.testing.expectEqualStrings("Needs an @.", announced(&t));
    // Said once, not each frame.
    t.ctx.access.announcement_len = 0;
    t.settle(2);
    try std.testing.expectEqualStrings("", announced(&t));
    // A new error is said.
    x.err = "Not while a backup runs.";
    t.frame();
    try std.testing.expectEqualStrings("Not while a backup runs.", announced(&t));
}
