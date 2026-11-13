//! One choice out of a few, as one stop for Tab: what each option is
//! (`Choice`), the keys that move the choice, and what a click on an
//! option does. Shared by `segmented` and `tabStrip`; not a control of
//! its own.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const focus = @import("focus.zig");
const parts = @import("parts.zig");

/// An option of a segmented group or a tab strip.
pub const Choice = struct {
    label: []const u8,
    /// An SF Symbol before the label.
    icon: []const u8 = "",
    /// How many it holds, in a badge after the label; null for none.
    count: ?usize = null,
    /// A spinner in the count's place, for a count still loading: it
    /// never reads as 0.
    loading: bool = false,
    /// The count in the danger color, when above 0.
    alert: bool = false,
    /// Dimmed, not chosen by a click, and passed by the keys.
    disabled: bool = false,
    /// Shown when the pointer rests on it.
    tooltip: []const u8 = "",
};

/// The keys that move the choice this frame, while the control has the
/// keyboard: the arrows, Home and End. Taken also where nanoui offers them
/// first as shortcuts; Enter is left for the app.
pub const Keys = struct {
    /// -1 to the one before, 1 to the one after.
    step: i2 = 0,
    first: bool = false,
    last: bool = false,

    pub fn read(c: *ui.Context) Keys {
        const keys = [_]focus.Key{ .left, .right, .up, .down, .home, .end };
        focus.keysOf(c, &keys);
        return switch (c.input.key orelse return .{}) {
            .left, .up => .{ .step = -1 },
            .right, .down => .{ .step = 1 },
            .home => .{ .first = true },
            .end => .{ .last = true },
            else => .{},
        };
    }

    pub fn any(k: Keys) bool {
        return k.step != 0 or k.first or k.last;
    }

    /// The option the keys move `at` to among `choices`, passing disabled
    /// ones; `at` when there is none that way.
    pub fn moved(k: Keys, at: usize, choices: []const Choice) usize {
        if (k.first) return seek(choices, null, 1) orelse at;
        if (k.last) return seek(choices, choices.len, -1) orelse at;
        return seek(choices, at, k.step) orelse at;
    }
};

/// The first option that isn't disabled from `from` (exclusive; null:
/// before the first, `choices.len`: after the last) in direction `dir`.
fn seek(choices: []const Choice, from: ?usize, dir: i2) ?usize {
    var i: isize = if (from) |f| @as(isize, @intCast(f)) + dir else 0;
    while (i >= 0 and i < choices.len) : (i += dir) {
        if (!choices[@intCast(i)].disabled) return @intCast(i);
    }
    return null;
}

/// A choice kept as a value of the enum `E` (`segmentedOf`,
/// `tabStripOf`): its values in their order, and a value's index.
pub fn Typed(comptime E: type) type {
    return struct {
        pub const all = std.enums.values(E);
        pub const count = all.len;

        pub fn index(value: E) usize {
            return std.mem.indexOfScalar(E, all, value) orelse 0;
        }
    };
}

