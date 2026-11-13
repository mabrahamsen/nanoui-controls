//! The toasts' tests: the list they are kept in, where and how they show,
//! their action and close buttons, their time, and what a screen reader
//! hears.

const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const toast_mod = @import("toasts.zig");
const max = toast_mod.max;
const Toasts = toast_mod.Toasts;
const Corner = toast_mod.Corner;
const Hit = toast_mod.Hit;
const toasts = toast_mod.toasts;

test "toasts keep the newest, copy their text, and close" {
    var list: Toasts = .{};
    var buf: [16]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "saved {d}", .{3}) catch unreachable;
    const first = list.show(msg, .{ .status = .success });
    @memset(&buf, 'x');
    try std.testing.expectEqualStrings("saved 3", list.items()[0].text());
    for (0..max) |i| _ = list.show(std.fmt.bufPrint(&buf, "more {d}", .{i}) catch unreachable, .{ .tag = @intCast(i) });
    // The same again: shown once.
    _ = list.show("more 0", .{});
    try std.testing.expectEqual(@as(usize, max), list.n);
    // The first pushed out by the last.
    for (list.items()) |x| try std.testing.expect(x.id != first);
    list.dismiss(list.items()[0].id);
    try std.testing.expectEqual(@as(usize, max - 1), list.n);
    // A long text is cut at a character.
    var long: [300]u8 = undefined;
    for (0..150) |i| @memcpy(long[i * 2 ..][0..2], "é");
    _ = list.show(&long, .{});
    try std.testing.expect(std.unicode.utf8ValidateSlice(list.items()[list.n - 1].text()));
}

test "a toast shows, its action is clicked, and one times out" {
    const T = struct {
        list: Toasts = .{},
        hit: ?Hit = null,
        fn view(x: *@This(), c: *ui.Context) void {
            const page = ui.div(c).sizeFull();
            page.end();
            if (toasts(c, &x.list, .{})) |h| x.hit = h;
        }
    };
    var x: T = .{};
    _ = x.list.show("Restored 120 files", .{ .status = .success, .action = "Show", .tag = 7, .payload = 42 });
    _ = x.list.show("Gone soon", .{ .seconds = 0.05 });
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 600, .height = 400 });
    defer t.deinit();
    t.settle(1);
    for (0..2) |_| t.frame();
    try std.testing.expect(t.hasText("Restored 120 files"));
    // In the bottom right corner.
    const r = t.findText("Restored 120 files").?;
    try std.testing.expect(r.x > 600 - 340 - 16 and r.y > 200);
    // Time passes: the short one slides out, the other stays.
    for (0..10) |_| t.frame();
    t.settle(1);
    try std.testing.expect(!t.hasText("Gone soon"));
    try std.testing.expect(t.hasText("Restored 120 files"));
    try t.clickText("Show");
    t.frame();
    try std.testing.expectEqual(@as(u32, 7), x.hit.?.tag);
    try std.testing.expectEqual(@as(u64, 42), x.hit.?.payload);
    // Clicked, it slides out, and is gone once it has.
    try std.testing.expect(x.list.items()[0].leaving);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 0), x.list.n);
}

test "a toast slides in, its title and text heard as one" {
    const T = struct {
        list: Toasts = .{},
        fn view(x: *@This(), c: *ui.Context) void {
            ui.div(c).sizeFull().end();
            _ = toasts(c, &x.list, .{});
        }
    };
    var x: T = .{};
    _ = x.list.show("The repository is locked by another client.", .{ .status = .danger, .title = "Backup failed" });
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 600, .height = 400 });
    defer t.deinit();
    t.frame();
    const a = &t.ctx.access;
    try std.testing.expectEqualStrings("Backup failed. The repository is locked by another client.", a.announcement[0..a.announcement_len]);
    const first = t.findText("Backup failed").?.x;
    t.settle(1);
    const settled = t.findText("Backup failed").?;
    // From the right, to its place.
    try std.testing.expect(first > settled.x);
    try std.testing.expect(settled.y < t.findText("The repository is locked by another client.").?.y);
}

test "with reduced motion a toast comes and goes at once" {
    const T = struct {
        list: Toasts = .{},
        fn view(x: *@This(), c: *ui.Context) void {
            c.reduced_motion = true;
            ui.div(c).sizeFull().end();
            _ = toasts(c, &x.list, .{});
        }
    };
    var x: T = .{};
    const id = x.list.show("Saved", .{});
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 600, .height = 400 });
    defer t.deinit();
    t.frame();
    const at = t.findText("Saved").?.x;
    t.frame();
    try std.testing.expectEqual(at, t.findText("Saved").?.x);
    x.list.close(id);
    t.frame();
    t.frame();
    try std.testing.expectEqual(@as(usize, 0), x.list.n);
}

