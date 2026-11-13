//! The form's tests: the label column, hints and errors, the rows' height,
//! and what a screen reader hears.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const form_mod = @import("form.zig");
const form = form_mod.form;

/// A view that draws a form with `opts`, by `draw`.
fn Fixture(comptime draw: fn (f: *form_mod.Form, c: *ui.Context) void) type {
    return struct {
        opts: form_mod.Options = .{},
        fn view(x: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(400);
            defer root.end();
            var f = form(c, x.opts);
            draw(&f, c);
            f.end();
        }
    };
}

fn start(x: anytype, t: *ui.Tester) !void {
    try t.init(std.testing.allocator, .init(x, @TypeOf(x.*).view), .{ .width = 420, .height = 400 });
    t.settle(1);
}

/// The text drawn that starts with `s`.
fn startingWith(t: *ui.Tester, s: []const u8) ?ui.Rect {
    for (t.ctx.nodes.items) |n| switch (n.content) {
        .text => |tx| if (std.mem.startsWith(u8, tx.str, s)) return n.rect,
        else => {},
    };
    return null;
}

fn twoProperties(f: *form_mod.Form, _: *ui.Context) void {
    f.property("Host", "studio.local", .{});
    f.property("Firmware version", "2.3.093", .{});
}

test "the labels' column is as wide as the widest label, and what follows lines up" {
    var x: Fixture(twoProperties) = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const label = t.findText("Firmware version").?;
    const host = t.findText("studio.local").?;
    const version = t.findText("2.3.093").?;
    try std.testing.expectEqual(host.x, version.x);
    // The values start the gap after the widest label, not further.
    try std.testing.expectApproxEqAbs(label.x + label.w + 12, version.x, 1);
}

test "a form's label_width sets its column, and a label longer than the widest is cut short" {
    var x: Fixture(twoProperties) = .{ .opts = .{ .label_width = 150 } };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    try std.testing.expectApproxEqAbs(t.findText("Host").?.x + 150 + 12, t.findText("studio.local").?.x, 0.5);
    x.opts = .{ .max_label_width = 60 };
    // A frame to measure the labels, and one to lay them out.
    for (0..2) |_| t.frame();
    // Cut short, the text drawn is what fits.
    const label = startingWith(&t, "Firm").?;
    try std.testing.expect(!t.hasText("Firmware version"));
    try std.testing.expect(label.w <= 60);
    try std.testing.expectApproxEqAbs(label.x + 60 + 12, t.findText("2.3.093").?.x, 0.5);
}

test "labels can sit at the column's end" {
    var x: Fixture(twoProperties) = .{ .opts = .{ .label_align = .end } };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const host = t.findText("Host").?;
    const label = t.findText("Firmware version").?;
    try std.testing.expectApproxEqAbs(host.x + host.w, label.x + label.w, 0.5);
}

test "rows are at least the kit's height for the form's size" {
    var x: Fixture(twoProperties) = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const step = t.findText("2.3.093").?.y - t.findText("studio.local").?.y;
    try std.testing.expectApproxEqAbs(kit.Size.md.height() + 4, step, 0.5);
    x.opts = .{ .size = .xs, .row_lines = true };
    t.settle(1);
    // A line between them, a point high, with the rows' gap above and
    // below it.
    const lined = t.findText("2.3.093").?.y - t.findText("studio.local").?.y;
    try std.testing.expectApproxEqAbs(kit.Size.xs.height() + 4 + 1 + 4, lined, 0.5);
}

fn hinted(f: *form_mod.Form, _: *ui.Context) void {
    f.property("Host", "studio.local", .{});
    {
        const r = f.row("Keep latest", .{ .hint = "Snapshots to keep.", .required = true });
        ui.text(r.c, "control", .{});
        r.end();
    }
    {
        const r = f.row("Name", .{ .hint = "A hint.", .err = "Can't be empty." });
        ui.text(r.c, "field", .{});
        r.end();
    }
}

test "a row puts its hint under the control, an error in its place, and marks a required label" {
    var x: Fixture(hinted) = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const control = t.findText("control").?;
    const hint = t.findText("Snapshots to keep.").?;
    try std.testing.expect(hint.y >= control.y + control.h);
    try std.testing.expectApproxEqAbs(control.x, hint.x, 0.5);
    try std.testing.expectEqual(control.x, t.findText("studio.local").?.x);
    try std.testing.expect(t.hasText("Can't be empty.") and !t.hasText("A hint."));
    // The mark is after the label, within the column.
    const star = t.findText("*").?;
    try std.testing.expect(star.x > t.findText("Keep latest").?.x);
    try std.testing.expect(star.x + star.w <= control.x - 12 + 0.5);
}

