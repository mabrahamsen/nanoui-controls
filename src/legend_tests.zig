//! The legend's tests of a fitted width, and a swatch on its own.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const chart = @import("chart.zig");
const shared = @import("chart_tests.zig");
const heights = shared.heights;
const red = shared.red;
const blue = shared.blue;
const legend_mod = @import("legend.zig");

/// A fitted legend beside a title, in a box `width` wide.
const Fitted = struct {
    width: f32 = 400,
    box: u32 = 0,

    fn view(x: *Fitted, c: *ui.Context) void {
        const root = ui.div(c).column().w(x.width);
        defer root.end();
        var l = legend_mod.legend(c, .{ .width = .fit });
        x.box = l.box.index;
        l.item(blue, "Read");
        l.item(red, "Write");
        l.item(blue, "Other things");
        l.end();
        legend_mod.swatch(c, red, .{ .shape = .dot });
        legend_mod.swatch(c, red, .{ .shape = .line });
    }
};

test "a fitted legend is as wide as its items, and still wraps where its parent ends" {
    var x: Fitted = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Fitted.view), .{ .width = 500, .height = 300 });
    defer t.deinit();
    t.settle(1);
    const r = t.ctx.rects.get(t.ctx.node(x.box).id).?;
    try std.testing.expect(r.w < 300);
    try std.testing.expectApproxEqAbs(t.findText("Read").?.y, t.findText("Other things").?.y, 0.5);
    // As a resize would, the width changes and frames follow.
    x.width = 120;
    t.frame();
    t.settle(1);
    try std.testing.expect(t.findText("Other things").?.y > t.findText("Read").?.y);
}

test "a swatch on its own is a dot or a line, as a legend draws one" {
    var x: Fitted = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Fitted.view), .{ .width = 500, .height = 300 });
    defer t.deinit();
    t.settle(1);
    var reds: [4]f32 = undefined;
    const h = heights(&t, red, &reds);
    // The legend's square, then the dot as tall, then the line thinner.
    try std.testing.expectEqual(@as(usize, 3), h.len);
    try std.testing.expectEqual(h[0], h[1]);
    try std.testing.expect(h[2] < h[1]);
}
