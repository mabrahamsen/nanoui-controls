//! The sidebar's tests of branches: rows with rows under them, folding
//! or fixed, their indent, clicks and keys, the folded selection's tint,
//! what a screen reader hears, and icons only.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const sidebar = @import("sidebar.zig").sidebar;
const helpers = @import("sidebar_tests.zig");
const clickRow = helpers.clickRow;
const elements = helpers.elements;

/// A settings window's sidebar: a branch of panes, one a branch in turn,
/// and a branch in a group.
const Settings = struct {
    selected: ?[]const u8 = "general",
    privacy_open: bool = true,
    apps_open: bool = true,
    more_open: bool = true,
    network_open: bool = true,
    network_disabled: bool = false,
    icons_only: bool = false,
    chosen: usize = 0,
    focused: bool = false,
    start_focused: bool = false,
    started: bool = false,

    fn view(s: *Settings, c: *ui.Context) void {
        const root = ui.div(c).column().w(220).h(400);
        defer root.end();
        if (s.start_focused and !s.started) c.focusNext(false);
        s.started = true;
        var sb = sidebar(c, "settings", s.selected, .{ .icons_only = s.icons_only });
        s.focused = sb.focused;
        sb.item("general", "General", .{ .icon = "gear" });
        if (sb.branch("privacy", "Privacy", .{ .icon = "hand.raised", .count = 2 }, &s.privacy_open)) |g| {
            sb.item("location", "Location", .{ .icon = "location" });
            if (sb.branch("apps", "Apps", .{ .icon = "app" }, &s.apps_open)) |g2| {
                sb.item("camera", "Camera", .{ .icon = "camera" });
                sb.item("microphone", "Microphone", .{ .icon = "mic" });
                g2.end();
            }
            g.end();
        }
        if (sb.group("more", "More", &s.more_open)) |g| {
            if (sb.branch("network", "Network", .{ .icon = "network", .disabled = s.network_disabled }, &s.network_open)) |g2| {
                sb.item("wifi", "Wi-Fi", .{ .icon = "wifi" });
                g2.end();
            }
            g.end();
        }
        if (sb.end()) |key| {
            s.selected = key;
            s.chosen += 1;
        }
    }

    /// The color `label` is drawn in.
    fn labelColor(t: *ui.Tester, label: []const u8) ui.Color {
        for (t.ctx.nodes.items) |node| switch (node.content) {
            .text => |tx| if (std.mem.eql(u8, tx.str, label)) return tx.style.color.?,
            else => {},
        };
        unreachable;
    }

    /// Clicks the chevron at the end of the row reading `label`.
    fn clickChevron(t: *ui.Tester, label: []const u8) void {
        const r = t.findText(label).?;
        t.click(203, r.y + r.h / 2);
        t.settle(1);
    }
};

fn startSettings(s: *Settings, t: *ui.Tester) !void {
    try t.init(std.testing.allocator, .init(s, Settings.view), .{ .width = 300, .height = 420 });
    t.settle(1);
}

test "a branch's rows are indented a step for each branch they are in, and a group's are not" {
    var s: Settings = .{};
    var t: ui.Tester = undefined;
    try startSettings(&s, &t);
    defer t.deinit();
    const general = t.findText("General").?.x;
    const step = t.findText("Location").?.x - t.findText("Privacy").?.x;
    try std.testing.expect(step > 10);
    try std.testing.expectEqual(general, t.findText("Privacy").?.x);
    try std.testing.expectApproxEqAbs(step, t.findText("Camera").?.x - t.findText("Apps").?.x, 0.5);
    // A branch in a group is where a row outside it would be.
    try std.testing.expectEqual(general, t.findText("Network").?.x);
    try std.testing.expectApproxEqAbs(general + step, t.findText("Wi-Fi").?.x, 0.5);
}

test "a branch's chevron folds and opens it without choosing it, and a click on it chooses it and opens it" {
    var s: Settings = .{};
    var t: ui.Tester = undefined;
    try startSettings(&s, &t);
    defer t.deinit();
    Settings.clickChevron(&t, "Privacy");
    try std.testing.expect(!s.privacy_open);
    try std.testing.expect(!t.hasText("Location"));
    try std.testing.expectEqualStrings("general", s.selected.?);
    try std.testing.expectEqual(@as(usize, 0), s.chosen);
    Settings.clickChevron(&t, "Privacy");
    try std.testing.expect(s.privacy_open);
    try std.testing.expect(t.hasText("Camera"));
    // Folded, a click on its label chooses it and opens it.
    s.privacy_open = false;
    t.settle(1);
    try clickRow(&t, "Privacy");
    try std.testing.expectEqualStrings("privacy", s.selected.?);
    try std.testing.expect(s.privacy_open);
    try std.testing.expect(t.hasText("Location"));
    // Open, a click chooses it and leaves it open.
    try clickRow(&t, "Location");
    try clickRow(&t, "Privacy");
    try std.testing.expectEqualStrings("privacy", s.selected.?);
    try std.testing.expect(s.privacy_open);
}

