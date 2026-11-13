//! The chips' tests: typing chips, separators, pasting, Enter, Backspace,
//! a × clicked and pressed, chips that don't read and inherited ones,
//! wrapping, a disabled input, and a chip turned on and off.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const chips_mod = @import("chips.zig");
const chipInput = chips_mod.chipInput;
const chip = chips_mod.chip;

/// Times of day, kept as the caller keeps them, one not a time.
const Times = struct {
    chips: std.ArrayList([]const u8) = .empty,
    invalid: std.ArrayList(bool) = .empty,
    buf: ui.TextBuffer = .{},
    focused: bool = false,

    fn view(x: *Times, c: *ui.Context) void {
        const r = chipInput(c, x.chips.items, &x.buf, .{ .placeholder = "times of day", .invalid = x.invalid.items, .inherited = &.{"3:00"} });
        x.focused = r.focused;
        const a = std.testing.allocator;
        for (r.added) |v| {
            x.chips.append(a, a.dupe(u8, v) catch return) catch return;
            x.invalid.append(a, std.mem.indexOfScalar(u8, v, ':') == null) catch return;
        }
        if (r.removed) |i| {
            a.free(x.chips.orderedRemove(i));
            _ = x.invalid.orderedRemove(i);
        }
    }

    fn deinit(x: *Times) void {
        for (x.chips.items) |v| std.testing.allocator.free(v);
        x.chips.deinit(std.testing.allocator);
        x.invalid.deinit(std.testing.allocator);
        x.buf.deinit();
    }
};

fn start(x: anytype, t: *ui.Tester, view: anytype) !void {
    try t.init(std.testing.allocator, .init(x, view), .{ .width = 400, .height = 160 });
    t.settle(1);
}

fn elements(t: *ui.Tester, arena: *std.heap.ArenaAllocator) ![]const ui.access.Element {
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    return list.items;
}

test "chips are typed, ended by a separator or Enter, pasted several at once, and Backspace takes the last back" {
    var x: Times = .{};
    defer x.deinit();
    var t: ui.Tester = undefined;
    try start(&x, &t, Times.view);
    defer t.deinit();
    x.buf.focus();
    t.frame();
    t.typeText("9:00, 21:30,");
    t.frame();
    try std.testing.expectEqual(@as(usize, 2), x.chips.items.len);
    try std.testing.expectEqualStrings("21:30", x.chips.items[1]);
    // Pasted text with separators, the last ended by Enter.
    t.typeText("6:00,7:00, noon");
    t.frame();
    t.key(.enter);
    t.frame();
    try std.testing.expectEqual(@as(usize, 5), x.chips.items.len);
    try std.testing.expectEqualStrings("noon", x.chips.items[4]);
    try std.testing.expectEqual(@as(usize, 0), x.buf.text().len);
    try std.testing.expect(t.hasText("noon") and t.hasText("3:00"));
    t.key(.backspace);
    t.frame();
    try std.testing.expectEqual(@as(usize, 4), x.chips.items.len);
}

test "a chip that doesn't read is the danger color and says so; an inherited one is muted, without a ×" {
    var x: Times = .{};
    defer x.deinit();
    try x.chips.append(std.testing.allocator, try std.testing.allocator.dupe(u8, "noon"));
    try x.invalid.append(std.testing.allocator, true);
    var t: ui.Tester = undefined;
    try start(&x, &t, Times.view);
    defer t.deinit();
    const tk = kit.tokens(&t.ctx);
    for (t.ctx.nodes.items) |n| switch (n.content) {
        .text => |s| {
            if (std.mem.eql(u8, s.str, "noon")) try std.testing.expectEqual(tk.danger, s.style.color.?);
            if (std.mem.eql(u8, s.str, "3:00")) try std.testing.expectEqual(tk.muted, s.style.color.?);
        },
        else => {},
    };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var removes: usize = 0;
    var flagged = false;
    for (try elements(&t, &arena)) |e| {
        if (std.mem.startsWith(u8, e.label, "Remove")) removes += 1;
        flagged = flagged or (std.mem.eql(u8, e.label, "noon") and std.mem.eql(u8, e.hint, "doesn't read"));
    }
    try std.testing.expectEqual(@as(usize, 1), removes);
    try std.testing.expect(flagged);
}

