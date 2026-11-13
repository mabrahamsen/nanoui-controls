//! The pill's tests: its colors, lengths and shapes, a lead, an open pill
//! with a button in it, and what a screen reader hears.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const pill_mod = @import("pill.zig");
const pill = pill_mod.pill;
const pillOpen = pill_mod.pillOpen;

/// Draws `view` and returns the tester, settled.
fn start(t: *ui.Tester, x: anytype, view: anytype, w: f32, h: f32) !void {
    try t.init(std.testing.allocator, .init(x, view), .{ .width = w, .height = h });
    t.settle(1);
}

/// What a screen reader walks, in the tester's frame.
fn elements(t: *ui.Tester, arena: *std.heap.ArenaAllocator) ![]const ui.access.Element {
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    return list.items;
}

/// The node holding `text`.
fn textNode(t: *ui.Tester, text: []const u8) ?@TypeOf(t.ctx.nodes.items[0]) {
    for (t.ctx.nodes.items) |n| switch (n.content) {
        .text => |x| if (std.mem.eql(u8, x.str, text)) return n,
        else => {},
    };
    return null;
}

test "a pill is the accent by default, a status's color with one, and proportional" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            const row = ui.div(c).row().gap(8).p(8);
            defer row.end();
            pill(c, "LIVE", .{});
            pill(c, "FAILED", .{ .status = .danger });
            pill(c, "OWN", .{ .status = .danger, .color = .hex(0x00ff00) });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try start(&t, &x, T.view, 300, 60);
    defer t.deinit();
    const tk = kit.tokens(&t.ctx);
    const live = textNode(&t, "LIVE").?.content.text.style;
    try std.testing.expectEqual(tk.primary, live.color.?);
    try std.testing.expect(!live.mono);
    try std.testing.expectEqual(tk.danger, textNode(&t, "FAILED").?.content.text.style.color.?);
    try std.testing.expectEqual(ui.Color.hex(0x00ff00), textNode(&t, "OWN").?.content.text.style.color.?);
}

test "a pill's lengths follow its size, and set ones go over them" {
    const xs = pill_mod.lengths(.{});
    try std.testing.expectEqual(@as(f32, 9), xs.px);
    try std.testing.expectEqual(@as(f32, 4), xs.py);
    try std.testing.expectEqual(@as(f32, 5), xs.radius);
    const md = pill_mod.lengths(.{ .size = .md });
    try std.testing.expect(md.px > xs.px and md.text > xs.text);
    const own = pill_mod.lengths(.{ .size = .md, .px = 3, .text_size = 20 });
    try std.testing.expectEqual(@as(f32, 3), own.px);
    try std.testing.expectEqual(@as(f32, 20), own.text);
    try std.testing.expectEqual(md.py, own.py);
}

test "a one-letter box is square, and a capsule fully rounded, both following scale" {
    const T = struct {
        box: u32 = 0,
        capsule: u32 = 0,
        fn view(x: *@This(), c: *ui.Context) void {
            const row = ui.div(c).row().gap(8).p(8).itemsStart();
            defer row.end();
            x.box = @intCast(c.nodes.items.len);
            pill(c, "P", .{ .shape = .box, .height = 18, .scale = 2 });
            x.capsule = @intCast(c.nodes.items.len);
            pill(c, "LIVE", .{ .scale = 2 });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try start(&t, &x, T.view, 300, 100);
    defer t.deinit();
    const b = t.ctx.rects.get(t.ctx.nodes.items[x.box].id).?;
    try std.testing.expectEqual(@as(f32, 36), b.h);
    try std.testing.expect(b.w >= b.h);
    try std.testing.expectEqual(@as(f32, 10), t.ctx.nodes.items[x.box].style.radius);
    try std.testing.expectEqual(@as(f32, 18), t.ctx.nodes.items[x.capsule].style.padding.left);
}

test "a pill's dot glows, and dim it is faint without a glow" {
    const T = struct {
        dim: bool = false,
        fn view(x: *@This(), c: *ui.Context) void {
            pill(c, "REC", .{ .status = .danger, .lead = .{ .dot = .{ .dim = x.dim } } });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try start(&t, &x, T.view, 200, 60);
    defer t.deinit();
    const danger = kit.tokens(&t.ctx).danger;
    var glowing = false;
    for (t.ctx.nodes.items) |n| if (n.style.background) |bg| if (std.meta.eql(bg, danger)) {
        glowing = n.style.shadow != null;
    };
    try std.testing.expect(glowing);
    x.dim = true;
    t.settle(1);
    for (t.ctx.nodes.items) |n| if (n.style.background) |bg| if (std.meta.eql(bg, danger.alpha(0.25))) {
        try std.testing.expect(n.style.shadow == null);
    };
}

test "a screen reader hears a pill's label, or its value_text, with its tooltip after it" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            const row = ui.div(c).row().gap(8).p(8);
            defer row.end();
            pill(c, "P", .{ .shape = .box, .tooltip = "Performance cores" });
            pill(c, "● REC", .{ .value_text = "Recording" });
            pill(c, "LIVE", .{});
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try start(&t, &x, T.view, 300, 60);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const list = try elements(&t, &arena);
    try std.testing.expectEqual(@as(usize, 3), list.len);
    try std.testing.expectEqualStrings("P", list[0].label);
    try std.testing.expectEqualStrings("Performance cores", list[0].hint);
    try std.testing.expectEqual(ui.access.Role.static_text, list[0].role);
    try std.testing.expectEqualStrings("Recording", list[1].label);
    try std.testing.expectEqualStrings("LIVE", list[2].label);
}

test "an open pill holds a button after its label, which is clicked and reached" {
    const T = struct {
        clicked: usize = 0,
        fn view(x: *@This(), c: *ui.Context) void {
            const row = ui.div(c).row().p(8);
            defer row.end();
            const p = pillOpen(c, "BREACHES?", .{ .tooltip = "Checks the password" });
            if (kit.button(c, "Check", .{ .size = .xs, .variant = .ghost }).clicked) x.clicked += 1;
            p.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try start(&t, &x, T.view, 300, 60);
    defer t.deinit();
    try std.testing.expect(t.findText("Check").?.x > t.findText("BREACHES?").?.x);
    try t.clickText("Check");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.clicked);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var check = false;
    for (try elements(&t, &arena)) |e| check = check or (e.role == .button and std.mem.eql(u8, e.label, "Check"));
    try std.testing.expect(check);
}
