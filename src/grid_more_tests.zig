//! The grid's tests of groups that fold, columns that hide by the grid's
//! width, fitting a column that grows, two-line cells, cards, no titles,
//! Backspace and Escape, and its titles to a screen reader.
const std = @import("std");
const builtin = @import("builtin");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const g_mod = @import("grid.zig");
const grid = g_mod.grid;
const Column = g_mod.Column;
const Groups = @import("grid_groups.zig").Groups;
const Group = @import("grid_groups.zig").Group;

/// Pull requests by repository: three groups, the last of one.
const Repos = struct {
    open: [3]bool = .{ true, true, true },
    selected: ?usize = null,
    singles: bool = true,
    cells: bool = false,
    start_focused: bool = false,
    started: bool = false,
    opened: usize = 0,

    const columns = [_]Column{
        .{ .title = "Title" },
        .{ .title = "Age", .width = 60, .alignment = .end },
    };
    const names = [_][]const u8{ "alpha", "beta", "gamma" };
    const groups = [_]Group{ .{ .size = 2 }, .{ .size = 3 }, .{ .size = 1 } };

    fn view(x: *Repos, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        if (x.start_focused and !x.started) c.focusNext(false);
        x.started = true;
        const gs = Groups.init(c, &groups, &x.open, .{ .singles = x.singles });
        var g = grid(c, &columns, .{ .count = gs.count(), .groups = gs, .selected = &x.selected });
        while (g.next()) |row| {
            if (row.opened) x.opened += 1;
            switch (gs.at(row.index)) {
                .heading => |h| {
                    g.heading(.{ .title = names[h.group], .detail = c.print("{d} pulls", .{groups[h.group].size}), .cells = x.cells });
                    if (x.cells and g.cellAt(1)) ui.text(c, "total", .{});
                },
                .row => |r| {
                    g.cell();
                    ui.text(c, c.print("{s} {d}", .{ names[r.group], r.index }), .{});
                    g.cell();
                    ui.text(c, "2d", .{});
                },
            }
        }
        g.end();
    }
};

fn start(x: anytype, t: *ui.Tester, view: anytype) !void {
    try t.init(std.testing.allocator, .init(x, view), .{ .width = 400, .height = 400 });
    t.settle(1);
}

test "a group's heading shows its title and detail, its rows step in, and a click folds and opens it" {
    var x: Repos = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t, Repos.view);
    defer t.deinit();
    try std.testing.expect(t.hasText("2 pulls"));
    // A row's text lines up with its heading's title, past the chevron.
    try std.testing.expectApproxEqAbs(t.findText("alpha").?.x, t.findText("alpha 0").?.x, 1);
    try std.testing.expect(t.findText("alpha 0").?.x > 20);
    try t.clickText("beta");
    t.settle(1);
    try std.testing.expect(!x.open[1]);
    try std.testing.expect(!t.hasText("beta 0"));
    try std.testing.expectEqual(@as(?usize, 3), x.selected);
    try t.clickText("beta");
    t.settle(1);
    try std.testing.expect(x.open[1]);
    try std.testing.expect(t.hasText("beta 2"));
}

test "a group's rows fade in as it opens, and at once with reduced motion" {
    var x: Repos = .{ .open = .{ false, true, true } };
    var t: ui.Tester = undefined;
    try start(&x, &t, Repos.view);
    defer t.deinit();
    try t.clickText("alpha");
    t.frame();
    t.frame();
    var faint: usize = 0;
    for (t.ctx.nodes.items) |n| if (n.style.opacity < 1) {
        faint += 1;
    };
    try std.testing.expect(faint >= 2);
    t.settle(1);
    for (t.ctx.nodes.items) |n| try std.testing.expectEqual(@as(f32, 1), n.style.opacity);
    t.ctx.reduced_motion = true;
    try t.clickText("alpha");
    t.settle(1);
    try t.clickText("alpha");
    t.frame();
    for (t.ctx.nodes.items) |n| try std.testing.expectEqual(@as(f32, 1), n.style.opacity);
}