test "Left and Right fold, open and move between a branch and its rows, at each level" {
    var s: Settings = .{ .start_focused = true };
    var t: ui.Tester = undefined;
    try startSettings(&s, &t);
    defer t.deinit();
    try std.testing.expect(s.focused);
    // Down onto the branch chooses it, as a row; Left folds it.
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqualStrings("privacy", s.selected.?);
    t.key(.left);
    t.settle(1);
    try std.testing.expect(!s.privacy_open);
    // Down passes its folded rows, to the group's heading.
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqualStrings("privacy", s.selected.?);
    t.key(.left);
    t.settle(1);
    try std.testing.expect(!s.more_open);
    t.key(.up);
    t.settle(1);
    try std.testing.expectEqualStrings("privacy", s.selected.?);
    // Right opens it, and again goes to its first row.
    t.key(.right);
    t.settle(1);
    try std.testing.expect(s.privacy_open);
    try std.testing.expectEqualStrings("privacy", s.selected.?);
    t.key(.right);
    t.settle(1);
    try std.testing.expectEqualStrings("location", s.selected.?);
    t.key(.down);
    t.key(.right);
    t.settle(1);
    try std.testing.expectEqualStrings("camera", s.selected.?);
    // Left from a row goes to its branch; Left again folds it, and again
    // goes to the branch it is in.
    t.key(.left);
    t.settle(1);
    try std.testing.expectEqualStrings("apps", s.selected.?);
    t.key(.left);
    t.settle(1);
    try std.testing.expect(!s.apps_open);
    t.key(.left);
    t.settle(1);
    try std.testing.expectEqualStrings("privacy", s.selected.?);
    try std.testing.expect(s.privacy_open);
}

test "a folded branch the selected row is in shows it in the selection's tint" {
    var s: Settings = .{ .selected = "camera" };
    var t: ui.Tester = undefined;
    try startSettings(&s, &t);
    defer t.deinit();
    const tint = nanoui.kit.tokens(&t.ctx).primary;
    try std.testing.expect(!std.meta.eql(tint, Settings.labelColor(&t, "Apps")));
    s.apps_open = false;
    t.settle(1);
    try std.testing.expectEqual(tint, Settings.labelColor(&t, "Apps"));
    try std.testing.expect(!std.meta.eql(tint, Settings.labelColor(&t, "Privacy")));
    // Folded further out, the branch that shows takes the tint.
    s.privacy_open = false;
    t.settle(1);
    try std.testing.expectEqual(tint, Settings.labelColor(&t, "Privacy"));
    // Another row selected: no tint.
    s.selected = "general";
    t.settle(1);
    try std.testing.expect(!std.meta.eql(tint, Settings.labelColor(&t, "Privacy")));
}

test "a screen reader hears a branch as a row with its count and whether it is open" {
    var s: Settings = .{};
    var t: ui.Tester = undefined;
    try startSettings(&s, &t);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list = try elements(&t, arena.allocator());
    // General, Privacy, Location, Apps, Camera, Microphone, More, Network,
    // Wi-Fi: the chevrons aren't elements of their own.
    try std.testing.expectEqual(@as(usize, 9), list.len);
    try std.testing.expectEqualStrings("Privacy", list[1].label);
    try std.testing.expectEqual(ui.access.Role.tab, list[1].role);
    try std.testing.expectEqualStrings("2, expanded", list[1].value);
    try std.testing.expectEqualStrings("expanded", list[3].value);
    s.apps_open = false;
    t.settle(1);
    list = try elements(&t, arena.allocator());
    try std.testing.expectEqualStrings("collapsed", list[3].value);
}

test "a disabled branch isn't chosen, but still folds by its chevron and the keys" {
    var s: Settings = .{ .network_disabled = true };
    var t: ui.Tester = undefined;
    try startSettings(&s, &t);
    defer t.deinit();
    try clickRow(&t, "Network");
    try std.testing.expectEqualStrings("general", s.selected.?);
    Settings.clickChevron(&t, "Network");
    try std.testing.expect(!s.network_open);
    // The keys reach it, pass it by when choosing, and Enter opens it.
    t.key(.end);
    t.settle(1);
    try std.testing.expectEqualStrings("general", s.selected.?);
    t.key(.enter);
    t.settle(1);
    try std.testing.expect(s.network_open);
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqualStrings("wifi", s.selected.?);
}

