//! The input box's tests: its glow, its buttons named and working and
//! giving the field the keyboard back, a plain box, a disabled one, its
//! width, two boxes, and a secret kept from a screen reader.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const box_mod = @import("input_box.zig");
const inputBox = box_mod.inputBox;

fn elements(t: *ui.Tester, arena: *std.heap.ArenaAllocator) ![]const ui.access.Element {
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    return list.items;
}

/// Presses the element a screen reader calls `name`, as VoiceOver does.
fn press(t: *ui.Tester, name: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    for (try elements(t, &arena)) |e| if (std.mem.eql(u8, e.label, name)) {
        t.ctx.a11yPress(e.id);
        t.frame();
        return;
    };
    return error.TestExpectedEqual;
}

const Secret = struct {
    buf: ui.TextBuffer = .{},
    shown: bool = false,
    cleared: bool = false,
    pasted: bool = false,
    clearable: ?bool = null,
    border: ?ui.Color = null,

    fn view(x: *Secret, c: *ui.Context) void {
        const before: u32 = @intCast(c.nodes.items.len);
        const r = inputBox(c, &x.buf, .{ .icon = "lock", .label = "Password", .shown = &x.shown, .paste = true, .clearable = x.clearable });
        x.border = c.node(before).style.border;
        if (r.cleared) {
            x.cleared = true;
            x.buf.set("");
        }
        if (r.pasted) x.pasted = true;
    }
};

test "an input box glows while it has the keyboard, and its buttons are named and work" {
    var x: Secret = .{ .clearable = true };
    defer x.buf.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Secret.view), .{ .width = 520, .height = 80 });
    defer t.deinit();
    t.settle(1);
    const tk = kit.tokens(&t.ctx);
    try std.testing.expectEqual(@as(?ui.Color, tk.border), x.border);
    x.buf.focus();
    t.settle(1);
    try std.testing.expectEqual(@as(?ui.Color, tk.primary.alpha(0.7)), x.border);
    t.typeText("hunter2");
    t.frame();
    try press(&t, "Show");
    try std.testing.expect(x.shown);
    try press(&t, "Hide");
    try std.testing.expect(!x.shown);
    try press(&t, "Paste");
    try std.testing.expect(x.pasted);
    try press(&t, "Clear");
    try std.testing.expect(x.cleared);
    try std.testing.expectEqual(@as(usize, 0), x.buf.text().len);
}

test "a click on the eye leaves the field the keyboard, and Tab reaches each button" {
    var x: Secret = .{};
    defer x.buf.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Secret.view), .{ .width = 520, .height = 80 });
    defer t.deinit();
    t.settle(1);
    x.buf.focus();
    t.settle(1);
    t.typeText("hun");
    t.frame();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    for (try elements(&t, &arena)) |e| if (std.mem.eql(u8, e.label, "Show")) t.click(e.rect.x + e.rect.w / 2, e.rect.y + e.rect.h / 2);
    t.settle(1);
    try std.testing.expect(x.shown);
    t.typeText("ter2");
    t.frame();
    try std.testing.expectEqualStrings("hunter2", x.buf.text());
    // From the field, Tab goes to the eye, and Space turns it.
    t.key(.tab);
    try std.testing.expect(t.shortcut(.{ .key = ' ' }));
    t.settle(1);
    try std.testing.expect(!x.shown);
}

test "a hidden secret's text isn't told to a screen reader, a shown one's is, and the field takes its label" {
    var x: Secret = .{};
    defer x.buf.deinit();
    x.buf.set("hunter2");
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Secret.view), .{ .width = 520, .height = 80 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var found = false;
    for (try elements(&t, &arena)) |e| if (e.role == .text_field) {
        found = true;
        try std.testing.expectEqualStrings("Password", e.label);
        try std.testing.expectEqualStrings("", e.value);
    };
    try std.testing.expect(found);
    x.shown = true;
    t.settle(1);
    for (try elements(&t, &arena)) |e| if (e.role == .text_field) try std.testing.expectEqualStrings("hunter2", e.value);
}

