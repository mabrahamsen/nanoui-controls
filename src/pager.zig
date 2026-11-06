//! A pager: "‹ 1 … 9 10 11 … 20 ›", for an app that shows numbered pages,
//! as a grid's `rows` does a page at a time. The caller keeps the page,
//! counted from 0; the pager shows it counted from 1. Clicking a number
//! goes to it and the arrows to the page before or after; once the pager
//! has the keyboard (a click on it, or Tab), Left and Right do too, and
//! Home and End go to the first and last page.
//!
//!     var page: usize = 0;
//!     // In the frame:
//!     if (controls.pager(c, &page, pages, .{})) loadPage(page);
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;

pub const Options = struct {
    /// How many pages either side of the current one are numbered, besides
    /// the first and the last; the rest are an ellipsis.
    around: usize = 1,
    /// Multiplies the pager's lengths, for an app that zooms its layout.
    scale: f32 = 1,
};

/// Draws the pager for `pages` pages, the current one `page.*`, and
/// returns whether the user changed it.
pub fn pager(c: *ui.Context, page: *usize, pages: usize, opts: Options) bool {
    const t = kit.tokens(c);
    const k = opts.scale;
    if (pages == 0) return false;
    if (page.* >= pages) page.* = pages - 1;
    const before = page.*;
    const box = ui.div(c).row().itemsCenter().gap(2 * k).p(2 * k).rounded(t.radius);
    const it = c.interact(box.index, .{ .focusable = true });
    if (it.focused) c.node(box.index).style.border = t.primary.alpha(0.6);
    {
        defer box.end();
        if (it.focused) keys(c, page, pages);
        if (button(c, "chevron.left", "", "Previous page", false, page.* == 0, opts)) page.* -= 1;
        var shown_last: ?usize = null;
        for (0..pages) |i| {
            if (!numbered(i, page.*, pages, opts.around)) continue;
            if (shown_last) |last| if (i > last + 1) gap(c, opts);
            shown_last = i;
            if (button(c, "", c.print("{d}", .{i + 1}), c.print("Page {d}", .{i + 1}), i == page.*, false, opts)) page.* = i;
        }
        if (button(c, "chevron.right", "", "Next page", false, page.* + 1 >= pages, opts)) page.* += 1;
    }
    if (page.* != before) c.changed = true;
    return page.* != before;
}

/// Page `i` is numbered: the first, the last, or within `around` of the
/// current one. An ellipsis standing for a single page would be no
/// shorter, so that page is numbered too.
fn numbered(i: usize, current: usize, pages: usize, around: usize) bool {
    if (i == 0 or i + 1 == pages) return true;
    const lo = current -| around;
    const hi = current + around;
    if (i >= lo and i <= hi) return true;
    // The one page an ellipsis would stand for, next to the first or last.
    return (i == 1 and lo == 2) or (i + 2 == pages and hi + 3 == pages);
}

/// Left and Right move a page, Home and End to the ends.
fn keys(c: *ui.Context, page: *usize, pages: usize) void {
    if (c.shortcut(.{ .key = ui.Shortcut.left })) {
        page.* -|= 1;
    } else if (c.shortcut(.{ .key = ui.Shortcut.right })) {
        page.* = @min(page.* + 1, pages - 1);
    } else if (c.input.key) |key| switch (key) {
        .left => page.* -|= 1,
        .right => page.* = @min(page.* + 1, pages - 1),
        .home => page.* = 0,
        .end => page.* = pages - 1,
        else => {},
    };
}

/// One of the pager's buttons: an arrow (`icon`) or a number (`text`),
/// the current page lit, a page past the ends dimmed. True when clicked.
fn button(c: *ui.Context, icon: []const u8, text: []const u8, label: []const u8, current: bool, disabled: bool, opts: Options) bool {
    const t = kit.tokens(c);
    const k = opts.scale;
    ui.key(c, label);
    var b = ui.div(c).row().center().h(26 * k).minW(26 * k).px(6 * k).rounded(t.radius - 2).control();
    if (current) b = b.bg(t.primary) else if (!disabled) b = b.hover(t.surface_hover);
    const it = b.interaction();
    defer b.end();
    if (disabled) c.node(b.index).style.opacity = 0.35;
    ui.access.describe(c, b.index, .{ .label = label, .selected = current, .enabled = !disabled });
    const fg = if (current) t.primary_foreground else t.foreground;
    if (icon.len > 0) ui.icon(c, icon, .{ .size = 11 * k, .color = fg }) else ui.text(c, text, .{ .size = 13, .weight = if (current) .semibold else .regular, .color = fg });
    return it.clicked and !disabled and !current;
}

