//! A pager: "‹ 1 … 9 10 11 … 20 ›", for an app that shows numbered pages,
//! as a grid's `rows` does a page at a time. The caller keeps the page,
//! counted from 0; the pager shows it counted from 1. Clicking a number
//! goes to it and the arrows to the page before or after; once the pager
//! has the keyboard (a click on it, or Tab), Left and Right do too, and
//! Home and End go to the first and last page.
//!
//! It is made of the kit's buttons, as `kit.pagination` is, and adds to
//! it the keyboard, a name for each button a screen reader says, and how
//! many pages around the current one are numbered. It keeps its width
//! from page to page, so the arrows stay under the pointer: it always
//! shows as many numbers and ellipses, each as wide as the widest number.
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
    /// The buttons' size, as the kit's.
    size: kit.Size = .sm,
};

/// Draws the pager for `pages` pages, the current one `page.*`, and
/// returns whether the user changed it.
pub fn pager(c: *ui.Context, page: *usize, pages: usize, opts: Options) bool {
    const t = kit.tokens(c);
    if (pages == 0) return false;
    if (page.* >= pages) page.* = pages - 1;
    const before = page.*;
    const box = ui.div(c).row().itemsCenter().gap(4).p(2).rounded(t.radius);
    const it = c.interact(box.index, .{ .focusable = true });
    if (it.focused) c.node(box.index).style.border = t.primary.alpha(0.6);
    {
        defer box.end();
        if (it.focused) keys(c, page, pages);
        const w = slotWidth(c, pages, opts.size);
        if (button(c, "chevron.left", "", "Previous page", false, page.* == 0, null, opts)) page.* -= 1;
        const current = page.*;
        for (0..slots(pages, opts.around)) |k| {
            const i = slot(k, current, pages, opts.around) orelse {
                gap(c, k, w, opts);
                continue;
            };
            if (button(c, "", c.print("{d}", .{i + 1}), c.print("Page {d}", .{i + 1}), i == current, false, w, opts)) page.* = i;
        }
        if (button(c, "chevron.right", "", "Next page", false, page.* + 1 >= pages, null, opts)) page.* += 1;
    }
    if (page.* != before) c.changed = true;
    return page.* != before;
}

/// How many numbers and ellipses the pager shows, the same on every page:
/// the first and last pages, `around` either side of the current one, the
/// current one, and an ellipsis or a page either side of those.
fn slots(pages: usize, around: usize) usize {
    return @min(pages, 2 * around + 5);
}

/// What slot `k` shows: a page, or null for an ellipsis. Near an end,
/// the pages run on from it where the ellipsis would have been.
fn slot(k: usize, current: usize, pages: usize, around: usize) ?usize {
    const n = slots(pages, around);
    if (n == pages) return k;
    if (current <= around + 2) {
        // Near the first page: 1 2 3 4 5 … 20.
        return if (k + 2 < n) k else if (k + 2 == n) null else pages - 1;
    }
    if (current + around + 3 >= pages) {
        // Near the last page: 1 … 16 17 18 19 20.
        return if (k == 0) 0 else if (k == 1) null else pages - (n - k);
    }
    // Between: 1 … 9 10 11 … 20.
    if (k == 0) return 0;
    if (k == 1 or k + 2 == n) return null;
    if (k + 1 == n) return pages - 1;
    return current - around + (k - 2);
}

