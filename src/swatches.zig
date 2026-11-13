//! Swatches: a row of round colors to pick one from, each named in a
//! tooltip and to a screen reader. The chosen one, kept by the caller as
//! the kit's radio group keeps its option, is ringed. A click chooses one;
//! so do Left, Right, Home and End while the row has the keyboard, which
//! it takes as the grid does: from a click, from Tab, or from
//! `c.focusNext` just before it.
//!
//!     const colors = [_]controls.Swatch{ .{ .color = red, .label = "Red" }, .{ .color = blue, .label = "Blue" } };
//!     if (controls.swatches(c, &colors, &chosen, .{})) apply(colors[chosen.?].color);
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const focus = @import("focus.zig");
const parts = @import("parts.zig");

pub const Swatch = struct {
    color: ui.Color,
    /// What it is called, in its tooltip and to a screen reader.
    label: []const u8,
};

pub const Options = struct {
    /// The swatches' size, in step with the kit's controls at it.
    size: kit.Size = .md,
    /// Between the swatches, in points before `scale`.
    gap: f32 = 6,
    /// Each swatch's edge; null takes the theme's border.
    border: ?ui.Color = null,
    /// The chosen one's ring; null takes the theme's text color, which
    /// shows on any swatch. While the row has the keyboard, the ring is
    /// the accent.
    selected_border: ?ui.Color = null,
    /// Each named in a tooltip under the pointer.
    tooltips: bool = true,
    /// Shown dimmed, it takes no clicks or keys, and a screen reader says
    /// it is disabled.
    disabled: bool = false,
    /// What the row is for ("Accent color"), said after each swatch's
    /// name. nanoui's screen-reader tree is flat: a box described as the
    /// row would hide the swatches in it.
    label: []const u8 = "",
    /// Multiplies its lengths, for an app that zooms its layout along with
    /// `c.setZoom`, as the grid's does.
    scale: f32 = 1,
};

/// Draws `colors` in a row, `selected.*` the one chosen, if any; true
/// when a click or a key chose another.
pub fn swatches(c: *ui.Context, colors: []const Swatch, selected: *?usize, opts: Options) bool {
    const k = opts.scale;
    const t = kit.tokens(c);
    // Unkeyed, so `c.focusNext` just before names it.
    var row = ui.div(c).row().gap(opts.gap * k).itemsCenter();
    if (opts.disabled) row = row.opacity(focus.dimmed);
    defer row.end();
    // Without colors, or disabled, it doesn't take Tab.
    const own = focus.takeIf(c, row, !opts.disabled and colors.len > 0);
    const before = selected.*;
    // An index past the colors is none chosen.
    const at: ?usize = if (selected.*) |i| (if (i < colors.len) i else null) else null;
    if (own.focused and colors.len > 0) focus.keysOf(c, &.{ .left, .right, .up, .down, .home, .end });
    if (own.focused and colors.len > 0) if (c.input.key) |key| {
        switch (key) {
            // Up and Down as Left and Right, as a radio group's keys.
            .left, .up => selected.* = if (at) |i| i -| 1 else 0,
            .right, .down => selected.* = if (at) |i| @min(i + 1, colors.len - 1) else 0,
            .home => selected.* = 0,
            .end => selected.* = colors.len - 1,
            else => {},
        }
        // Used up, even at an end, so a control after it doesn't take it
        // too, as the grid's keys are.
        switch (key) {
            .left, .right, .up, .down, .home, .end => c.input.key = null,
            else => {},
        }
    };
    const d = @round(opts.size.height() * 0.65) * k;
    // None chosen, as the keys left it: nothing, or an index past the
    // colors.
    const none = if (selected.*) |i| i >= colors.len else true;
    for (colors, 0..) |sw, i| {
        const chosen = selected.* == i;
        // With the keyboard and nothing chosen, the first is where the
        // keys start.
        const keyed = focus.showRing(c, own.focused);
        const ringed = chosen or (keyed and none and i == 0);
        const edge = if (ringed and keyed) focus.ringIn(c, t.primary) else if (chosen) opts.selected_border orelse t.foreground else opts.border orelse t.border;
        var dot = ui.div(c).w(d).h(d).roundedFull().bg(sw.color).border(edge);
        if (ringed) dot = dot.borderW(2 * k);
        defer dot.end();
        var it = if (opts.disabled) parts.still(c, dot) else dot.interaction();
        if (opts.disabled) it.clicked = false else if (it.hovered) c.cursor_hand = true;
        if (it.clicked) {
            selected.* = i;
            // Taking the keyboard shows in the ring, drawn again at once.
            if (c.focus != own.id) c.changed = true;
            c.focus = own.id;
        }
        if (opts.tooltips) kit.tooltip(c, it, sw.label, .{});
        ui.access.describe(c, dot.index, .{ .role = .radio_button, .label = sw.label, .hint = opts.label, .selected = chosen, .enabled = !opts.disabled });
    }
    const changed = selected.* != before;
    if (changed) c.changed = true;
    return changed;
}

