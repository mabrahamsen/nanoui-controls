//! The grid with ten thousand files. Click a column's title to sort by
//! it, drag the edge between two titles to resize a column, narrow the
//! window to hide the kind and modified columns, switch on stripes, or
//! show only the five largest files. Search to filter them. Click a row
//! to select it, move the selection with the arrow keys, Page Up and Page
//! Down, Home and End, and open it with Enter or a double click. Cmd-click
//! (Ctrl-click) and Shift select several, Cmd+A (Ctrl+A) all of them, and
//! a right-click opens a menu to open, select or delete them. "Load as it
//! scrolls" has rows arrive a page at a time, as from a server.
const std = @import("std");
const builtin = @import("builtin");
const nanoui = @import("nanoui");
const controls = @import("nanoui_controls");
const ui = nanoui.ui;
const kit = nanoui.kit;

const File = struct {
    name: []const u8,
    kind: []const u8,
    size: u64,
    /// Days since it was last changed.
    age: u32,
    /// Selected, kept here while the rows are sorted or searched anew.
    marked: bool = false,
    /// Deleted from its menu: no longer shown.
    deleted: bool = false,
};

const columns = [_]controls.GridColumn{
    .{ .title = "Name", .sortable = true },
    .{ .title = "Kind", .width = 90, .sortable = true, .min_window_width = 560 },
    .{ .title = "Modified", .width = 110, .alignment = .end, .sortable = true, .min_window_width = 680 },
    .{ .title = "Size", .width = 90, .alignment = .end, .sortable = true, .descending_first = true },
};

/// With "Load as it scrolls", rows arrive this many at a time, this long
/// after the grid shows them, as from a server.
const page_rows = 50;
const page_delay = 0.6;
const file_count = 10_000;