fn headed(f: *form_mod.Form, _: *ui.Context) void {
    f.heading("Network", .{});
    f.property("Host", "studio.local", .{ .mono = true });
    {
        const r = f.row("Port", .{});
        ui.text(r.c, "51515", .{});
        r.end();
    }
}

test "a screen reader hears a property as one, and a heading as one" {
    var x: Fixture(headed) = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    var heading = false;
    var property = false;
    for (list.items) |e| {
        if (std.mem.eql(u8, e.label, "Network")) heading = e.header;
        if (std.mem.eql(u8, e.label, "Host")) property = std.mem.eql(u8, e.value, "studio.local");
        // The value isn't heard again on its own.
        try std.testing.expect(!std.mem.eql(u8, e.label, "studio.local"));
    }
    try std.testing.expect(heading and property);
}

test "a form keeps its column when controls in its rows make many states" {
    // In the second frame, each row makes more new state than nanoui's
    // store has room for, so it grows, and moves, while the form is open.
    const T = struct {
        frames: usize = 0,
        fn view(x: *@This(), c: *ui.Context) void {
            x.frames += 1;
            var f = form(c, .{});
            f.property("A longer label", "beside it", .{});
            for (0..3) |i| {
                const r = f.row(c.print("Row {d}", .{i}), .{});
                if (x.frames == 2) for (0..20_000) |j| {
                    ui.key(c, c.print("churn-{d}-{d}", .{ i, j }));
                    _ = c.state(struct { x: u8 = 0 }, "churn");
                    c.next_key = null;
                };
                ui.text(c, c.print("value {d}", .{i}), .{});
                r.end();
            }
            f.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 420, .height = 300 });
    defer t.deinit();
    t.settle(1);
    t.frame();
    t.frame();
    const label = t.findText("A longer label").?;
    try std.testing.expectApproxEqAbs(label.x + label.w + 12, t.findText("value 0").?.x, 1);
}

fn tall(f: *form_mod.Form, c: *ui.Context) void {
    {
        const r = f.row("Centered", .{});
        ui.div(c).w(40).h(80).end();
        r.end();
    }
    {
        const r = f.row("At the top", .{ .label_top = true });
        ui.div(c).w(40).h(80).end();
        r.end();
    }
}

test "a label sits centered by its control, or at the top beside a tall one" {
    var x: Fixture(tall) = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const centered = t.findText("Centered").?;
    const top = t.findText("At the top").?;
    // Rows 80 high with a gap of 4: the first label at its row's middle,
    // the second at its row's top.
    try std.testing.expectApproxEqAbs(@as(f32, 40), centered.y + centered.h / 2, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 84), top.y, 0.5);
}

fn twoSections(f: *form_mod.Form, _: *ui.Context) void {
    f.heading("One", .{});
    f.property("A", "a", .{});
    f.property("B", "b", .{});
    f.heading("Two", .{});
    f.property("C", "c", .{});
}

/// The lines a form drew between its rows.
fn lines(t: *ui.Tester) usize {
    const border = kit.tokens(&t.ctx).border;
    var n: usize = 0;
    for (t.ctx.nodes.items) |node| {
        const bg = node.style.background orelse continue;
        if (std.meta.eql(bg, border) and t.ctx.rects.get(node.id).?.h == 1) n += 1;
    }
    return n;
}

test "lines go between rows, not under a heading" {
    var x: Fixture(twoSections) = .{ .opts = .{ .row_lines = true } };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    try std.testing.expectEqual(@as(usize, 1), lines(&t));
    x.opts = .{};
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 0), lines(&t));
}

/// The elements a screen reader hears.
fn elements(t: *ui.Tester, arena: std.mem.Allocator) ![]const ui.access.Element {
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena, &list);
    return list.items;
}

const Toggles = struct {
    on: bool = true,
    width: f32 = 400,
    /// The toggle's own name.
    name: []const u8 = "",
    fn view(x: *Toggles, c: *ui.Context) void {
        const root = ui.div(c).column().w(x.width);
        defer root.end();
        var f = form(c, .{ .stack_below = 360 });
        const r = f.row("Notify", .{ .required = true, .info = "When a backup ends." });
        _ = ui.toggle(c, x.name, &x.on);
        r.end();
        f.end();
    }
};

