//! The sidebar's tests of where its keys start, where they go back to,
//! and typing to move to a row.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const helpers = @import("sidebar_tests.zig");
const Mail = helpers.Mail;
const start = helpers.start;

test "with nothing selected, the keys start at the first row, and the keys they take are their own" {
    var m: Mail = .{ .selected = null, .start_focused = true };
    var t: ui.Tester = undefined;
    try start(&m, &t);
    defer t.deinit();
    // The first row shows the keys are on it.
    var ringed = false;
    for (t.ctx.nodes.items) |node| if (node.style.border != null) {
        ringed = true;
    };
    try std.testing.expect(ringed);
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqualStrings("inbox", m.selected.?);
    t.key(.end);
    t.key(.home);
    t.key(.enter);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 0), m.leaked);
}

test "when the keys' row is folded away, they go back to the selected row" {
    var m: Mail = .{ .selected = "sent", .start_focused = true, .choose_on_enter = true };
    var t: ui.Tester = undefined;
    try start(&m, &t);
    defer t.deinit();
    // To "travel", then fold its group from outside: the keys go back to
    // the selected row, "sent", and Down from there is the group's
    // heading, which Enter opens.
    t.key(.end);
    t.settle(1);
    m.folders_open = false;
    t.settle(1);
    t.key(.down);
    t.key(.enter);
    t.settle(1);
    try std.testing.expect(m.folders_open);
    try std.testing.expectEqualStrings("sent", m.selected.?);
}

test "typing a row's first letters moves the keys to it, and a letter again to the next" {
    var m: Mail = .{ .start_focused = true };
    var t: ui.Tester = undefined;
    try start(&m, &t);
    defer t.deinit();
    t.typeText("se");
    t.settle(1);
    try std.testing.expectEqualStrings("sent", m.selected.?);
    // After a pause, a new start.
    t.advance(1.5);
    t.typeText("w");
    t.settle(1);
    try std.testing.expectEqualStrings("work", m.selected.?);
    // "f", then "f" again: "family", then on past it to the next row that
    // begins with "f", the folders' heading, which isn't chosen.
    t.advance(1.5);
    t.typeText("f");
    t.settle(1);
    try std.testing.expectEqualStrings("family", m.selected.?);
    t.typeText("f");
    t.settle(1);
    try std.testing.expectEqualStrings("family", m.selected.?);
    // Down from the heading: its first row.
    t.key(.down);
    t.settle(1);
    try std.testing.expectEqualStrings("work", m.selected.?);
}
