//! Tests of a form's sections and what goes in them: headings that fold,
//! a heading in a status's color, notes, rows that lead somewhere, and
//! controls at the row's end.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const form_mod = @import("form.zig");
const form = form_mod.form;

/// A form of a plain section, a folding one, a link and a note.
const Settings = struct {
    opts: form_mod.Options = .{},
    advanced: bool = false,
    shown: bool = false,
    opened: usize = 0,
    link_disabled: bool = false,

    fn view(x: *Settings, c: *ui.Context) void {
        const root = ui.div(c).column().w(400);
        defer root.end();
        var f = form(c, x.opts);
        f.heading("General", .{});
        f.property("Name", "studio", .{});
        if (f.link("Repository", "studio", .{ .disabled = x.link_disabled })) x.opened += 1;
        f.note("Settings apply at once.");
        x.shown = f.foldingHeading("Advanced", &x.advanced, .{ .description = "For the curious." });
        if (x.shown) f.property("Threads", "4", .{});
        f.heading("Danger zone", .{ .status = .danger });
        f.property("Reset", "everything", .{});
        f.end();
    }
};

fn start(x: *Settings, t: *ui.Tester) !void {
    try t.init(std.testing.allocator, .init(x, Settings.view), .{ .width = 420, .height = 500 });
    t.settle(1);
    for (0..2) |_| t.frame();
}

fn elements(t: *ui.Tester, arena: std.mem.Allocator) ![]const ui.access.Element {
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena, &list);
    return list.items;
}

fn find(list: []const ui.access.Element, label: []const u8) ?ui.access.Element {
    for (list) |e| if (std.mem.eql(u8, e.label, label)) return e;
    return null;
}

/// The height of the box holding the folding section's rows, if drawn.
fn foldHeight(t: *ui.Tester) ?f32 {
    for (t.ctx.nodes.items) |node| {
        if (!node.style.clip) continue;
        const h = node.style.height;
        if (h == .px) return h.px;
    }
    return null;
}

test "a folding heading hides its rows until opened, by a click or the keys, easing open" {
    var x: Settings = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    try std.testing.expect(!x.shown and !t.hasText("Threads"));
    try std.testing.expect(t.hasText("For the curious."));
    try t.clickText("Advanced");
    try std.testing.expect(x.advanced);
    t.frame();
    t.frame();
    // Part of the way open, then all the way.
    const moving = foldHeight(&t).?;
    try std.testing.expect(moving > 0);
    t.settle(2);
    try std.testing.expect(t.hasText("Threads"));
    try std.testing.expectEqual(@as(?f32, null), foldHeight(&t));
    // Enter, then Space, once it has the keyboard.
    t.key(.enter);
    try std.testing.expect(!x.advanced);
    _ = t.shortcut(.{ .key = ' ' });
    t.frame();
    try std.testing.expect(x.advanced);
}

test "with reduced motion, a folding heading opens at once" {
    var x: Settings = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    t.ctx.reduce_motion = true;
    x.advanced = true;
    t.frame();
    t.frame();
    try std.testing.expect(t.hasText("Threads"));
    try std.testing.expectEqual(@as(?f32, null), foldHeight(&t));
}

test "a screen reader hears a folding heading as a button that says whether it is open" {
    var x: Settings = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var e = find(try elements(&t, arena.allocator()), "Advanced").?;
    try std.testing.expectEqual(ui.access.Role.button, e.role);
    try std.testing.expectEqualStrings("collapsed", e.value);
    try std.testing.expectEqualStrings("For the curious.", e.hint);
    x.advanced = true;
    t.settle(2);
    e = find(try elements(&t, arena.allocator()), "Advanced").?;
    try std.testing.expectEqualStrings("expanded", e.value);
    // A plain heading is a header.
    try std.testing.expect(find(try elements(&t, arena.allocator()), "General").?.header);
}

