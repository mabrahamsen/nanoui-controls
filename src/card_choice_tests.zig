//! The card choice's tests: radio buttons, a click, the keys by a card
//! and by a row, disabled cards, and a choice that may be none.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const card_choice = @import("card_choice.zig");

const names = [_][]const u8{ "House", "Paper", "Panel", "Contrast", "Night" };

/// Five themes as cards, 120 wide in a pane of 400: three to a row.
const Themes = struct {
    index: usize = 0,
    maybe: ?usize = null,
    may_be_none: bool = false,
    disabled: bool = false,
    disabled_cards: []const bool = &.{},
    changes: usize = 0,

    fn view(x: *Themes, c: *ui.Context) void {
        const root = ui.div(c).column().w(400);
        defer root.end();
        const opts: card_choice.Options = .{ .cell_width = 120, .label = "Theme", .disabled = x.disabled, .disabled_cards = x.disabled_cards };
        var cc = if (x.may_be_none) card_choice.cardChoice(c, &names, &x.maybe, opts) else card_choice.cardChoice(c, &names, &x.index, opts);
        while (cc.next()) |i| {
            ui.div(c).wFull().h(40).bg(.hex(0x334455)).end();
            ui.text(c, names[i], .{ .size = 12, .weight = .semibold });
        }
        if (cc.end()) x.changes += 1;
    }
};

fn start(x: *Themes, t: *ui.Tester) !void {
    try t.init(std.testing.allocator, .init(x, Themes.view), .{ .width = 500, .height = 400 });
    t.settle(2);
}

fn elements(t: *ui.Tester, arena: std.mem.Allocator) ![]const ui.access.Element {
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena, &list);
    return list.items;
}

test "cards are radio buttons named by their labels, the chosen one selected, the content not heard on its own" {
    var x: Themes = .{ .index = 2 };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const list = try elements(&t, arena.allocator());
    try std.testing.expectEqual(names.len, list.len);
    for (list, names, 0..) |e, name, i| {
        try std.testing.expectEqual(ui.access.Role.radio_button, e.role);
        try std.testing.expectEqualStrings(name, e.label);
        try std.testing.expectEqualStrings("Theme", e.hint);
        try std.testing.expectEqual(i == 2, e.selected);
    }
}

test "a click chooses a card and gives the choice the keyboard; the arrows move by a card, Up and Down by a row" {
    var x: Themes = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    // Three to a row: the fourth starts the second.
    try std.testing.expect(t.findText("Contrast").?.y > t.findText("House").?.y);
    try std.testing.expectEqual(t.findText("House").?.x, t.findText("Contrast").?.x);
    try t.clickText("Paper");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.index);
    try std.testing.expectEqual(@as(usize, 1), x.changes);
    t.key(.right);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 2), x.index);
    t.key(.down);
    t.settle(1);
    // A row down from the third: there is none under it, so it stays.
    try std.testing.expectEqual(@as(usize, 2), x.index);
    t.key(.left);
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 4), x.index);
    t.key(.up);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.index);
    t.key(.end);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 4), x.index);
    t.key(.home);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 0), x.index);
}

test "disabled cards are passed by the keys and take no click; a disabled choice takes neither" {
    const off = [_]bool{ false, true, false, false, false };
    var x: Themes = .{ .disabled_cards = &off };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    try t.clickText("Paper");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 0), x.index);
    try t.clickText("House");
    t.key(.right);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 2), x.index);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const list = try elements(&t, arena.allocator());
    try std.testing.expect(!list[1].enabled and list[0].enabled);
    x.disabled = true;
    t.settle(1);
    try t.clickText("House");
    t.key(.left);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 2), x.index);
}

test "a choice that may be none chooses nothing until a click or a key" {
    var x: Themes = .{ .may_be_none = true };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    for (try elements(&t, arena.allocator())) |e| try std.testing.expect(!e.selected);
    // Tab reaches it, and the first key chooses the first card.
    t.key(.tab);
    t.settle(1);
    t.key(.right);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 0), x.maybe);
    try t.clickText("Night");
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 4), x.maybe);
}

test "an index past the last card moves to the last, and says it changed" {
    var x: Themes = .{ .index = 9 };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    try std.testing.expectEqual(@as(usize, 4), x.index);
    try std.testing.expectEqual(@as(usize, 1), x.changes);
}

test "the chosen card is tinted and outlined in the accent" {
    var x: Themes = .{ .index = 3 };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const tk = kit.tokens(&t.ctx);
    var outlined: usize = 0;
    for (t.ctx.nodes.items) |n| if (n.style.border) |b| if (std.meta.eql(b, tk.primary) and n.style.border_width == 2) {
        outlined += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), outlined);
}
