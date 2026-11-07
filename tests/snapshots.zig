//! The controls drawn as an app sees them, compared with the PNGs in
//! `tests/snapshots`: what the behaviour tests can't see, such as the
//! grid's colors, stripes, selection and titles, and the charts' colors,
//! in light and dark.
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
    max_rows: ?usize = null,
    title_style: controls.GridTitleStyle = .{},
    header_line: bool = true,
    count: usize = files.len,
    order: [3]usize = .{ 0, 1, 2 },
    /// Wide columns that scroll sideways past a frozen name.
    wide: bool = false,
    /// A Kind column too narrow for its words.
    narrow: bool = false,
    /// Lines between the rows and the columns.
    lines: bool = false,
    /// The grid has the keyboard, so its selection is the accent's color.
    focused: bool = true,

    const columns = [_]controls.GridColumn{
        .{ .title = "Name", .sortable = true },
        .{ .title = "Kind", .width = 70, .sortable = true },
        .{ .title = "Size", .width = 80, .alignment = .end, .sortable = true, .descending_first = true },
    };
    const wide_columns = [_]controls.GridColumn{
        .{ .title = "Name", .width = 110, .sortable = true },
        .{ .title = "Kind", .width = 140, .sortable = true },
        .{ .title = "Size", .width = 140, .alignment = .end, .sortable = true, .descending_first = true },
    };
    const narrow_columns = [_]controls.GridColumn{
        .{ .title = "Name", .sortable = true },
        .{ .title = "Kind", .width = 36, .sortable = true },
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
        const cols: []const controls.GridColumn = if (f.wide) &wide_columns else if (f.narrow) &narrow_columns else &columns;
        if (f.focused) c.focusNext(false);
        var g = controls.grid(c, cols, .{
            .count = f.count,
            .empty = "No files here.",
            .sort = &f.sort,
            .selected = &f.selected,
            .striped = true,
            .hidden = &f.hidden,
            .max_rows = f.max_rows,
            .title_style = f.title_style,
            .header_line = f.header_line,
            .order = &f.order,
            .scroll_x = f.wide,
            .freeze_first = f.wide,
            .row_lines = f.lines,
            .column_lines = f.lines,
        });
        while (g.next()) |row| {
            const file = files[row.index];
            if (g.cellAt(0)) ui.text(c, file[0], .{});
            if (g.cellAt(1)) ui.text(c, file[1], .{ .color = kit.tokens(c).muted, .truncate = .ellipsis });
            if (g.cellAt(2)) ui.text(c, file[2], .{ .mono = true });
        }
        g.end();
    }
};

var fonts_registered = false;

/// Draws `f` in a window 360 by 240 and compares it with `name`'s PNG.
fn expectSnapshot(name: []const u8, f: *Files, dark: bool) !void {
    return expectSnapshotWith(name, f, .{ .dark = dark });
}

/// The same, with the pointer resting on the text `over`.
fn expectSnapshotAt(name: []const u8, f: *Files, dark: bool, over: ?[]const u8) !void {
    return expectSnapshotWith(name, f, .{ .dark = dark, .over = over });
}

const Setup = struct {
    dark: bool = false,
    /// The pointer rests on this text, or in this column's cell (by its
    /// title) of this row (by its first cell's text).
    over: ?[]const u8 = null,
    cell: ?[2][]const u8 = null,
    /// The columns scrolled sideways this far.
    scroll_x: f32 = 0,
    height: f32 = 240,
};

fn expectSnapshotWith(name: []const u8, f: *Files, setup: Setup) !void {
    return expectView(name, .init(f, Files.view), setup);
}

