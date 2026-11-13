//! The gallery's choices pane: a backup's history to filter, by words in
//! a search box (its ✕ clears it) and by more. A segmented
//! group picks the range (its counts change with it), a tab strip what
//! kind of run, chips that turn on and off narrow it, and a field of
//! chips holds the times of day it runs (type "9:00," or paste several;
//! one that isn't a time shows in red). The buttons raise toasts in the
//! corner: one with "Undo", one that fails, and the same one twice, which
//! shows once.
const std = @import("std");
const nanoui = @import("nanoui");
const controls = @import("nanoui_controls");
const ui = nanoui.ui;
const kit = nanoui.kit;

const Range = enum { today, week, month, year };

pub const History = struct {
    range: Range = .week,
    tab: usize = 0,
    search: ui.TextBuffer = .{},
    mine: bool = false,
    large: bool = true,
    /// The times of day, kept here: what the field gives is the frame's.
    times: [8][16]u8 = undefined,
    lens: [8]u8 = undefined,
    n: usize = 0,
    started: bool = false,
    field: ui.TextBuffer = .{},
    toasts: controls.Toasts = .{},
    undone: usize = 0,

    const undo_tag = 1;

    pub fn view(h: *History, c: *ui.Context) void {
        const t = kit.tokens(c);
        const page = ui.div(c).column().wFull().hFull().p(16).gap(14);
        defer page.end();
        const runs: usize = switch (h.range) {
            .today => 4,
            .week => 28,
            .month => 120,
            .year => 1460,
        };
        {
            const r = controls.inputBox(c, &h.search, .{ .icon = "magnifyingglass", .placeholder = "Filter runs", .size = .sm });
            if (r.cleared) h.search.set("");
        }
        _ = controls.segmentedOf(c, Range, &h.range, &.{
            .{ .label = "Today" },
            .{ .label = "Week" },
            .{ .label = "Month" },
            .{ .label = "Year", .tooltip = "Kept only on the server" },
        }, .{ .label = "Range" });
        var strip = controls.tabStripOpen(c, &.{
            .{ .label = "All runs", .count = runs },
            .{ .label = "Failed", .count = runs / 14, .alert = true },
            .{ .label = "Running", .loading = true },
        }, &h.tab, .{});
        _ = kit.button(c, "Export", .{ .size = .xs, .variant = .ghost });
        _ = strip.end();
        {
            const row = ui.div(c).row().gap(6);
            defer row.end();
            _ = controls.chip(c, "Mine only", &h.mine, .{});
            _ = controls.chip(c, "Over 1 GB", &h.large, .{ .swatch = t.warning });
        }
        controls.caption(c, "RUNS AT", .{});
        if (!h.started) {
            h.add("9:00");
            h.add("21:30");
            h.started = true;
        }
        var shown: [8][]const u8 = undefined;
        var invalid: [8]bool = undefined;
        for (0..h.n) |i| {
            shown[i] = h.times[i][0..h.lens[i]];
            invalid[i] = std.mem.indexOfScalar(u8, shown[i], ':') == null;
        }
        const r = controls.chipInput(c, shown[0..h.n], &h.field, .{ .placeholder = "9:00", .add_placeholder = "add a time", .invalid = invalid[0..h.n], .inherited = &.{"3:00"}, .inherited_note = "from the server's policy" });
        for (r.added) |v| h.add(v);
        if (r.removed) |i| {
            for (i..h.n - 1) |j| {
                h.times[j] = h.times[j + 1];
                h.lens[j] = h.lens[j + 1];
            }
            h.n -= 1;
        }
        {
            const row = ui.div(c).row().gap(8);
            defer row.end();
            if (kit.button(c, "Delete a run", .{ .size = .sm }).clicked) _ = h.toasts.show("Moved a run to the Trash.", .{ .action = "Undo", .tag = undo_tag });
            if (kit.button(c, "Back up now", .{ .size = .sm }).clicked) _ = h.toasts.show("The repository is locked by another client.", .{ .status = .danger, .title = "Backup failed", .seconds = 0 });
            if (kit.button(c, "Save", .{ .size = .sm }).clicked) _ = h.toasts.show("Saved.", .{ .status = .success });
        }
        if (h.undone > 0) ui.text(c, c.print("Undone {d} time{s}.", .{ h.undone, if (h.undone == 1) "" else "s" }), .{ .size = 12, .color = t.muted });
        if (controls.toasts(c, &h.toasts, .{})) |hit| if (hit.tag == undo_tag) {
            h.undone += 1;
        };
    }

    /// Keeps time `v`, cut to 16 bytes, if there is room.
    fn add(h: *History, v: []const u8) void {
        if (h.n == h.times.len) return;
        const len = @min(v.len, 16);
        @memcpy(h.times[h.n][0..len], v[0..len]);
        h.lens[h.n] = @intCast(len);
        h.n += 1;
    }
};
