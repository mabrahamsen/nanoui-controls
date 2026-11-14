//! The shape's tests: it scales the corners and glows the controls choose
//! themselves, and leaves a caller's as given.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const shape = @import("shape.zig");
const segmented = @import("segmented.zig").segmented;
const panel = @import("panel.zig").panel;
const pill_mod = @import("pill.zig");
const input_box = @import("input_box.zig");
const Choice = @import("choices.zig").Choice;

const Boxes = struct {
    index: usize = 0,
    fn view(x: *Boxes, c: *ui.Context) void {
        const root = ui.div(c).column().w(300).gap(8);
        defer root.end();
        _ = segmented(c, &[_]Choice{ .{ .label = "Day" }, .{ .label = "Week" } }, &x.index, .{});
        panel(c, .{}).end();
        panel(c, .{ .card = .{ .radius = 12 } }).end();
    }
};

/// Whether some box was drawn with corners of `r`.
fn hasRadius(t: *ui.Tester, r: f32) bool {
    for (t.ctx.nodes.items) |n| if (@abs(n.style.radius - r) < 0.01) return true;
    return false;
}

test "a shape scales the corners the controls choose themselves, and leaves the caller's as given" {
    defer shape.setShape(.{});
    var x: Boxes = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Boxes.view), .{ .width = 400, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // The segmented group and a segment from the kit's radius of 8, a
    // panel at it, and the caller's 12.
    for ([_]f32{ 9, 7, 8, 12 }) |r| try std.testing.expect(hasRadius(&t, r));
    shape.setShape(.{ .corner = 0.5 });
    t.settle(1);
    for ([_]f32{ 4.5, 3.5, 4, 12 }) |r| try std.testing.expect(hasRadius(&t, r));
    for ([_]f32{ 9, 7, 8 }) |r| try std.testing.expect(!hasRadius(&t, r));
}

const Dots = struct {
    lead: pill_mod.Lead = .{ .dot = .{} },
    fn view(x: *Dots, c: *ui.Context) void {
        pill_mod.pill(c, "LIVE", .{ .lead = x.lead });
    }
};

/// The opacity of the first glow drawn, or 0.
fn glowOf(t: *ui.Tester) f32 {
    for (t.ctx.nodes.items) |n| if (n.style.shadow) |s| return s.color.a;
    return 0;
}

test "a pill's dot glows at 0.8 in the shape, at its own glow as given, and plain at 0" {
    defer shape.setShape(.{});
    var x: Dots = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Dots.view), .{ .width = 200, .height = 60 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), glowOf(&t), 0.001);
    shape.setShape(.{ .glow = 0.5 });
    t.settle(1);
    try std.testing.expectApproxEqAbs(@as(f32, 0.4), glowOf(&t), 0.001);
    x.lead = .{ .dot = .{ .glow = 0.3 } };
    t.settle(1);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), glowOf(&t), 0.001);
    x.lead = .{ .dot = .{ .glow = 0 } };
    t.settle(1);
    try std.testing.expectEqual(@as(f32, 0), glowOf(&t));
}

const Field = struct {
    buffer: ui.TextBuffer = .{},
    glow: ?f32 = null,
    fn view(x: *Field, c: *ui.Context) void {
        const root = ui.div(c).column().w(300).p(10);
        defer root.end();
        _ = input_box.inputBox(c, &x.buffer, .{ .placeholder = "Search", .glow = x.glow });
    }
};

test "a field's glow takes the shape by default, and the caller's as given" {
    defer shape.setShape(.{});
    var x: Field = .{};
    defer x.buffer.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Field.view), .{ .width = 400, .height = 100 });
    defer t.deinit();
    t.settle(1);
    try t.clickText("Search");
    t.settle(1);
    try std.testing.expectApproxEqAbs(@as(f32, 0.22), glowOf(&t), 0.001);
    shape.setShape(.{ .glow = 0 });
    t.settle(1);
    try std.testing.expectEqual(@as(f32, 0), glowOf(&t));
    x.glow = 0.3;
    t.settle(1);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), glowOf(&t), 0.001);
}
