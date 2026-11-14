//! The sidebar's tests of rows keyed by the caller's own type, an enum
//! or a tagged union, and of its marker as it narrows to its icons.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const sidebar_mod = @import("sidebar.zig");
const sidebarOf = sidebar_mod.sidebarOf;
const clickRow = @import("sidebar_tests.zig").clickRow;

const Tool = enum { git, shell };
const Page = enum { settings, history };

/// An app's screens: an overview, and a tool's pages under each tool.
const Screen = union(enum) {
    overview,
    tool: Tool,
    page: struct { tool: Tool, page: Page },
};

const App = struct {
    screen: ?Screen = .overview,
    git_open: bool = true,
    chosen: usize = 0,
    menu: ?Screen = null,

    fn view(a: *App, c: *ui.Context) void {
        const root = ui.div(c).column().w(220).h(400);
        defer root.end();
        var sb = sidebarOf(Screen, c, "app", a.screen, .{});
        sb.item(.overview, "Overview", .{ .icon = "house" });
        sb.heading("Tools");
        if (sb.branch(.{ .tool = .git }, "Git", .{ .icon = "folder" }, &a.git_open)) |g| {
            sb.item(.{ .page = .{ .tool = .git, .page = .settings } }, "Git settings", .{});
            sb.item(.{ .page = .{ .tool = .git, .page = .history } }, "Git history", .{});
            g.end();
        }
        sb.item(.{ .tool = .shell }, "Shell", .{ .icon = "terminal" });
        if (sb.end()) |s| {
            a.screen = s;
            a.chosen += 1;
        }
        if (sb.secondary_clicked) |s| a.menu = s;
    }
};

fn start(a: *App, t: *ui.Tester) !void {
    try t.init(std.testing.allocator, .init(a, App.view), .{ .width = 300, .height = 420 });
    t.settle(1);
}

test "rows keyed by a tagged union are chosen by a click, and the key comes back as it was" {
    var a: App = .{};
    var t: ui.Tester = undefined;
    try start(&a, &t);
    defer t.deinit();
    try clickRow(&t, "Git history");
    try std.testing.expectEqual(Screen{ .page = .{ .tool = .git, .page = .history } }, a.screen.?);
    try clickRow(&t, "Shell");
    try std.testing.expectEqual(Screen{ .tool = .shell }, a.screen.?);
    // The selected row again chooses nothing anew.
    try clickRow(&t, "Shell");
    try std.testing.expectEqual(@as(usize, 2), a.chosen);
}

test "the keys move between rows keyed by a union, and Left goes from a page to its tool" {
    var a: App = .{};
    var t: ui.Tester = undefined;
    try start(&a, &t);
    defer t.deinit();
    try clickRow(&t, "Overview");
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqual(Screen{ .tool = .git }, a.screen.?);
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqual(Screen{ .page = .{ .tool = .git, .page = .settings } }, a.screen.?);
    t.key(.left);
    t.settle(1);
    try std.testing.expectEqual(Screen{ .tool = .git }, a.screen.?);
}

test "a branch folded over the selected page shows it holds it, by the key's hash" {
    var a: App = .{ .screen = .{ .page = .{ .tool = .git, .page = .history } } };
    var t: ui.Tester = undefined;
    try start(&a, &t);
    defer t.deinit();
    a.git_open = false;
    t.settle(2);
    try std.testing.expect(!t.hasText("Git history"));
    // Folded, its label takes the selection's tint.
    var tinted = false;
    for (t.ctx.nodes.items) |n| switch (n.content) {
        .text => |tx| if (std.mem.eql(u8, tx.str, "Git")) {
            tinted = std.meta.eql(tx.color, nanoui.kit.tokens(&t.ctx).primary);
        },
        else => {},
    };
    try std.testing.expect(tinted);
}

test "a right-click on a row keyed by a union reports its key" {
    var a: App = .{};
    var t: ui.Tester = undefined;
    try start(&a, &t);
    defer t.deinit();
    const r = t.findText("Shell").?;
    t.secondaryClick(r.x + 2, r.y + r.h / 2);
    t.settle(1);
    try std.testing.expectEqual(Screen{ .tool = .shell }, a.menu.?);
    try std.testing.expectEqual(Screen.overview, a.screen.?);
}

/// Rows keyed by an enum, narrowed to their icons or not.
const Narrowing = struct {
    const Kind = enum { inbox, sent, work };
    selected: ?Kind = .work,
    icons_only: bool = false,

    fn view(x: *Narrowing, c: *ui.Context) void {
        const root = ui.div(c).column().w(if (x.icons_only) 48 else 220).h(300);
        defer root.end();
        var sb = sidebarOf(Kind, c, "kinds", x.selected, .{ .icons_only = x.icons_only });
        sb.heading("Mailboxes");
        sb.item(.inbox, "Inbox", .{ .icon = "doc.text" });
        sb.item(.sent, "Sent", .{ .icon = "arrow.up" });
        sb.heading("Folders");
        sb.item(.work, "Work", .{ .icon = "folder" });
        if (sb.end()) |key| x.selected = key;
    }
};

/// The marker's top, and whether it is drawn.
fn markerY(t: *ui.Tester) ?f32 {
    for (t.ctx.nodes.items) |node| {
        if (!node.style.absolute or node.style.background == null) continue;
        return t.ctx.rects.get(node.id).?.y;
    }
    return null;
}

test "as the sidebar narrows and widens, its marker goes to the row at once, not sliding" {
    var x: Narrowing = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Narrowing.view), .{ .width = 300, .height = 320 });
    defer t.deinit();
    t.settle(2);
    const wide = markerY(&t).?;
    x.icons_only = true;
    // Until the row has been laid out narrowed, it tints itself.
    t.frame();
    try std.testing.expect(markerY(&t) == null);
    t.frame();
    try std.testing.expect(markerY(&t) == null);
    t.frame();
    const narrow = markerY(&t).?;
    t.settle(2);
    try std.testing.expectEqual(narrow, markerY(&t).?);
    // Headings became lines, so the row moved up.
    try std.testing.expect(narrow < wide);
    x.icons_only = false;
    for (0..3) |_| t.frame();
    try std.testing.expectEqual(wide, markerY(&t).?);
    // A row chosen after still slides.
    x.selected = .inbox;
    t.frame();
    t.frame();
    const moving = markerY(&t).?;
    t.settle(2);
    try std.testing.expect(markerY(&t).? < moving);
}
