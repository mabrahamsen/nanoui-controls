//! The controls' own buttons: the kit's, which Tab passes by, made
//! focusable and named. Tab reaches one (not a disabled one), Enter or
//! Space presses it, its ring shows as `setFocusRingShows` says, and a
//! screen reader hears its words, not its symbol. Not a control of its
//! own: they go once the kit's buttons take the keyboard and a name.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const focus = @import("focus.zig");

pub const Options = struct {
    variant: @FieldType(kit.ButtonOptions, "variant") = .default,
    size: kit.Size = .sm,
    /// An SF Symbol before the title, or alone in an `iconButton`.
    icon: []const u8 = "",
    /// What a screen reader calls it; empty takes its title, or else its
    /// `tooltip`.
    label: []const u8 = "",
    /// Shown when the pointer rests on it.
    tooltip: []const u8 = "",
    disabled: bool = false,
};

/// A button reading `title`; its interaction, `clicked` by a click, or by
/// Enter or Space while it has the keyboard.
pub fn button(c: *ui.Context, title: []const u8, opts: Options) ui.Interaction {
    // The kit's button is the next box: its index, to make it focusable.
    const index: u32 = @intCast(c.nodes.items.len);
    const was = c.focus;
    const o: kit.ButtonOptions = .{ .variant = opts.variant, .size = opts.size, .icon = opts.icon, .disabled = opts.disabled, .tooltip = opts.tooltip };
    var it = if (title.len == 0) kit.iconButton(c, opts.icon, o) else kit.button(c, title, o);
    // A press on a box that isn't focusable takes the keyboard from where
    // it was; this one is, and says itself where the keyboard goes.
    c.focus = was;
    if (index >= c.nodes.items.len or c.nodes.items[index].id != it.id) return it;
    const name = if (opts.label.len > 0) opts.label else if (title.len > 0) title else opts.tooltip;
    ui.access.describe(c, index, .{ .role = .button, .label = name, .enabled = !opts.disabled });
    if (opts.disabled) return it;
    const own = focus.button(c, index, true);
    if (focus.showRing(c, own.focused)) {
        const n = c.node(index);
        n.style.border = focus.ring(c);
        n.style.border_width = focus.ringWidth(c);
    }
    if (own.clicked and !it.clicked) c.changed = true;
    it.clicked = it.clicked or own.clicked;
    it.focused = own.focused;
    return it;
}

/// A square button showing only `icon`. Name it with `label` or a
/// `tooltip`.
pub fn iconButton(c: *ui.Context, icon: []const u8, opts: Options) ui.Interaction {
    var o = opts;
    o.icon = icon;
    if (o.variant == .default) o.variant = .ghost;
    return button(c, "", o);
}

/// A ✕, `text` in its tooltip and its name to a screen reader: what
/// closes a callout or a toast.
pub fn closeButton(c: *ui.Context, text: []const u8) ui.Interaction {
    return iconButton(c, "xmark", .{ .size = .xs, .label = text, .tooltip = text });
}

test "a button is reached by Tab, pressed with Enter or Space, and named by its words" {
    const T = struct {
        clicked: usize = 0,
        disabled: bool = false,
        fn view(x: *@This(), c: *ui.Context) void {
            const row = ui.div(c).row().gap(8).p(8);
            defer row.end();
            if (iconButton(c, "eye", .{ .label = "Show password", .disabled = x.disabled }).clicked) x.clicked += 1;
            if (closeButton(c, "Close").clicked) x.clicked += 10;
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 200, .height = 60 });
    defer t.deinit();
    t.settle(1);
    t.key(.tab);
    t.key(.enter);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.clicked);
    t.key(.tab);
    try std.testing.expect(t.shortcut(.{ .key = ' ' }));
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 11), x.clicked);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &list);
    var named: usize = 0;
    for (list.items) |e| if (std.mem.eql(u8, e.label, "Show password") or std.mem.eql(u8, e.label, "Close")) {
        named += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), named);
    // Disabled, Tab passes it by, to the ✕.
    x.disabled = true;
    t.ctx.focus = 0;
    t.settle(1);
    t.key(.tab);
    t.key(.enter);
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 21), x.clicked);
}

test "a click on a button doesn't count twice, and with .keyboard leaves the keyboard where it was" {
    const T = struct {
        buf: ui.TextBuffer = .{},
        clicked: usize = 0,
        fn view(x: *@This(), c: *ui.Context) void {
            const row = ui.div(c).row().gap(8).p(8);
            defer row.end();
            _ = ui.textField(c, &x.buf, .{ .width = .{ .px = 120 } });
            if (button(c, "Go", .{}).clicked) x.clicked += 1;
        }
    };
    focus.setRingShows(.keyboard);
    defer focus.setRingShows(.focused);
    var x: T = .{};
    defer x.buf.deinit();
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 400, .height = 60 });
    defer t.deinit();
    t.settle(1);
    t.key(.tab);
    t.settle(1);
    const field = t.ctx.focus;
    try std.testing.expect(field != 0);
    try t.clickText("Go");
    t.settle(1);
    try std.testing.expectEqual(@as(usize, 1), x.clicked);
    try std.testing.expectEqual(field, t.ctx.focus);
}