/// Draws `view` as `setup` says and compares it with `name`'s PNG.
fn expectView(name: []const u8, view: ui.View, setup: Setup) !void {
    const dark = setup.dark;
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
    try t.init(gpa, view, .{ .width = 360, .height = setup.height, .theme = theme });
    defer t.deinit();
    t.settle(1);
    if (setup.scroll_x != 0) {
        t.hscroll(180, 120, -setup.scroll_x);
        t.moveTo(-100, -100);
        t.settle(1);
    }
    if (setup.over) |text| {
        const r = t.findText(text).?;
        t.moveTo(r.x + r.w / 2, r.y + r.h / 2);
        t.settle(1);
    }
    if (setup.cell) |cell| {
        const row = t.findText(cell[1]).?;
        t.moveTo(t.findText(cell[0]).?.x + 6, row.y + row.h / 2);
        t.settle(1);
    }
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

test "a grid without the keyboard, its selection grey, light and dark" {
    var f: Files = .{ .focused = false };
    try expectSnapshot("grid-unfocused", &f, false);
    try expectSnapshot("grid-unfocused-dark", &f, true);
}

test "the selected row keeps its color under the pointer, and another row lights up" {
    var f: Files = .{};
    try expectSnapshotAt("grid-hover-selected", &f, false, "photo.png");
    try expectSnapshotAt("grid-hover", &f, false, "notes.txt");
}

test "columns in another order, their cells with them" {
    var f: Files = .{ .order = .{ 2, 0, 1 } };
    try expectSnapshot("grid-reordered", &f, false);
}

test "a cut-off cell's whole text over it" {
    var f: Files = .{ .narrow = true, .selected = null };
    // On photo.png's Kind, "Image", which 36 points cut off.
    try expectSnapshotWith("grid-tooltip", &f, .{ .cell = .{ "Kind", "photo.png" } });
}

test "columns scrolled sideways past the name, which stays" {
    var f: Files = .{ .wide = true };
    try expectSnapshotWith("grid-scrolled", &f, .{ .scroll_x = 60 });
}

test "lines between the rows and the columns, light and dark" {
    var f: Files = .{ .lines = true };
    try expectSnapshot("grid-lines", &f, false);
    try expectSnapshot("grid-lines-dark", &f, true);
}

/// A pager of twenty pages, on the tenth.
const Pages = struct {
    page: usize = 9,
    fn view(p: *Pages, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull().p(12);
        defer root.end();
        _ = controls.pager(c, &p.page, 20, .{});
    }
};

test "a pager, light and dark" {
    var p: Pages = .{};
    try expectView("pager", .init(&p, Pages.view), .{ .height = 60 });
    try expectView("pager-dark", .init(&p, Pages.view), .{ .height = 60, .dark = true });
}

/// Each chart, drawn from fixed readings in the theme's colors.
const Charts = struct {
    const history = [_]f32{ 0.2, 0.35, 0.3, 0.5, 0.45, 0.7, 0.65, 0.9, 0.6, 0.8, 0.55, 0.75 };
    const read = [_]f32{ 0.3, 0.5, 0.2, 0.6, 0.4, 0.35, 0.5, 0.25 };
    const write = [_]f32{ 0.2, 0.1, 0.3, 0.2, 0.35, 0.1, 0.2, 0.3 };

    fn heat(at: f32) ui.Color {
        const cool: ui.Color = .hex(0x22d3ee);
        const hot: ui.Color = .hex(0xfb7185);
        return cool.mix(hot, at);
    }

    fn view(_: *Charts, c: *ui.Context) void {
        const t = kit.tokens(c);
        const root = ui.div(c).column().sizeFull().p(12).gap(10);
        defer root.end();
        {
            const row = ui.div(c).row().wFull().gap(10).h(40);
            defer row.end();
            controls.trend(c, &history, .{ .capacity = 16, .height = .fill });
            var b = controls.bars(c, .{ .count = read.len, .height = .fill, .gap = 2 });
            while (b.next()) |slot| controls.stack(c, &.{ .{ .value = read[slot.index], .color = t.primary }, .{ .value = write[slot.index], .color = t.success } });
            b.end();
        }
        controls.split(c, &.{ .{ .value = 0.4, .color = t.primary }, .{ .value = 0.2, .color = t.success }, .{ .value = 0.1, .color = t.warning } }, .{});
        controls.split(c, &.{ .{ .value = 3, .color = t.primary }, .{ .value = 2, .color = t.success }, .{ .value = 1, .color = t.warning } }, .{ .whole = true });
        controls.split(c, &.{.{ .value = 0.65, .color = t.danger }}, .{ .part_radius = 3, .glow = 0.6 });
        controls.meter(c, 0.62, .{});
        controls.meter(c, 0.8, .{ .ramp = heat, .glow = 0.6 });
        controls.meter(c, 1, .{ .ramp = heat, .gap = 0, .radius = 0, .height = 6 });
        var l = controls.legend(c, .{});
        l.item(t.primary, "Read");
        l.item(t.success, "Write");
        const peak = l.itemOpen(t.warning, "Other");
        ui.text(c, "▲4.2", .{ .size = 10, .color = t.muted });
        peak.end();
        l.end();
    }
};

test "the charts, light and dark" {
    var x: Charts = .{};
    try expectView("charts", .init(&x, Charts.view), .{ .height = 200 });
    try expectView("charts-dark", .init(&x, Charts.view), .{ .height = 200, .dark = true });
}

test "an empty grid says so under its titles" {
    var f: Files = .{ .count = 0, .selected = null };
    try expectSnapshot("grid-empty", &f, false);
}

test "a grid of three rows with styled titles, a hidden column and no header line" {
    var f: Files = .{
        .max_rows = 3,
        .hidden = .{ false, true, false },
        .header_line = false,
        .selected = null,
        .title_style = .{ .size = 12, .mono = true, .weight = .bold, .color = .{ .r = 0.2, .g = 0.4, .b = 0.8 }, .sorted_color = .{ .r = 0.8, .g = 0.3, .b = 0.1 } },
    };
    try expectSnapshot("grid-styled", &f, false);
}
