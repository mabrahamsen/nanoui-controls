//! The grid drawn as an app sees it, compared with the PNGs in
//! `tests/snapshots`: what the behaviour tests can't see, its colors,
//! stripes, selection and titles, in light and dark.
//!
//! nanoui draws them itself (`-Dportable=true`) in the DejaVu fonts in
//! `tests/fonts`, so a drawing doesn't depend on the fonts installed. A
//! drawing that differs is written to `zig-out/snapshots` to compare;
//! `zig build test-snapshots -Dupdate-snapshots` writes them all anew.
const std = @import("std");
const nanoui = @import("nanoui");
const controls = @import("nanoui_controls");
const options = @import("snapshot_options");
const ui = nanoui.ui;
const kit = nanoui.kit;

const sans = @embedFile("fonts/DejaVuSans.ttf");
const sans_bold = @embedFile("fonts/DejaVuSans-Bold.ttf");
const mono = @embedFile("fonts/DejaVuSansMono.ttf");

const Files = struct {
    sort: controls.GridSort = .{ .column = 2, .descending = true },
    selected: ?usize = 1,
    hidden: [3]bool = .{ false, false, false },
    rows: ?usize = null,
    title: controls.GridTitleStyle = .{},
    rule: bool = true,

    const columns = [_]controls.GridColumn{
        .{ .title = "Name", .sortable = true },
        .{ .title = "Kind", .width = 70, .sortable = true },
        .{ .title = "Size", .width = 80, .alignment = .end, .sortable = true, .descending_first = true },
    };
    const files = [_]struct { []const u8, []const u8, []const u8 }{
        .{ "budget.csv", "Table", "4.1 MB" },
        .{ "photo.png", "Image", "2.7 MB" },
        .{ "report.pdf", "PDF", "880 KB" },
        .{ "notes.txt", "Text", "12 KB" },
        .{ "readme.txt", "Text", "2 KB" },
    };

    fn view(f: *Files, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull().p(12);
        defer root.end();
        var g = controls.grid(c, &columns, .{
            .count = files.len,
            .sort = &f.sort,
            .selected = &f.selected,
            .striped = true,
            .hidden = &f.hidden,
            .rows = f.rows,
            .title = f.title,
            .rule = f.rule,
        });
        while (g.next()) |row| {
            const file = files[row.index];
            if (g.cellAt(0)) ui.text(c, file[0], .{});
            if (g.cellAt(1)) ui.text(c, file[1], .{ .color = kit.tokens(c).muted });
            if (g.cellAt(2)) ui.text(c, file[2], .{ .mono = true });
        }
        g.end();
    }
};

var fonts_registered = false;

/// Draws `f` in a window 360 by 240 and compares it with `name`'s PNG.
fn expectSnapshot(name: []const u8, f: *Files, dark: bool) !void {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!fonts_registered) {
        for ([_][]const u8{ sans, sans_bold, mono }) |font| if (!ui.registerFont(font)) return error.FontNotRegistered;
        fonts_registered = true;
    }
    var theme = if (dark) ui.Theme.dark_theme else ui.Theme.light;
    theme.font = "DejaVu Sans";
    theme.mono_font = "DejaVu Sans Mono";
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(f, Files.view), .{ .width = 360, .height = 240, .theme = theme });
    defer t.deinit();
    t.settle(1);
    const pixels = try t.render(gpa);
    defer pixels.deinit(gpa);
    const stored = try ui.png.encode(gpa, pixels);
    defer gpa.free(stored);
    const png = try compressed(gpa, stored);
    defer gpa.free(png);

    var path_buf: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "tests/snapshots/{s}.png", .{name});
    const cwd = std.Io.Dir.cwd();
    if (options.update) return cwd.writeFile(io, .{ .sub_path = path, .data = png });
    const expected = cwd.readFileAlloc(io, path, gpa, .limited(16 << 20)) catch |err| {
        try writeActual(name, png);
        std.debug.print("no snapshot {s} ({t}): run `zig build test-snapshots -Dupdate-snapshots`\n", .{ path, err });
        return error.SnapshotMissing;
    };
    defer gpa.free(expected);
    const want = try rows(gpa, expected);
    defer gpa.free(want);
    const got = try rows(gpa, stored);
    defer gpa.free(got);
    if (!std.mem.eql(u8, want, got)) {
        try writeActual(name, png);
        std.debug.print("{s} differs: the drawing is in zig-out/snapshots/{s}.png\n", .{ path, name });
        return error.SnapshotDiffers;
    }
}