const palette = [_]Swatch{
    .{ .color = .hex(0xef4444), .label = "Red" },
    .{ .color = .hex(0xf59e0b), .label = "Amber" },
    .{ .color = .hex(0x22c55e), .label = "Green" },
    .{ .color = .hex(0x3b82f6), .label = "Blue" },
};

const Picker = struct {
    chosen: ?usize = null,
    changes: usize = 0,
    /// Changes that set `c.changed`, as the kit's controls do.
    marked: usize = 0,
    /// Frames that set `c.changed` at all.
    redrawn: usize = 0,
    /// A key was left for the controls after the swatches.
    key_left: bool = false,
    fn view(p: *Picker, c: *ui.Context) void {
        c.changed = false;
        if (swatches(c, &palette, &p.chosen, .{})) {
            p.changes += 1;
            if (c.changed) p.marked += 1;
        }
        if (c.changed) p.redrawn += 1;
        if (c.input.key != null) p.key_left = true;
    }
    /// The middle of swatch `i`: 22 across, with gaps of 6.
    fn at(i: usize) f32 {
        return @as(f32, @floatFromInt(i)) * 28 + 11;
    }
};

test "a click chooses a swatch, and then the keys move from it" {
    var p: Picker = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Picker.view), .{ .width = 300, .height = 60 });
    defer t.deinit();
    t.settle(1);
    // Without the keyboard, the keys are someone else's.
    t.key(.right);
    try std.testing.expectEqual(@as(?usize, null), p.chosen);
    t.click(Picker.at(2), 11);
    try std.testing.expectEqual(@as(?usize, 2), p.chosen);
    try std.testing.expectEqual(@as(usize, 1), p.changes);
    // The chosen one again changes nothing.
    t.click(Picker.at(2), 11);
    try std.testing.expectEqual(@as(usize, 1), p.changes);
    t.key(.right);
    try std.testing.expectEqual(@as(?usize, 3), p.chosen);
    t.key(.right);
    try std.testing.expectEqual(@as(?usize, 3), p.chosen);
    t.key(.home);
    try std.testing.expectEqual(@as(?usize, 0), p.chosen);
    t.key(.left);
    try std.testing.expectEqual(@as(?usize, 0), p.chosen);
    t.key(.end);
    try std.testing.expectEqual(@as(?usize, 3), p.chosen);
    try std.testing.expectEqual(@as(usize, 4), p.changes);
    try std.testing.expectEqual(p.changes, p.marked);
}

test "a click on the chosen swatch takes the keyboard, and draws its ring at once" {
    var p: Picker = .{ .chosen = 2 };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Picker.view), .{ .width = 300, .height = 60 });
    defer t.deinit();
    t.settle(1);
    t.click(Picker.at(2), 11);
    try std.testing.expectEqual(@as(usize, 0), p.changes);
    try std.testing.expectEqual(@as(usize, 1), p.redrawn);
}

