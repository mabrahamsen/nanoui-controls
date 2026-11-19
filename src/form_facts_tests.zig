//! Tests of a form of facts: labels drawn as captions, and properties
//! left open after their values for pills.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const form_mod = @import("form.zig");
const form = form_mod.form;

/// The style of the text `str`, the first drawn.
fn styleOf(t: *ui.Tester, str: []const u8) ui.TextStyle {
    for (t.ctx.nodes.items) |node| switch (node.content) {
        .text => |tx| if (std.mem.eql(u8, tx.str, str)) return tx.style,
        else => {},
    };
    unreachable;
}

/// A form of facts at `width`, its labels as `label_style` says, a
/// property and one left open for a pill.
const Facts = struct {
    width: f32 = 400,
    label_style: form_mod.LabelStyle = .caption,
    wrap: bool = false,
    value: []const u8 = "40 Gb/s",
    fn view(x: *Facts, c: *ui.Context) void {
        const root = ui.div(c).column().w(x.width);
        defer root.end();
        var f = form(c, .{ .label_style = x.label_style });
        f.property("LINK", "USB 3.2", .{});
        const p = f.propertyOpen("THUNDERBOLT", x.value, .{ .wrap = x.wrap });
        ui.text(c, "TUNNELED", .{ .size = 10 });
        p.end();
        f.end();
    }
};

test "a form's caption labels are drawn as a caption draws its text, and its column fits them" {
    var x: Facts = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Facts.view), .{ .width = 420, .height = 200 });
    defer t.deinit();
    t.settle(2);
    const caption = styleOf(&t, "LINK");
    try std.testing.expectEqual(kit.Size.xs.text() - 1, caption.size);
    try std.testing.expectEqual(ui.Weight.semibold, caption.weight);
    try std.testing.expectEqual(kit.tokens(&t.ctx).muted, caption.color.?);
    // The values keep the form's text, and line up after the column, as
    // wide as the widest caption.
    try std.testing.expectEqual(kit.Size.md.text(), styleOf(&t, "USB 3.2").size);
    const usb = t.findText("USB 3.2").?;
    try std.testing.expectEqual(usb.x, t.findText("40 Gb/s").?.x);
    const widest = t.findText("THUNDERBOLT").?;
    try std.testing.expect(usb.x >= widest.x + widest.w);
    try std.testing.expect(usb.x < widest.x + widest.w + 20);
    // Plain, the labels are the form's text.
    x.label_style = .plain;
    t.settle(2);
    try std.testing.expectEqual(kit.Size.md.text(), styleOf(&t, "LINK").size);
}

test "an open property's pill follows its value, which is cut short before it, and it is heard as label and value" {
    var x: Facts = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Facts.view), .{ .width = 420, .height = 200 });
    defer t.deinit();
    t.settle(2);
    // Right after the value, on its line.
    const value = t.findText("40 Gb/s").?;
    const pill = t.findText("TUNNELED").?;
    try std.testing.expect(pill.x > value.x + value.w and pill.x < value.x + value.w + 10);
    try std.testing.expect(@abs((pill.y + pill.h / 2) - (value.y + value.h / 2)) < 1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    var heard = false;
    for (list.items) |el| heard = heard or (std.mem.eql(u8, el.label, "THUNDERBOLT") and std.mem.eql(u8, el.value, "40 Gb/s"));
    try std.testing.expect(heard);
    // A value too long for the room is cut short, the pill still after it
    // and in the form, and the value whole under the pointer.
    const long = "40 Gb/s over a cable that is far longer than the pane";
    x.value = long;
    x.width = 300;
    t.settle(3);
    try std.testing.expect(!t.hasText(long));
    const cut = startingWith(&t, "40 Gb/s").?;
    const after = t.findText("TUNNELED").?;
    try std.testing.expect(after.x >= cut.x + cut.w and after.x + after.w <= 300.5);
    t.moveTo(cut.x + 10, cut.y + cut.h / 2);
    t.settle(2);
    try std.testing.expect(t.hasText(long));
}

test "an open property's value wraps in the room its pill leaves" {
    const long = "40 Gb/s over a cable that is far longer than the pane";
    var x: Facts = .{ .width = 300, .wrap = true, .value = long };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Facts.view), .{ .width = 420, .height = 200 });
    defer t.deinit();
    t.settle(3);
    const value = t.findText(long).?;
    const pill = t.findText("TUNNELED").?;
    try std.testing.expect(value.h > t.findText("USB 3.2").?.h * 1.5);
    try std.testing.expect(pill.x >= value.x + value.w and pill.x + pill.w <= 300.5);
    // It takes the room the pill leaves, not a sliver of it, and its row
    // is no taller than its lines.
    try std.testing.expect(value.w > 90);
    try std.testing.expect(value.h < t.findText("USB 3.2").?.h * 4);
}

/// The text drawn that starts with `s`.
fn startingWith(t: *ui.Tester, s: []const u8) ?ui.Rect {
    for (t.ctx.nodes.items) |n| switch (n.content) {
        .text => |tx| if (std.mem.startsWith(u8, tx.str, s)) return n.rect,
        else => {},
    };
    return null;
}