const Browser = struct {
    files: []File,
    /// The files the search matches, in order: the grid's rows.
    shown: []u32,
    shown_len: usize = 0,
    /// Which rows are selected, one flag a row of `shown`.
    marked: []bool,
    search: ui.TextBuffer = .{},
    sort: controls.GridSort = .{},
    widths: [columns.len]f32 = @splat(0),
    striped: bool = false,
    show_kind: bool = true,
    loading: bool = false,
    /// When each page of rows arrives; 0 for one not asked for yet.
    arrives: [file_count / page_rows]f64 = @splat(0),
    /// 0 shows every file, 1 the five largest.
    view_mode: usize = 0,
    /// The selected row; sorting and searching find its file again.
    selected: ?usize = null,
    scroll_to: ?usize = null,
    /// The selection's menu, open where it was right-clicked.
    menu_open: bool = false,
    menu_at: ?ui.Rect = null,
    /// What the last action did, said under the grid.
    note: []const u8 = "",
    note_buf: [160]u8 = undefined,

    fn view(b: *Browser, c: *ui.Context) void {
        const t = kit.tokens(c);
        const page = ui.div(c).column().wFull().hFull().p(16).gap(12);
        defer page.end();
        {
            const bar = ui.div(c).row().wFull().itemsCenter().gap(16);
            defer bar.end();
            ui.textf(c, .{ .size = 16, .weight = .semibold }, "{d} files", .{b.shown_len});
            ui.spacer(c);
            if (ui.textField(c, &b.search, .{ .placeholder = "Search", .width = .{ .px = 200 } }).changed) {
                b.keepMarks();
                b.refilter(b.selectedName());
            }
        }
        {
            const bar = ui.div(c).row().wFull().itemsCenter().gap(16);
            defer bar.end();
            _ = ui.toggle(c, "Striped", &b.striped);
            _ = ui.toggle(c, "Kind", &b.show_kind);
            if (ui.toggle(c, "Load as it scrolls", &b.loading)) b.arrives = @splat(0);
            ui.spacer(c);
            if (ui.segmented(c, &.{ "All", "Largest five" }, &b.view_mode) and b.view_mode == 1) {
                b.sort = .{ .column = 3, .descending = true };
                b.resort();
            }
        }

        const hidden = [columns.len]bool{ false, !b.show_kind, false, false };
        var g = controls.grid(c, &columns, .{
            .count = b.shown_len,
            .sort = &b.sort,
            .striped = b.striped,
            .hidden = &hidden,
            .rows = if (b.view_mode == 1) 5 else null,
            .selected = &b.selected,
            .multi = b.marked[0..b.shown_len],
            .widths = &b.widths,
            .scroll_to = b.scroll_to,
            .empty = "No files match the search.",
        });
        b.scroll_to = null;
        if (g.sorted) b.resort();
        if (b.loading) b.ask(c, g.first, g.last);
        while (g.next()) |row| {
            if (b.loading and !b.arrived(c, row.index)) {
                _ = g.cellAt(0);
                ui.text(c, "Loading…", .{ .color = t.muted });
                continue;
            }
            const f = b.files[b.shown[row.index]];
            if (row.opened) b.say("Opened {s}.", .{f.name});
            if (row.clicked) b.note = "";
            if (row.secondary_clicked) {
                b.note = "";
                b.menu_open = true;
                b.menu_at = .{ .x = c.input.mouse.x, .y = c.input.mouse.y, .w = 1, .h = 1 };
            }
            _ = g.cellAt(0);
            ui.text(c, f.name, .{ .truncate = .ellipsis });
            if (g.cellAt(1)) ui.text(c, f.kind, .{ .color = t.muted });
            if (g.cellAt(2)) ui.text(c, ago(c, f.age), .{ .color = t.muted });
            _ = g.cellAt(3);
            ui.text(c, size(c, f.size), .{ .mono = true });
        }
        g.end();

        var marked: usize = 0;
        for (b.marked[0..b.shown_len]) |on| marked += @intFromBool(on);
        const mac = builtin.os.tag.isDarwin();
        if (kit.menu(c, "file-menu", &b.menu_open, b.menu_at, &.{
            .{ .label = if (marked > 1) c.print("Open {d} files", .{marked}) else "Open", .icon = "doc", .shortcut = "↩" },
            .{ .label = "Select all", .shortcut = if (mac) "⌘A" else "Ctrl+A" },
            .{ .separator = true },
            .{ .label = if (marked > 1) c.print("Delete {d} files", .{marked}) else "Delete", .icon = "trash", .danger = true },
        }, .{})) |item| switch (item) {
            0 => b.openSelection(marked),
            1 => @memset(b.marked[0..b.shown_len], true),
            3 => b.deleteSelection(marked),
            else => {},
        };

        if (b.note.len > 0) {
            ui.text(c, b.note, .{ .color = t.muted });
        } else if (marked > 1) {
            ui.textf(c, .{ .color = t.muted }, "{d} files selected: a right-click shows what to do with them.", .{marked});
        } else if (b.selected) |i| {
            ui.textf(c, .{ .color = t.muted }, "Selected {s}: Enter or a double click opens it, a right-click shows a menu.", .{b.files[b.shown[i]].name});
        } else ui.text(c, "Click a row to select it, then move with the arrow keys.", .{ .color = t.muted });
    }

    /// Says what an action did, under the grid, until the next.
    fn say(b: *Browser, comptime fmt: []const u8, args: anytype) void {
        b.note = std.fmt.bufPrint(&b.note_buf, fmt, args) catch "";
    }

    fn openSelection(b: *Browser, marked: usize) void {
        if (marked != 1) return b.say("Opened {d} files.", .{marked});
        for (b.shown[0..b.shown_len], b.marked[0..b.shown_len]) |file, on| if (on) {
            return b.say("Opened {s}.", .{b.files[file].name});
        };
    }

    /// Takes the selected files out of the list: the menu's Delete.
    fn deleteSelection(b: *Browser, marked: usize) void {
        for (b.shown[0..b.shown_len], b.marked[0..b.shown_len]) |file, on| if (on) {
            b.files[file].deleted = true;
        };
        @memset(b.marked[0..b.shown_len], false);
        b.keepMarks();
        b.refilter(null);
        b.say("Deleted {d} file{s}.", .{ marked, if (marked == 1) "" else "s" });
    }

    /// Sorts the files as `sort` says, then finds the search's matches
    /// among them again. Searching alone doesn't sort: the files keep the
    /// order they have.
    fn resort(b: *Browser) void {
        const name = b.selectedName();
        b.keepMarks();
        sortFiles(b.files, b.sort);
        b.refilter(name);
    }

    /// Moves the rows' selection onto their files, which `refilter` moves
    /// back onto the new rows. A file the search hides is no longer
    /// selected.
    fn keepMarks(b: *Browser) void {
        for (b.files) |*f| f.marked = false;
        for (b.shown[0..b.shown_len], b.marked[0..b.shown_len]) |file, on| b.files[file].marked = on;
    }

    /// Finds the files the search matches, in their order, keeping the
    /// file `name` selected and in view. The rows are new, so their pages
    /// load again.
    fn refilter(b: *Browser, name: ?[]const u8) void {
        const query = b.search.text();
        b.shown_len = 0;
        for (b.files, 0..) |f, i| if (!f.deleted and std.mem.indexOf(u8, f.name, query) != null) {
            b.shown[b.shown_len] = @intCast(i);
            b.marked[b.shown_len] = f.marked;
            b.shown_len += 1;
        };
        b.selected = null;
        if (name) |n| for (b.shown[0..b.shown_len], 0..) |file, i| if (b.files[file].name.ptr == n.ptr) {
            b.selected = i;
            break;
        };
        b.scroll_to = b.selected;
        b.arrives = @splat(0);
    }

    fn selectedName(b: *const Browser) ?[]const u8 {
        const i = b.selected orelse return null;
        return b.files[b.shown[i]].name;
    }

    /// Asks for the pages of the rows in view, and one either side, as
    /// an app would of a server, and draws again until they arrive.
    fn ask(b: *Browser, c: *ui.Context, first: usize, last: usize) void {
        const from = (first / page_rows) -| 1;
        const to = @min(b.arrives.len, last / page_rows + 2);
        var waiting = false;
        for (b.arrives[from..to]) |*at| {
            if (at.* == 0) at.* = c.time + page_delay;
            if (c.time < at.*) waiting = true;
        }
        if (waiting) c.frameIn(0.1);
    }

    fn arrived(b: *Browser, c: *ui.Context, row: usize) bool {
        const at = b.arrives[row / page_rows];
        return at != 0 and c.time >= at;
    }
};