test "the keys fold and open groups, and move between a heading and its rows" {
    var x: Repos = .{ .start_focused = true };
    var t: ui.Tester = undefined;
    try start(&x, &t, Repos.view);
    defer t.deinit();
    t.key(.down);
    try std.testing.expectEqual(@as(?usize, 0), x.selected);
    // Right on an open heading goes to its first row; Left back to it.
    t.key(.right);
    try std.testing.expectEqual(@as(?usize, 1), x.selected);
    t.key(.left);
    try std.testing.expectEqual(@as(?usize, 0), x.selected);
    // Left folds it, Right opens it.
    t.key(.left);
    t.settle(1);
    try std.testing.expect(!x.open[0]);
    t.key(.right);
    t.settle(1);
    try std.testing.expect(x.open[0]);
    // Up and Down pass folded rows.
    t.key(.left);
    t.settle(1);
    t.key(.down);
    try std.testing.expectEqual(@as(?usize, 1), x.selected);
    // Enter and Space fold and open a heading, and don't open it as a row.
    t.key(.enter);
    t.settle(1);
    try std.testing.expect(!x.open[1]);
    try std.testing.expect(t.shortcut(.{ .key = ' ' }));
    t.settle(1);
    try std.testing.expect(x.open[1]);
    try std.testing.expectEqual(@as(usize, 0), x.opened);
    // Enter on a row opens it.
    t.key(.down);
    t.key(.enter);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.opened);
}

test "the selection stays on its row as groups above it fold, and goes to its heading when folded away" {
    var x: Repos = .{ .selected = 8 };
    var t: ui.Tester = undefined;
    try start(&x, &t, Repos.view);
    defer t.deinit();
    // gamma 0, after alpha (3 rows) and beta (4).
    x.open[0] = false;
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 6), x.selected);
    x.open[0] = true;
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 8), x.selected);
    x.open[2] = false;
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 7), x.selected);
    // A selection the caller moves stays where it put it.
    x.selected = 2;
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 2), x.selected);
}

test "a screen reader hears a heading with its detail and whether it is open" {
    var x: Repos = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t, Repos.view);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    var found = false;
    for (list.items) |e| if (std.mem.eql(u8, e.label, "alpha, 2 pulls")) {
        found = true;
        try std.testing.expectEqualStrings("expanded", e.value);
    };
    try std.testing.expect(found);
}

test "without singles, a group of one shows its row alone; a heading can fill cells" {
    var x: Repos = .{ .singles = false, .cells = true };
    var t: ui.Tester = undefined;
    try start(&x, &t, Repos.view);
    defer t.deinit();
    try std.testing.expect(t.hasText("gamma 0"));
    try std.testing.expect(!t.hasText("gamma"));
    try std.testing.expect(t.hasText("total"));
    // The total sits in the Age column, at its end.
    try std.testing.expectApproxEqAbs(t.findText("Age").?.x + t.findText("Age").?.w, t.findText("total").?.x + t.findText("total").?.w, 1);
}

/// A grid beside a pane the caller widens, its third column hiding when
/// the grid is narrow; under a bar, in a column of a set height.
const Beside = struct {
    pane: f32 = 100,
    hidden_cells: usize = 0,
    box: u32 = 0,

    const columns = [_]Column{
        .{ .title = "Name" },
        .{ .title = "Size", .width = 80 },
        .{ .title = "Kind", .width = 80, .min_grid_width = 400 },
    };

    fn view(x: *Beside, c: *ui.Context) void {
        const root = ui.div(c).column().w(800).h(300);
        defer root.end();
        ui.div(c).wFull().h(50).end();
        // A row that grows, a pane and the grid side by side, nothing
        // telling it how short it may be.
        const row = ui.div(c).row().wFull().grow();
        defer row.end();
        ui.div(c).w(x.pane).hFull().end();
        const col = ui.div(c).column().w(0).grow().hFull();
        defer col.end();
        var g = grid(c, &columns, .{ .count = 100 });
        x.box = g.box.index;
        while (g.next()) |r| {
            for (0..3) |i| if (g.cellAt(i)) {
                ui.text(c, c.print("{d}-{d}", .{ r.index, i }), .{});
            } else {
                x.hidden_cells += 1;
            };
        }
        g.end();
    }
};

test "a column hides when the grid is narrow, though the window is wide" {
    var x: Beside = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Beside.view), .{ .width = 800, .height = 300 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(t.hasText("Kind"));
    try std.testing.expect(t.hasText("0-2"));
    x.pane = 500;
    t.frame();
    t.settle(1);
    try std.testing.expect(!t.hasText("Kind"));
    try std.testing.expect(!t.hasText("0-2"));
    try std.testing.expect(x.hidden_cells > 0);
    x.pane = 100;
    t.frame();
    t.settle(1);
    try std.testing.expect(t.hasText("Kind"));
}

