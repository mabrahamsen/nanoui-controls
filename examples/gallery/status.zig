//! The gallery's status pane: a backup service seen at a glance. Pills
//! say how it stands, a row of compact readings what it last did (in
//! sizes and times as `format` writes them), and callouts what needs a
//! look; close the warning, or bring it back with "Show the warning".
//! A header names it, its tile green while it runs. Panels group its
//! settings, one of them folding, with its password in an input box that
//! hides it until the eye shows it, and "Server" stops,
//! starts and connects the service, its pane a notice while it isn't
//! running.
const std = @import("std");
const nanoui = @import("nanoui");
const controls = @import("nanoui_controls");
const ui = nanoui.ui;
const kit = nanoui.kit;
const format = controls.format;

pub const Backups = struct {
    server: enum { running, stopped, connecting } = .running,
    warning: bool = true,
    advanced: bool = false,
    password: ui.TextBuffer = .{},
    show_password: bool = false,
    since: f64 = 0,
    /// The readings, as the last backup left them.
    files: u64 = 312_480,
    bytes: u64 = 4_213_000_000,
    took: i64 = 42 * 60 + 7,
    ago: i64 = 12 * 60,

    pub fn view(b: *Backups, c: *ui.Context) void {
        const t = kit.tokens(c);
        const scroll = ui.div(c).column().sizeFull().scrollY();
        defer scroll.end();
        const page = ui.div(c).column().wFull().p(16).gap(12);
        defer page.end();
        // Connecting takes a moment, as a server's answer would.
        if (b.server == .connecting) {
            if (c.time - b.since > 1.5) b.server = .running else c.frameIn(0.1);
        }
        {
            const bar = controls.header(c, .{ .icon = "internaldrive", .title = "Backups", .subtitle = "~/Documents to the office server", .subtitle_mono = true, .status = if (b.server == .running) .success else .warning });
            defer bar.end();
            switch (b.server) {
                .running => controls.pill(c, "RUNNING", .{ .status = .success, .lead = .{ .dot = .{ .dim = @mod(c.time, 2) > 1.4 } } }),
                .stopped => controls.pill(c, "STOPPED", .{ .status = .warning }),
                .connecting => controls.pill(c, "CONNECTING", .{ .lead = .{ .icon = .{ .name = "arrow.clockwise" } } }),
            }
            if (b.server == .running) c.frameIn(0.2);
            controls.pill(c, "E2E", .{ .shape = .box, .tooltip = "Encrypted end to end", .value_text = "Encrypted end to end" });
            const label = switch (b.server) {
                .running => "Stop server",
                .stopped => "Start server",
                .connecting => "Connecting…",
            };
            if (kit.button(c, label, .{ .size = .sm, .disabled = b.server == .connecting }).clicked) b.toggle(c);
        }
        if (b.server != .running) {
            const n = controls.noticeOpen(c, .{
                .loading = b.server == .connecting,
                .icon = "network",
                .title = if (b.server == .connecting) "Connecting" else "Server stopped",
                .description = if (b.server == .connecting) "Asking the server how the backups stand." else "Nothing is backed up while it is stopped. Start it to back up again.",
                .status = if (b.server == .connecting) .neutral else .warning,
                .announce = true,
            });
            defer n.end();
            if (b.server == .stopped and kit.button(c, "Start server", .{ .variant = .primary, .size = .sm }).clicked) b.toggle(c);
            return;
        }
        {
            var f = controls.flow(c, 110, .{ .gap = 16 });
            defer f.end();
            const reading: controls.StatOptions = .{ .size = .xs, .card = null, .mono = true };
            f.stat("FILES", format.grouped(c, b.files), reading);
            f.stat("SIZE", format.size(c, b.bytes), reading);
            f.stat("TOOK", format.clock(c, b.took), reading);
            f.stat("LAST", format.ago(c, b.ago, .{}), reading);
            f.stat("SPEED", format.rate(c, @as(f64, @floatFromInt(b.bytes)) / @as(f64, @floatFromInt(b.took))), reading);
        }
        _ = controls.callout(c, "Snapshots are kept for 30 days, then pruned.", .{});
        if (b.warning) {
            if (controls.callout(c, "~/Projects/old-site doesn't exist any more, so it is skipped.", .{ .status = .warning, .title = "Missing folder", .closable = true })) b.warning = false;
        } else if (kit.button(c, "Show the warning", .{ .size = .sm, .variant = .ghost }).clicked) b.warning = true;
        {
            const row = ui.div(c).row().wFull().gap(12).itemsStart();
            defer row.end();
            {
                const p = controls.panel(c, .{ .title = "RETENTION", .card = .{ .width = .fill } });
                defer p.end();
                ui.text(c, "Keep 10 snapshots", .{ .size = 13 });
                ui.text(c, "and one a day for a month", .{ .size = 12, .color = t.muted });
            }
            {
                const p = controls.panel(c, .{ .title = "DANGER ZONE", .status = .danger, .card = .{ .width = .fill } });
                defer p.end();
                ui.text(c, "Deleting the repository can't be undone.", .{ .size = 12, .wrap = true, .color = t.muted });
                _ = kit.button(c, "Delete…", .{ .size = .sm, .variant = .danger });
            }
        }
        {
            const p = controls.panel(c, .{ .title = "ADVANCED", .open = &b.advanced });
            defer p.end();
            if (b.advanced) {
                controls.caption(c, "REPOSITORY PASSWORD", .{ .heading = false });
                if (controls.inputBox(c, &b.password, .{ .icon = "lock", .label = "Repository password", .shown = &b.show_password, .paste = true, .size = .sm }).cleared) b.password.set("");
                const h = controls.captionOpen(c, "COMPRESSION", .{ .aside = "zstd", .heading = false });
                h.trailing();
                controls.pill(c, "FAST", .{ .status = .info });
                h.end();
                const r = controls.calloutOpen(c, "Changing it starts a new repository.", .{ .status = .info, .plain = true });
                _ = kit.button(c, "Learn more", .{ .size = .xs, .variant = .ghost });
                r.end();
            }
        }
    }

    fn toggle(b: *Backups, c: *ui.Context) void {
        b.server = if (b.server == .running) .stopped else .connecting;
        b.since = c.time;
    }
};