test "a link row is clicked as a whole, or with Enter once Tab reaches it, unless disabled" {
    var x: Settings = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    // Its value at the row's end, before the chevron.
    var value: ?ui.Rect = null;
    for (t.ctx.nodes.items) |node| switch (node.content) {
        .text => |tx| if (std.mem.eql(u8, tx.str, "studio")) {
            value = node.rect;
        },
        else => {},
    };
    try std.testing.expect(value.?.x + value.?.w > 360);
    try t.clickText("Repository");
    try std.testing.expectEqual(@as(usize, 1), x.opened);
    t.key(.enter);
    try std.testing.expectEqual(@as(usize, 2), x.opened);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const e = find(try elements(&t, arena.allocator()), "Repository").?;
    try std.testing.expectEqual(ui.access.Role.button, e.role);
    x.link_disabled = true;
    t.settle(1);
    try t.clickText("Repository");
    t.key(.enter);
    try std.testing.expectEqual(@as(usize, 2), x.opened);
}

test "a note sits under its section, and the rows after it start a new card" {
    var x: Settings = .{ .opts = .{ .grouped = true } };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const note = t.findText("Settings apply at once.").?;
    const surface = kit.tokens(&t.ctx).surface;
    var cards: usize = 0;
    for (t.ctx.nodes.items) |node| {
        const bg = node.style.background orelse continue;
        if (!std.meta.eql(bg, surface)) continue;
        cards += 1;
        // Outside every card.
        const r = t.ctx.rects.get(node.id).?;
        try std.testing.expect(note.y >= r.y + r.h or note.y + note.h <= r.y);
    }
    // General's and Danger zone's: Advanced is folded.
    try std.testing.expectEqual(@as(usize, 2), cards);
}

test "a danger heading's title and card are in the danger color" {
    var x: Settings = .{ .opts = .{ .grouped = true } };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const danger = kit.tokens(&t.ctx).danger;
    var title_tinted = false;
    var card_tinted = false;
    for (t.ctx.nodes.items) |node| {
        switch (node.content) {
            .text => |tx| if (std.mem.eql(u8, tx.str, "Danger zone")) {
                title_tinted = std.meta.eql(tx.style.color.?, danger);
            },
            else => {},
        }
        if (node.style.border) |b| if (std.meta.eql(b, danger.alpha(0.5))) {
            card_tinted = true;
        };
    }
    try std.testing.expect(title_tinted and card_tinted);
}

test "with control_align = .end, values and controls sit at the row's end" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(400);
            defer root.end();
            var f = form(c, .{ .control_align = .end });
            f.property("Host", "studio.local", .{});
            f.property("About", "A value long enough to wrap onto more lines than one, at the row's end", .{});
            {
                const r = f.row("Keep", .{ .hint = "How many." });
                ui.text(c, "control", .{});
                r.end();
            }
            f.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 420, .height = 200 });
    defer t.deinit();
    t.settle(1);
    for (0..2) |_| t.frame();
    for ([_][]const u8{ "studio.local", "control", "How many." }) |s| {
        // Drawn from where it ends, not from the column: its box no wider
        // than its words.
        const r = t.findText(s).?;
        try std.testing.expectApproxEqAbs(@as(f32, 400), r.x + r.w, 1);
        try std.testing.expect(r.x > 250);
    }
    // A long one wraps within the room after the labels, once the row has
    // been laid out.
    for (t.ctx.nodes.items) |node| switch (node.content) {
        .text => |tx| if (std.mem.startsWith(u8, tx.str, "A value long")) {
            const r = t.ctx.rects.get(node.id).?;
            try std.testing.expect(r.x > t.findText("About").?.x + t.findText("About").?.w);
            try std.testing.expect(r.x + r.w <= 400.5 and r.h > t.findText("About").?.h * 1.5);
        },
        else => {},
    };
}

test "the rows after a note start without a line over them" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(400);
            defer root.end();
            var f = form(c, .{ .grouped = true, .row_lines = true });
            f.property("A", "a", .{});
            f.note("About A.");
            f.property("B", "b", .{});
            f.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 420, .height = 200 });
    defer t.deinit();
    t.settle(1);
    const border = kit.tokens(&t.ctx).border;
    for (t.ctx.nodes.items) |node| {
        const bg = node.style.background orelse continue;
        try std.testing.expect(!(std.meta.eql(bg, border) and t.ctx.rects.get(node.id).?.h == 1));
    }
}
