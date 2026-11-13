//! The segmented control's tests: choosing by click and key, the keys it
//! takes, Tab, disabled options and groups, an enum's value, counts, and
//! what a screen reader hears.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const seg_mod = @import("segmented.zig");
const segmented = seg_mod.segmented;
const Choice = @import("choices.zig").Choice;

const Range = struct {
    index: usize = 0,
    changes: usize = 0,
    disabled: bool = false,
    /// Whether a key reached the app after the group.
    key_left: bool = false,
    after_focused: bool = false,
    after: ui.TextBuffer = .{},

    const options = [_]Choice{
        .{ .label = "Today" },
        .{ .label = "Week", .count = 12 },
        .{ .label = "Month", .disabled = true },
        .{ .label = "Year", .loading = true },
    };

    fn view(x: *Range, c: *ui.Context) void {
        const root = ui.div(c).column().gap(8).p(8);
        defer root.end();
        if (segmented(c, &options, &x.index, .{ .label = "Range", .disabled = x.disabled })) x.changes += 1;
        x.after_focused = ui.textField(c, &x.after, .{ .width = .{ .px = 100 } }).focused;
        x.key_left = c.input.key != null;
    }
};

fn start(x: *Range, t: *ui.Tester) !void {
    try t.init(std.testing.allocator, .init(x, Range.view), .{ .width = 420, .height = 120 });
    t.settle(1);
}

test "a click chooses an option, and choosing the chosen one changes nothing" {
    var x: Range = .{};
    defer x.after.deinit();
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    try t.clickText("Week");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.index);
    try std.testing.expectEqual(@as(usize, 1), x.changes);
    try t.clickText("Week");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.changes);
    // A disabled option isn't chosen by a click.
    try t.clickText("Month");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.index);
}

test "the arrows, Home and End choose, passing a disabled option, and are used up even at an end" {
    var x: Range = .{};
    defer x.after.deinit();
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    try t.clickText("Today");
    t.key(.right);
    try std.testing.expectEqual(@as(usize, 1), x.index);
    t.key(.right);
    try std.testing.expectEqual(@as(usize, 3), x.index);
    t.key(.right);
    try std.testing.expectEqual(@as(usize, 3), x.index);
    try std.testing.expect(!x.key_left);
    // Offered first as a shortcut, as the Mac does, Home is its own.
    try std.testing.expect(t.shortcut(.{ .key = ui.Shortcut.home }));
    try std.testing.expectEqual(@as(usize, 0), x.index);
    t.key(.end);
    try std.testing.expectEqual(@as(usize, 3), x.index);
    // Enter is the app's.
    t.key(.enter);
    try std.testing.expect(x.key_left);
}

test "the group is one stop for Tab, and disabled, Tab passes it by and nothing changes it" {
    var x: Range = .{};
    defer x.after.deinit();
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    t.key(.tab);
    t.key(.right);
    try std.testing.expectEqual(@as(usize, 1), x.index);
    t.key(.tab);
    t.settle(1);
    try std.testing.expect(x.after_focused);
    x.disabled = true;
    t.ctx.focus = 0;
    t.settle(1);
    t.key(.tab);
    t.settle(1);
    try std.testing.expect(x.after_focused);
    try t.clickText("Today");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.index);
}

test "a screen reader hears each option as a radio button, with its count and the group's label" {
    var x: Range = .{};
    defer x.after.deinit();
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(ui.access.Role.radio_button, list.items[0].role);
    try std.testing.expect(list.items[0].selected);
    try std.testing.expectEqualStrings("Range", list.items[0].hint);
    try std.testing.expectEqualStrings("12", list.items[1].value);
    try std.testing.expect(!list.items[2].enabled);
    try std.testing.expectEqualStrings("loading", list.items[3].value);
}

test "segmentedOf keeps an enum's value, and draws as the index it replaces" {
    const Mode = enum { light, dark, system };
    const T = struct {
        mode: Mode = .dark,
        fn view(x: *@This(), c: *ui.Context) void {
            _ = seg_mod.segmentedOf(c, Mode, &x.mode, &.{ .{ .label = "Light" }, .{ .label = "Dark" }, .{ .label = "System" } }, .{});
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 60 });
    defer t.deinit();
    t.settle(1);
    const primary = kit.tokens(&t.ctx).primary;
    var chosen: ?ui.Rect = null;
    for (t.ctx.nodes.items) |n| if (n.style.background) |bg| if (std.meta.eql(bg, primary)) {
        chosen = t.ctx.rects.get(n.id);
    };
    const dark = t.findText("Dark").?;
    try std.testing.expect(chosen.?.x <= dark.x and chosen.?.x + chosen.?.w >= dark.x + dark.w);
    try t.clickText("System");
    t.settle(1);
    try std.testing.expectEqual(Mode.system, x.mode);
}

test "a click shows the choice in the frame it is made in" {
    var x: Range = .{};
    defer x.after.deinit();
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const week = t.findText("Week").?;
    t.click(week.x + 2, week.y + 2);
    for (t.ctx.nodes.items) |n| switch (n.content) {
        .text => |s| if (std.mem.eql(u8, s.str, "Week")) try std.testing.expectEqual(kit.tokens(&t.ctx).primary_foreground, s.style.color.?),
        else => {},
    };
}