test "the keys the swatches take are used up, even at an end" {
    var p: Picker = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Picker.view), .{ .width = 300, .height = 60 });
    defer t.deinit();
    t.settle(1);
    t.click(Picker.at(0), 11);
    t.key(.left);
    t.key(.home);
    try std.testing.expect(!p.key_left);
    // Offered first as a shortcut, as the Mac offers it, End is its own.
    try std.testing.expect(t.shortcut(.{ .key = ui.Shortcut.end }));
    try std.testing.expectEqual(@as(?usize, 3), p.chosen);
    // A key it doesn't move by is left for what comes after it.
    t.key(.enter);
    try std.testing.expect(p.key_left);
}

test "swatches take the keyboard from Tab, and the first key chooses the first" {
    var p: Picker = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Picker.view), .{ .width = 300, .height = 60 });
    defer t.deinit();
    t.settle(1);
    t.key(.tab);
    t.settle(1);
    t.key(.right);
    try std.testing.expectEqual(@as(?usize, 0), p.chosen);
}

test "with the keyboard and a chosen index past the colors, the first swatch shows where the keys start" {
    const T = struct {
        chosen: ?usize = 9,
        fn view(x: *@This(), c: *ui.Context) void {
            if (c.frame == 0) c.focusNext(false);
            _ = swatches(c, &palette, &x.chosen, .{});
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 60 });
    defer t.deinit();
    t.settle(1);
    const primary = nanoui.kit.tokens(&t.ctx).primary;
    var ringed: usize = 0;
    for (t.ctx.nodes.items) |node| if (node.style.border) |b| if (std.meta.eql(b, primary)) {
        ringed += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), ringed);
}

test "each swatch is named in a tooltip and to a screen reader, the chosen one selected" {
    var p: Picker = .{ .chosen = 1 };
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&p, Picker.view), .{ .width = 300, .height = 80 });
    defer t.deinit();
    t.settle(1);
    try std.testing.expect(!t.hasText("Blue"));
    t.moveTo(Picker.at(3), 11);
    t.settle(2);
    try std.testing.expect(t.hasText("Blue"));
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    var radios: usize = 0;
    for (list.items) |e| if (e.role == .radio_button) {
        radios += 1;
        try std.testing.expectEqual(std.mem.eql(u8, e.label, "Amber"), e.selected);
    };
    try std.testing.expectEqual(palette.len, radios);
}

test "disabled swatches take no clicks or keys, and none at all don't take Tab" {
    const T = struct {
        chosen: ?usize = null,
        empty: bool = false,
        field: ui.TextBuffer = .{},
        field_focused: bool = false,
        fn view(x: *@This(), c: *ui.Context) void {
            const root = ui.div(c).column();
            defer root.end();
            _ = swatches(c, if (x.empty) &.{} else &palette, &x.chosen, .{ .disabled = !x.empty });
            x.field_focused = ui.textField(c, &x.field, .{}).focused;
        }
    };
    var x: T = .{};
    defer x.field.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 100 });
    defer t.deinit();
    t.settle(1);
    t.click(Picker.at(2), 11);
    t.settle(1);
    try std.testing.expectEqual(@as(?usize, null), x.chosen);
    // Tab passes them by, to the field.
    t.key(.tab);
    t.settle(1);
    try std.testing.expect(x.field_focused);
    x.empty = true;
    t.ctx.focus = 0;
    t.settle(1);
    t.key(.tab);
    t.settle(1);
    try std.testing.expect(x.field_focused);
}

test "Up and Down move as Left and Right, and the row's label is said with each swatch" {
    const T = struct {
        chosen: ?usize = 1,
        fn view(x: *@This(), c: *ui.Context) void {
            if (c.frame == 0) c.focusNext(false);
            _ = swatches(c, &palette, &x.chosen, .{ .label = "Accent color" });
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 300, .height = 60 });
    defer t.deinit();
    t.settle(1);
    t.key(.down);
    try std.testing.expectEqual(@as(?usize, 2), x.chosen);
    t.key(.up);
    t.key(.up);
    try std.testing.expectEqual(@as(?usize, 0), x.chosen);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    try std.testing.expectEqualStrings("Accent color", list.items[0].hint);
}
