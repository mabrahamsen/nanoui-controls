//! The grid's tests of selecting several rows, its right-click hook,
//! rows that take no clicks, and what a screen reader is told of it.
const std = @import("std");
const builtin = @import("builtin");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const grid = @import("grid.zig").grid;
const Sort = @import("grid.zig").Sort;
const Fruit = @import("grid_tests.zig").Fruit;

/// A grid of a hundred rows, several of which select.
const Many = struct {
    marked: [100]bool = @splat(false),
    selected: ?usize = null,
    sort: Sort = .{},
    menu: ?usize = null,
    /// Make new widget state between the grid and its rows, as a busy
    /// app's widgets do, so nanoui's store of it grows.
    churn: bool = false,
    frames: usize = 0,
    burst: usize = 0,
    drag_rows: bool = false,
    /// The row a drag started on, and how many rows it carried.
    dragged: ?usize = null,
    carried: usize = 0,
    /// The text the drag was given, as nanoui had it in that frame: it
    /// keeps it only for the frame, as the window hands it on then.
    drag_text: [32]u8 = undefined,
    drag_len: usize = 0,

    fn view(m: *Many, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        var g = grid(c, &Fruit.columns, .{ .count = m.marked.len, .sort = &m.sort, .selected = &m.selected, .multi = &m.marked, .drag_rows = m.drag_rows });
        m.frames += 1;
        // In the frame a click lands, more new state than the store has
        // room for, twice as much each time, so it grows then.
        if (m.churn and c.input.released) {
            m.burst = if (m.burst == 0) 20_000 else m.burst * 2;
            for (0..m.burst) |j| {
                ui.key(c, c.print("churn-{d}-{d}", .{ m.frames, j }));
                _ = c.state(struct { x: u8 = 0 }, "churn");
                c.next_key = null;
            }
        }
        while (g.next()) |row| {
            if (row.secondary_clicked) m.menu = row.index;
            if (row.drag_started) {
                m.dragged = row.index;
                m.carried = m.count();
                g.dragOut(c.print("{d} fruit", .{m.carried}));
                const text = c.drag_request.?.text;
                @memcpy(m.drag_text[0..text.len], text);
                m.drag_len = text.len;
            }
            g.cell();
            ui.text(c, c.print("fruit {d}", .{row.index}), .{});
            g.cell();
            ui.text(c, c.print("{d}", .{row.index * 100}), .{});
            g.cell();
            ui.text(c, if (row.selected) "picked" else "-", .{});
        }
        g.end();
    }

    /// The rows selected, in order.
    fn rows(m: *const Many, buf: []usize) []usize {
        var n: usize = 0;
        for (m.marked, 0..) |on, i| if (on) {
            buf[n] = i;
            n += 1;
        };
        return buf[0..n];
    }

    fn count(m: *const Many) usize {
        var n: usize = 0;
        for (m.marked) |on| n += @intFromBool(on);
        return n;
    }

    fn expectRows(m: *const Many, want: []const usize) !void {
        var buf: [100]usize = undefined;
        try std.testing.expectEqualSlices(usize, want, m.rows(&buf));
    }
};

/// Clicks row `i` with the modifier keys held, as a window gets it.
fn clickRow(t: *ui.Tester, i: usize, mods: struct { adds: bool = false, shift: bool = false }) !void {
    var buf: [32]u8 = undefined;
    const r = t.findText(try std.fmt.bufPrint(&buf, "fruit {d}", .{i})).?;
    const mac = builtin.os.tag.isDarwin();
    t.setMods(.{ .cmd = mac and mods.adds, .ctrl = !mac and mods.adds, .shift = mods.shift });
    t.click(r.x + 2, r.y + r.h / 2);
    t.setMods(.{});
    t.settle(1);
}

fn start(t: *ui.Tester, m: *Many) !void {
    try t.init(std.testing.allocator, .init(m, Many.view), .{ .width = 400, .height = 400 });
    t.settle(1);
}

test "a click selects one row, and Cmd-click (Ctrl-click) adds and takes away rows" {
    var m: Many = .{};
    var t: ui.Tester = undefined;
    try start(&t, &m);
    defer t.deinit();
    try clickRow(&t, 2, .{});
    try m.expectRows(&.{2});
    try clickRow(&t, 5, .{ .adds = true });
    try clickRow(&t, 7, .{ .adds = true });
    try m.expectRows(&.{ 2, 5, 7 });
    try std.testing.expectEqual(@as(?usize, 7), m.selected);
    try clickRow(&t, 5, .{ .adds = true });
    try m.expectRows(&.{ 2, 7 });
    // A plain click selects its row alone again.
    try clickRow(&t, 3, .{});
    try m.expectRows(&.{3});
}