fn sortFiles(files: []File, sort: controls.GridSort) void {
    std.mem.sort(File, files, sort, struct {
        fn less(s: controls.GridSort, a: File, b: File) bool {
            const order: std.math.Order = switch (s.column) {
                0 => std.mem.order(u8, a.name, b.name),
                1 => std.mem.order(u8, a.kind, b.kind),
                // Newest first is the smallest age.
                2 => std.math.order(b.age, a.age),
                else => std.math.order(a.size, b.size),
            };
            return if (s.descending) order == .gt else order == .lt;
        }
    }.less);
}

fn size(c: *ui.Context, bytes: u64) []const u8 {
    const b: f64 = @floatFromInt(bytes);
    if (bytes < 1024) return c.print("{d} B", .{bytes});
    if (bytes < 1024 * 1024) return c.print("{d:.1} KB", .{b / 1024});
    return c.print("{d:.1} MB", .{b / (1024 * 1024)});
}

fn ago(c: *ui.Context, days: u32) []const u8 {
    return switch (days) {
        0 => "Today",
        1 => "Yesterday",
        else => c.print("{d} days ago", .{days}),
    };
}

/// `file_count` files with made-up names, kinds, sizes and ages, the same
/// on every run.
fn makeFiles(gpa: std.mem.Allocator) ![]File {
    const words = [_][]const u8{ "report", "invoice", "photo", "notes", "budget", "draft", "summary", "backup", "design", "readme" };
    const kinds = [_][2][]const u8{ .{ "pdf", "PDF" }, .{ "png", "Image" }, .{ "txt", "Text" }, .{ "csv", "Table" }, .{ "zip", "Archive" } };
    var prng: std.Random.DefaultPrng = .init(1);
    const r = prng.random();
    const files = try gpa.alloc(File, file_count);
    for (files, 0..) |*f, i| {
        const kind = kinds[r.uintLessThan(usize, kinds.len)];
        f.* = .{
            .name = try std.fmt.allocPrint(gpa, "{s}-{d:0>5}.{s}", .{ words[r.uintLessThan(usize, words.len)], i, kind[0] }),
            .kind = kind[1],
            .size = r.uintLessThan(u64, @as(u64, 1) << r.intRangeAtMost(u6, 8, 28)),
            .age = r.uintLessThan(u32, 400),
        };
    }
    return files;
}

pub fn main(init: std.process.Init) !void {
    const app = try nanoui.App.create(init, .{ .name = "Grid" });
    defer app.destroy();
    const arena = init.arena.allocator();
    const files = try makeFiles(arena);
    var state: Browser = .{ .files = files, .shown = try arena.alloc(u32, files.len), .marked = try arena.alloc(bool, files.len) };
    @memset(state.marked, false);
    defer state.search.deinit();
    state.resort();
    _ = try app.newWindow(.{
        .title = "Grid",
        .width = 760,
        .height = 520,
        .content = .{ .view = .init(&state, Browser.view) },
    });
    try app.run();
}
