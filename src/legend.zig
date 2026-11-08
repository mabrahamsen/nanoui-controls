//! A legend: what a chart's colors stand for, a swatch and a label each,
//! side by side, running on to a new line where the legend's width ends,
//! as text wraps.
//!
//!     var l = controls.legend(c, .{});
//!     l.item(t.primary, "App 12.0 GB");
//!     l.itemDetail(t.warning, "Wired 3.0 GB", "▲4.2");
//!     l.trailing("Free 7.0 GB");
//!     l.end();
//!
//! With `width = .fit`, it is only as wide as its items, for a legend
//! beside a chart's title. `swatch` (exported as `legendSwatch`) draws a legend's swatch on
//! its own.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const chart = @import("chart.zig");

pub const Options = struct {
    /// Between the items on a line, in points before `scale`.
    gap: f32 = 14,
    /// Between the lines, in points before `scale`.
    row_gap: f32 = 4,
    /// The labels' size, as the kit's; the swatches go with it.
    size: kit.Size = .xs,
    /// Labels in the monospaced font, so figures line up.
    mono: bool = false,
    /// The labels' color; null takes the theme's muted text.
    color: ?ui.Color = null,
    /// Multiplies the legend's lengths but not its text, as the charts'.
    scale: f32 = 1,
    /// As wide as its parent, or only as wide as its items: they still
    /// run on to a new line where the parent's width ends.
    width: Width = .fill,

    pub const Width = enum { fill, fit };
};

/// Opens a legend: add items with `item` or `itemDetail`, then `end`.
pub fn legend(c: *ui.Context, opts: Options) Legend {
    if (opts.width == .fit) {
        // The parent's width, measured by a box across it that takes no
        // room, as the legend itself is only as wide as its items.
        const probe = ui.div(c).absolute().wFull().h(0);
        const room = if (chart.lastSize(c, probe.index)) |s| s.w else c.size.w;
        probe.end();
        const box = ui.div(c).column().gap(opts.row_gap * opts.scale);
        return .{ .c = c, .box = box, .opts = opts, .width = room };
    }
    const box = ui.div(c).column().wFull().gap(opts.row_gap * opts.scale);
    // The width as the last frame laid it out; until then, the window's.
    const width = if (chart.lastSize(c, box.index)) |s| s.w else c.size.w;
    return .{ .c = c, .box = box, .opts = opts, .width = width };
}

/// A swatch's shape: a rounded square, as a legend's, a dot, or a short
/// line, for a line chart's series.
pub const SwatchShape = enum { square, dot, line };

pub const SwatchOptions = struct {
    /// Sized as a legend's labels at this size.
    size: kit.Size = .xs,
    shape: SwatchShape = .square,
    scale: f32 = 1,
};

/// A swatch of `color` on its own, as a legend draws it: in a chart's
/// title, a table's cell or a tooltip. A decoration to a screen reader.
pub fn swatch(c: *ui.Context, color: ui.Color, opts: SwatchOptions) void {
    const sw = @round(opts.size.text() * 0.72) * opts.scale;
    const d = switch (opts.shape) {
        .square => ui.div(c).w(sw).h(sw).rounded(sw / 4),
        .dot => ui.div(c).w(sw).h(sw).roundedFull(),
        .line => ui.div(c).w(sw * 1.4).h(@max(2, @round(sw / 4))).roundedFull(),
    };
    d.bg(color).end();
}

