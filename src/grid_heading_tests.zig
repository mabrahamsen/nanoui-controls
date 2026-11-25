//! The grid's tests of headings the caller draws, how far groups step
//! in, and showing a group's rows at once as it opens.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const g_mod = @import("grid.zig");
const grid = g_mod.grid;
const Column = g_mod.Column;
const Groups = @import("grid_groups.zig").Groups;
const Group = @import("grid_groups.zig").Group;

/// Two groups, the second in the first, under headings the caller draws:
/// its own marks for open and folded, the title and a second line.
const Drawn = struct {
    open: [2]bool = .{ true, true },
    cells: bool = false,
    indent_step: f32 = 18,
    fade_in: bool = true,
    /// What the heading rows said, by group, in the last frame.
    was_open: [2]bool = .{ false, false },
    depths: [2]u8 = .{ 9, 9 },

    const columns = [_]Column{
        .{ .title = "Title" },
        .{ .title = "Age", .width = 60, .alignment = .end },
    };
    const names = [_][]const u8{ "alpha", "beta" };
    const groups = [_]Group{ .{ .size = 1 }, .{ .size = 2, .depth = 1 } };

    fn view(x: *Drawn, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        const gs = Groups.init(c, &groups, &x.open, .{});
        var g = grid(c, &columns, .{ .count = gs.count(), .groups = gs, .lines = 2, .indent_step = x.indent_step, .fade_in = x.fade_in });
        while (g.next()) |row| switch (gs.at(row.index)) {
            .heading => |h| {
                const head = g.headingRow(.{ .title = names[h.group], .detail = "2 runs", .cells = x.cells });
                x.was_open[h.group] = head.open;
                x.depths[h.group] = head.depth;
                ui.text(c, if (head.open) "v" else ">", .{});
                const lines = ui.div(c).column();
                ui.text(c, names[h.group], .{});
                ui.text(c, c.print("{s} failed", .{names[h.group]}), .{});
                lines.end();
                head.box.end();
                if (x.cells and g.cellAt(1)) ui.text(c, "total", .{});
            },
            .row => |r| {
                g.cell();
                ui.text(c, c.print("{s} {d}", .{ names[r.group], r.index }), .{});
                g.cell();
                ui.text(c, "2d", .{});
            },
        };
        g.end();
    }
};

fn start(x: *Drawn, t: *ui.Tester) !void {
    try t.init(std.testing.allocator, .init(x, Drawn.view), .{ .width = 400, .height = 400 });
    t.settle(1);
}

test "a heading the caller draws has only the caller's content, and folds and opens on a click" {
    for ([_]bool{ false, true }) |in_cells| {
        var x: Drawn = .{ .cells = in_cells };
        var t: ui.Tester = undefined;
        try start(&x, &t);
        defer t.deinit();
        // No chevron of the grid's, nor its title's look: only the caller's.
        for (t.ctx.nodes.items) |node| switch (node.content) {
            .icon => return error.TestUnexpectedResult,
            else => {},
        };
        try std.testing.expect(t.hasText("alpha failed"));
        try std.testing.expect(!t.hasText("2 runs"));
        try std.testing.expectEqual(@as(u8, 0), x.depths[0]);
        try std.testing.expectEqual(@as(u8, 1), x.depths[1]);
        try std.testing.expect(x.was_open[1]);
        if (in_cells) try std.testing.expect(t.hasText("total"));
        // A click on the caller's content folds the group, and the row
        // says so in the same frame.
        try t.clickText("beta failed");
        t.settle(1);
        try std.testing.expect(!x.open[1]);
        try std.testing.expect(!x.was_open[1]);
        try std.testing.expect(!t.hasText("beta 0"));
        try t.clickText("beta failed");
        t.settle(1);
        try std.testing.expect(x.open[1]);
        try std.testing.expect(t.hasText("beta 0"));
    }
}

test "a heading the caller draws is heard with its title and detail, and whether it is open" {
    var x: Drawn = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    var found = false;
    for (list.items) |e| if (std.mem.eql(u8, e.label, "beta, 2 runs")) {
        found = true;
        try std.testing.expectEqualStrings("expanded", e.value);
    };
    try std.testing.expect(found);
}

test "a heading's two lines fit its row, as tall as the grid's lines" {
    var x: Drawn = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const title = t.findText("alpha").?;
    const second = t.findText("alpha failed").?;
    try std.testing.expect(second.y >= title.y + title.h - 0.5);
    // Both lines sit above the next row's text.
    const next = t.findText("beta").?;
    try std.testing.expect(second.y + second.h <= next.y + 0.5);
}