test "a plain box has no eye, and a clear button only with text" {
    const T = struct {
        buf: ui.TextBuffer = .{},
        fn view(x: *@This(), c: *ui.Context) void {
            _ = inputBox(c, &x.buf, .{ .icon = "magnifyingglass", .placeholder = "Search" });
        }
    };
    var x: T = .{};
    defer x.buf.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 400, .height = 80 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    for (try elements(&t, &arena)) |e| try std.testing.expect(e.role != .button);
    x.buf.set("logs");
    t.settle(1);
    var clear = false;
    for (try elements(&t, &arena)) |e| {
        try std.testing.expect(!std.mem.eql(u8, e.label, "Show"));
        clear = clear or std.mem.eql(u8, e.label, "Clear");
    }
    try std.testing.expect(clear);
}

test "a disabled box shows its text, a secret's as dots, without a field or buttons" {
    const T = struct {
        buf: ui.TextBuffer = .{},
        show: bool = false,
        secret: bool = false,
        fn view(x: *@This(), c: *ui.Context) void {
            _ = inputBox(c, &x.buf, .{ .placeholder = "Password", .shown = if (x.secret) &x.show else null, .paste = true, .clearable = true, .disabled = true });
        }
    };
    var x: T = .{};
    defer x.buf.deinit();
    x.buf.set("hunter2");
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 400, .height = 80 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(t.hasText("hunter2"));
    try std.testing.expect(!t.hasText("Paste"));
    t.typeText("x");
    try std.testing.expectEqualStrings("hunter2", x.buf.text());
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    for (try elements(&t, &arena)) |e| {
        try std.testing.expect(e.role != .button and !e.enabled);
    }
    x.secret = true;
    t.settle(1);
    try std.testing.expect(!t.hasText("hunter2") and t.hasText("•••••••"));
    for (try elements(&t, &arena)) |e| try std.testing.expectEqualStrings("", e.value);
}

test "a box is as wide as its parent, in a row the room the rest leaves, and a width in points follows scale" {
    const T = struct {
        a: ui.TextBuffer = .{},
        b: ui.TextBuffer = .{},
        c: ui.TextBuffer = .{},
        boxes: [3]u32 = undefined,
        fn view(x: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(400).gap(8);
            defer root.end();
            x.boxes[0] = @intCast(c.nodes.items.len);
            _ = inputBox(c, &x.a, .{});
            {
                const row = ui.div(c).row().wFull().itemsCenter().gap(10);
                defer row.end();
                x.boxes[1] = @intCast(c.nodes.items.len);
                _ = inputBox(c, &x.b, .{});
                ui.div(c).w(100).h(10).end();
            }
            x.boxes[2] = @intCast(c.nodes.items.len);
            _ = inputBox(c, &x.c, .{ .scale = 1.5, .card = .{ .width = .{ .px = 140 } } });
        }
    };
    var x: T = .{};
    defer x.a.deinit();
    defer x.b.deinit();
    defer x.c.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 420, .height = 200 });
    defer t.deinit();
    t.settle(1);
    const w = struct {
        fn of(tt: *ui.Tester, i: u32) f32 {
            return tt.ctx.rects.get(tt.ctx.nodes.items[i].id).?.w;
        }
    }.of;
    try std.testing.expectEqual(@as(f32, 400), w(&t, x.boxes[0]));
    try std.testing.expectEqual(@as(f32, 290), w(&t, x.boxes[1]));
    try std.testing.expectEqual(@as(f32, 210), w(&t, x.boxes[2]));
}

test "two input boxes each glow for their own field" {
    const T = struct {
        a: ui.TextBuffer = .{},
        b: ui.TextBuffer = .{},
        borders: [2]?ui.Color = .{ null, null },
        fn view(x: *@This(), c: *ui.Context) void {
            for ([_]*ui.TextBuffer{ &x.a, &x.b }, 0..) |buf, i| {
                const before: u32 = @intCast(c.nodes.items.len);
                _ = inputBox(c, buf, .{ .placeholder = "Name" });
                x.borders[i] = c.node(before).style.border;
            }
        }
    };
    var x: T = .{};
    defer x.a.deinit();
    defer x.b.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 400, .height = 160 });
    defer t.deinit();
    t.settle(1);
    const tk = kit.tokens(&t.ctx);
    x.b.focus();
    t.settle(1);
    try std.testing.expectEqual(@as(?ui.Color, tk.border), x.borders[0]);
    try std.testing.expectEqual(@as(?ui.Color, tk.primary.alpha(0.7)), x.borders[1]);
    x.a.focus();
    t.settle(1);
    try std.testing.expectEqual(@as(?ui.Color, tk.primary.alpha(0.7)), x.borders[0]);
    try std.testing.expectEqual(@as(?ui.Color, tk.border), x.borders[1]);
}
