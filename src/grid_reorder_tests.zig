//! The grid's tests of where the line shows that a dragged title would go:
//! in place, scrolled sideways, and past a frozen column.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const g_mod = @import("grid.zig");
const grid = g_mod.grid;
const Column = g_mod.Column;

const Wide = struct {
    order: [4]usize = .{ 0, 1, 2, 3 },
    scroll: bool = false,
    freeze: bool = false,
    const columns = [_]Column{
        .{ .title = "Alpha", .width = 120 },
        .{ .title = "Beta", .width = 120 },
        .{ .title = "Gamma", .width = 120 },
        .{ .title = "Delta", .width = 120 },
    };
    fn view(w: *Wide, c: *ui.Context) void {
        var g = grid(c, &columns, .{ .count = 2, .order = &w.order, .scroll_x = w.scroll, .freeze_first = w.freeze });
        while (g.next()) |_| {
            for (0..4) |_| {
                g.cell();
                ui.text(c, "x", .{});
            }
        }
        g.end();
    }
};

/// Holds a drag of `from`'s title at `x`, and returns the middle of the
/// line drawn, or null for none; the drag goes on.
fn lineWhileDragging(t: *ui.Tester, from: []const u8, x: f32) ?f32 {
    const r = t.findText(from).?;
    const y = r.y + r.h / 2;
    t.down(r.x + 4, y);
    t.move(x, y);
    t.move(x + 1, y);
    const primary = kit.tokens(&t.ctx).primary;
    var mid: ?f32 = null;
    for (t.ctx.nodes.items) |n| if (n.style.background) |bg| if (std.meta.eql(bg, primary) and n.rect.w <= 2.5) {
        mid = n.rect.x + n.rect.w / 2;
    };
    return mid;
}

test "the drop line sits in the gap before the column the title would go before" {
    var w: Wide = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&w, Wide.view), .{ .width = 600, .height = 200 });
    defer t.deinit();
    t.settle(1);
    const beta = t.findText("Beta").?;
    const mid = lineWhileDragging(&t, "Delta", beta.x + 4).?;
    // The gap is 10 points: its middle is 5 before the title.
    try std.testing.expectApproxEqAbs(beta.x - 5, mid, 1);
    t.up();
}

test "scrolled sideways, the drop line follows the columns" {
    var w: Wide = .{ .scroll = true };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&w, Wide.view), .{ .width = 300, .height = 200 });
    defer t.deinit();
    t.settle(1);
    t.hscroll(100, 60, -100);
    t.settle(1);
    const gamma = t.findText("Gamma").?;
    const mid = lineWhileDragging(&t, "Beta", gamma.x + gamma.w + 30).?;
    // Past Gamma's middle: before Delta, a gap after Gamma's column.
    try std.testing.expectApproxEqAbs(gamma.x + 120 + 5, mid, 1);
    t.up();
}

test "past a frozen column, the drop line shows where the scrolled columns start" {
    var w: Wide = .{ .scroll = true, .freeze = true };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&w, Wide.view), .{ .width = 300, .height = 200 });
    defer t.deinit();
    t.settle(1);
    t.hscroll(150, 60, -60);
    t.settle(1);
    const alpha = t.findText("Alpha").?;
    // Beta is partly under Alpha; the drop goes before it, at the edge of
    // the scrolled columns, not under the frozen one.
    const mid = lineWhileDragging(&t, "Delta", alpha.x + 122).?;
    try std.testing.expectApproxEqAbs(alpha.x + 120 + 5, mid, 1);
    t.up();
}
