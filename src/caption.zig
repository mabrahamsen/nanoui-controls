//! A caption: a small heading in muted capitals, heard as a heading, with
//! a muted aside by it if wanted. `captionOpen` leaves its line open, for
//! a pill right after it and, after `trailing()`, a count or a button at
//! the line's end. A panel's title is one.
//!
//!     controls.caption(c, "RETENTION", .{});
//!
//!     const h = controls.captionOpen(c, "LIGHTS", .{});
//!     controls.pill(c, "3 ON", .{});
//!     h.trailing();
//!     ui.text(c, "80%", .{});
//!     h.end();
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const parts = @import("parts.zig");

pub const Options = struct {
    /// As the kit's tag: a point under the kit's text at that size.
    size: kit.Size = .xs,
    /// The size in points, over `size`'s.
    text_size: ?f32 = null,
    /// Null takes the theme's muted text.
    color: ?ui.Color = null,
    /// An SF Symbol before it, in its color.
    icon: []const u8 = "",
    mono: bool = false,
    /// Heard as a heading by a screen reader, so it can move from section
    /// to section; false for a caption that only labels a value beside it.
    heading: bool = true,
    /// A muted note after it, at its size but plain ("16 GB"), heard after
    /// it.
    aside: []const u8 = "",
    /// Cut short with an ellipsis where the room its line leaves ends, so
    /// what is beside it keeps its room: a caption holding a path, before
    /// buttons.
    cut: bool = false,
    /// Multiplies the gaps on its line and its icon, not its text, for an
    /// app that zooms its layout along with `c.setZoom`. A panel's caption
    /// takes the panel's.
    scale: f32 = 1,
};

/// `text` as a small heading: semibold and muted. Write it in capitals.
pub fn caption(c: *ui.Context, text: []const u8, opts: Options) void {
    const t = kit.tokens(c);
    const k = opts.scale;
    const size = opts.text_size orelse opts.size.text() - 1;
    const col = opts.color orelse t.muted;
    var box = ui.div(c).row().itemsCenter().gap(6 * k);
    if (opts.cut) box = box.w(0).grow();
    defer box.end();
    if (opts.icon.len > 0) ui.icon(c, opts.icon, .{ .size = (size + 1) * k, .color = col });
    const style: ui.TextStyle = .{ .size = size, .weight = .semibold, .mono = opts.mono, .color = col };
    if (opts.cut) {
        _ = parts.oneLine(c, text, style);
    } else ui.text(c, text, style);
    if (opts.aside.len > 0) ui.text(c, opts.aside, .{ .size = size, .mono = opts.mono, .color = t.muted });
    const said = if (opts.aside.len > 0) c.print("{s}, {s}", .{ text, opts.aside }) else text;
    ui.access.describe(c, box.index, .{ .role = .static_text, .label = said, .header = opts.heading });
}

/// A caption's line, left open: what is drawn in it goes right after the
/// caption, and after `trailing` at the line's end. End it.
pub const CaptionLine = struct {
    // The line's own: callers use the methods.
    c: *ui.Context,
    line: ui.Div,
    cut: bool,

    /// Moves what follows to the line's end. A cut caption takes the room
    /// between, so what follows it is at the end already.
    pub fn trailing(l: CaptionLine) void {
        if (!l.cut) ui.spacer(l.c);
    }

    pub fn end(l: CaptionLine) void {
        l.line.end();
    }
};

/// A caption on a line as wide as its parent, left open for what goes
/// beside it: right after the caption, then, after `trailing`, at the
/// line's end. With `cut`, the caption takes the room between, cut short
/// where what follows begins.
pub fn captionOpen(c: *ui.Context, text: []const u8, opts: Options) CaptionLine {
    const line = ui.div(c).row().wFull().itemsCenter().gap(8 * opts.scale);
    caption(c, text, opts);
    return .{ .c = c, .line = line, .cut = opts.cut };
}

test "a caption is muted and heard as a heading, with its aside after it" {
    const T = struct {
        heading: bool = true,
        fn view(x: *@This(), c: *ui.Context) void {
            const col = ui.div(c).column().gap(8).p(8);
            defer col.end();
            caption(c, "MEMORY", .{ .aside = "16 GB", .heading = x.heading });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 60 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(t.findText("16 GB").?.x > t.findText("MEMORY").?.x);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings("MEMORY, 16 GB", list.items[0].label);
    try std.testing.expect(list.items[0].header);
    x.heading = false;
    t.settle(1);
    list = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expect(!list.items[0].header);
}

test "an open caption line holds a pill by the caption and a figure at its end" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            const col = ui.div(c).column().w(300).p(8);
            defer col.end();
            const h = captionOpen(c, "LIGHTS", .{});
            ui.text(c, "3 ON", .{});
            h.trailing();
            ui.text(c, "80%", .{});
            h.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 400, .height = 60 });
    defer t.deinit();
    t.settle(1);
    const by = t.findText("3 ON").?;
    const pct = t.findText("80%").?;
    try std.testing.expect(by.x < 120);
    try std.testing.expectApproxEqAbs(@as(f32, 292), pct.x + pct.w, 1);
}

test "a cut caption gives way to what follows it, cut short with an ellipsis" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            const col = ui.div(c).column().w(160).p(8);
            defer col.end();
            const h = captionOpen(c, "/Users/someone/Documents/Projects/a-long-folder", .{ .cut = true });
            h.trailing();
            ui.text(c, "Open", .{});
            h.end();
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 60 });
    defer t.deinit();
    t.settle(1);
    const open = t.findText("Open").?;
    try std.testing.expectApproxEqAbs(@as(f32, 152), open.x + open.w, 1);
}