test "a chip's × is named, removes the chip on a click, and with Tab and Enter gives the field the keyboard" {
    var x: Times = .{};
    defer x.deinit();
    for ([_][]const u8{ "9:00", "21:30" }) |v| {
        try x.chips.append(std.testing.allocator, try std.testing.allocator.dupe(u8, v));
        try x.invalid.append(std.testing.allocator, false);
    }
    var t: ui.Tester = undefined;
    try start(&x, &t, Times.view);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var named = false;
    for (try elements(&t, &arena)) |e| named = named or std.mem.eql(u8, e.label, "Remove 21:30");
    try std.testing.expect(named);
    t.key(.tab);
    t.key(.enter);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.chips.items.len);
    try std.testing.expectEqualStrings("21:30", x.chips.items[0]);
    try std.testing.expect(x.focused);
}

test "chips wrap onto new lines in a narrow box, the field on a line of its own when little is left" {
    const T = struct {
        buf: ui.TextBuffer = .{},
        fn view(x: *@This(), c: *ui.Context) void {
            _ = chipInput(c, &.{ "node_modules/", "*.tmp", "/Downloads", "build/", "*.iso" }, &x.buf, .{ .width = .{ .px = 260 }, .placeholder = "add a rule" });
        }
    };
    var x: T = .{};
    defer x.buf.deinit();
    var t: ui.Tester = undefined;
    try start(&x, &t, T.view);
    defer t.deinit();
    for (0..2) |_| t.frame();
    const a = t.findText("node_modules/").?;
    const b = t.findText("*.iso").?;
    try std.testing.expect(b.y > a.y);
    try std.testing.expect(b.x + b.w < 260);
}

test "a disabled chip input shows its chips without a × or a field" {
    const T = struct {
        buf: ui.TextBuffer = .{},
        fn view(x: *@This(), c: *ui.Context) void {
            _ = chipInput(c, &.{ "9:00", "21:30" }, &x.buf, .{ .placeholder = "add a time", .disabled = true });
        }
    };
    var x: T = .{};
    defer x.buf.deinit();
    var t: ui.Tester = undefined;
    try start(&x, &t, T.view);
    defer t.deinit();
    try std.testing.expect(t.hasText("9:00") and t.hasText("21:30"));
    try std.testing.expect(!t.hasText("add a time"));
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    for (try elements(&t, &arena)) |e| try std.testing.expect(!std.mem.startsWith(u8, e.label, "Remove"));
}

test "a chip turns on and off by a click and by the keys, and is a checkbox to a screen reader" {
    const T = struct {
        on: bool = false,
        disabled: bool = false,
        turns: usize = 0,
        fn view(x: *@This(), c: *ui.Context) void {
            const row = ui.div(c).row().p(8);
            defer row.end();
            if (chip(c, "Grouped", &x.on, .{ .swatch = .hex(0x22c55e), .disabled = x.disabled })) x.turns += 1;
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t, T.view);
    defer t.deinit();
    try t.clickText("Grouped");
    t.settle(1);
    try std.testing.expect(x.on);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list = try elements(&t, &arena);
    try std.testing.expectEqual(ui.access.Role.checkbox, list[0].role);
    try std.testing.expect(list[0].selected);
    try std.testing.expectEqualStrings("on", list[0].value);
    t.ctx.focus = 0;
    t.key(.tab);
    try std.testing.expect(t.shortcut(.{ .key = ' ' }));
    t.settle(1);
    try std.testing.expect(!x.on);
    try std.testing.expectEqual(@as(usize, 2), x.turns);
    // Disabled, it doesn't turn and is said to be unavailable.
    x.disabled = true;
    t.settle(1);
    try t.clickText("Grouped");
    t.settle(1);
    try std.testing.expect(!x.on);
    list = try elements(&t, &arena);
    try std.testing.expect(!list[0].enabled);
}