test "a row's label names its control to a screen reader, saying it is required in words, not by its mark" {
    var x: Toggles = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const list = try elements(&t, arena.allocator());
    try std.testing.expectEqual(@as(usize, 1), list.len);
    try std.testing.expectEqualStrings("Notify, required", list[0].label);
}

test "a row names its control with its ⓘ as the hint, its label beside it or above it" {
    var x: Toggles = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    for ([_]f32{ 400, 300 }) |width| {
        x.width = width;
        // A frame to lay out the width, and one to stack (or not) for it.
        for (0..2) |_| t.frame();
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const list = try elements(&t, arena.allocator());
        try std.testing.expectEqual(@as(usize, 1), list.len);
        try std.testing.expectEqual(ui.access.Role.switch_toggle, list[0].role);
        try std.testing.expectEqualStrings("Notify, required", list[0].label);
        try std.testing.expectEqualStrings("When a backup ends.", list[0].hint);
        // Beside the toggle at 400, above it at 300.
        const label = t.findText("Notify").?;
        if (width < 360) {
            try std.testing.expect(label.y + label.h <= list[0].rect.y);
        } else try std.testing.expect(list[0].rect.x > label.x + label.w);
    }
}

test "a control with a name of its own keeps it, the row's label read before it" {
    var x: Toggles = .{ .name = "Email" };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const list = try elements(&t, arena.allocator());
    try std.testing.expectEqual(@as(usize, 2), list.len);
    try std.testing.expectEqualStrings("Notify, required", list[0].label);
    try std.testing.expectEqualStrings("Email", list[1].label);
}

test "an ⓘ after a label says more in a tooltip, and the column makes room for it" {
    var x: Toggles = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    // A frame to measure the label, and one to lay out its column.
    for (0..2) |_| t.frame();
    try std.testing.expect(!t.hasText("When a backup ends."));
    var icon: ?ui.Rect = null;
    for (t.ctx.nodes.items) |node| switch (node.content) {
        .icon => icon = t.ctx.rects.get(node.id),
        else => {},
    };
    const star = t.findText("*").?;
    // After the mark, inside the column: the toggle starts the gap after it.
    try std.testing.expect(icon.?.x > star.x);
    // The toggle: the interactive box after the ⓘ's, which is one too.
    var toggle_x: f32 = std.math.inf(f32);
    for (t.ctx.nodes.items) |node| if (node.interactive) {
        const at = t.ctx.rects.get(node.id).?.x;
        if (at > icon.?.x + 1) toggle_x = @min(toggle_x, at);
    };
    try std.testing.expect(icon.?.x + icon.?.w <= toggle_x - 12 + 0.5);
    // With room for the label whole.
    try std.testing.expect(t.hasText("Notify"));
    t.moveTo(icon.?.x + icon.?.w / 2, icon.?.y + icon.?.h / 2);
    t.settle(2);
    try std.testing.expect(t.hasText("When a backup ends."));
}

fn dimmed(f: *form_mod.Form, c: *ui.Context) void {
    const r = f.row("Every", .{ .hint = "How often.", .disabled = true });
    ui.text(c, "Day", .{});
    r.end();
}

test "a disabled row dims its label and its hint" {
    var x: Fixture(dimmed) = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    var dim: usize = 0;
    for (t.ctx.nodes.items) |node| {
        if (node.style.opacity == 0.45) dim += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), dim);
}

const long_path = "/Volumes/Backup/kopia/repositories/studio/snapshots/latest";

fn values(f: *form_mod.Form, _: *ui.Context) void {
    f.property("Host", "studio.local", .{ .selectable = true, .wrap = false });
    f.property("Path", long_path, .{ .wrap = false });
}

test "a property's value can be selected, or kept to a line with the whole in a tooltip" {
    var x: Fixture(values) = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    var selectable: usize = 0;
    for (t.ctx.nodes.items) |node| {
        if (node.style.selectable) selectable += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), selectable);
    // Cut short on its line, and whole under the pointer.
    try std.testing.expect(!t.hasText(long_path));
    const path = startingWith(&t, "/Volumes").?;
    try std.testing.expectEqual(t.findText("studio.local").?.h, path.h);
    t.moveTo(path.x + 20, path.y + path.h / 2);
    t.settle(2);
    try std.testing.expect(t.hasText(long_path));
    // A value that fits says nothing more.
    const host = t.findText("studio.local").?;
    t.moveTo(host.x + 5, host.y + host.h / 2);
    t.settle(2);
    try std.testing.expect(!t.hasText(long_path));
    var tips: usize = 0;
    for (t.ctx.nodes.items) |node| switch (node.content) {
        .text => |tx| if (std.mem.eql(u8, tx.str, "studio.local")) {
            tips += 1;
        },
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 1), tips);
}