/// An ellipsis for the pages between two numbered ones.
fn gap(c: *ui.Context, opts: Options) void {
    const k = opts.scale;
    const d = ui.div(c).row().center().h(26 * k).w(20 * k);
    defer d.end();
    ui.access.hide(c, d.index);
    ui.text(c, "…", .{ .size = 13, .color = kit.tokens(c).muted });
}

const Pages = struct {
    page: usize = 0,
    pages: usize = 20,
    changed: usize = 0,
    fn view(p: *Pages, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull().p(10);
        defer root.end();
        if (pager(c, &p.page, p.pages, .{})) p.changed += 1;
    }
};

test "a pager numbers the ends and the pages around the current one" {
    var p: Pages = .{ .page = 9 };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Pages.view), .{ .width = 500, .height = 100 });
    defer t.deinit();
    t.settle(1);
    for ([_][]const u8{ "1", "9", "10", "11", "20" }) |n| try std.testing.expect(t.hasText(n));
    for ([_][]const u8{ "2", "8", "12", "19" }) |n| try std.testing.expect(!t.hasText(n));
    var gaps: usize = 0;
    for (t.ctx.nodes.items) |node| switch (node.content) {
        .text => |tx| gaps += @intFromBool(std.mem.eql(u8, tx.str, "…")),
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 2), gaps);
    // Near the start, the page an ellipsis would stand for is numbered.
    p.page = 2;
    t.settle(1);
    for ([_][]const u8{ "1", "2", "3", "4", "20" }) |n| try std.testing.expect(t.hasText(n));
    // Few pages: all numbered.
    p.pages = 4;
    t.settle(1);
    for ([_][]const u8{ "1", "2", "3", "4" }) |n| try std.testing.expect(t.hasText(n));
}

test "a pager's numbers and arrows go to their pages, not past the ends" {
    var p: Pages = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Pages.view), .{ .width = 500, .height = 100 });
    defer t.deinit();
    t.settle(1);
    try t.clickText("20");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 19), p.page);
    try std.testing.expectEqual(@as(usize, 1), p.changed);
    try t.clickText("19");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 18), p.page);
    try clickLabel(&t, "Previous page");
    try std.testing.expectEqual(@as(usize, 17), p.page);
    for (0..3) |_| try clickLabel(&t, "Next page");
    try std.testing.expectEqual(@as(usize, 19), p.page);
    // The current page's number does nothing.
    const changed = p.changed;
    try t.clickText("20");
    t.settle(1);
    try std.testing.expectEqual(changed, p.changed);
}

/// Clicks the button a screen reader calls `label`, where it is now.
fn clickLabel(t: *ui.Tester, label: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var out: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &out);
    for (out.items) |e| if (std.mem.eql(u8, e.label, label)) {
        t.click(e.rect.x + e.rect.w / 2, e.rect.y + e.rect.h / 2);
        t.settle(1);
        return;
    };
    return error.NoSuchButton;
}

test "a pager with the keyboard moves with Left, Right, Home and End" {
    var p: Pages = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Pages.view), .{ .width = 500, .height = 100 });
    defer t.deinit();
    t.settle(1);
    // Without the keyboard, the keys are someone else's.
    try std.testing.expect(!t.shortcut(.{ .key = ui.Shortcut.right }));
    try std.testing.expectEqual(@as(usize, 0), p.page);
    t.key(.tab);
    t.settle(1);
    try std.testing.expect(t.shortcut(.{ .key = ui.Shortcut.right }));
    try std.testing.expectEqual(@as(usize, 1), p.page);
    t.key(.end);
    try std.testing.expectEqual(@as(usize, 19), p.page);
    t.key(.right);
    try std.testing.expectEqual(@as(usize, 19), p.page);
    t.key(.home);
    try std.testing.expectEqual(@as(usize, 0), p.page);
    t.key(.left);
    try std.testing.expectEqual(@as(usize, 0), p.page);
}

test "a screen reader hears the pager's buttons, the current page selected" {
    var p: Pages = .{ .page = 4 };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Pages.view), .{ .width = 500, .height = 100 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var out: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &out);
    var current: ?ui.access.Element = null;
    var previous = false;
    for (out.items) |e| {
        if (e.selected) current = e;
        if (std.mem.eql(u8, e.label, "Previous page")) previous = true;
        try std.testing.expect(!std.mem.eql(u8, e.label, "…"));
    }
    try std.testing.expectEqualStrings("Page 5", current.?.label);
    try std.testing.expect(previous);
}