/// A grid under a bar, in a column of a set height, and nothing else
/// telling it how short it may be.
const Under = struct {
    box: u32 = 0,

    fn view(x: *Under, c: *ui.Context) void {
        const root = ui.div(c).column().w(400).h(300);
        defer root.end();
        // A pane that grows, as an app's are, around a bar and the grid.
        const pane = ui.div(c).column().wFull().grow();
        defer pane.end();
        ui.div(c).wFull().h(50).end();
        var g = grid(c, &Beside.columns, .{ .count = 100 });
        x.box = g.box.index;
        while (g.next()) |r| if (g.cellAt(0)) ui.text(c, c.print("{d}-0", .{r.index}), .{});
        g.end();
    }
};

test "a grid in a column that grows takes the room left, and scrolls" {
    var x: Under = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Under.view), .{ .width = 400, .height = 400 });
    defer t.deinit();
    t.settle(1);
    const r = t.ctx.rects.get(t.ctx.node(x.box).id).?;
    // Under the bar, to the bottom of the column.
    try std.testing.expectApproxEqAbs(@as(f32, 250), r.h, 1);
    try std.testing.expect(!t.hasText("99-0"));
}

test "a grid in a row that grows, beside a pane, takes the room left, and scrolls" {
    var x: Beside = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Beside.view), .{ .width = 800, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const r = t.ctx.rects.get(t.ctx.node(x.box).id).?;
    try std.testing.expectApproxEqAbs(@as(f32, 250), r.h, 1);
    try std.testing.expect(!t.hasText("99-0"));
}

/// Runs as cards or two-line rows, with a status, keys and no titles.
const Runs = struct {
    cards: bool = false,
    two: bool = false,
    header: bool = true,
    selected: ?usize = 0,
    backs: usize = 0,
    escapes: usize = 0,

    const columns = [_]Column{
        .{ .title = "Run", .width = 140 },
        .{ .title = "Took", .width = 60, .alignment = .end },
    };

    fn view(x: *Runs, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        if (c.frame == 0) c.focusNext(false);
        var g = grid(c, &columns, .{ .count = 3, .rows = if (x.cards) .cards else .plain, .lines = if (x.two) 2 else 1, .header = x.header, .selected = &x.selected });
        if (g.back) x.backs += 1;
        if (g.escaped) x.escapes += 1;
        while (g.next()) |row| {
            if (row.index == 1) row.status(.danger);
            g.cell();
            if (x.two) {
                g.twoLines(c.print("build {d}", .{row.index}), "main · a long branch name that runs on", .{});
            } else ui.text(c, c.print("build {d}", .{row.index}), .{});
            g.cell();
            ui.text(c, "2m", .{});
        }
        g.end();
    }
};

test "cards have room between them, the selected one in the accent, and a status tints a border" {
    var x: Runs = .{ .cards = true };
    var t: ui.Tester = undefined;
    try start(&x, &t, Runs.view);
    defer t.deinit();
    const tk = kit.tokens(&t.ctx);
    try std.testing.expectApproxEqAbs(@as(f32, 28 + 6), t.findText("build 1").?.y - t.findText("build 0").?.y, 0.5);
    var danger = false;
    var accent = false;
    for (t.ctx.nodes.items) |n| if (n.style.border) |b| {
        if (std.meta.eql(b, kit.statusColor(tk, .danger))) danger = true;
        if (std.meta.eql(b, tk.primary)) accent = true;
    };
    try std.testing.expect(danger and accent);
}

test "a status on a plain row is a bar at its leading edge" {
    var x: Runs = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t, Runs.view);
    defer t.deinit();
    const danger = kit.statusColor(kit.tokens(&t.ctx), .danger);
    var bars: usize = 0;
    for (t.ctx.nodes.items) |n| if (n.style.background) |b| if (std.meta.eql(b, danger) and n.style.width == .px and n.style.width.px == 3) {
        bars += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), bars);
}

test "two-line cells take taller rows, and show whole in a tooltip when cut off" {
    var x: Runs = .{ .two = true };
    var t: ui.Tester = undefined;
    try start(&x, &t, Runs.view);
    defer t.deinit();
    try std.testing.expectApproxEqAbs(@as(f32, 28 + 16 + 2), t.findText("build 1").?.y - t.findText("build 0").?.y, 0.5);
    try std.testing.expect(startsWith(&t, "main").?.y > t.findText("build 0").?.y);
    // Cut off where it is drawn, its whole text shows only in the tooltip.
    try std.testing.expectEqual(@as(usize, 0), containing(&t, "runs on"));
    try t.hoverText("build 0");
    t.settle(2);
    try std.testing.expectEqual(@as(usize, 1), containing(&t, "runs on"));
}