/// A number's width: room for the widest of `pages`' digits as many times
/// as it has them, so no number is wider, and at least a square.
fn slotWidth(c: *ui.Context, pages: usize, size: kit.Size) f32 {
    const style: ui.TextStyle = .{ .size = size.text(), .weight = .medium };
    var digit: f32 = 0;
    for ("0123456789") |d| digit = @max(digit, c.text.width(&.{d}, style));
    var digits: f32 = 1;
    var p = pages;
    while (p >= 10) : (p /= 10) digits += 1;
    return @max(size.height(), @ceil(digits * digit + 2 * size.text() * 0.6));
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

/// One of the pager's buttons, a kit button: an arrow (`icon`) or a
/// number (`text`) `width` wide, the current page primary, a page past
/// the ends disabled; a screen reader calls it `label`. True when clicked.
fn button(c: *ui.Context, icon: []const u8, text: []const u8, label: []const u8, current: bool, disabled: bool, width: ?f32, opts: Options) bool {
    ui.key(c, label);
    const box = if (width) |w| ui.div(c).w(w) else null;
    defer if (box) |b| b.end();
    // The kit's button is the next box: its index, to name it.
    const index: u32 = @intCast(c.nodes.items.len);
    const o: kit.ButtonOptions = .{ .size = opts.size, .variant = if (current) .primary else .ghost, .disabled = disabled, .full_width = width != null };
    const it = if (icon.len > 0) kit.iconButton(c, icon, o) else kit.button(c, text, o);
    if (index < c.nodes.items.len and c.nodes.items[index].id == it.id) {
        ui.access.describe(c, index, .{ .label = label, .selected = current, .enabled = !disabled });
        // The slot is its width: the number centers in it, unpadded.
        if (width != null) c.node(index).style.padding = .{};
    }
    return it.clicked and !current;
}

/// An ellipsis for the pages between two numbered ones, in slot `k`, as
/// wide as a number.
fn gap(c: *ui.Context, k: usize, w: f32, opts: Options) void {
    ui.key(c, c.print("gap-{d}", .{k}));
    const d = ui.div(c).row().center().h(opts.size.height()).w(w);
    defer d.end();
    ui.access.hide(c, d.index);
    ui.text(c, "…", .{ .size = opts.size.text(), .color = kit.tokens(c).muted });
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
    // At the first page, Previous is there but disabled.
    p.page = 0;
    t.settle(1);
    out.clearRetainingCapacity();
    try ui.access.tree(&t.ctx, arena.allocator(), &out);
    var found = false;
    for (out.items) |e| if (std.mem.eql(u8, e.label, "Previous page")) {
        found = true;
        try std.testing.expect(!e.enabled);
    } else if (std.mem.eql(u8, e.label, "Next page")) try std.testing.expect(e.enabled);
    try std.testing.expect(found);
}

test "a pager's slots: as many on every page, the current, the ends, and ellipses for pages left out" {
    for (0..4) |around| for (1..40) |pages| for (0..pages) |current| {
        const n = slots(pages, around);
        var prev: ?usize = null;
        var gap_before = false;
        var saw_current = false;
        for (0..n) |k| {
            const s = slot(k, current, pages, around) orelse {
                // An ellipsis stands for pages, never next to another.
                try std.testing.expect(!gap_before and prev != null);
                gap_before = true;
                continue;
            };
            if (prev) |p| try std.testing.expect(if (gap_before) s > p + 1 else s == p + 1);
            if (k == 0) try std.testing.expectEqual(@as(usize, 0), s);
            if (k + 1 == n) try std.testing.expectEqual(pages - 1, s);
            saw_current = saw_current or s == current;
            prev = s;
            gap_before = false;
        }
        try std.testing.expect(saw_current);
    };
}

test "a pager keeps its arrows in place from page to page" {
    for ([_]usize{ 7, 20, 150 }) |pages| {
        var p: Pages = .{ .pages = pages };
        var t: ui.Tester = undefined;
        try t.init(std.testing.allocator, .init(&p, Pages.view), .{ .width = 700, .height = 100 });
        defer t.deinit();
        var first: ?[2]f32 = null;
        for (0..pages) |i| {
            p.page = i;
            t.settle(1);
            var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
            defer arena.deinit();
            var out: std.ArrayList(ui.access.Element) = .empty;
            try ui.access.tree(&t.ctx, arena.allocator(), &out);
            var at: [2]f32 = .{ -1, -1 };
            for (out.items) |e| {
                if (std.mem.eql(u8, e.label, "Previous page")) at[0] = e.rect.x;
                if (std.mem.eql(u8, e.label, "Next page")) at[1] = e.rect.x;
            }
            try std.testing.expect(at[0] >= 0 and at[1] >= 0);
            if (first) |f| try std.testing.expectEqualSlices(f32, &f, &at) else first = at;
        }
    }
}
