//! The callout's tests: its colors and icon, its text wrapping, an open
//! callout's button, its close button, its width, and what a screen
//! reader hears and is told.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const callout_mod = @import("callout.zig");
const callout = callout_mod.callout;
const calloutOpen = callout_mod.calloutOpen;
const Options = callout_mod.Options;

const Page = struct {
    text: []const u8 = "That folder doesn't exist.",
    opts: Options = .{},
    open: bool = false,
    closed: usize = 0,
    retried: usize = 0,
    box: u32 = 0,

    fn view(x: *Page, c: *ui.Context) void {
        const root = ui.div(c).column().w(300).p(8).gap(8);
        defer root.end();
        x.box = @intCast(c.nodes.items.len);
        if (x.open) {
            const r = calloutOpen(c, x.text, x.opts);
            if (kit.button(c, "Retry", .{ .size = .sm }).clicked) x.retried += 1;
            r.end();
        } else if (callout(c, x.text, x.opts)) x.closed += 1;
    }
};

fn start(x: *Page, t: *ui.Tester) !void {
    try t.init(std.testing.allocator, .init(x, Page.view), .{ .width = 320, .height = 200 });
    t.settle(1);
}

fn icon(t: *ui.Tester) ?[]const u8 {
    for (t.ctx.nodes.items) |n| switch (n.content) {
        .icon => |i| return i.name,
        else => {},
    };
    return null;
}

fn announced(t: *ui.Tester) []const u8 {
    return t.ctx.access.announcement[0..t.ctx.access.announcement_len];
}

test "a callout is the accent with an info icon by default, and a status's color and icon with one" {
    var x: Page = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const tk = kit.tokens(&t.ctx);
    try std.testing.expectEqualStrings("info.circle", icon(&t).?);
    try std.testing.expectEqual(tk.primary.alpha(0.25), t.ctx.nodes.items[x.box].style.border.?);
    x.opts = .{ .status = .warning };
    t.settle(1);
    try std.testing.expectEqualStrings("exclamationmark.triangle.fill", icon(&t).?);
    try std.testing.expectEqual(tk.warning.alpha(0.25), t.ctx.nodes.items[x.box].style.border.?);
    // Plain, there is no box.
    x.opts = .{ .plain = true };
    t.settle(1);
    try std.testing.expect(t.ctx.nodes.items[x.box].style.border == null);
}

test "a callout's text wraps within its parent, and with .auto it is as wide as its text" {
    var x: Page = .{ .text = "A message long enough that it has to wrap onto a second line in this pane." };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const r = t.ctx.rects.get(t.ctx.nodes.items[x.box].id).?;
    try std.testing.expectEqual(@as(f32, 284), r.w);
    try std.testing.expect(r.h > 40);
    x.text = "Short.";
    x.opts = .{ .width = .auto };
    t.settle(1);
    try std.testing.expect(t.ctx.rects.get(t.ctx.nodes.items[x.box].id).?.w < 120);
}

test "an open callout holds the caller's button at its end" {
    var x: Page = .{ .open = true };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const text = t.findText("That folder doesn't exist.").?;
    const retry = t.findText("Retry").?;
    try std.testing.expect(retry.x > text.x + text.w);
    try t.clickText("Retry");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.retried);
}

test "a closable callout's ✕ is named, reached by Tab, and says it was clicked" {
    var x: Page = .{ .opts = .{ .closable = true, .close_text = "Dismiss" } };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqualStrings("That folder doesn't exist.", list.items[0].label);
    try std.testing.expectEqualStrings("Dismiss", list.items[1].label);
    try std.testing.expectEqual(ui.access.Role.button, list.items[1].role);
    t.key(.tab);
    t.key(.enter);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.closed);
}

test "a screen reader hears a title and text as one, and a danger callout is said once, and again when it changes" {
    var x: Page = .{ .opts = .{ .status = .danger, .title = "Backup failed" } };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    try std.testing.expectEqualStrings("Backup failed. That folder doesn't exist.", announced(&t));
    t.ctx.access.announcement_len = 0;
    t.settle(1);
    t.frame();
    try std.testing.expectEqualStrings("", announced(&t));
    x.text = "The disk is full.";
    t.settle(1);
    try std.testing.expectEqualStrings("Backup failed. The disk is full.", announced(&t));
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings("Backup failed. The disk is full.", list.items[0].label);
}

test "a neutral callout isn't said unless asked, and a danger one not when told not to" {
    var x: Page = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    try std.testing.expectEqualStrings("", announced(&t));
    x.opts = .{ .announce = true };
    t.settle(1);
    try std.testing.expectEqualStrings("That folder doesn't exist.", announced(&t));
    t.ctx.access.announcement_len = 0;
    x.text = "Gone.";
    x.opts = .{ .status = .danger, .announce = false };
    t.settle(1);
    try std.testing.expectEqualStrings("", announced(&t));
}
