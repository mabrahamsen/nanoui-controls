//! A segmented control: one choice out of a few, as one bordered group,
//! the chosen option filled with the accent. nanoui's `ui.segmented`,
//! with the keyboard (one stop for Tab, the arrows choosing), counts,
//! icons, options disabled on their own, and `scale`.
//!
//!     const ranges = [_]controls.Choice{ .{ .label = "Today" }, .{ .label = "Week", .count = 12 } };
//!     if (controls.segmented(c, &ranges, &s.range, .{ .label = "Range" })) s.refilter();
//!
//! `segmentedOf` keeps the choice as a value of an enum, an option for
//! each of its values in their order.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const focus = @import("focus.zig");
const choices_mod = @import("choices.zig");
const Choice = choices_mod.Choice;

pub const Options = struct {
    /// What the group is, said by a screen reader after each option.
    label: []const u8 = "",
    /// The labels' size, as the kit's; `text_size` in points, over it.
    size: kit.Size = .sm,
    text_size: ?f32 = null,
    /// The group's fill and border; null takes the theme's background and
    /// border.
    background: ?ui.Color = null,
    border: ?ui.Color = null,
    /// An option's padding across and down, in points before `scale`.
    px: f32 = 12,
    py: f32 = 5,
    /// A count past it shows as "999+".
    max_count: usize = 999,
    /// What a screen reader says of a count still loading.
    loading_text: []const u8 = "loading",
    /// Dimmed, it doesn't change or take the keyboard, and is said to be
    /// unavailable.
    disabled: bool = false,
    scale: f32 = 1,
};

/// The options `choices`, `index` the one chosen; true when a click or a
/// key changed it.
pub fn segmented(c: *ui.Context, choices: []const Choice, index: *usize, opts: Options) bool {
    const k = opts.scale;
    const t = kit.tokens(c);
    const size = opts.text_size orelse opts.size.text();
    var group = ui.div(c).row().itemsCenter().gap(2 * k).p(2 * k).rounded(9 * k).bg(opts.background orelse t.background).border(opts.border orelse t.border);
    if (opts.disabled) group = group.opacity(focus.dimmed);
    defer group.end();
    var g = choices_mod.Group.take(c, group, index, choices, opts.disabled);
    if (g.ringed(c)) _ = group.border(focus.ring(c)).borderW(focus.ringWidth(c));
    g.keys(c);
    for (choices, 0..) |choice, i| {
        const on = index.* == i;
        const off = opts.disabled or choice.disabled;
        // Keyed by place: labels may repeat, or be empty.
        ui.keyInt(c, i);
        var seg = ui.div(c).row().itemsCenter().gap(6 * k).px(opts.px * k).py(opts.py * k).rounded(7 * k).control();
        seg = if (on) seg.bg(t.primary) else if (off) seg else seg.hover(t.surface_hover);
        if (choice.disabled and !opts.disabled) seg = seg.opacity(focus.dimmed);
        const hit = g.interact(c, seg, i);
        {
            defer seg.end();
            const ink = if (on) t.primary_foreground else t.muted;
            if (choice.icon.len > 0) ui.icon(c, choice.icon, .{ .size = size * k, .color = ink });
            ui.text(c, choice.label, .{ .size = size, .weight = if (on) .semibold else .regular, .color = ink });
            if (choice.count != null or choice.loading) choices_mod.badge(c, choice, false, opts.max_count, k);
        }
        ui.access.describe(c, seg.index, .{ .role = .radio_button, .label = choice.label, .value = choices_mod.countText(c, choice, opts.loading_text), .hint = opts.label, .selected = on, .enabled = !off });
        g.click(c, i, hit);
    }
    return g.end(c);
}

/// As `segmented`, the choice kept as `value`, a value of the enum `E`:
/// `choices` has an option for each of its values, in their order. True
/// when a click or a key changed `value`.
pub fn segmentedOf(c: *ui.Context, comptime E: type, value: *E, choices: *const [choices_mod.Typed(E).count]Choice, opts: Options) bool {
    const T = choices_mod.Typed(E);
    var at = T.index(value.*);
    if (!segmented(c, choices, &at, opts)) return false;
    value.* = T.all[at];
    return true;
}

test {
    _ = @import("segmented_tests.zig");
}