test "headings and rows step in by indent_step" {
    var at: [2]f32 = undefined;
    for ([_]f32{ 18, 30 }, 0..) |step, i| {
        var x: Drawn = .{ .indent_step = step };
        var t: ui.Tester = undefined;
        try start(&x, &t);
        defer t.deinit();
        // The nested heading steps in a level past the top one, and its
        // rows a level past it.
        const top = t.findText("v").?.x;
        try std.testing.expectApproxEqAbs(top + step, t.findText("beta").?.x - (t.findText("alpha").?.x - top), 0.5);
        at[i] = t.findText("beta 0").?.x;
    }
    try std.testing.expectApproxEqAbs(@as(f32, 24), at[1] - at[0], 0.5);
}

test "without fade_in, a group's rows show at once as it opens" {
    var x: Drawn = .{ .open = .{ true, false }, .fade_in = false };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    try t.clickText("beta failed");
    t.frame();
    try std.testing.expect(x.open[1]);
    for (t.ctx.nodes.items) |n| try std.testing.expectEqual(@as(f32, 1), n.style.opacity);
}

/// Headings across the columns with a total under Size, for a title too
/// long for the first column.
const After = struct {
    open: [2]bool = .{ true, true },
    chevron: g_mod.HeadingChevron = .plain,

    const columns = [_]Column{
        .{ .title = "Name" },
        .{ .title = "Kind", .width = 90, .min_window_width = 560 },
        .{ .title = "Size", .width = 70, .alignment = .end },
        .{ .title = "Changed", .width = 80, .alignment = .end },
    };
    const names = [_][]const u8{ "Archives and disk images", "Photos" };
    const groups = [_]Group{ .{ .size = 2 }, .{ .size = 1 } };

    fn view(x: *After, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        const gs = Groups.init(c, &groups, &x.open, .{});
        var g = grid(c, &columns, .{ .count = gs.count(), .groups = gs });
        while (g.next()) |row| switch (gs.at(row.index)) {
            .heading => |h| {
                g.heading(.{ .title = names[h.group], .cells_after = 2, .chevron = x.chevron });
                if (g.cellAt(2)) ui.text(c, if (h.group == 0) "12 GB" else "3 GB", .{});
            },
            .row => |r| {
                g.cell();
                ui.text(c, c.print("file {d}", .{r.index}), .{});
                if (g.cellAt(1)) ui.text(c, "Disk image", .{});
                if (g.cellAt(2)) ui.text(c, "1 GB", .{});
                if (g.cellAt(3)) ui.text(c, "2d", .{});
            },
        };
        g.end();
    }
};

test "a heading across the columns gives its title the room up to the caller's cells, under their columns" {
    var x: After = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, After.view), .{ .width = 700, .height = 300 });
    defer t.deinit();
    t.settle(1);
    for ([_]f32{ 700, 500 }) |width| {
        t.resize(width, 300);
        t.settle(1);
        // Kind shows in the wide window and hides in the narrow one: the
        // total stays under Size, its right edge on the rows' figures'.
        try std.testing.expectEqual(width > 560, t.hasText("Kind"));
        const total = t.findText("12 GB").?;
        const figure = t.findText("1 GB").?;
        try std.testing.expectApproxEqAbs(figure.x + figure.w, total.x + total.w, 0.5);
        // The title whole, ending before Size's column starts.
        const title = t.findText(After.names[0]).?;
        const size = t.findText("Size").?;
        try std.testing.expect(title.x + title.w <= size.x + size.w - 70 + 0.5);
    }
    // A click on the title still folds its group.
    const title = t.findText(After.names[0]).?;
    t.click(title.x + 4, title.y + title.h / 2);
    t.settle(1);
    try std.testing.expect(!x.open[0]);
}

test "a heading's chevron can sit in a round well" {
    for ([_]g_mod.HeadingChevron{ .plain, .well }) |look| {
        var x: After = .{ .chevron = look };
        var t: ui.Tester = undefined;
        try t.init(std.testing.allocator, .init(&x, After.view), .{ .width = 700, .height = 300 });
        defer t.deinit();
        t.settle(1);
        const hover = nanoui.kit.tokens(&t.ctx).surface_hover;
        var wells: usize = 0;
        for (t.ctx.nodes.items) |n| if (n.style.background) |b| if (std.meta.eql(b, hover) and n.style.width == .px and n.style.width.px == 16) {
            wells += 1;
        };
        // One for each heading, and none drawn bare.
        try std.testing.expectEqual(@as(usize, if (look == .well) 2 else 0), wells);
    }
}
