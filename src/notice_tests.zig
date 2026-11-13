//! The notice's tests: its colors and icon, a spinner while loading, its
//! description centered and wrapped, an open notice's button, and what a
//! screen reader hears and is told.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const notice_mod = @import("notice.zig");
const Options = notice_mod.Options;

const Pane = struct {
    opts: Options = .{ .icon = "tray", .title = "No snapshots yet", .description = "They show here." },
    open: bool = false,
    started: usize = 0,

    fn view(x: *Pane, c: *ui.Context) void {
        const root = ui.div(c).column().w(320).p(8);
        defer root.end();
        if (x.open) {
            const n = notice_mod.noticeOpen(c, x.opts);
            if (kit.button(c, "Start", .{ .variant = .primary }).clicked) x.started += 1;
            n.end();
        } else notice_mod.notice(c, x.opts);
    }
};

fn start(x: *Pane, t: *ui.Tester) !void {
    try t.init(std.testing.allocator, .init(x, Pane.view), .{ .width = 340, .height = 300 });
    t.settle(1);
}

fn iconNode(t: *ui.Tester) ?@TypeOf(t.ctx.nodes.items[0].content.icon) {
    for (t.ctx.nodes.items) |n| switch (n.content) {
        .icon => |i| return i,
        else => {},
    };
    return null;
}

test "a notice is the accent with its icon over its title and description, centered, and proportional" {
    var x: Pane = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const tk = kit.tokens(&t.ctx);
    const ic = iconNode(&t).?;
    try std.testing.expectEqualStrings("tray", ic.name);
    try std.testing.expectEqual(tk.primary, ic.color);
    const title = t.findText("No snapshots yet").?;
    const desc = t.findText("They show here.").?;
    try std.testing.expect(desc.y > title.y);
    // Both centered in the panel, which spans 8 to 312.
    try std.testing.expectApproxEqAbs(@as(f32, 160), title.x + title.w / 2, 1.5);
    try std.testing.expectApproxEqAbs(@as(f32, 160), desc.x + desc.w / 2, 1.5);
    for (t.ctx.nodes.items) |n| switch (n.content) {
        .text => |s| if (std.mem.eql(u8, s.str, "No snapshots yet")) try std.testing.expect(!s.style.mono),
        else => {},
    };
}

test "a status colors the title and icon, and its icon is the status's" {
    var x: Pane = .{ .opts = .{ .title = "Server stopped", .status = .warning } };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const ic = iconNode(&t).?;
    try std.testing.expectEqualStrings("exclamationmark.triangle.fill", ic.name);
    try std.testing.expectEqual(kit.tokens(&t.ctx).warning, ic.color);
}

test "loading, a spinner stands where the icon was, and the title doesn't move" {
    var x: Pane = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const before = t.findText("No snapshots yet").?.y;
    x.opts.loading = true;
    t.settle(1);
    try std.testing.expectEqual(before, t.findText("No snapshots yet").?.y);
    try std.testing.expectEqual(@as(f32, 0), iconNode(&t).?.color.a);
}

test "a long description wraps within the panel in lines of about one length" {
    var x: Pane = .{ .opts = .{ .title = "Nothing here", .description = "Add a folder to back up, and its snapshots will show here as they are made, newest first." } };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    t.settle(1);
    const desc = t.findText("Add a folder to back up, and its snapshots will show here as they are made, newest first.").?;
    try std.testing.expect(desc.h > 20);
    try std.testing.expect(desc.w <= 276);
    try std.testing.expectApproxEqAbs(@as(f32, 160), desc.x + desc.w / 2, 1.5);
}

test "an open notice holds a button under its description" {
    var x: Pane = .{ .open = true };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    try std.testing.expect(t.findText("Start").?.y > t.findText("They show here.").?.y);
    try t.clickText("Start");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.started);
}

test "a screen reader hears the title as a heading, then the description, and with announce is told once" {
    var x: Pane = .{};
    x.opts.announce = true;
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    try std.testing.expectEqualStrings("No snapshots yet. They show here.", t.ctx.access.announcement[0..t.ctx.access.announcement_len]);
    t.ctx.access.announcement_len = 0;
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 0), t.ctx.access.announcement_len);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqualStrings("No snapshots yet", list.items[0].label);
    try std.testing.expect(list.items[0].header);
    try std.testing.expectEqualStrings("They show here.", list.items[1].label);
}

test "a notice without a title is said by its description alone" {
    var x: Pane = .{ .opts = .{ .description = "Nothing to show yet.", .announce = true } };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    try std.testing.expectEqualStrings("Nothing to show yet.", t.ctx.access.announcement[0..t.ctx.access.announcement_len]);
}