test "Shift-click selects from where the selection started" {
    var m: Many = .{};
    var t: ui.Tester = undefined;
    try start(&t, &m);
    defer t.deinit();
    try clickRow(&t, 4, .{});
    try clickRow(&t, 7, .{ .shift = true });
    try m.expectRows(&.{ 4, 5, 6, 7 });
    // From the same start, the other way: the run moves, it doesn't grow.
    try clickRow(&t, 2, .{ .shift = true });
    try m.expectRows(&.{ 2, 3, 4 });
    try std.testing.expectEqual(@as(?usize, 2), m.selected);
    // A Cmd-click starts the next run.
    try clickRow(&t, 8, .{ .adds = true });
    try clickRow(&t, 10, .{ .shift = true });
    try m.expectRows(&.{ 8, 9, 10 });
}

test "Shift with the keys extends the selection, and the keys alone move it" {
    var m: Many = .{};
    var t: ui.Tester = undefined;
    try start(&t, &m);
    defer t.deinit();
    try clickRow(&t, 3, .{});
    try std.testing.expect(t.shortcut(.{ .key = ui.Shortcut.down, .shift = true }));
    try std.testing.expect(t.shortcut(.{ .key = ui.Shortcut.down, .shift = true }));
    try m.expectRows(&.{ 3, 4, 5 });
    try std.testing.expect(t.shortcut(.{ .key = ui.Shortcut.up, .shift = true }));
    try m.expectRows(&.{ 3, 4 });
    // Shift with End, a key rather than a shortcut: from 3 to the last.
    t.ctx.input.shift = true;
    t.key(.end);
    t.ctx.input.shift = false;
    try std.testing.expectEqual(@as(usize, 97), m.count());
    try std.testing.expect(m.marked[3] and m.marked[99] and !m.marked[2]);
    // The keys alone select the row they move to, alone.
    t.key(.home);
    try m.expectRows(&.{0});
    try std.testing.expect(t.shortcut(.{ .key = ui.Shortcut.down }));
    try m.expectRows(&.{1});
}

test "Cmd+A (Ctrl+A) selects every row, unless a text field has the keys" {
    var m: Many = .{};
    var t: ui.Tester = undefined;
    try start(&t, &m);
    defer t.deinit();
    try std.testing.expect(t.shortcut(.{ .key = 'a', .cmd = true }));
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 100), m.count());
    try clickRow(&t, 1, .{});
    try std.testing.expectEqual(@as(usize, 1), m.count());
}

test "a right-click reports the row, selecting it unless it is selected" {
    var m: Many = .{};
    var t: ui.Tester = undefined;
    try start(&t, &m);
    defer t.deinit();
    try clickRow(&t, 2, .{});
    try clickRow(&t, 3, .{ .shift = true });
    // On a selected row: the menu is for the selection, which stays.
    const three = t.findText("fruit 3").?;
    t.secondaryClick(three.x + 2, three.y + 4);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 3), m.menu);
    try m.expectRows(&.{ 2, 3 });
    // On another row: it becomes the selection.
    const six = t.findText("fruit 6").?;
    t.secondaryClick(six.x + 2, six.y + 4);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 6), m.menu);
    try m.expectRows(&.{6});
    try std.testing.expectEqual(@as(?usize, 6), m.selected);
}

test "a right-click selects its row in a grid of one selected row" {
    const One = struct {
        selected: ?usize = null,
        menu: ?usize = null,
        fn view(o: *@This(), c: *ui.Context) void {
            var g = grid(c, &Fruit.columns, .{ .count = 3, .selected = &o.selected });
            while (g.next()) |row| {
                if (row.secondary_clicked) o.menu = row.index;
                g.cell();
                ui.text(c, Fruit.names[row.index], .{});
            }
            g.end();
        }
    };
    var o: One = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&o, One.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const banana = t.findText("banana").?;
    t.secondaryClick(banana.x + 2, banana.y + 4);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, 1), o.menu);
    try std.testing.expectEqual(@as(?usize, 1), o.selected);
}

test "a screen reader hears rows, which are selected, and how the rows are sorted" {
    var m: Many = .{ .sort = .{ .column = 1, .descending = true } };
    var t: ui.Tester = undefined;
    try start(&t, &m);
    defer t.deinit();
    try clickRow(&t, 1, .{});
    try clickRow(&t, 2, .{ .adds = true });
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var out: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &out);
    var rows: usize = 0;
    var selected: usize = 0;
    var count: ?ui.access.Element = null;
    var fruit: ?ui.access.Element = null;
    for (out.items) |e| {
        if (e.role == .row) {
            rows += 1;
            if (e.selected) selected += 1;
            if (std.mem.eql(u8, e.label, "fruit 1, 100, picked")) try std.testing.expect(e.selected);
            if (std.mem.eql(u8, e.label, "fruit 0, 0, -")) try std.testing.expect(!e.selected);
        }
        if (std.mem.eql(u8, e.label, "Count")) count = e;
        if (std.mem.eql(u8, e.label, "Fruit")) fruit = e;
    }
    try std.testing.expect(rows >= 10);
    try std.testing.expectEqual(@as(usize, 2), selected);
    try std.testing.expectEqual(ui.access.Role.button, count.?.role);
    try std.testing.expectEqualStrings("sorted descending", count.?.value);
    try std.testing.expectEqualStrings("", fruit.?.value);
}

