//! The grid's tests of loading: sketched rows under a label while there
//! are none, a thin line once some are in, and empty only once loaded.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const g_mod = @import("grid.zig");
const grid = g_mod.grid;
const Column = g_mod.Column;

/// Fruit, loading: with none, or with some in.
const Loader = struct {
    count: usize = 0,
    loading: ?g_mod.Loading = .{ .label = "Asking the orchard…" },

    const columns = [_]Column{
        .{ .title = "Fruit" },
        .{ .title = "Count", .width = 80, .alignment = .end },
    };

    fn view(x: *Loader, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        var g = grid(c, &columns, .{ .count = x.count, .loading = x.loading, .empty = "No fruit" });
        while (g.next()) |row| {
            g.cell();
            ui.text(c, c.print("fruit {d}", .{row.index}), .{});
            g.cell();
            ui.text(c, "1", .{});
        }
        g.end();
    }
};

test "a grid loading with no rows sketches them under its label, and is empty only once loaded" {
    var x: Loader = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Loader.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.frame();
    try std.testing.expect(std.mem.indexOf(u8, t.ctx.access.announcement[0..t.ctx.access.announcement_len], "Asking the orchard") != null);
    t.settle(1);
    try std.testing.expect(t.hasText("Asking the orchard…"));
    try std.testing.expect(!t.hasText("No fruit"));
    // Sketched rows fill the view: placeholder bars, a pair a row.
    var bars: usize = 0;
    for (t.ctx.nodes.items) |n| if (n.style.height == .px and n.style.height.px == 10 and n.style.background != null) {
        bars += 1;
    };
    try std.testing.expect(bars >= 2 * 7);
    x.loading = null;
    t.settle(1);
    try std.testing.expect(t.hasText("No fruit"));
    try std.testing.expect(!t.hasText("Asking the orchard…"));
}

test "a grid loading with rows in shows a thin line, and doesn't move its rows" {
    var x: Loader = .{ .count = 3, .loading = null };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Loader.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const y = t.findText("fruit 0").?.y;
    x.loading = .{ .label = "More", .done = 1, .total = 4 };
    t.settle(1);
    try std.testing.expectEqual(y, t.findText("fruit 0").?.y);
    try std.testing.expect(!t.hasText("More"));
    var line = false;
    for (t.ctx.nodes.items) |n| if (n.style.height == .px and n.style.height.px == 2) {
        line = true;
    };
    try std.testing.expect(line);
}

/// Cards loading, then in.
const CardLoader = struct {
    count: usize = 0,

    fn view(x: *CardLoader, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        var g = grid(c, &Loader.columns, .{ .count = x.count, .rows = .cards, .loading = if (x.count == 0) .{} else null });
        while (g.next()) |row| {
            g.cell();
            ui.text(c, c.print("fruit {d}", .{row.index}), .{});
        }
        g.end();
    }
};

test "sketched rows take the room real rows do, cards' gap included, and an empty label isn't said" {
    var x: CardLoader = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, CardLoader.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.frame();
    try std.testing.expectEqual(@as(usize, 0), t.ctx.access.announcement_len);
    t.settle(1);
    // The sketched rows' bars, a pair a row: one row's to the next.
    var ys: [64]f32 = undefined;
    var n: usize = 0;
    for (t.ctx.nodes.items) |node| if (node.style.height == .px and node.style.height.px == 10 and node.style.background != null) {
        const y = t.ctx.rects.get(node.id).?.y;
        if (n == 0 or ys[n - 1] != y) {
            ys[n] = y;
            n += 1;
        }
    };
    try std.testing.expect(n >= 3);
    try std.testing.expectApproxEqAbs(@as(f32, 28 + 6), ys[1] - ys[0], 0.5);
}
