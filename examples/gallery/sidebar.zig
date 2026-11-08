//! The gallery's sidebar settings: the sidebar's options in a form, which
//! the gallery's own sidebar takes as they change, so each can be tried on
//! it: its size, its tint, a background behind its rows, the gap between
//! them and its scale; whether the keys choose as they go or only on
//! Enter; icons only; whether "Every chart" is a branch that folds or a
//! fixed one; and whether the Monitor's alerts are a pill.
const nanoui = @import("nanoui");
const controls = @import("nanoui_controls");
const ui = nanoui.ui;
const kit = nanoui.kit;

pub const Tuning = struct {
    /// Into `sizes`.
    size: ?usize = 1,
    /// Into the tints `view` offers, the first the theme's accent.
    tint: ?usize = 0,
    background: bool = false,
    gap: f64 = 2,
    scale: f64 = 1,
    choose_on_enter: bool = false,
    icons_only: bool = false,
    /// "Every chart" is a fixed branch, always open, not one that folds.
    fixed: bool = false,
    pill: bool = true,

    const sizes = [_]kit.Size{ .xs, .sm, .md, .lg };
    const size_names = [_][]const u8{ "Extra small", "Small", "Medium", "Large" };
    const tints = [_]controls.Swatch{
        .{ .color = .hex(0x000000), .label = "Accent" },
        .{ .color = .hex(0xef4444), .label = "Red" },
        .{ .color = .hex(0xf59e0b), .label = "Amber" },
        .{ .color = .hex(0x22c55e), .label = "Green" },
        .{ .color = .hex(0xa855f7), .label = "Purple" },
    };

    /// The sidebar's options as set here; `narrowed` when the splitter has
    /// made it too narrow for its labels.
    pub fn options(s: *const Tuning, c: *ui.Context, narrowed: bool) controls.SidebarOptions {
        const t = kit.tokens(c);
        const tint = s.tint orelse 0;
        return .{
            .size = sizes[s.size orelse 1],
            .color = if (tint == 0) null else tints[tint].color,
            .background = if (s.background) t.foreground.alpha(0.04) else null,
            .gap = @floatCast(s.gap),
            .scale = @floatCast(s.scale),
            .choose_on_enter = s.choose_on_enter,
            .icons_only = narrowed or s.icons_only,
        };
    }

    pub fn view(s: *Tuning, c: *ui.Context) void {
        const scroll = ui.div(c).column().sizeFull().scrollY();
        defer scroll.end();
        const root = ui.div(c).column().wFull().maxW(560).p(16).gap(12);
        defer root.end();
        ui.text(c, "Sidebar", .{ .size = 16, .weight = .semibold });
        var f = controls.form(c, .{ .row_lines = true, .grouped = true, .control_align = .end, .size = .sm, .stack_below = 420 });
        f.heading("Look", .{ .description = "The sidebar at the left takes these as they change." });
        {
            const r = f.row("Size", .{ .hint = "As the kit's controls at this size." });
            _ = kit.select(c, "sidebar-size", &size_names, &s.size, .{ .width = 140 });
            r.end();
        }
        {
            // The first swatch is the theme's accent, as the sidebar takes
            // it without a tint of its own.
            var offered = tints;
            offered[0].color = kit.tokens(c).primary;
            const r = f.row("Tint", .{ .hint = tints[s.tint orelse 0].label });
            _ = controls.swatches(c, &offered, &s.tint, .{ .size = .sm });
            r.end();
        }
        {
            const r = f.row("Row background", .{ .hint = "Behind each row not selected." });
            _ = ui.toggle(c, "", &s.background);
            r.end();
        }
        {
            const r = f.row("Gap", .{ .hint = "Between the rows, in points." });
            _ = kit.numberInput(c, &s.gap, .{ .min = 0, .max = 12, .width = 120 });
            r.end();
        }
        {
            const r = f.row("Scale", .{ .hint = "Its lengths, for an app that zooms its layout." });
            _ = kit.numberInput(c, &s.scale, .{ .min = 0.75, .max = 1.5, .step = 0.25, .width = 120 });
            r.end();
        }
        {
            const r = f.row("Icons only", .{ .hint = "Also when the splitter makes it narrow." });
            _ = ui.toggle(c, "", &s.icons_only);
            r.end();
        }
        {
            const r = f.row("Alerts as a pill", .{ .hint = "The Monitor's count." });
            _ = ui.toggle(c, "", &s.pill);
            r.end();
        }
        f.heading("Behavior", .{});
        {
            const r = f.row("Choose on Enter", .{ .hint = "The keys move a highlight; Enter or Space chooses." });
            _ = ui.toggle(c, "", &s.choose_on_enter);
            r.end();
        }
        {
            const r = f.row("Fixed branches", .{ .hint = "\"Every chart\" always open, without a chevron." });
            _ = ui.toggle(c, "", &s.fixed);
            r.end();
        }
        {
            const r = f.row("Defaults", .{});
            if (kit.button(c, "Reset", .{ .size = .sm }).clicked) s.* = .{};
            r.end();
        }
        f.end();
    }
};