pub const Legend = struct {
    /// How many lines the items took, so far.
    lines: usize = 0,

    // The rest is the legend's own.
    c: *ui.Context,
    box: ui.Div,
    opts: Options,
    width: f32,
    line: ?ui.Div = null,
    /// How much of the line the items on it take.
    used: f32 = 0,

    /// Adds a swatch of `color` and `label`.
    pub fn item(l: *Legend, color: ui.Color, label: []const u8) void {
        l.itemDetail(color, label, "");
    }

    /// As `item`, with `detail` after the label, smaller and fainter,
    /// such as a peak ("▲4.2").
    pub fn itemDetail(l: *Legend, color: ui.Color, label: []const u8, detail: []const u8) void {
        const c = l.c;
        const k = l.opts.scale;
        const style = l.labelStyle();
        const detail_style = l.detailStyle();
        const sw = @round(style.size * 0.72) * k;
        const inner = @round(style.size * 0.55) * k;
        var w = sw + inner + @ceil(c.text.width(label, style));
        if (detail.len > 0) w += inner + @ceil(c.text.width(detail, detail_style));
        l.place(w);
        const it = ui.div(c).row().itemsCenter().gap(inner);
        defer it.end();
        swatch(c, color, .{ .size = l.opts.size, .scale = k });
        ui.text(c, label, style);
        if (detail.len > 0) ui.text(c, detail, detail_style);
    }

    /// `text` at the end of the last line, or of a line of its own when
    /// it doesn't fit there: a total, or what the items leave ("Free 7.0
    /// GB").
    pub fn trailing(l: *Legend, text: []const u8) void {
        const style = l.labelStyle();
        // The spacer before it is a box of its own: one more gap.
        l.place(@ceil(l.c.text.width(text, style)) + l.opts.gap * l.opts.scale);
        ui.spacer(l.c);
        ui.text(l.c, text, style);
    }

    /// Ends the legend.
    pub fn end(l: *Legend) void {
        if (l.line) |r| r.end();
        l.line = null;
        l.box.end();
    }

    /// Makes room for something `w` wide on the line, or starts a new one.
    fn place(l: *Legend, w: f32) void {
        const gap = l.opts.gap * l.opts.scale;
        // A point to spare: text measured and laid out may round apart.
        if (l.line == null or (l.used > 0 and l.used + gap + w > l.width - 1)) {
            if (l.line) |r| r.end();
            var line = ui.div(l.c).row().itemsCenter().gap(gap);
            if (l.opts.width == .fill) line = line.wFull();
            l.line = line;
            l.used = 0;
            l.lines += 1;
        }
        l.used += (if (l.used > 0) gap else 0) + w;
    }

    fn labelStyle(l: *const Legend) ui.TextStyle {
        return .{ .size = l.opts.size.text(), .mono = l.opts.mono, .color = l.opts.color orelse kit.tokens(l.c).muted };
    }

    fn detailStyle(l: *const Legend) ui.TextStyle {
        const s = l.labelStyle();
        return .{ .size = s.size - 1, .mono = s.mono, .color = s.color.?.alpha(0.7) };
    }
};

const Memory = struct {
    lines: usize = 0,
    fn view(m: *Memory, c: *ui.Context) void {
        const root = ui.div(c).column().wFull().p(10);
        defer root.end();
        var l = legend(c, .{});
        l.item(.hex(0x22d3ee), "App 12.0 GB");
        l.itemDetail(.hex(0xa78bfa), "Wired 3.0 GB", "▲4.2");
        l.item(.hex(0xfbbf24), "Compressed 1.0 GB");
        l.trailing("Free 7.0 GB");
        m.lines = l.lines;
        l.end();
    }
};

test "a legend's items sit on one line when they fit, what trails at its end" {
    var m: Memory = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&m, Memory.view), .{ .width = 700, .height = 100 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), m.lines);
    const app = t.findText("App 12.0 GB").?;
    const wired = t.findText("Wired 3.0 GB").?;
    try std.testing.expectEqual(app.y, wired.y);
    try std.testing.expect(wired.x > app.x);
    // The detail follows its label, and the trailing text ends the line.
    try std.testing.expect(t.findText("▲4.2").?.x > wired.x);
    const free = t.findText("Free 7.0 GB").?;
    try std.testing.expectApproxEqAbs(@as(f32, 690), free.x + free.w, 1);
}

test "a legend's items run on to new lines in a narrow legend" {
    var m: Memory = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&m, Memory.view), .{ .width = 260, .height = 200 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(m.lines > 1);
    const app = t.findText("App 12.0 GB").?;
    const compressed = t.findText("Compressed 1.0 GB").?;
    try std.testing.expect(compressed.y > app.y);
    // Every item stays inside the legend.
    for ([_][]const u8{ "App 12.0 GB", "Wired 3.0 GB", "▲4.2", "Compressed 1.0 GB", "Free 7.0 GB" }) |s| {
        const r = t.findText(s).?;
        try std.testing.expect(r.x + r.w <= 250.5);
    }
}

test "a legend follows its width as the window changes" {
    var m: Memory = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&m, Memory.view), .{ .width = 700, .height = 200 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), m.lines);
    t.resize(260, 200);
    t.settle(1);
    try std.testing.expect(m.lines > 1);
    // The frame that saw the width change asked for another with it.
    try std.testing.expect(t.ctx.frame_in != null);
    t.resize(700, 200);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), m.lines);
}

test "a legend keeps everything inside it at any width" {
    var m: Memory = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&m, Memory.view), .{ .width = 800, .height = 300 });
    defer t.deinit();
    var w: f32 = 250;
    while (w <= 800) : (w += 6) {
        t.resize(w, 300);
        t.settle(1);
        // The legend ends at the root's padding.
        for ([_][]const u8{ "App 12.0 GB", "Wired 3.0 GB", "▲4.2", "Compressed 1.0 GB", "Free 7.0 GB" }) |s| {
            const r = t.findText(s).?;
            try std.testing.expect(r.x + r.w <= w - 10 + 0.5);
        }
    }
}

test {
    _ = @import("legend_tests.zig");
}