const Narrow = struct {
    width: f32 = 300,
    stacked: bool = false,
    fn view(x: *Narrow, c: *ui.Context) void {
        const root = ui.div(c).column().w(x.width);
        defer root.end();
        var f = form(c, .{ .stack_below = 360 });
        x.stacked = f.stacked;
        {
            const r = f.row("Keep latest", .{ .hint = "Snapshots to keep." });
            ui.text(c, "control", .{});
            r.end();
        }
        f.property("Host", "studio.local", .{});
        f.end();
    }
};

test "narrower than stack_below, the labels go above what they name" {
    var x: Narrow = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Narrow.view), .{ .width = 600, .height = 300 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(x.stacked);
    const label = t.findText("Keep latest").?;
    const control = t.findText("control").?;
    try std.testing.expectEqual(label.x, control.x);
    try std.testing.expect(control.y >= label.y + label.h);
    try std.testing.expectEqual(control.x, t.findText("Snapshots to keep.").?.x);
    try std.testing.expect(t.findText("studio.local").?.y > t.findText("Host").?.y);
    x.width = 500;
    for (0..3) |_| t.frame();
    try std.testing.expect(!x.stacked);
    try std.testing.expect(t.findText("control").?.x > t.findText("Keep latest").?.x);
    try std.testing.expectEqual(t.findText("Keep latest").?.y, t.findText("control").?.y);
}

const LongLabel = struct {
    on: bool = true,
    fn view(x: *LongLabel, c: *ui.Context) void {
        const root = ui.div(c).column().w(400);
        defer root.end();
        var f = form(c, .{ .max_label_width = 80 });
        const r = f.row("Notify when a backup ends", .{ .required = true });
        _ = ui.toggle(c, "", &x.on);
        r.end();
        f.end();
    }
};

test "a label cut short still names its control whole" {
    var x: LongLabel = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    for (0..2) |_| t.frame();
    try std.testing.expect(!t.hasText("Notify when a backup ends"));
    // The mark still shows, at the column's end.
    try std.testing.expect(t.hasText("*"));
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const list = try elements(&t, arena.allocator());
    try std.testing.expectEqual(@as(usize, 1), list.len);
    // Required, as its name says.
    try std.testing.expectEqualStrings("Notify when a backup ends, required", list[0].label);
}

fn wrapping(f: *form_mod.Form, _: *ui.Context) void {
    f.property("About", "A value long enough to wrap onto a second line and a third, in a form four hundred points wide", .{});
}

test "a property's label sits beside its value's first line" {
    var x: Fixture(wrapping) = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const label = t.findText("About").?;
    var value: ?ui.Rect = null;
    for (t.ctx.nodes.items) |node| switch (node.content) {
        .text => |tx| if (std.mem.startsWith(u8, tx.str, "A value")) {
            value = node.rect;
        },
        else => {},
    };
    try std.testing.expect(value.?.h > 1.5 * label.h);
    try std.testing.expectApproxEqAbs(label.y, value.?.y, 1);
}

const Changing = struct {
    long: bool = false,
    fn view(x: *Changing, c: *ui.Context) void {
        const row = ui.div(c).row().w(800).gap(20);
        defer row.end();
        for ([_][]const u8{ "left", "right" }, 0..) |side, i| {
            ui.keyInt(c, i);
            const col = ui.div(c).column().w(380);
            defer col.end();
            var f = form(c, .{ .scale = if (i == 1) 2 else 1 });
            f.property("A", c.print("{s} a", .{side}), .{});
            f.property(if (x.long and i == 0) "A longer label" else "B", c.print("{s} b", .{side}), .{});
            f.end();
        }
    }
};

