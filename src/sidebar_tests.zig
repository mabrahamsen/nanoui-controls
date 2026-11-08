//! The sidebar's tests: choosing by key, groups that fold, the keys, the
//! marker and the hover, and what a screen reader hears.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const sidebar_mod = @import("sidebar.zig");
const sidebar = sidebar_mod.sidebar;

/// A mail app's sidebar: two mailboxes, then a group of folders.
const Mail = struct {
    selected: ?[]const u8 = "inbox",
    folders_open: bool = true,
    /// Rows are added and removed, as data changes.
    drafts: bool = false,
    choose_on_enter: bool = false,
    chosen: usize = 0,
    focused: bool = false,
    /// Takes the keyboard in the first frame.
    start_focused: bool = false,
    started: bool = false,

    const folders = [_][]const u8{ "work", "family", "travel" };

    fn view(m: *Mail, c: *ui.Context) void {
        const root = ui.div(c).column().w(220).h(400);
        defer root.end();
        if (m.start_focused and !m.started) c.focusNext(false);
        m.started = true;
        var sb = sidebar(c, "mail", m.selected, .{ .choose_on_enter = m.choose_on_enter });
        m.focused = sb.focused;
        sb.heading("Mailboxes");
        if (m.drafts) sb.item("drafts", "Drafts", .{ .icon = "doc" });
        sb.item("inbox", "Inbox", .{ .icon = "tray", .count = 12 });
        sb.item("sent", "Sent", .{ .icon = "paperplane" });
        if (sb.group("folders", "Folders", &m.folders_open)) |g| {
            for (folders) |f| sb.item(f, f, .{ .icon = "folder" });
            g.end();
        }
        if (sb.end()) |key| {
            m.selected = key;
            m.chosen += 1;
        }
    }
};

fn start(m: *Mail, t: *ui.Tester) !void {
    try t.init(std.testing.allocator, .init(m, Mail.view), .{ .width = 300, .height = 420 });
    t.settle(1);
}

test "a click chooses a row by its key, and the selection follows its key as rows come and go" {
    var m: Mail = .{};
    var t: ui.Tester = undefined;
    try start(&m, &t);
    defer t.deinit();
    try t.clickText("Sent");
    t.settle(1);
    try std.testing.expectEqualStrings("sent", m.selected.?);
    try std.testing.expectEqual(@as(usize, 1), m.chosen);
    // A click on the selected row chooses nothing anew.
    try t.clickText("Sent");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), m.chosen);
    // A row added above it: "Sent" stays selected, by its key.
    m.drafts = true;
    t.settle(1);
    try std.testing.expectEqualStrings("sent", m.selected.?);
    try clickRow(&t, "Drafts");
    try std.testing.expectEqualStrings("drafts", m.selected.?);
}

fn clickRow(t: *ui.Tester, text: []const u8) !void {
    try t.clickText(text);
    t.settle(1);
}

test "a group folds and opens by its heading, its rows going with it" {
    var m: Mail = .{};
    var t: ui.Tester = undefined;
    try start(&m, &t);
    defer t.deinit();
    try std.testing.expect(t.hasText("work"));
    try clickRow(&t, "Folders");
    try std.testing.expect(!m.folders_open);
    try std.testing.expect(!t.hasText("work"));
    try clickRow(&t, "Folders");
    try std.testing.expect(m.folders_open);
    try std.testing.expect(t.hasText("work"));
}

test "a selected row in a folded group shows nothing selected, and nothing breaks" {
    var m: Mail = .{ .selected = "travel" };
    var t: ui.Tester = undefined;
    try start(&m, &t);
    defer t.deinit();
    m.folders_open = false;
    t.settle(1);
    try std.testing.expect(!t.hasText("travel"));
    m.selected = "nowhere";
    t.settle(1);
    m.selected = null;
    t.settle(1);
}