/// A choice group taking the keyboard: the keys choose while it has it,
/// and a click on an option chooses it and gives the group the keyboard.
/// The chosen option, a disabled one and every one while the group is
/// disabled show no hand. An index past the last option is the last.
pub const Group = struct {
    /// The group's own interaction: `focused` while it has the keyboard.
    own: ui.Interaction,
    index: *usize,
    choices: []const Choice,
    disabled: bool,
    changed: bool = false,

    /// Takes the keyboard for `box`, open now, unless disabled or empty.
    pub fn take(c: *ui.Context, box: ui.Div, index: *usize, choices: []const Choice, disabled: bool) Group {
        if (choices.len > 0 and index.* >= choices.len) index.* = choices.len - 1;
        return .{ .own = focus.takeIf(c, box, !disabled and choices.len > 0), .index = index, .choices = choices, .disabled = disabled };
    }

    /// The group's ring shows now.
    pub fn ringed(g: *const Group, c: *ui.Context) bool {
        return focus.showRing(c, g.own.focused);
    }

    /// Option `i`'s interaction, its box just made, with its tooltip.
    pub fn interact(g: *const Group, c: *ui.Context, box: ui.Div, i: usize) ui.Interaction {
        const off = g.disabled or g.choices[i].disabled;
        const it = if (g.index.* == i or off) parts.still(c, box) else box.interaction();
        if (g.choices[i].tooltip.len > 0) kit.tooltip(c, it, g.choices[i].tooltip, .{});
        return it;
    }

    /// Chooses `i` if `hit` says it was clicked, and gives the group the
    /// keyboard, drawn again at once.
    pub fn click(g: *Group, c: *ui.Context, i: usize, hit: ui.Interaction) void {
        if (g.disabled or g.choices[i].disabled or !hit.clicked) return;
        if (c.focus != g.own.id) c.changed = true;
        c.focus = g.own.id;
        if (g.index.* == i) return;
        g.index.* = i;
        g.changed = true;
    }

    /// Moves the choice as the keys ask, while the group has the keyboard:
    /// before the options are drawn, for them to show it. The keys it
    /// moves by are used up, even at an end.
    pub fn keys(g: *Group, c: *ui.Context) void {
        if (!g.own.focused or g.disabled or g.choices.len == 0) return;
        const k = Keys.read(c);
        if (!k.any()) return;
        c.input.key = null;
        const to = k.moved(g.index.*, g.choices);
        if (to == g.index.*) return;
        g.index.* = to;
        g.changed = true;
    }

    /// Whether the choice changed this frame, which then shows in it.
    pub fn end(g: *Group, c: *ui.Context) bool {
        if (g.changed) c.changed = true;
        return g.changed;
    }
};

/// What a screen reader says of an option's count: `loading_text` while
/// it loads, the figure, or nothing.
pub fn countText(c: *ui.Context, choice: Choice, loading_text: []const u8) []const u8 {
    if (choice.loading) return loading_text;
    return if (choice.count) |n| c.print("{d}", .{n}) else "";
}

/// An option's count as a badge: the accent on the chosen one (`on`), the
/// danger color when it alerts, plain and outlined otherwise; a spinner
/// while it loads. Past `max_count`, "999+".
pub fn badge(c: *ui.Context, choice: Choice, on: bool, max_count: usize, k: f32) void {
    const t = kit.tokens(c);
    const n = choice.count orelse 0;
    const alert = choice.alert and n > 0 and !choice.loading;
    const fill = if (alert) t.danger else if (on) t.primary else t.surface_hover;
    const ink = if (alert or on) t.primary_foreground else t.muted;
    var b = ui.div(c).row().itemsCenter().justifyCenter().minW(20 * k).px(7 * k).py(1 * k).roundedFull().bg(fill);
    if (!on and !alert) b = b.border(t.border);
    defer b.end();
    if (choice.loading) return kit.spinner(c, .{ .size = 11 * k, .color = if (on) t.primary_foreground else t.primary });
    ui.text(c, if (n > max_count) c.print("{d}+", .{max_count}) else c.print("{d}", .{n}), .{ .size = kit.Size.xs.text(), .weight = .semibold, .color = ink });
}

test "the keys move to the next option that isn't disabled, and stay at an end" {
    const choices = [_]Choice{ .{ .label = "a" }, .{ .label = "b", .disabled = true }, .{ .label = "c" }, .{ .label = "d", .disabled = true } };
    try std.testing.expectEqual(@as(usize, 2), (Keys{ .step = 1 }).moved(0, &choices));
    try std.testing.expectEqual(@as(usize, 2), (Keys{ .step = 1 }).moved(2, &choices));
    try std.testing.expectEqual(@as(usize, 0), (Keys{ .step = -1 }).moved(2, &choices));
    try std.testing.expectEqual(@as(usize, 2), (Keys{ .last = true }).moved(0, &choices));
    try std.testing.expectEqual(@as(usize, 0), (Keys{ .first = true }).moved(2, &choices));
}