/// Where the icon's slot of `row`, the row's first box, starts.
fn iconLeft(t: *ui.Tester, row: ui.access.Element) f32 {
    for (t.ctx.nodes.items) |node| if (node.id == row.id) {
        return t.ctx.rects.get(t.ctx.node(node.first_child).id).?.x;
    };
    unreachable;
}

test "icons only, a branch's rows aren't indented, and the keys fold it" {
    var s: Settings = .{ .icons_only = true, .start_focused = true };
    var t: ui.Tester = undefined;
    try startSettings(&s, &t);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const list = try elements(&t, arena.allocator());
    // General, Privacy and Camera: their icons start at one left.
    try std.testing.expectEqualStrings("Camera", list[4].label);
    for ([_]usize{ 1, 4 }) |i| try std.testing.expectEqual(iconLeft(&t, list[0]), iconLeft(&t, list[i]));
    s.icons_only = false;
    t.settle(1);
    try std.testing.expect(iconLeft(&t, list[4]) > iconLeft(&t, list[0]));
    s.icons_only = true;
    t.settle(1);
    t.key(.down);
    t.key(.left);
    t.settle(1);
    try std.testing.expectEqualStrings("privacy", s.selected.?);
    try std.testing.expect(!s.privacy_open);
    t.key(.right);
    t.settle(1);
    try std.testing.expect(s.privacy_open);
}

/// A docs site's sidebar: a fixed tree, its branches always open.
const Docs = struct {
    selected: ?[]const u8 = "intro",
    chosen: usize = 0,
    start_focused: bool = false,
    started: bool = false,

    fn view(d: *Docs, c: *ui.Context) void {
        const root = ui.div(c).column().w(220).h(400);
        defer root.end();
        if (d.start_focused and !d.started) c.focusNext(false);
        d.started = true;
        var sb = sidebar(c, "docs", d.selected, .{});
        sb.item("intro", "Introduction", .{ .icon = "doc" });
        if (sb.branch("guides", "Guides", .{ .icon = "folder", .count = 2 }, null)) |g| {
            sb.item("start", "Getting started", .{ .icon = "doc" });
            if (sb.branch("deploy", "Deploying", .{ .icon = "folder" }, null)) |g2| {
                sb.item("docker", "Docker", .{ .icon = "doc" });
                g2.end();
            }
            g.end();
        }
        sb.item("faq", "FAQ", .{ .icon = "doc" });
        if (sb.end()) |key| {
            d.selected = key;
            d.chosen += 1;
        }
    }
};

test "a fixed branch always shows its rows, indented, has no chevron, and a click only chooses it" {
    var d: Docs = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&d, Docs.view), .{ .width = 300, .height = 420 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(t.findText("Docker").?.x > t.findText("Getting started").?.x);
    try std.testing.expect(t.findText("Getting started").?.x > t.findText("Guides").?.x);
    // Where a chevron would be, a click chooses the branch.
    const r = t.findText("Deploying").?;
    t.click(203, r.y + r.h / 2);
    t.settle(1);
    try std.testing.expectEqualStrings("deploy", d.selected.?);
    try std.testing.expect(t.hasText("Docker"));
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const list = try elements(&t, arena.allocator());
    try std.testing.expectEqual(@as(usize, 6), list.len);
    try std.testing.expectEqualStrings("Guides", list[1].label);
    try std.testing.expectEqualStrings("2", list[1].value);
    try std.testing.expectEqualStrings("", list[3].value);
}

test "in a fixed tree, Right goes into a branch and Left out of it, folding nothing" {
    var d: Docs = .{ .start_focused = true };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&d, Docs.view), .{ .width = 300, .height = 420 });
    defer t.deinit();
    t.settle(1);
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqualStrings("guides", d.selected.?);
    // Left on a branch outside any goes nowhere, and folds nothing.
    t.key(.left);
    t.settle(1);
    try std.testing.expectEqualStrings("guides", d.selected.?);
    try std.testing.expect(t.hasText("Docker"));
    t.key(.right);
    t.settle(1);
    try std.testing.expectEqualStrings("start", d.selected.?);
    t.key(.down);
    t.key(.right);
    t.settle(1);
    try std.testing.expectEqualStrings("docker", d.selected.?);
    // Right on a row goes nowhere.
    t.key(.right);
    t.settle(1);
    try std.testing.expectEqualStrings("docker", d.selected.?);
    t.key(.left);
    t.settle(1);
    try std.testing.expectEqualStrings("deploy", d.selected.?);
    t.key(.left);
    t.settle(1);
    try std.testing.expectEqualStrings("guides", d.selected.?);
    t.key(.end);
    t.settle(1);
    try std.testing.expectEqualStrings("faq", d.selected.?);
}
