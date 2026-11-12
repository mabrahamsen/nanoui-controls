//! The sidebar's tests of counts that are loading: a spinner in the
//! count's place, at the icon's corner when narrowed, and what a screen
//! reader hears.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const sidebar = @import("sidebar.zig").sidebar;
const elements = @import("sidebar_tests.zig").elements;

/// Rows whose counts are loading: plain, a pill, and a branch.
const Loading = struct {
    loading: bool = true,
    icons_only: bool = false,
    open: bool = true,

    fn view(x: *Loading, c: *ui.Context) void {
        const root = ui.div(c).column().w(if (x.icons_only) 48 else 220).h(300);
        defer root.end();
        var sb = sidebar(c, "loading", "inbox", .{ .icons_only = x.icons_only });
        sb.item("inbox", "Inbox", .{ .icon = "tray", .count = 4, .loading = x.loading });
        sb.item("unread", "Unread", .{ .icon = "envelope", .count = 7, .count_style = .pill, .loading = x.loading });
        if (sb.branch("folders", "Folders", .{ .icon = "folder", .count = 2, .loading = x.loading }, &x.open)) |g| {
            sb.item("archive", "Archive", .{});
            g.end();
        }
        _ = sb.end();
    }

    /// The spinners' dots in the row at `y`: their rightmost edge, and how
    /// many.
    fn dots(t: *ui.Tester, y: f32) struct { f32, usize } {
        var right: f32 = 0;
        var n: usize = 0;
        for (t.ctx.nodes.items) |node| {
            if (!node.style.absolute or node.style.background == null) continue;
            const r = t.ctx.rects.get(node.id) orelse continue;
            if (r.w > 4 or @abs(r.y + r.h / 2 - y) > 12) continue;
            right = @max(right, r.x + r.w);
            n += 1;
        }
        return .{ right, n };
    }

    fn value(t: *ui.Tester, arena: std.mem.Allocator, label: []const u8) ![]const u8 {
        for (try elements(t, arena)) |e| if (std.mem.eql(u8, e.label, label)) return e.value;
        return error.NotFound;
    }
};

test "a loading row shows a spinner where its count goes, not the count, and says it is loading" {
    var x: Loading = .{ .loading = false };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Loading.view), .{ .width = 300, .height = 320 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const label = t.findText("Inbox").?;
    const four = t.findText("4").?;
    try std.testing.expectEqualStrings("4", try Loading.value(&t, arena.allocator(), "Inbox"));
    try std.testing.expectEqualStrings("2, expanded", try Loading.value(&t, arena.allocator(), "Folders"));
    x.loading = true;
    t.settle(1);
    for ([_][]const u8{ "4", "7", "2" }) |n| try std.testing.expect(!t.hasText(n));
    // The label stays put, and the spinner ends where the count did.
    try std.testing.expectEqual(label.x, t.findText("Inbox").?.x);
    const right, const n = Loading.dots(&t, label.y + label.h / 2);
    try std.testing.expect(n > 0);
    try std.testing.expectApproxEqAbs(four.x + four.w, right, 2);
    // The pill's spinner is in its tint, with no pill behind it.
    const unread = t.findText("Unread").?;
    const tint = nanoui.kit.tokens(&t.ctx).primary;
    for (t.ctx.nodes.items) |node| {
        const bg = node.style.background orelse continue;
        const r = t.ctx.rects.get(node.id) orelse continue;
        if (r.x < unread.x + unread.w or @abs(r.y + r.h / 2 - (unread.y + unread.h / 2)) > 12) continue;
        try std.testing.expect(r.w <= 4);
        try std.testing.expectEqual(tint.r, bg.r);
    }
    try std.testing.expectEqualStrings("loading", try Loading.value(&t, arena.allocator(), "Inbox"));
    try std.testing.expectEqualStrings("loading", try Loading.value(&t, arena.allocator(), "Unread"));
    try std.testing.expectEqualStrings("loading, expanded", try Loading.value(&t, arena.allocator(), "Folders"));
}

test "icons only, a loading row shows a small spinner at its icon's corner in place of the count's dot" {
    var x: Loading = .{ .icons_only = true, .loading = false };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Loading.view), .{ .width = 300, .height = 320 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const list = try elements(&t, arena.allocator());
    const row = list[0].rect;
    try std.testing.expectEqual(@as(usize, 0), Loading.dots(&t, row.y + row.h / 2)[1]);
    x.loading = true;
    t.settle(1);
    const right, const n = Loading.dots(&t, row.y + row.h / 2);
    try std.testing.expect(n > 0);
    // Over the icon's right, inside the row.
    try std.testing.expect(right > row.x + row.w / 2 and right <= row.x + row.w);
    try std.testing.expectEqualStrings("loading", try Loading.value(&t, arena.allocator(), "Inbox"));
}