test "the keys move between rows and headings, past folded rows, and choose as they go" {
    var m: Mail = .{ .start_focused = true };
    var t: ui.Tester = undefined;
    try start(&m, &t);
    defer t.deinit();
    try std.testing.expect(m.focused);
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqualStrings("sent", m.selected.?);
    // Onto the group's heading: nothing chosen, and Left folds it.
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqualStrings("sent", m.selected.?);
    t.key(.left);
    try std.testing.expect(!m.folders_open);
    // Its rows are folding away, and then gone: End stops at the heading.
    t.key(.end);
    t.settle(1);
    try std.testing.expectEqualStrings("sent", m.selected.?);
    t.key(.end);
    t.settle(1);
    try std.testing.expectEqualStrings("sent", m.selected.?);
    t.key(.right);
    t.settle(1);
    try std.testing.expect(m.folders_open);
    t.key(.end);
    t.settle(1);
    try std.testing.expectEqualStrings("travel", m.selected.?);
    // Left from a row in a group goes to its heading, and Down from there
    // to its first row.
    t.key(.left);
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqualStrings("work", m.selected.?);
    t.key(.home);
    t.settle(1);
    try std.testing.expectEqualStrings("inbox", m.selected.?);
}

test "with choose_on_enter, the keys move a highlight, and Enter chooses" {
    var m: Mail = .{ .start_focused = true, .choose_on_enter = true };
    var t: ui.Tester = undefined;
    try start(&m, &t);
    defer t.deinit();
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqualStrings("inbox", m.selected.?);
    t.key(.enter);
    t.settle(1);
    try std.testing.expectEqualStrings("sent", m.selected.?);
    // Enter on a heading folds its group.
    t.key(.down);
    t.key(.enter);
    t.settle(1);
    try std.testing.expect(!m.folders_open);
}

test "without the keyboard, the keys are someone else's" {
    var m: Mail = .{};
    var t: ui.Tester = undefined;
    try start(&m, &t);
    defer t.deinit();
    try std.testing.expect(!m.focused);
    try std.testing.expect(!t.shortcut(.{ .key = ui.Shortcut.down }));
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqualStrings("inbox", m.selected.?);
    // A click gives it the keyboard.
    try clickRow(&t, "Inbox");
    try std.testing.expect(m.focused);
}

/// The marker's top, from the sidebar's.
fn markerY(t: *ui.Tester) ?f32 {
    for (t.ctx.nodes.items) |node| {
        if (!node.style.absolute or node.style.background == null) continue;
        return t.ctx.rects.get(node.id).?.y;
    }
    return null;
}

test "the marker slides to the row chosen, and rests there" {
    var m: Mail = .{};
    var t: ui.Tester = undefined;
    try start(&m, &t);
    defer t.deinit();
    const inbox = markerY(&t).?;
    try clickRow(&t, "Sent");
    // Part of the way, then at rest on the row.
    m.selected = "travel";
    t.frame();
    t.frame();
    const moving = markerY(&t).?;
    t.settle(2);
    const rest = markerY(&t).?;
    try std.testing.expect(rest > moving and moving > inbox);
    try std.testing.expectApproxEqAbs(t.findText("travel").?.y + t.findText("travel").?.h / 2, rest + 14, 2);
}

test "a screen reader hears each row, the selected one selected, and the headings" {
    var m: Mail = .{};
    var t: ui.Tester = undefined;
    try start(&m, &t);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    // A heading, two mailboxes, the group's heading and its three folders.
    try std.testing.expectEqual(@as(usize, 7), list.items.len);
    try std.testing.expectEqualStrings("Mailboxes", list.items[0].label);
    try std.testing.expect(list.items[0].header);
    try std.testing.expectEqualStrings("Inbox", list.items[1].label);
    try std.testing.expectEqualStrings("12", list.items[1].value);
    try std.testing.expect(list.items[1].selected);
    try std.testing.expect(!list.items[2].selected);
    try std.testing.expectEqualStrings("Folders", list.items[3].label);
    try std.testing.expectEqualStrings("expanded", list.items[3].value);
    try std.testing.expectEqualStrings("work", list.items[4].label);
}

test "a sidebar with more rows than room scrolls the keys' row into view" {
    const T = struct {
        // The keys outlive the frame: the chosen one is kept.
        const names = blk: {
            var out: [20][]const u8 = undefined;
            for (&out, 0..) |*n, i| n.* = std.fmt.comptimePrint("row-{d}", .{i});
            break :blk out;
        };
        selected: ?[]const u8 = "row-0",
        started: bool = false,
        fn view(x: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column().w(220).h(120);
            defer root.end();
            if (!x.started) c.focusNext(false);
            x.started = true;
            var sb = sidebar(c, "many", x.selected, .{});
            for (names) |key| sb.item(key, key, .{});
            if (sb.end()) |key| x.selected = key;
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 200 });
    defer t.deinit();
    t.settle(1);
    t.key(.end);
    t.settle(1);
    t.settle(1);
    try std.testing.expectEqualStrings("row-19", x.selected.?);
    const r = t.findText("row-19").?;
    try std.testing.expect(r.y >= 0 and r.y + r.h <= 120.5);
}

