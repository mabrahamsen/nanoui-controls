//! The tab strip's tests: choosing by click and key, badges, an open
//! strip's button, an enum's value, and what a screen reader hears.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const strip_mod = @import("tab_strip.zig");
const Choice = @import("choices.zig").Choice;

const Tabs = struct {
    index: usize = 0,
    changes: usize = 0,
    managed: usize = 0,
    open: bool = false,

    const tabs = [_]Choice{
        .{ .label = "Reviews", .count = 3 },
        .{ .label = "Failed", .count = 1, .alert = true },
        .{ .label = "Work", .loading = true },
        .{ .label = "Archive", .count = 1500 },
    };

    fn view(x: *Tabs, c: *ui.Context) void {
        const root = ui.div(c).column().w(560).p(8);
        defer root.end();
        if (x.open) {
            var s = strip_mod.tabStripOpen(c, &tabs, &x.index, .{});
            if (kit.button(c, "Manage", .{ .size = .xs }).clicked) x.managed += 1;
            if (s.end()) x.changes += 1;
        } else if (strip_mod.tabStrip(c, &tabs, &x.index, .{})) x.changes += 1;
    }
};

fn start(x: *Tabs, t: *ui.Tester) !void {
    try t.init(std.testing.allocator, .init(x, Tabs.view), .{ .width = 600, .height = 100 });
    t.settle(1);
}

test "a click or the keys choose a tab, which has an accent bar under it" {
    var x: Tabs = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    try t.clickText("Failed");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.index);
    t.key(.right);
    try std.testing.expectEqual(@as(usize, 2), x.index);
    t.key(.end);
    try std.testing.expectEqual(@as(usize, 3), x.index);
    try std.testing.expectEqual(@as(usize, 3), x.changes);
    const primary = kit.tokens(&t.ctx).primary;
    const archive = t.findText("Archive").?;
    var bar: ?ui.Rect = null;
    for (t.ctx.nodes.items) |n| if (n.style.background) |bg| if (std.meta.eql(bg, primary)) {
        const r = t.ctx.rects.get(n.id).?;
        if (r.h <= 2) bar = r;
    };
    try std.testing.expect(bar.?.y > archive.y and bar.?.x <= archive.x);
}

test "counts are badges, past the most as 999+, alerting in the danger color" {
    var x: Tabs = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    try std.testing.expect(t.hasText("3") and t.hasText("999+"));
    const danger = kit.tokens(&t.ctx).danger;
    var alerted = false;
    for (t.ctx.nodes.items) |n| if (n.style.background) |bg| {
        alerted = alerted or std.meta.eql(bg, danger);
    };
    try std.testing.expect(alerted);
}

test "an open strip keeps the caller's button on the tabs' line, at its end" {
    var x: Tabs = .{ .open = true };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const manage = t.findText("Manage").?;
    const archive = t.findText("Archive").?;
    try std.testing.expect(manage.x > archive.x);
    try std.testing.expect(manage.y < archive.y + archive.h);
    try t.clickText("Manage");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.managed);
    try t.clickText("Work");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.changes);
}

test "a screen reader hears each tab as a tab, with its count or that it is loading" {
    var x: Tabs = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(@as(usize, 4), list.items.len);
    try std.testing.expectEqual(ui.access.Role.tab, list.items[0].role);
    try std.testing.expectEqualStrings("Reviews", list.items[0].label);
    try std.testing.expectEqualStrings("3", list.items[0].value);
    try std.testing.expect(list.items[0].selected);
    try std.testing.expectEqualStrings("loading", list.items[2].value);
}

test "tabStripOf keeps an enum's value" {
    const Pane = enum { general, advanced };
    const T = struct {
        pane: Pane = .general,
        fn view(x: *@This(), c: *ui.Context) void {
            _ = strip_mod.tabStripOf(c, Pane, &x.pane, &.{ .{ .label = "General" }, .{ .label = "Advanced" } }, .{});
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 60 });
    defer t.deinit();
    t.settle(1);
    try t.clickText("Advanced");
    t.settle(1);
    try std.testing.expectEqual(Pane.advanced, x.pane);
}

/// Chevrons drawn, by their icons.
fn chevrons(t: *ui.Tester) usize {
    var n: usize = 0;
    for (t.ctx.nodes.items) |node| switch (node.content) {
        .icon => |i| n += @intFromBool(std.mem.startsWith(u8, i.name, "chevron.")),
        else => {},
    };
    return n;
}

const Many = struct {
    index: usize = 0,
    const tabs = [_]Choice{
        .{ .label = "Overview" }, .{ .label = "Reviews" },  .{ .label = "Failed runs" }, .{ .label = "Work" },
        .{ .label = "Archive" },  .{ .label = "Settings" }, .{ .label = "Members" },     .{ .label = "Billing" },
    };
    fn view(x: *Many, c: *ui.Context) void {
        const root = ui.div(c).column().w(300).p(8);
        defer root.end();
        _ = strip_mod.tabStrip(c, &tabs, &x.index, .{});
    }
};

test "tabs too many for the strip scroll sideways, between chevrons, the chosen one into view" {
    var x: Many = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Many.view), .{ .width = 400, .height = 100 });
    defer t.deinit();
    for (0..3) |_| t.frame();
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 2), chevrons(&t));
    // The strip's right edge: 8 + 300 - 8.
    const edge: f32 = 300;
    try std.testing.expect(t.findText("Billing").?.x > edge);
    // The keys choose the last, which is scrolled into view.
    try t.clickText("Overview");
    t.key(.end);
    for (0..3) |_| t.frame();
    try std.testing.expectEqual(@as(usize, 7), x.index);
    const billing = t.findText("Billing").?;
    try std.testing.expect(billing.x + billing.w <= edge);
    try std.testing.expect(t.findText("Overview").?.x < 8);
    // The wheel pans back toward the first.
    const y = billing.y + billing.h / 2;
    const before = billing.x;
    t.scroll(150, y, 60);
    t.frame();
    try std.testing.expect(t.findText("Billing").?.x > before);
    // The left chevron pages back to the start; the choice stays.
    for (0..5) |_| {
        t.click(20, y);
        t.frame();
    }
    try std.testing.expect(t.findText("Overview").?.x >= 8);
    try std.testing.expectEqual(@as(usize, 7), x.index);
}

test "tabs that fit have no chevrons" {
    var x: Tabs = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    for (0..2) |_| t.frame();
    try std.testing.expectEqual(@as(usize, 0), chevrons(&t));
}
