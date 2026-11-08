//! The gallery's form: a settings pane of the kit's controls in rows, a
//! row of swatches to pick a color from, and properties to read. Leave
//! the name empty to see an error in place of its hint; rest on the ⓘ by
//! "Keep latest" for more; switch off backups to dim the rows that
//! depend on them; open "Advanced", which folds; click "Repository",
//! which leads somewhere. The host and the version can be selected and
//! copied, and the path, cut short, shows whole in a tooltip. Its last
//! section is a danger zone.
//! Narrow the window (or widen the sidebar) and the labels go above
//! their controls. Above the form, put its labels at the end of their
//! column, by their controls, draw lines between its rows, put each
//! heading's rows in a card under it, or its controls at the rows' ends.
const std = @import("std");
const nanoui = @import("nanoui");
const controls = @import("nanoui_controls");
const ui = nanoui.ui;
const kit = nanoui.kit;

pub const Settings = struct {
    name: ui.TextBuffer = .{},
    color: ?usize = 3,
    keep: f64 = 10,
    every: ?usize = 1,
    notify: bool = true,
    backups: bool = true,
    labels_at_end: bool = false,
    lines: bool = true,
    cards: bool = true,
    controls_at_end: bool = true,
    advanced: bool = false,
    compression: ?usize = 1,
    limit: f64 = 0,
    opened: usize = 0,
    deleted: usize = 0,

    const colors = [_]controls.Swatch{
        .{ .color = .hex(0xef4444), .label = "Red" },
        .{ .color = .hex(0xf59e0b), .label = "Amber" },
        .{ .color = .hex(0x22c55e), .label = "Green" },
        .{ .color = .hex(0x3b82f6), .label = "Blue" },
        .{ .color = .hex(0xa855f7), .label = "Purple" },
        .{ .color = .hex(0xec4899), .label = "Pink" },
    };

    pub fn view(s: *Settings, c: *ui.Context) void {
        const scroll = ui.div(c).column().sizeFull().scrollY();
        defer scroll.end();
        const root = ui.div(c).column().wFull().maxW(560).p(16).gap(12);
        defer root.end();
        ui.text(c, "Form and swatches", .{ .size = 16, .weight = .semibold });
        {
            const row = ui.div(c).row().gap(16);
            defer row.end();
            _ = ui.checkbox(c, "Labels by their controls", &s.labels_at_end);
            _ = ui.checkbox(c, "Lines between rows", &s.lines);
            _ = ui.checkbox(c, "Sections as cards", &s.cards);
            _ = ui.checkbox(c, "Controls at the end", &s.controls_at_end);
        }
        var f = controls.form(c, .{ .label_align = if (s.labels_at_end) .end else .start, .row_lines = s.lines, .grouped = s.cards, .control_align = if (s.controls_at_end) .end else .start, .size = .sm, .stack_below = 420 });
        f.heading("Account", .{ .description = "How you appear to others on this computer." });
        {
            const empty = s.name.text().len == 0;
            const r = f.row("Name", .{ .required = true, .hint = "As others see it.", .err = if (empty) "A name is required." else "" });
            _ = ui.textField(c, &s.name, .{ .placeholder = "Your name", .width = .{ .px = 220 } });
            r.end();
        }
        {
            const r = f.row("Highlight", .{ .hint = if (s.color) |i| colors[i].label else "None" });
            _ = controls.swatches(c, &colors, &s.color, .{ .size = .sm });
            r.end();
        }
        f.heading("Backups", .{ .description = "How often to back up, and how many snapshots to keep." });
        {
            const r = f.row("Back up", .{});
            _ = ui.toggle(c, "", &s.backups);
            r.end();
        }
        const off = !s.backups;
        {
            const r = f.row("Keep latest", .{ .hint = "Snapshots to keep, newest first.", .info = "Older snapshots are deleted after each backup, once this many newer ones are kept.", .disabled = off });
            _ = kit.numberInput(c, &s.keep, .{ .min = 1, .max = 100, .width = 120 });
            r.end();
        }
        {
            const r = f.row("Every", .{ .disabled = off });
            _ = kit.select(c, "every", &.{ "Hour", "Day", "Week" }, &s.every, .{ .width = 120, .disabled = off });
            r.end();
        }
        {
            const r = f.row("Notify when done", .{ .disabled = off });
            _ = ui.toggle(c, "", &s.notify);
            r.end();
        }
        f.note("Snapshots older than a year are thinned to one a month.");
        if (f.foldingHeading("Advanced", &s.advanced, .{ .description = "Rarely needed: how snapshots are packed and sent." })) {
            {
                const r = f.row("Compression", .{});
                _ = kit.select(c, "compression", &.{ "None", "Fast", "Small" }, &s.compression, .{ .width = 120 });
                r.end();
            }
            {
                const r = f.row("Upload limit", .{ .hint = "In MB/s; 0 for none." });
                _ = kit.numberInput(c, &s.limit, .{ .min = 0, .max = 1000, .step = 5, .width = 120 });
                r.end();
            }
        }
        f.heading("This computer", .{});
        f.property("Version", "1.4.2", .{ .mono = true, .selectable = true });
        f.property("Host", "studio.local", .{ .mono = true, .selectable = true });
        f.property("Path", "/Volumes/Backup/kopia/repositories/studio/snapshots/latest", .{ .mono = true, .wrap = false });
        if (f.link("Repository", "studio", .{})) s.opened += 1;
        if (s.opened > 0) f.note(c.print("Opened the repository's settings {d} times.", .{s.opened}));
        f.heading("Danger zone", .{ .status = .danger, .description = "These can't be undone." });
        {
            const r = f.row("Snapshots", .{ .hint = if (s.deleted > 0) c.print("Deleted {d} times; there were none to delete.", .{s.deleted}) else "" });
            if (kit.button(c, "Delete all", .{ .variant = .danger, .size = .sm }).clicked) s.deleted += 1;
            r.end();
        }
        f.end();
    }
};

pub fn init() Settings {
    var s: Settings = .{};
    s.name.set("Ada Lovelace");
    return s;
}