test "with reduced motion, the marker moves at once" {
    var m: Mail = .{};
    var t: ui.Tester = undefined;
    try start(&m, &t);
    defer t.deinit();
    t.ctx.reduce_motion = true;
    m.selected = "travel";
    t.frame();
    t.frame();
    const at = markerY(&t).?;
    t.settle(2);
    try std.testing.expectEqual(at, markerY(&t).?);
}

/// The background of the row reading `text`.
fn rowBackground(t: *ui.Tester, text: []const u8) ?ui.Color {
    const r = t.findText(text).?;
    var found: ?ui.Color = null;
    for (t.ctx.nodes.items) |node| {
        const b = t.ctx.rects.get(node.id) orelse continue;
        if (node.style.absolute or b.h > 40 or !b.contains(.{ .x = r.x, .y = r.y + r.h / 2 })) continue;
        if (node.style.background) |bg| found = bg;
    }
    return found;
}

test "a row eases into a wash under the pointer, and out again" {
    var m: Mail = .{};
    var t: ui.Tester = undefined;
    try start(&m, &t);
    defer t.deinit();
    try std.testing.expectEqual(@as(?ui.Color, null), rowBackground(&t, "Sent"));
    const r = t.findText("Sent").?;
    t.moveTo(r.x, r.y + r.h / 2);
    t.frame();
    t.frame();
    const easing = rowBackground(&t, "Sent").?.a;
    t.settle(1);
    const full = rowBackground(&t, "Sent").?.a;
    try std.testing.expect(easing > 0 and easing < full);
    t.moveTo(290, 410);
    t.settle(1);
    try std.testing.expectEqual(@as(?ui.Color, null), rowBackground(&t, "Sent"));
}

test "having lost the keyboard, the keys start again from the selected row" {
    var m: Mail = .{ .start_focused = true };
    var t: ui.Tester = undefined;
    try start(&m, &t);
    defer t.deinit();
    // The keys go to the group's heading, past "Sent", choosing it.
    t.key(.down);
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqualStrings("sent", m.selected.?);
    m.selected = "inbox";
    t.ctx.focus = 0;
    t.settle(1);
    try std.testing.expect(!m.focused);
    // Back by Tab: the keys start from "Inbox", not the heading they left.
    t.key(.tab);
    t.settle(1);
    try std.testing.expect(m.focused);
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqualStrings("sent", m.selected.?);
}

/// Rows of each kind: a pill count, a disabled row, icons only or not.
const Kinds = struct {
    selected: ?[]const u8 = "inbox",
    icons_only: bool = false,
    secondary: ?[]const u8 = null,
    started: bool = false,
    start_focused: bool = false,
    open: bool = true,

    fn view(x: *Kinds, c: *ui.Context) void {
        const root = ui.div(c).column().w(if (x.icons_only) 48 else 220).h(300);
        defer root.end();
        if (x.start_focused and !x.started) c.focusNext(false);
        x.started = true;
        var sb = sidebar(c, "kinds", x.selected, .{ .icons_only = x.icons_only });
        sb.heading("Mailboxes");
        sb.item("inbox", "Inbox", .{ .icon = "doc.text", .count = 4, .count_style = .pill });
        sb.item("offline", "Offline", .{ .icon = "globe", .disabled = true });
        sb.item("sent", "Sent", .{ .icon = "arrow.up", .count = 2 });
        if (sb.group("folders", "Folders", &x.open)) |g| {
            sb.item("work", "Work", .{ .icon = "folder" });
            g.end();
        }
        if (sb.end()) |key| x.selected = key;
        if (sb.secondary_clicked) |key| x.secondary = key;
    }
};

fn elements(t: *ui.Tester, arena: std.mem.Allocator) ![]const ui.access.Element {
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena, &list);
    return list.items;
}

test "a disabled row is dimmed, takes no click, is passed by the keys, and is said as disabled" {
    var x: Kinds = .{ .start_focused = true };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Kinds.view), .{ .width = 300, .height = 320 });
    defer t.deinit();
    t.settle(1);
    try t.clickText("Offline");
    t.settle(1);
    try std.testing.expectEqualStrings("inbox", x.selected.?);
    t.ctx.focus = 0;
    t.key(.tab);
    t.settle(1);
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqualStrings("sent", x.selected.?);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const list = try elements(&t, arena.allocator());
    try std.testing.expectEqualStrings("Offline", list[2].label);
    try std.testing.expect(!list[2].enabled);
}