test "two forms keep their own columns, which follow their labels as they change" {
    var x: Changing = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Changing.view), .{ .width = 820, .height = 200 });
    defer t.deinit();
    t.settle(1);
    for (0..2) |_| t.frame();
    const narrow = t.findText("left a").?.x - t.findText("A").?.x;
    x.long = true;
    for (0..2) |_| t.frame();
    const label = t.findText("A longer label").?;
    try std.testing.expectApproxEqAbs(label.x + label.w + 12, t.findText("left a").?.x, 1);
    // The right form's column didn't follow the left's; scaled, its gap
    // is twice as wide.
    const right_b = t.findText("right b").?;
    const b = t.findText("B").?;
    try std.testing.expectApproxEqAbs(b.x + b.w + 24, right_b.x, 1);
    x.long = false;
    for (0..2) |_| t.frame();
    try std.testing.expectApproxEqAbs(narrow, t.findText("left a").?.x - t.findText("A").?.x, 0.5);
}

fn grouped(f: *form_mod.Form, _: *ui.Context) void {
    f.property("Before", "any heading", .{});
    f.heading("One", .{});
    f.property("A", "a", .{});
    f.property("B", "b", .{});
    f.heading("Two", .{});
    f.property("C", "c", .{});
}

/// The cards a grouped form drew: boxes in the theme's surface.
fn cards(t: *ui.Tester) [8]ui.Rect {
    const surface = kit.tokens(&t.ctx).surface;
    var out: [8]ui.Rect = @splat(.{});
    var n: usize = 0;
    for (t.ctx.nodes.items) |node| {
        const bg = node.style.background orelse continue;
        if (std.meta.eql(bg, surface) and n < out.len) {
            out[n] = t.ctx.rects.get(node.id).?;
            n += 1;
        }
    }
    return out;
}

fn inside(r: ui.Rect, outer: ui.Rect) bool {
    return r.x >= outer.x and r.y >= outer.y and r.x + r.w <= outer.x + outer.w and r.y + r.h <= outer.y + outer.h;
}

test "grouped, each heading's rows are in a card under it, and rows before any heading in one too" {
    var x: Fixture(grouped) = .{ .opts = .{ .grouped = true, .row_lines = true } };
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    for (0..2) |_| t.frame();
    const box = cards(&t);
    try std.testing.expect(box[2].w > 0 and box[3].w == 0);
    try std.testing.expect(inside(t.findText("any heading").?, box[0]));
    try std.testing.expect(inside(t.findText("a").?, box[1]) and inside(t.findText("b").?, box[1]));
    try std.testing.expect(inside(t.findText("c").?, box[2]));
    // The headings are above their cards, in line with the labels in them.
    const one = t.findText("One").?;
    try std.testing.expect(one.y + one.h <= box[1].y and one.y >= box[0].y + box[0].h);
    try std.testing.expectEqual(t.findText("A").?.x, one.x);
    // A line between A and B only: none under a heading, none across cards.
    try std.testing.expectEqual(@as(usize, 1), lines(&t));
    // The column is still measured, and kept, with its rows in cards.
    const label = t.findText("Before").?;
    try std.testing.expectApproxEqAbs(label.x + label.w + 12, t.findText("any heading").?.x, 1);
}

fn described(f: *form_mod.Form, _: *ui.Context) void {
    f.heading("Backups", .{ .description = "How often, and how many to keep." });
    f.property("Every", "Day", .{});
}

test "a heading's description sits under its title, and a screen reader hears both" {
    var x: Fixture(described) = .{};
    var t: ui.Tester = undefined;
    try start(&x, &t);
    defer t.deinit();
    const title = t.findText("Backups").?;
    const description = t.findText("How often, and how many to keep.").?;
    try std.testing.expect(description.y >= title.y + title.h);
    try std.testing.expect(t.findText("Every").?.y > description.y);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const list = try elements(&t, arena.allocator());
    try std.testing.expect(list[0].header and std.mem.eql(u8, list[0].label, "Backups"));
    try std.testing.expectEqualStrings("How often, and how many to keep.", list[1].label);
    try std.testing.expect(!list[1].header);
}

test "a required row says so to a screen reader, in the caller's words" {
    const T = struct {
        name: ui.TextBuffer = .{},
        fn view(x: *@This(), c: *ui.Context) void {
            var f = form(c, .{ .required_text = "obligatoire" });
            const r = f.row("Nom", .{ .required = true });
            _ = ui.textField(c, &x.name, .{});
            r.end();
            f.end();
        }
    };
    var x: T = .{};
    defer x.name.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 500, .height = 200 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    var found = false;
    for (list.items) |e| if (std.mem.eql(u8, e.label, "Nom, obligatoire")) {
        found = true;
        try std.testing.expectEqual(ui.access.Role.text_field, e.role);
    };
    try std.testing.expect(found);
}