test "toasts sit in their corner, and narrow to a narrow window" {
    const T = struct {
        list: Toasts = .{},
        corner: Corner = .top_left,
        fn view(x: *@This(), c: *ui.Context) void {
            ui.div(c).sizeFull().end();
            _ = toasts(c, &x.list, .{ .corner = x.corner });
        }
    };
    var x: T = .{};
    _ = x.list.show("Saved", .{ .seconds = 0 });
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 600, .height = 400 });
    defer t.deinit();
    t.settle(1);
    const r = t.findText("Saved").?;
    try std.testing.expect(r.x < 60 and r.y < 60);
    x.corner = .bottom_center;
    t.settle(1);
    const b = t.findText("Saved").?;
    // Centered: (600 - 340) / 2, and 12 points of padding.
    try std.testing.expectApproxEqAbs(@as(f32, 142), b.x, 0.5);
    try std.testing.expect(b.y > 300);
    // A window narrower than a toast: it fits, inside its margins.
    t.resize(240, 400);
    t.settle(1);
    for (t.ctx.nodes.items) |node| if (node.style.background != null and node.style.shadow != null) {
        try std.testing.expect(node.rect.x >= 16 - 0.5 and node.rect.x + node.rect.w <= 240 - 16 + 0.5);
    };
}

test "a toast's close button is named, and closes it" {
    const T = struct {
        list: Toasts = .{},
        fn view(x: *@This(), c: *ui.Context) void {
            ui.div(c).sizeFull().end();
            _ = toasts(c, &x.list, .{ .close_text = "Dismiss" });
        }
    };
    var x: T = .{};
    _ = x.list.show("Saved", .{ .seconds = 0 });
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 600, .height = 400 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tree: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &tree);
    var id: ?u64 = null;
    for (tree.items) |e| if (std.mem.eql(u8, e.label, "Dismiss")) {
        id = e.id;
    };
    t.ctx.a11yPress(id orelse return error.TestExpectedEqual);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 0), x.list.n);
}

test "a toast's seconds are the clock's, however few frames the window draws" {
    const T = struct {
        list: Toasts = .{},
        fn view(x: *@This(), c: *ui.Context) void {
            const page = ui.div(c).sizeFull();
            page.end();
            _ = toasts(c, &x.list, .{});
        }
    };
    var x: T = .{};
    _ = x.list.show("Saved", .{ .seconds = 4 });
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 600, .height = 400 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(!x.list.items()[0].leaving);
    // Nothing else draws: the window wakes once, when the toast asked,
    // its frame one refresh after the last.
    t.time += 5;
    t.frame();
    try std.testing.expect(x.list.n == 0 or x.list.items()[0].leaving);
}

test "a toast's time stops while the pointer rests on it" {
    const T = struct {
        list: Toasts = .{},
        fn view(x: *@This(), c: *ui.Context) void {
            const page = ui.div(c).sizeFull();
            page.end();
            _ = toasts(c, &x.list, .{});
        }
    };
    var x: T = .{};
    _ = x.list.show("Saved", .{ .seconds = 4 });
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 600, .height = 400 });
    defer t.deinit();
    t.settle(1);
    const r = t.findText("Saved").?;
    t.moveTo(r.x + 2, r.y + 2);
    t.frame();
    t.time += 10;
    t.frame();
    try std.testing.expect(!x.list.items()[0].leaving);
    t.moveTo(2, 2);
    t.frame();
    t.time += 2;
    t.frame();
    try std.testing.expect(!x.list.items()[0].leaving);
    t.time += 3;
    t.frame();
    try std.testing.expect(x.list.n == 0 or x.list.items()[0].leaving);
}

test "a click on a toast's button leaves the keyboard in the field, and Tab reaches its buttons" {
    const T = struct {
        list: Toasts = .{},
        field: ui.TextBuffer = .{},
        undone: usize = 0,
        fn view(x: *@This(), c: *ui.Context) void {
            const page = ui.div(c).sizeFull().p(8);
            _ = ui.textField(c, &x.field, .{ .width = .{ .px = 160 } });
            page.end();
            if (toasts(c, &x.list, .{})) |_| x.undone += 1;
        }
    };
    var x: T = .{};
    defer x.field.deinit();
    _ = x.list.show("Moved to the Trash", .{ .action = "Undo", .seconds = 0 });
    _ = x.list.show("Saved", .{ .seconds = 0 });
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 600, .height = 400 });
    defer t.deinit();
    t.settle(1);
    t.key(.tab);
    t.settle(1);
    const field = t.ctx.focus;
    try std.testing.expect(field != 0);
    try t.clickText("Undo");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.undone);
    try std.testing.expectEqual(field, t.ctx.focus);
    // Tab goes on from the field to the other toast's close button, and
    // Enter presses it.
    t.key(.tab);
    t.key(.enter);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 0), x.list.n);
}