test "a right-click on a row reports it, without choosing it" {
    var x: Kinds = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Kinds.view), .{ .width = 300, .height = 320 });
    defer t.deinit();
    t.settle(1);
    const r = t.findText("Sent").?;
    t.secondaryClick(r.x + 2, r.y + r.h / 2);
    t.settle(1);
    try std.testing.expectEqualStrings("sent", x.secondary.?);
    try std.testing.expectEqualStrings("inbox", x.selected.?);
}

test "a pill count stands out in the selection's tint" {
    var x: Kinds = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Kinds.view), .{ .width = 300, .height = 320 });
    defer t.deinit();
    t.settle(1);
    const four = t.findText("4").?;
    var pill: ?ui.Color = null;
    for (t.ctx.nodes.items) |node| {
        const b = t.ctx.rects.get(node.id) orelse continue;
        if (node.style.background == null or b.h > 30 or !b.contains(.{ .x = four.x + 1, .y = four.y + four.h / 2 })) continue;
        pill = node.style.background;
    }
    try std.testing.expectEqual(nanoui.kit.tokens(&t.ctx).primary, pill.?);
}

test "icons only, rows show their icons, labels in tooltips and to a screen reader" {
    var x: Kinds = .{ .icons_only = true };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Kinds.view), .{ .width = 300, .height = 320 });
    defer t.deinit();
    t.settle(1);
    for ([_][]const u8{ "Inbox", "Sent", "Mailboxes", "Folders", "4", "2" }) |s| try std.testing.expect(!t.hasText(s));
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const list = try elements(&t, arena.allocator());
    try std.testing.expectEqualStrings("Mailboxes", list[0].label);
    try std.testing.expectEqualStrings("Inbox", list[1].label);
    try std.testing.expectEqualStrings("4", list[1].value);
    // Under the pointer, a row says its label in a tooltip.
    const sent = list[3].rect;
    t.moveTo(sent.x + sent.w / 2, sent.y + sent.h / 2);
    t.settle(2);
    try std.testing.expect(t.hasText("Sent"));
    // A click still chooses.
    t.click(sent.x + sent.w / 2, sent.y + sent.h / 2);
    t.settle(1);
    try std.testing.expectEqualStrings("sent", x.selected.?);
}

test "icons only, a disabled row still says its label in a tooltip" {
    var x: Kinds = .{ .icons_only = true };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, Kinds.view), .{ .width = 300, .height = 320 });
    defer t.deinit();
    t.settle(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const list = try elements(&t, arena.allocator());
    const offline = list[2].rect;
    t.moveTo(offline.x + offline.w / 2, offline.y + offline.h / 2);
    t.settle(2);
    try std.testing.expect(t.hasText("Offline"));
    t.click(offline.x + offline.w / 2, offline.y + offline.h / 2);
    t.settle(1);
    try std.testing.expectEqualStrings("inbox", x.selected.?);
}

test "a sidebar keeps working when what its rows draw makes many states" {
    // In a frame a key lands, each row makes more new state than nanoui's
    // store has room for, so it grows, and moves, while the sidebar is
    // open.
    const T = struct {
        selected: ?[]const u8 = "inbox",
        frames: usize = 0,
        fn view(x: *@This(), c: *ui.Context) void {
            if (x.frames == 0) c.focusNext(false);
            x.frames += 1;
            var sb = sidebar(c, "mail", x.selected, .{ .choose_on_enter = true });
            for ([_][]const u8{ "inbox", "sent", "drafts" }) |key| {
                sb.item(key, key, .{});
                if (c.input.key != null) for (0..20_000) |j| {
                    ui.key(c, c.print("churn-{d}-{s}-{d}", .{ x.frames, key, j }));
                    _ = c.state(struct { x: u8 = 0 }, "churn");
                    c.next_key = null;
                };
            }
            if (sb.end()) |key| x.selected = key;
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 300 });
    defer t.deinit();
    t.settle(1);
    // Down moves the highlight to "sent", and Enter chooses it.
    t.key(.down);
    t.settle(1);
    t.key(.enter);
    t.settle(1);
    try std.testing.expectEqualStrings("sent", x.selected.?);
}
