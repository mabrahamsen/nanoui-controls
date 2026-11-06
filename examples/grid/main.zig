//! The grid with ten thousand files. Click a column's title to sort by
//! it, narrow the window to hide the kind and modified columns, switch on
//! stripes, or show only the five largest files. Click a row to select
//! it, move the selection with the arrow keys, Page Up and Page Down,
//! Home and End, and open it with Enter or a double click.
const std = @import("std");
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
};

const columns = [_]controls.GridColumn{
    .{ .title = "Name", .sortable = true },
    .{ .title = "Kind", .width = 90, .sortable = true, .min_window_width = 560 },
    .{ .title = "Modified", .width = 110, .alignment = .end, .sortable = true, .min_window_width = 680 },
    .{ .title = "Size", .width = 90, .alignment = .end, .sortable = true, .descending_first = true },
};

const Browser = struct {
    files: []File,
    sort: controls.GridSort = .{},
    striped: bool = false,
    show_kind: bool = true,
    /// 0 shows every file, 1 the five largest.
    view_mode: usize = 0,
    /// The selected row; sorting finds its file again.
    selected: ?usize = null,
    opened: ?[]const u8 = null,

    fn view(b: *Browser, c: *ui.Context) void {
        const t = kit.tokens(c);
        const page = ui.div(c).column().wFull().hFull().p(16).gap(12);
        defer page.end();
        {
            const bar = ui.div(c).row().wFull().itemsCenter().gap(16);
            defer bar.end();
            ui.textf(c, .{ .size = 16, .weight = .semibold }, "{d} files", .{b.files.len});
            ui.spacer(c);
            _ = ui.toggle(c, "Striped", &b.striped);
            _ = ui.toggle(c, "Kind", &b.show_kind);
            if (ui.segmented(c, &.{ "All", "Largest five" }, &b.view_mode) and b.view_mode == 1) {
                b.sort = .{ .column = 3, .descending = true };
                b.resort();
            }
        }

        const hidden = [columns.len]bool{ false, !b.show_kind, false, false };
        var g = controls.grid(c, &columns, .{
            .count = b.files.len,
            .sort = &b.sort,
            .striped = b.striped,
            .hidden = &hidden,
            .rows = if (b.view_mode == 1) 5 else null,
            .selected = &b.selected,
        });
        if (g.sorted) b.resort();
        while (g.next()) |row| {
            const f = b.files[row.index];
            if (row.opened) b.opened = f.name;
            _ = g.cellAt(0);
            ui.text(c, f.name, .{ .truncate = .ellipsis });
            if (g.cellAt(1)) ui.text(c, f.kind, .{ .color = t.muted });
            if (g.cellAt(2)) ui.text(c, ago(c, f.age), .{ .color = t.muted });
            _ = g.cellAt(3);
            ui.text(c, size(c, f.size), .{ .mono = true });
        }
        g.end();

        if (b.opened) |name| {
            ui.textf(c, .{ .color = t.muted }, "Opened {s}.", .{name});
        } else if (b.selected) |i| {
            ui.textf(c, .{ .color = t.muted }, "Selected {s}: Enter or a double click opens it.", .{b.files[i].name});
        } else ui.text(c, "Click a row to select it, then move with the arrow keys.", .{ .color = t.muted });
    }

    /// Sorts the files as `sort` says, keeping the same file selected.
    fn resort(b: *Browser) void {
        const name = if (b.selected) |i| b.files[i].name else null;
        sortFiles(b.files, b.sort);
        const n = name orelse return;
        b.selected = for (b.files, 0..) |f, i| {
            if (f.name.ptr == n.ptr) break i;
        } else null;
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

/// Ten thousand files with made-up names, kinds, sizes and ages, the same
/// on every run.
fn makeFiles(gpa: std.mem.Allocator) ![]File {
    const words = [_][]const u8{ "report", "invoice", "photo", "notes", "budget", "draft", "summary", "backup", "design", "readme" };
    const kinds = [_][2][]const u8{ .{ "pdf", "PDF" }, .{ "png", "Image" }, .{ "txt", "Text" }, .{ "csv", "Table" }, .{ "zip", "Archive" } };
    var prng: std.Random.DefaultPrng = .init(1);
    const r = prng.random();
    const files = try gpa.alloc(File, 10_000);
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
    var state: Browser = .{ .files = try makeFiles(init.arena.allocator()) };
    sortFiles(state.files, state.sort);
    _ = try app.newWindow(.{
        .title = "Grid",
        .width = 760,
        .height = 520,
        .content = .{ .view = .init(&state, Browser.view) },
    });
    try app.run();
}
