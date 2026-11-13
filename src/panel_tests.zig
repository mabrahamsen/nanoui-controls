//! The panel's tests: its look, a status's tint, its card, its title to a
//! screen reader, and folding by click and key.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const panel = @import("panel.zig").panel;
const Options = @import("panel.zig").Options;

const Pane = struct {
    opts: Options = .{ .title = "RETENTION" },
    open: bool = true,
    folds: bool = false,
    box: u32 = 0,
    clicks: usize = 0,

    fn view(x: *Pane, c: *ui.Context) void {
        const root = ui.div(c).column().w(300).p(8).gap(8);
        defer root.end();
        var o = x.opts;
        if (x.folds) o.open = &x.open;
        const p = panel(c, o);
        x.box = p.index;
        if (!x.folds or x.open) {
            ui.text(c, "Keep 10 snapshots", .{});
            if (kit.button(c, "Prune", .{ .size = .sm }).clicked) x.clicks += 1;
        }
        p.end();
    }
};

fn start(x: *Pane, t: *ui.Tester) !void {
    try t.init(std.testing.allocator, .init(x, Pane.view), .{ .width = 320, .height = 240 });
    t.settle(1);
}

fn elements(t: *ui.Tester, arena: *std.heap.ArenaAllocator) ![]const ui.access.Element {
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    return list.items;
}

test "a panel is the theme's surface, border and radius, as wide as its parent, its title a heading over what it holds" {
    var x: Pane = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const tk = kit.tokens(&t.ctx);
    const n = t.ctx.nodes.items[x.box];
    try std.testing.expectEqual(tk.surface, n.style.background.?);
    try std.testing.expectEqual(tk.border, n.style.border.?);
    try std.testing.expectEqual(@as(f32, 14), n.style.padding.left);
    try std.testing.expectEqual(@as(f32, 284), t.ctx.rects.get(n.id).?.w);
    try std.testing.expect(t.findText("RETENTION").?.y < t.findText("Keep 10 snapshots").?.y);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const list = try elements(&t, &arena);
    try std.testing.expectEqualStrings("RETENTION", list[0].label);
    try std.testing.expect(list[0].header);
    // What it holds is reached as it is.
    var prune = false;
    for (list) |e| prune = prune or (e.role == .button and std.mem.eql(u8, e.label, "Prune"));
    try std.testing.expect(prune);
}

test "a status tints the border and the caption, and the card goes over the panel's own" {
    var x: Pane = .{ .opts = .{ .title = "DANGER ZONE", .status = .danger, .card = .{ .px = 4, .radius = 0, .width = .{ .px = 100 } } } };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const tk = kit.tokens(&t.ctx);
    const n = t.ctx.nodes.items[x.box];
    try std.testing.expectEqual(tk.danger.alpha(0.5), n.style.border.?);
    try std.testing.expectEqual(@as(f32, 4), n.style.padding.left);
    try std.testing.expectEqual(@as(f32, 14), n.style.padding.top);
    try std.testing.expectEqual(@as(f32, 0), n.style.radius);
    try std.testing.expectEqual(ui.Length{ .px = 100 }, n.style.width);
    for (t.ctx.nodes.items) |node| switch (node.content) {
        .text => |s| if (std.mem.eql(u8, s.str, "DANGER ZONE")) try std.testing.expectEqual(tk.danger, s.style.color.?),
        else => {},
    };
}

test "a folding panel folds by a click and by the keys, and says whether it is open" {
    var x: Pane = .{ .folds = true };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list = try elements(&t, &arena);
    try std.testing.expectEqual(ui.access.Role.button, list[0].role);
    try std.testing.expectEqualStrings("RETENTION", list[0].label);
    try std.testing.expectEqualStrings("expanded", list[0].value);
    try t.clickText("RETENTION");
    t.settle(1);
    try std.testing.expect(!x.open);
    try std.testing.expect(!t.hasText("Keep 10 snapshots"));
    list = try elements(&t, &arena);
    try std.testing.expectEqualStrings("collapsed", list[0].value);
    // Tab reaches the head, and Enter and Space flip it.
    t.ctx.focus = 0;
    t.key(.tab);
    t.key(.enter);
    t.settle(1);
    try std.testing.expect(x.open);
    try std.testing.expect(t.shortcut(.{ .key = ' ' }));
    t.settle(1);
    try std.testing.expect(!x.open);
}