/// How many texts hold `part`.
fn containing(t: *ui.Tester, part: []const u8) usize {
    var n: usize = 0;
    for (t.ctx.nodes.items) |node| switch (node.content) {
        .text => |tx| if (std.mem.indexOf(u8, tx.str, part) != null) {
            n += 1;
        },
        else => {},
    };
    return n;
}

/// The first text that starts with `prefix`, cut short or not.
fn startsWith(t: *ui.Tester, prefix: []const u8) ?ui.Rect {
    for (t.ctx.nodes.items) |n| switch (n.content) {
        .text => |tx| if (std.mem.startsWith(u8, tx.str, prefix)) return n.rect,
        else => {},
    };
    return null;
}

test "without titles, the grid starts with its rows" {
    var x: Runs = .{ .header = false };
    var t: ui.Tester = undefined;
    try start(&x, &t, Runs.view);
    defer t.deinit();
    try std.testing.expect(!t.hasText("Run"));
    try std.testing.expect(t.findText("build 0").?.y < 20);
}

test "Backspace and Cmd+Up go back, and Escape is reported, while the grid has the keyboard" {
    var x: Runs = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t, Runs.view);
    defer t.deinit();
    t.key(.backspace);
    try std.testing.expectEqual(@as(usize, 1), x.backs);
    const mac = builtin.os.tag.isDarwin();
    try std.testing.expect(t.shortcut(.{ .key = ui.Shortcut.up, .cmd = mac, .alt = !mac }));
    try std.testing.expectEqual(@as(usize, 2), x.backs);
    // Up alone still moves the selection.
    x.selected = 2;
    t.key(.up);
    try std.testing.expectEqual(@as(?usize, 1), x.selected);
    t.key(.escape);
    try std.testing.expectEqual(@as(usize, 1), x.escapes);
    // Without the keyboard, they are someone else's.
    t.ctx.focus = 0;
    t.key(.backspace);
    try std.testing.expectEqual(@as(usize, 2), x.backs);
}

test "a double click on a heading folds it once, not back open" {
    var x: Repos = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t, Repos.view);
    defer t.deinit();
    const r = t.findText("beta").?;
    t.doubleClick(r.x + 2, r.y + r.h / 2);
    t.settle(1);
    try std.testing.expect(!x.open[1]);
}

/// Ten rows, five shown.
const Few = struct {
    selected: ?usize = 8,
    cards: bool = false,
    scale: f32 = 1,

    const columns = [_]Column{.{ .title = "Name" }};

    fn view(x: *Few, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        var g = grid(c, &columns, .{ .count = 10, .max_rows = 5, .selected = &x.selected });
        while (g.next()) |row| {
            g.cell();
            ui.text(c, c.print("row {d}", .{row.index}), .{});
        }
        g.end();
    }
};

test "with max_rows, a selection past the rows shown moves back to the last shown" {
    var x: Few = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t, Few.view);
    defer t.deinit();
    try std.testing.expectEqual(@as(?usize, 4), x.selected);
}

test "a heading's chevron follows the grid's scale" {
    const T = struct {
        open: [1]bool = .{true},
        fn view(x: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().sizeFull();
            defer root.end();
            const gs = Groups.init(c, &.{.{ .size = 1 }}, &x.open, .{});
            var g = grid(c, &Repos.columns, .{ .count = gs.count(), .groups = gs, .scale = 2 });
            while (g.next()) |row| switch (gs.at(row.index)) {
                .heading => g.heading(.{ .title = "alpha" }),
                .row => {
                    g.cell();
                    ui.text(c, "a", .{});
                },
            };
            g.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    var size: f32 = 0;
    for (t.ctx.nodes.items) |node| switch (node.content) {
        .icon => |ic| size = ic.size,
        else => {},
    };
    try std.testing.expectEqual(@as(f32, 19), size);
}

test "column titles are headers to a screen reader, in the caller's words" {
    const T = struct {
        sort: g_mod.Sort = .{},
        fn view(x: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().sizeFull();
            defer root.end();
            const columns = [_]Column{ .{ .title = "Title", .sortable = true }, .{ .title = "Age", .width = 60 } };
            var g = grid(c, &columns, .{ .count = 1, .sort = &x.sort, .ascending_text = "croissant", .sort_hint_text = "trie" });
            while (g.next()) |_| {
                g.cell();
                ui.text(c, "a", .{});
            }
            g.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqualStrings("Title", list.items[0].label);
    try std.testing.expect(list.items[0].header);
    try std.testing.expectEqualStrings("croissant", list.items[0].value);
    try std.testing.expectEqualStrings("trie", list.items[0].hint);
}

test {
    _ = @import("grid_loading_tests.zig");
}