/// A PNG's pixel rows: its IDAT chunks, inflated.
fn rows(gpa: std.mem.Allocator, png: []const u8) ![]u8 {
    var idat: std.ArrayList(u8) = .empty;
    defer idat.deinit(gpa);
    var pos: usize = 8;
    while (pos + 12 <= png.len) {
        const len = std.mem.readInt(u32, png[pos..][0..4], .big);
        if (std.mem.eql(u8, png[pos + 4 ..][0..4], "IDAT")) try idat.appendSlice(gpa, png[pos + 8 ..][0..len]);
        pos += 12 + len;
    }
    var in: std.Io.Reader = .fixed(idat.items);
    var window: [std.compress.flate.max_window_len]u8 = undefined;
    var inflate: std.compress.flate.Decompress = .init(&in, .zlib, &window);
    return inflate.reader.allocRemaining(gpa, .unlimited);
}

/// `png` with its rows compressed: nanoui stores them as they are, which
/// is fast to write but large to keep.
fn compressed(gpa: std.mem.Allocator, png: []const u8) ![]u8 {
    const raw = try rows(gpa, png);
    defer gpa.free(raw);
    var z: std.Io.Writer.Allocating = try .initCapacity(gpa, 64 * 1024);
    defer z.deinit();
    var window: [std.compress.flate.max_window_len]u8 = undefined;
    var deflate: std.compress.flate.Compress = try .init(&z.writer, &window, .zlib, .best);
    try deflate.writer.writeAll(raw);
    try deflate.finish();
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    // The signature and the header chunk, IHDR, as they are.
    try out.writer.writeAll(png[0 .. 8 + 12 + 13]);
    try chunk(&out.writer, "IDAT", z.written());
    try chunk(&out.writer, "IEND", "");
    return out.toOwnedSlice();
}

fn chunk(w: *std.Io.Writer, kind: *const [4]u8, data: []const u8) !void {
    try w.writeInt(u32, @intCast(data.len), .big);
    try w.writeAll(kind);
    try w.writeAll(data);
    var crc: std.hash.Crc32 = .init();
    crc.update(kind);
    crc.update(data);
    try w.writeInt(u32, crc.final(), .big);
}

fn writeActual(name: []const u8, png: []const u8) !void {
    const io = std.testing.io;
    var path_buf: [128]u8 = undefined;
    try std.Io.Dir.cwd().createDirPath(io, "zig-out/snapshots");
    const path = try std.fmt.bufPrint(&path_buf, "zig-out/snapshots/{s}.png", .{name});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = png });
}

test "a sorted, striped grid with a selected row, light" {
    var f: Files = .{};
    try expectSnapshot("grid-light", &f, false);
}

test "a sorted, striped grid with a selected row, dark" {
    var f: Files = .{};
    try expectSnapshot("grid-dark", &f, true);
}

test "a grid of three rows with styled titles, a hidden column and no rule" {
    var f: Files = .{
        .rows = 3,
        .hidden = .{ false, true, false },
        .rule = false,
        .selected = null,
        .title = .{ .size = 12, .mono = true, .weight = .bold, .color = .{ .r = 0.2, .g = 0.4, .b = 0.8 }, .sorted_color = .{ .r = 0.8, .g = 0.3, .b = 0.1 } },
    };
    try expectSnapshot("grid-styled", &f, false);
}
