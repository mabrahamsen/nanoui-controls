//! A legend: what a chart's colors stand for, a swatch and a label each,
//! side by side in a wide window and one under another in a narrow one.
//!
//!     var l = controls.legend(c, .{ .row_from = 560 });
//!     l.item(cyan, "App 12.0 GB");
//!     l.item(violet, "Wired 3.0 GB");
//!     if (l.wide) ui.spacer(c);
//!     ui.text(c, "Free 7.0 GB", .{});
//!     l.end();
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;

pub const Options = struct {
    /// The items sit in a row in windows at least this wide (in points
    /// before `scale`) and in a column in narrower ones; 0 keeps them in a
    /// row.
    row_from: f32 = 0,
    /// Between the items in a row, and in a column.
    gap: f32 = 14,
    column_gap: f32 = 4,
    /// The labels' size, as the kit's; the swatches go with it.
    size: kit.Size = .xs,
    /// Labels in the monospaced font, so figures line up.
    mono: bool = false,
    /// The labels' color; null takes the theme's muted text.
    color: ?ui.Color = null,
    /// Multiplies the legend's lengths but not its text, as `bars`.
    scale: f32 = 1,
};

/// Opens a legend: add items with `item` or `itemOpen`, then `end`.
pub fn legend(c: *ui.Context, opts: Options) Legend {
    const k = opts.scale;
    const wide = c.size.w / k >= opts.row_from;
    const box = if (wide) ui.div(c).row().wFull().itemsCenter().gap(opts.gap * k) else ui.div(c).column().wFull().gap(opts.column_gap * k);
    return .{ .wide = wide, .c = c, .box = box, .opts = opts };
}

pub const Legend = struct {
    /// The items are side by side: a caller can push what follows them to
    /// the end with a spacer.
    wide: bool,

    // The rest is the legend's own.
    c: *ui.Context,
    box: ui.Div,
    opts: Options,

    /// Adds a swatch of `color` and `label`.
    pub fn item(l: *const Legend, color: ui.Color, label: []const u8) void {
        l.itemOpen(color, label).end();
    }

    /// As `item`, left open after the label for more, such as a peak;
    /// end it.
    pub fn itemOpen(l: *const Legend, color: ui.Color, label: []const u8) ui.Div {
        const k = l.opts.scale;
        const size = l.opts.size.text();
        const it = ui.div(l.c).row().itemsCenter().gap(@round(size * 0.55) * k);
        const sw = @round(size * 0.72) * k;
        ui.div(l.c).w(sw).h(sw).rounded(sw / 4).bg(color).end();
        ui.text(l.c, label, .{ .size = size, .mono = l.opts.mono, .color = l.opts.color orelse kit.tokens(l.c).muted });
        return it;
    }

    /// Ends the legend.
    pub fn end(l: *const Legend) void {
        l.box.end();
    }
};

const Color = ui.Color;

const Memory = struct {
    row_from: f32 = 560,
    wide: bool = false,
    fn view(m: *Memory, c: *ui.Context) void {
        var l = legend(c, .{ .row_from = m.row_from });
        m.wide = l.wide;
        l.item(.hex(0x22d3ee), "App");
        const peak = l.itemOpen(.hex(0xa78bfa), "Wired");
        ui.text(c, "▲4.2", .{ .size = 10 });
        peak.end();
        l.end();
    }
};

test "a legend's items sit in a row when the window is wide enough" {
    var m: Memory = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&m, Memory.view), .{ .width = 600, .height = 100 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(m.wide);
    const app = t.findText("App").?;
    const wired = t.findText("Wired").?;
    try std.testing.expectEqual(app.y, wired.y);
    try std.testing.expect(wired.x > app.x);
    // What is added to an open item follows its label.
    try std.testing.expect(t.findText("▲4.2").?.x > wired.x);
}

test "a legend's items stack in a narrow window" {
    var m: Memory = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&m, Memory.view), .{ .width = 400, .height = 100 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(!m.wide);
    const app = t.findText("App").?;
    const wired = t.findText("Wired").?;
    try std.testing.expectEqual(app.x, wired.x);
    try std.testing.expect(wired.y > app.y);
}

test "a legend with no width to switch at stays in a row" {
    var m: Memory = .{ .row_from = 0 };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&m, Memory.view), .{ .width = 200, .height = 100 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(m.wide);
}