test "a grid whose rows aren't clickable is a table to read" {
    const Table = struct {
        clickable: bool = false,
        clicked: usize = 0,
        selected: ?usize = null,
        fn view(tb: *@This(), c: *ui.Context) void {
            var g = grid(c, &Fruit.columns, .{ .count = 3, .rows = 3, .clickable = tb.clickable, .selected = &tb.selected });
            while (g.next()) |row| {
                if (row.clicked) tb.clicked += 1;
                g.cell();
                ui.text(c, Fruit.names[row.index], .{});
            }
            g.end();
        }
    };
    var tb: Table = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&tb, Table.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const banana = t.findText("banana").?;
    t.moveTo(banana.x + banana.w + 40, banana.y + 4);
    t.settle(1);
    try std.testing.expect(!t.ctx.cursor_hand);
    try t.clickText("banana");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 0), tb.clicked);
    try std.testing.expectEqual(@as(?usize, null), tb.selected);
    // Still rows to a screen reader.
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var out: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &out);
    var rows: usize = 0;
    for (out.items) |e| rows += @intFromBool(e.role == .row);
    try std.testing.expectEqual(@as(usize, 3), rows);
    // The same rows clickable: the hand, and the click.
    tb.clickable = true;
    t.moveTo(banana.x + banana.w + 40, banana.y + 4);
    t.settle(1);
    try std.testing.expect(t.ctx.cursor_hand);
    try t.clickText("banana");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), tb.clicked);
    try std.testing.expectEqual(@as(?usize, 1), tb.selected);
}

test "the selection's anchor holds while other widgets make state between the grid and its rows" {
    var m: Many = .{ .churn = true };
    var t: ui.Tester = undefined;
    try start(&t, &m);
    defer t.deinit();
    try clickRow(&t, 2, .{});
    for (0..5) |_| t.frame();
    try clickRow(&t, 6, .{ .shift = true });
    try m.expectRows(&.{ 2, 3, 4, 5, 6 });
    for (0..5) |_| t.frame();
    try clickRow(&t, 4, .{ .shift = true });
    try m.expectRows(&.{ 2, 3, 4 });
}

/// Holds row `i` and moves `by` points down, then lets go.
fn dragRow(t: *ui.Tester, i: usize, by: f32) !void {
    var buf: [32]u8 = undefined;
    const r = t.findText(try std.fmt.bufPrint(&buf, "fruit {d}", .{i})).?;
    t.drag(r.x + 2, r.y + r.h / 2, r.x + 2, r.y + r.h / 2 + by);
    t.settle(1);
}

test "dragging a row selects it and carries what the caller gives" {
    var m: Many = .{ .drag_rows = true };
    var t: ui.Tester = undefined;
    try start(&t, &m);
    defer t.deinit();
    try clickRow(&t, 1, .{});
    try dragRow(&t, 5, 40);
    try std.testing.expectEqual(@as(?usize, 5), m.dragged);
    try m.expectRows(&.{5});
    try std.testing.expectEqualStrings("1 fruit", m.drag_text[0..m.drag_len]);
}

test "dragging a selected row carries the whole selection" {
    var m: Many = .{ .drag_rows = true };
    var t: ui.Tester = undefined;
    try start(&t, &m);
    defer t.deinit();
    try clickRow(&t, 2, .{});
    try clickRow(&t, 4, .{ .shift = true });
    try dragRow(&t, 3, 40);
    try std.testing.expectEqual(@as(?usize, 3), m.dragged);
    try m.expectRows(&.{ 2, 3, 4 });
    try std.testing.expectEqualStrings("3 fruit", m.drag_text[0..m.drag_len]);
}

test "a row held and barely moved is a click, and rows don't drag unless asked" {
    var m: Many = .{ .drag_rows = true };
    var t: ui.Tester = undefined;
    try start(&t, &m);
    defer t.deinit();
    try dragRow(&t, 6, 2);
    try std.testing.expectEqual(@as(?usize, null), m.dragged);
    try m.expectRows(&.{6});
    m.drag_rows = false;
    try dragRow(&t, 8, 40);
    try std.testing.expectEqual(@as(?usize, null), m.dragged);
    try std.testing.expect(t.ctx.drag_request == null);
}
