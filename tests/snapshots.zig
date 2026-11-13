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
    /// The pointer rests here.
    at: ?[2]f32 = null,
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
    if (setup.at) |p| {
        t.moveTo(p[0], p[1]);
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
    const change = [_]f32{ 0.3, -0.2, 0.5, 0.1, -0.35, 0.2, -0.1, 0.4 };
    const heat = [_]ui.Color{ .hex(0x22d3ee), .hex(0xfbbf24), .hex(0xfb7185) };

    fn view(_: *Charts, c: *ui.Context) void {
        const t = kit.tokens(c);
        const root = ui.div(c).column().sizeFull().p(12).gap(10);
        defer root.end();
        {
            const row = ui.div(c).row().wFull().gap(10).h(40);
            defer row.end();
            controls.trend(c, &history, .{ .capacity = 16, .height = .fill, .value_lines = &.{.{ .value = 0.5 }} });
            var b = controls.bars(c, .{ .count = read.len, .height = .fill, .gap = 2 });
            while (b.next()) |slot| slot.bar(&.{ .{ .value = read[slot.index], .color = t.primary }, .{ .value = write[slot.index], .color = t.success } });
            b.end();
            var d = controls.bars(c, .{ .count = change.len, .height = .fill, .gap = 2, .below = 0.4 });
            while (d.next()) |slot| slot.bar(&.{.{ .value = change[slot.index], .color = if (change[slot.index] < 0) t.danger else t.success }});
            d.end();
        }
        controls.breakdown(c, &.{ .{ .value = 0.4, .color = t.primary }, .{ .value = 0.2, .color = t.success }, .{ .value = 0.1, .color = t.warning } }, .{});
        controls.breakdown(c, &.{ .{ .value = 3, .color = t.primary }, .{ .value = 2, .color = t.success }, .{ .value = 1, .color = t.warning } }, .{ .whole = true });
        controls.breakdown(c, &.{.{ .value = 0.65, .color = t.danger }}, .{ .part_radius = 3, .glow = 0.6 });
        controls.meter(c, 0.62, .{});
        controls.meter(c, 0.8, .{ .ramp = &heat, .glow = 0.6 });
        controls.meter(c, 1, .{ .ramp = &heat, .gap = 0, .radius = 0, .height = .{ .px = 6 } });
        var l = controls.legend(c, .{});
        l.item(t.primary, "Read");
        l.item(t.success, "Write");
        l.itemDetail(t.warning, "Other", "▲4.2");
        l.trailing("Free 7.0 GB");
        l.end();
    }
};

/// The charts drawn with nanoui's canvas, a list of bars and stats.
const MoreCharts = struct {
    const cpu = [_]f32{ 0.2, 0.35, 0.3, 0.5, 0.45, 0.7, 0.65, 0.9, 0.6, 0.8, 0.55, 0.75 };
    const gpu = [_]f32{ 0.1, 0.15, 0.2, 0.15, 0.3, 0.25, 0.4, 0.35, 0.3, 0.45, 0.4, 0.5 };
    const folders = [_]controls.BarListItem{
        .{ .label = "Photos", .value = 41.2, .value_text = "41.2 GB" },
        .{ .label = "Music", .value = 12.9, .value_text = "12.9 GB" },
        .{ .label = "Documents", .value = 4.4, .value_text = "4.4 GB" },
    };

    fn view(_: *MoreCharts, c: *ui.Context) void {
        const t = kit.tokens(c);
        const root = ui.div(c).column().sizeFull().p(12).gap(10);
        defer root.end();
        var l = controls.line(c, &.{ .{ .values = &cpu, .area = 0.15 }, .{ .values = &gpu, .color = t.success } }, .{ .capacity = 12, .height = .{ .px = 56 }, .value_lines = &.{.{ .value = 0.5, .label = "50%" }} });
        l.end();
        {
            const row = ui.div(c).row().wFull().gap(12).itemsCenter();
            defer row.end();
            controls.donut(c, &.{ .{ .value = 0.45, .color = t.primary }, .{ .value = 0.2, .color = t.success }, .{ .value = 0.06, .color = t.warning } }, .{ .diameter = 84, .text = "71%", .caption = "used" });
            const right = ui.div(c).column().wFull().gap(2);
            defer right.end();
            _ = controls.barList(c, &folders, .{ .label_width = 74, .value_width = 54, .size = .xs });
        }
        {
            const row = ui.div(c).row().wFull().gap(10).itemsStretch();
            defer row.end();
            controls.stat(c, "Requests", "12,480", .{ .change = "+8%", .status = .success, .history = &cpu, .size = .sm });
            controls.stat(c, "Errors", "37", .{ .change = "+3", .status = .danger, .size = .sm });
        }
    }
};

test "the charts, light and dark" {
    var x: Charts = .{};
    try expectView("charts", .init(&x, Charts.view), .{ .height = 200 });
    try expectView("charts-dark", .init(&x, Charts.view), .{ .height = 200, .dark = true });
}

/// Interactive charts with the pointer on one: its marker and tooltip.
const Inspected = struct {
    const read = [_]f32{ 0.2, 0.35, 0.3, 0.5, 0.45, 0.7, 0.65, 0.9, 0.6, 0.8, 0.55, 0.75 };

    fn view(_: *Inspected, c: *ui.Context) void {
        const t = kit.tokens(c);
        const root = ui.div(c).column().sizeFull().p(12).gap(16);
        defer root.end();
        ui.div(c).h(24).end();
        var l = controls.line(c, &.{.{ .values = &read, .area = 0.15 }}, .{ .capacity = 12, .height = .{ .px = 56 }, .interactive = true });
        if (l.current) |i| l.tooltip(c.print("{d:.0}%", .{read[i] * 100}));
        l.end();
        var b = controls.bars(c, .{ .count = read.len, .height = .{ .px = 40 }, .gap = 2, .interactive = true });
        while (b.next()) |slot| {
            if (slot.current) _ = slot.box.bg(t.surface_hover);
            slot.bar(&.{.{ .value = read[slot.index], .color = t.success }});
        }
        b.end();
    }
};

test "a line chart pointed at, its reading marked and said, light and dark" {
    var x: Inspected = .{};
    // The pointer on the line's eighth reading, 336 points across.
    try expectView("charts-inspected", .init(&x, Inspected.view), .{ .height = 170, .at = .{ 12 + 7.0 / 11.0 * 336, 70 } });
    try expectView("charts-inspected-dark", .init(&x, Inspected.view), .{ .height = 170, .dark = true, .at = .{ 12 + 7.0 / 11.0 * 336, 70 } });
}

/// Two sidebars, at two sizes: headings, counts, a group open and one
/// folded, a row selected.
const Sidebars = struct {
    open: bool = true,
    folded: bool = false,

    fn view(x: *Sidebars, c: *ui.Context) void {
        const root = ui.div(c).row().sizeFull().p(8).gap(8);
        defer root.end();
        for ([_]kit.Size{ .sm, .md }, 0..) |size, i| {
            ui.keyInt(c, i);
            const col = ui.div(c).column().wFull().hFull();
            defer col.end();
            var sb = controls.sidebar(c, "mail", if (i == 0) "inbox" else "work", .{ .size = size });
            sb.heading("Mailboxes");
            sb.item("inbox", "Inbox", .{ .icon = "doc.text", .count = 12 });
            sb.item("sent", "Sent", .{ .icon = "arrow.up" });
            if (sb.group("folders", "Folders", if (i == 0) &x.folded else &x.open)) |g| {
                sb.item("work", "Work", .{ .icon = "folder", .count = 3 });
                sb.item("travel", "Travel", .{ .icon = "folder" });
                g.end();
            }
            _ = sb.end();
        }
    }
};

/// The same sidebar narrowed to its icons and wide, a splitter between
/// them: a pill count, a disabled row, a heading and a group.
const Narrowed = struct {
    open: bool = true,
    width: f32 = 150,

    fn view(x: *Narrowed, c: *ui.Context) void {
        const root = ui.div(c).row().sizeFull().p(8);
        defer root.end();
        mail(x, c, true, 44);
        _ = controls.splitter(c, &x.width, .{ .label = "Sidebar width" });
        mail(x, c, false, x.width);
    }

    fn mail(x: *Narrowed, c: *ui.Context, icons_only: bool, w: f32) void {
        ui.keyInt(c, @intFromBool(icons_only));
        const col = ui.div(c).column().w(w).hFull();
        defer col.end();
        var sb = controls.sidebar(c, "mail", "inbox", .{ .icons_only = icons_only });
        sb.heading("Mailboxes");
        sb.item("inbox", "Inbox", .{ .icon = "doc.text", .count = 4, .count_style = .pill });
        sb.item("sent", "Sent", .{ .icon = "arrow.up", .count = 2 });
        sb.item("offline", "Offline", .{ .icon = "globe", .disabled = true });
        if (sb.group("folders", "Folders", &x.open)) |g| {
            sb.item("work", "Work", .{ .icon = "folder" });
            g.end();
        }
        _ = sb.end();
    }
};

/// A settings sidebar with branches: one open with a branch open in it,
/// one folded with the selected row in it, and one in a group.
const Branches = struct {
    privacy: bool = true,
    apps: bool = true,
    sharing: bool = false,
    more: bool = true,
    network: bool = true,
    frames: u32 = 0,

    fn view(x: *Branches, c: *ui.Context) void {
        const root = ui.div(c).column().w(220).hFull().p(8);
        defer root.end();
        // Open in the first frame, so it knows it holds the selected row
        // once folded.
        if (x.frames < 2) x.sharing = x.frames == 0;
        x.frames += 1;
        var sb = controls.sidebar(c, "settings", "airdrop", .{});
        sb.item("general", "General", .{ .icon = "gearshape" });
        if (sb.branch("privacy", "Privacy", .{ .icon = "hand.raised", .count = 3 }, &x.privacy)) |g| {
            sb.item("location", "Location", .{ .icon = "bookmark" });
            if (sb.branch("apps", "Apps", .{ .icon = "square.grid.2x2" }, &x.apps)) |g2| {
                sb.item("camera", "Camera", .{ .icon = "photo" });
                sb.item("microphone", "Microphone", .{ .icon = "waveform.path.ecg" });
                g2.end();
            }
            g.end();
        }
        if (sb.branch("sharing", "Sharing", .{ .icon = "square.and.arrow.up" }, &x.sharing)) |g| {
            sb.item("airdrop", "AirDrop", .{ .icon = "arrow.up" });
            g.end();
        }
        if (sb.group("more", "More", &x.more)) |g| {
            if (sb.branch("network", "Network", .{ .icon = "globe" }, &x.network)) |g2| {
                sb.item("wifi", "Wi-Fi", .{ .icon = "network" });
                g2.end();
            }
            g.end();
        }
        _ = sb.end();
    }
};

test "a sidebar with branches, open and folded, light and dark" {
    var x: Branches = .{};
    try expectView("sidebar-branches", .init(&x, Branches.view), .{ .height = 330 });
    x = .{};
    try expectView("sidebar-branches-dark", .init(&x, Branches.view), .{ .height = 330, .dark = true });
}

/// A docs site's sidebar: a fixed tree, its branches always open and
/// without chevrons, a row three levels in selected.
fn fixedTree(_: *u8, c: *ui.Context) void {
    const root = ui.div(c).column().w(220).hFull().p(8);
    defer root.end();
    var sb = controls.sidebar(c, "docs", "docker", .{});
    sb.item("intro", "Introduction", .{ .icon = "doc.text" });
    if (sb.branch("guides", "Guides", .{ .icon = "folder", .count = 3 }, null)) |g| {
        sb.item("start", "Getting started", .{ .icon = "doc.text" });
        if (sb.branch("deploy", "Deploying", .{ .icon = "folder" }, null)) |g2| {
            sb.item("docker", "Docker", .{ .icon = "cube" });
            sb.item("cloud", "To the cloud", .{ .icon = "globe" });
            g2.end();
        }
        g.end();
    }
    if (sb.branch("reference", "Reference", .{ .icon = "folder" }, null)) |g| {
        sb.item("api", "API", .{ .icon = "code" });
        g.end();
    }
    _ = sb.end();
}

test "a sidebar that is a fixed tree, light and dark" {
    var x: u8 = 0;
    try expectView("sidebar-fixed", .init(&x, fixedTree), .{ .height = 300 });
    try expectView("sidebar-fixed-dark", .init(&x, fixedTree), .{ .height = 300, .dark = true });
}

test "a sidebar narrowed to its icons, and wide, light and dark" {
    var x: Narrowed = .{};
    try expectView("sidebar-icons", .init(&x, Narrowed.view), .{ .height = 230 });
    try expectView("sidebar-icons-dark", .init(&x, Narrowed.view), .{ .height = 230, .dark = true });
}

test "sidebars at two sizes, light and dark" {
    var x: Sidebars = .{};
    try expectView("sidebar", .init(&x, Sidebars.view), .{ .height = 230 });
    try expectView("sidebar-dark", .init(&x, Sidebars.view), .{ .height = 230, .dark = true });
}

test "lines, a donut, a list of bars and stats, light and dark" {
    var x: MoreCharts = .{};
    try expectView("charts-more", .init(&x, MoreCharts.view), .{ .height = 290 });
    try expectView("charts-more-dark", .init(&x, MoreCharts.view), .{ .height = 290, .dark = true });
}

/// A form: a heading, rows of the kit's controls with a hint and an
/// error, and properties under a second heading; swatches in a row, one
/// chosen.
const Forms = struct {
    grouped: bool = false,
    keep: f64 = 10,
    every: ?usize = 1,
    notify: bool = true,
    color: ?usize = 2,
    const colors = [_]controls.Swatch{
        .{ .color = .hex(0xef4444), .label = "Red" },
        .{ .color = .hex(0xf59e0b), .label = "Amber" },
        .{ .color = .hex(0x22c55e), .label = "Green" },
        .{ .color = .hex(0x3b82f6), .label = "Blue" },
        .{ .color = .hex(0xa855f7), .label = "Purple" },
    };

    fn view(x: *Forms, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull().p(12);
        defer root.end();
        var f = controls.form(c, .{ .size = .sm, .row_lines = true, .grouped = x.grouped });
        f.heading("Snapshots", .{ .description = "How many to keep, and how often." });
        {
            const r = f.row("Keep latest", .{ .hint = "Snapshots to keep, newest first." });
            _ = kit.numberInput(c, &x.keep, .{ .min = 1, .width = 110 });
            r.end();
        }
        {
            const r = f.row("Every", .{ .err = "Too often for this disk.", .required = true });
            _ = kit.select(c, "every", &.{ "Hour", "Day", "Week" }, &x.every, .{ .width = 110 });
            r.end();
        }
        {
            const r = f.row("Color", .{});
            _ = controls.swatches(c, &colors, &x.color, .{ .size = .sm });
            r.end();
        }
        f.heading("Repository", .{});
        f.property("Host", "studio.local", .{ .mono = true });
        f.property("Path", "/Volumes/Backup/kopia", .{ .mono = true });
        f.end();
    }
};

test "a form with kit controls, a hint, an error, swatches and properties, light and dark" {
    var x: Forms = .{};
    try expectView("form", .init(&x, Forms.view), .{ .height = 340 });
    try expectView("form-dark", .init(&x, Forms.view), .{ .height = 340, .dark = true });
}

test "a form's sections in cards, light and dark" {
    var x: Forms = .{ .grouped = true };
    try expectView("form-grouped", .init(&x, Forms.view), .{ .height = 380 });
    try expectView("form-grouped-dark", .init(&x, Forms.view), .{ .height = 380, .dark = true });
}

/// A settings pane: sections as cards with their controls at the rows'
/// ends, a note, a folded heading, a row that leads somewhere, and a
/// danger zone.
const SettingsPane = struct {
    on: bool = true,
    every: ?usize = 1,
    advanced: bool = false,

    fn view(x: *SettingsPane, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull().p(12);
        defer root.end();
        var f = controls.form(c, .{ .size = .sm, .row_lines = true, .grouped = true, .control_align = .end });
        f.heading("Backups", .{ .description = "How often, and how many to keep." });
        {
            const r = f.row("Back up", .{});
            _ = ui.toggle(c, "", &x.on);
            r.end();
        }
        {
            const r = f.row("Every", .{ .hint = "While the computer is awake." });
            _ = kit.select(c, "every", &.{ "Hour", "Day", "Week" }, &x.every, .{ .width = 100 });
            r.end();
        }
        f.note("Snapshots older than a year are kept monthly.");
        _ = f.foldingHeading("Advanced", &x.advanced, .{});
        f.heading("This computer", .{});
        f.property("Host", "studio.local", .{ .mono = true });
        _ = f.link("Repository", "studio", .{});
        f.heading("Danger zone", .{ .status = .danger });
        {
            const r = f.row("Snapshots", .{});
            _ = kit.button(c, "Delete all", .{ .variant = .danger, .size = .sm });
            r.end();
        }
        f.end();
    }
};

test "a settings pane: cards, controls at the end, a note, a fold, a link and a danger zone, light and dark" {
    var x: SettingsPane = .{};
    try expectView("form-settings", .init(&x, SettingsPane.view), .{ .height = 560 });
    try expectView("form-settings-dark", .init(&x, SettingsPane.view), .{ .height = 560, .dark = true });
}

/// Gauges at a few values, one in a ramp's colors, and a stat as a
/// reading in a color, in a flow.
const Gauges = struct {
    const strength = [_]ui.Color{ .hex(0xf43f5e), .hex(0xfb923c), .hex(0xfacc15), .hex(0xa3e635), .hex(0x34d399) };

    fn view(_: *Gauges, c: *ui.Context) void {
        const t = kit.tokens(c);
        const root = ui.div(c).column().sizeFull().p(12);
        defer root.end();
        var f = controls.flow(c, 104, .{ .gap = 12 });
        for ([_]struct { f32, []const u8, []const u8 }{ .{ 0.62, "B", "62 bits" }, .{ 0.25, "25%", "battery" }, .{ 0.9, "A", "strong" } }, 0..) |g, i| {
            const cell = f.cell();
            controls.gauge(c, g[0], .{ .diameter = 104, .ramp = if (i == 1) &.{} else &strength, .text = g[1], .caption = g[2] });
            cell.end();
        }
        {
            const cell = f.cell();
            controls.stat(c, "Thermal", "Nominal", .{ .card = null, .size = .xs, .value_color = t.success });
            cell.end();
        }
        f.end();
    }
};

test "gauges and a reading in a flow, light and dark" {
    var x: Gauges = .{};
    try expectView("gauges", .init(&x, Gauges.view), .{ .height = 260 });
    try expectView("gauges-dark", .init(&x, Gauges.view), .{ .height = 260, .dark = true });
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

/// Pull requests by repository: one open with a group in it, one folded,
/// one whose heading fills a cell with its total, a row selected.
const Grouped = struct {
    open: [4]bool = .{ true, true, false, true },
    selected: ?usize = 2,

    const columns = [_]controls.GridColumn{
        .{ .title = "Title" },
        .{ .title = "Age", .width = 56, .alignment = .end },
    };
    const groups = [_]controls.GridGroup{ .{ .size = 2 }, .{ .size = 1, .depth = 1 }, .{ .size = 3 }, .{ .size = 2 } };
    const names = [_][]const u8{ "nanoui", "docs", "controls", "gallery" };
    const titles = [_][]const u8{ "Fix the scroll", "Faster text", "A new guide", "", "", "", "Sidebar view", "Charts page" };

    fn view(x: *Grouped, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull().p(8);
        defer root.end();
        const gs = controls.GridGroups.init(c, &groups, &x.open, .{});
        var g = controls.grid(c, &columns, .{ .count = gs.count(), .groups = gs, .selected = &x.selected });
        while (g.next()) |row| switch (gs.at(row.index)) {
            .heading => |h| if (h.group == 3) {
                g.heading(.{ .title = names[h.group], .cells = true });
                if (g.cellAt(1)) ui.text(c, "5d", .{ .size = 13, .weight = .semibold });
            } else g.heading(.{ .title = names[h.group], .detail = c.print("{d} pull request{s}", .{ groups[h.group].size, if (groups[h.group].size == 1) "" else "s" }) }),
            .row => |r| {
                g.cell();
                ui.text(c, titles[r.group * 2 + r.index], .{ .size = 13 });
                g.cell();
                ui.text(c, c.print("{d}d", .{r.index + 1}), .{ .size = 13 });
            },
        };
        g.end();
    }
};

test "a grid in groups, open, folded and nested, light and dark" {
    var x: Grouped = .{};
    try expectView("grid-groups", .init(&x, Grouped.view), .{ .height = 270 });
    x = .{};
    try expectView("grid-groups-dark", .init(&x, Grouped.view), .{ .height = 270, .dark = true });
}

/// The same groups under headings the caller draws: a chevron in a well,
/// the title over a line saying how many fail, two lines a row, a smaller
/// step.
const OwnHeadings = struct {
    open: [4]bool = .{ true, true, false, true },
    selected: ?usize = 2,

    fn view(x: *OwnHeadings, c: *ui.Context) void {
        const t = kit.tokens(c);
        const root = ui.div(c).column().sizeFull().p(8);
        defer root.end();
        const gs = controls.GridGroups.init(c, &Grouped.groups, &x.open, .{});
        var g = controls.grid(c, &Grouped.columns, .{ .count = gs.count(), .groups = gs, .selected = &x.selected, .lines = 2, .indent_step = 12 });
        while (g.next()) |row| switch (gs.at(row.index)) {
            .heading => |h| {
                const head = g.headingRow(.{ .title = Grouped.names[h.group] });
                defer head.box.end();
                {
                    const well = ui.div(c).w(16).h(16).roundedFull().bg(t.surface_hover).center();
                    defer well.end();
                    ui.icon(c, if (head.open) "chevron.down" else "chevron.right", .{ .size = 8, .color = t.foreground });
                }
                const lines = ui.div(c).column().gap(1);
                defer lines.end();
                ui.text(c, Grouped.names[h.group], .{ .size = 12, .weight = .semibold });
                ui.text(c, if (h.group == 0) "1 failing" else "all passing", .{ .size = 11, .color = if (h.group == 0) t.danger else t.muted });
            },
            .row => |r| {
                g.cell();
                ui.text(c, Grouped.titles[r.group * 2 + r.index], .{ .size = 13 });
                g.cell();
                ui.text(c, c.print("{d}d", .{r.index + 1}), .{ .size = 13 });
            },
        };
        g.end();
    }
};

test "a grid in groups under headings the caller draws, light and dark" {
    var x: OwnHeadings = .{};
    try expectView("grid-own-headings", .init(&x, OwnHeadings.view), .{ .height = 384 });
    x = .{};
    try expectView("grid-own-headings-dark", .init(&x, OwnHeadings.view), .{ .height = 384, .dark = true });
}

/// Two grids loading: one with rows in and a line under its titles, one
/// with none yet, its rows sketched.
fn loadingGrids(_: *u8, c: *ui.Context) void {
    const columns = [_]controls.GridColumn{
        .{ .title = "Name" },
        .{ .title = "Size", .width = 70, .alignment = .end },
        .{ .title = "Kind", .width = 70, .alignment = .center },
    };
    const root = ui.div(c).column().sizeFull().p(8).gap(10);
    defer root.end();
    {
        var g = controls.grid(c, &columns, .{ .count = 2, .max_rows = 2, .loading = .{ .label = "More", .done = 2, .total = 5 } });
        while (g.next()) |row| {
            g.cell();
            ui.text(c, if (row.index == 0) "notes.txt" else "photo.heic", .{ .size = 13 });
            g.cell();
            ui.text(c, "12 KB", .{ .size = 13 });
            g.cell();
            ui.text(c, "File", .{ .size = 13 });
        }
        g.end();
    }
    var g = controls.grid(c, &columns, .{ .count = 0, .empty = "No files", .loading = .{ .label = "Asking the server…", .done = 1, .total = 3 } });
    g.end();
}

test "grids loading, with rows and without, light and dark" {
    var x: u8 = 0;
    try expectView("grid-loading", .init(&x, loadingGrids), .{ .height = 270 });
    try expectView("grid-loading-dark", .init(&x, loadingGrids), .{ .height = 270, .dark = true });
}

/// Runs as cards without titles, one failed and one selected; then plain
/// rows of two lines, one with a warning.
fn runGrids(_: *u8, c: *ui.Context) void {
    const columns = [_]controls.GridColumn{
        .{ .title = "Run" },
        .{ .title = "Took", .width = 56, .alignment = .end },
    };
    const names = [_][]const u8{ "Build #412", "Tests #411", "Deploy #410" };
    const details = [_][]const u8{ "main · 2 min ago", "dev/35 · failed in snapshots", "main · an hour ago" };
    const root = ui.div(c).column().sizeFull().p(8).gap(12);
    defer root.end();
    for ([_]bool{ true, false }) |cards| {
        ui.keyInt(c, @intFromBool(cards));
        var selected: ?usize = if (cards) 0 else null;
        var g = controls.grid(c, &columns, .{ .count = 3, .max_rows = 3, .rows = if (cards) .cards else .plain, .lines = 2, .header = !cards, .selected = &selected });
        while (g.next()) |row| {
            if (row.index == 1) row.status(if (cards) .danger else .warning);
            g.cell();
            g.twoLines(names[row.index], details[row.index], .{});
            g.cell();
            ui.text(c, "2m", .{ .size = 13 });
        }
        g.end();
    }
}

test "runs as cards and as two-line rows, with statuses, light and dark" {
    var x: u8 = 0;
    try expectView("grid-cards", .init(&x, runGrids), .{ .height = 400 });
    try expectView("grid-cards-dark", .init(&x, runGrids), .{ .height = 400, .dark = true });
}

/// The charts' richer looks: bars in units with an axis and a short
/// history, a line with an axis at its end, a bar list of levels and one
/// of meters, stats with units, a detail and loading, a fitted legend
/// with swatches, and meters rounded at their ends and in zones.
fn richerCharts(_: *u8, c: *ui.Context) void {
    const t = kit.tokens(c);
    const heat = [_]ui.Color{ .hex(0x22d3ee), .hex(0xfbbf24), .hex(0xfb7185) };
    const load = [_]f32{ 22, 35, 30, 58, 64, 41, 77, 92, 70 };
    const root = ui.div(c).column().sizeFull().p(10).gap(10);
    defer root.end();
    {
        const row = ui.div(c).row().wFull().gap(14);
        defer row.end();
        var b = controls.bars(c, .{ .count = 16, .readings = load.len, .units = true, .max = 100, .fixed_max = true, .height = .{ .px = 56 }, .gap = 2, .axis = .start, .value_lines = &.{ .{ .value = 100, .label = "100" }, .{ .value = 50, .label = "50" }, .{ .value = 0, .label = "0" } }, .start_text = "-16 s", .end_text = "now", .width = .{ .px = 160 } });
        while (b.next()) |slot| {
            const v = load[slot.reading.?];
            slot.bar(&.{.{ .value = v, .color = controls.rampColor(&heat, v / 100) }});
        }
        b.end();
        var l = controls.line(c, &.{.{ .values = &load, .area = 0.15 }}, .{ .capacity = load.len, .max = 100, .fixed_max = true, .height = .{ .px = 56 }, .axis = .end, .value_lines = &.{ .{ .value = 80, .label = "80" }, .{ .value = 40, .label = "40" } }, .start_text = "-9 s", .end_text = "now" });
        l.end();
    }
    _ = controls.barList(c, &.{
        .{ .label = "CPU", .value = 74, .value_text = "74 °C", .detail = "max 94", .badge = "P", .icon = "cpu", .value_color = controls.rampColor(&heat, 0.6) },
        .{ .label = "GPU", .value = 52, .value_text = "52 °C", .detail = "max 81", .badge = "G", .icon = "cube" },
        .{ .label = "Disk", .value = 38, .value_text = "38 °C", .icon = "internaldrive" },
    }, .{ .min = 20, .max = 110, .ramp = &heat, .glow = 0.5, .label_width = 90 });
    _ = controls.barList(c, &.{
        .{ .label = "Fan 1", .value = 0.62, .value_text = "2,480 rpm" },
        .{ .label = "Fan 2", .value = 0.3, .value_text = "1,200 rpm" },
    }, .{ .max = 1, .style = .meter, .segments = 14, .ramp = &heat, .label_width = 90 });
    {
        const row = ui.div(c).row().wFull().gap(10).itemsStretch();
        defer row.end();
        controls.stat(c, "Peak", "87", .{ .unit = "%", .detail = "over the last hour", .size = .sm, .value_color = controls.rampColor(&heat, 0.87) });
        controls.stat(c, "Rate", "2.4", .{ .unit = "GB/s", .detail = "read", .size = .sm });
        controls.stat(c, "Queue", "0", .{ .loading = true, .detail = "asking…", .size = .sm });
    }
    {
        const row = ui.div(c).row().wFull().itemsCenter().gap(12);
        defer row.end();
        ui.text(c, "Memory", .{ .size = 13, .weight = .semibold });
        var lg = controls.legend(c, .{ .width = .fit });
        lg.item(t.primary, "App");
        lg.item(t.warning, "Wired");
        lg.end();
        ui.spacer(c);
        controls.legendSwatch(c, t.success, .{ .shape = .dot });
        controls.legendSwatch(c, t.danger, .{ .shape = .line });
    }
    controls.meter(c, 1, .{ .ramp = &heat, .gap = 0, .radius = 4, .height = .{ .px = 8 }, .segments = 40 });
    controls.meter(c, 0.5, .{ .segments = 15, .zones = &.{ "<20", "<40", "<60", "<80", "80+" }, .ramp = &heat });
}

test "the charts' richer looks, light and dark" {
    var x: u8 = 0;
    try expectView("charts-richer", .init(&x, richerCharts), .{ .height = 470 });
    try expectView("charts-richer-dark", .init(&x, richerCharts), .{ .height = 470, .dark = true });
}

/// Tasks by project, their headings open for tags, the task column sized
/// by hand and the owner's sharing what is left.
const Tagged = struct {
    open: [2]bool = .{ true, false },
    widths: [3]f32 = .{ 150, 0, 0 },

    const columns = [_]controls.GridColumn{
        .{ .title = "Task" },
        .{ .title = "Owner" },
        .{ .title = "Due", .width = 48, .alignment = .end },
    };
    const groups = [_]controls.GridGroup{ .{ .size = 2 }, .{ .size = 1 } };
    const names = [_][]const u8{ "Design", "Release" };
    const tasks = [_][]const u8{ "Draw the icons", "Pick the colors", "Write the notes" };

    fn view(x: *Tagged, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull().p(8);
        defer root.end();
        const gs = controls.GridGroups.init(c, &groups, &x.open, .{});
        var g = controls.grid(c, &columns, .{ .count = gs.count(), .groups = gs, .widths = &x.widths });
        while (g.next()) |row| switch (gs.at(row.index)) {
            .heading => |h| {
                const box = g.headingOpen(.{ .title = names[h.group], .detail = c.print("{d}", .{groups[h.group].size}) });
                if (h.group == 0) kit.tag(c, "2 OVERDUE", .{ .status = .warning, .size = .xs, .pill = true });
                kit.tag(c, "1 NEW", .{ .status = .info, .size = .xs, .pill = true });
                box.end();
            },
            .row => |r| {
                const i = r.group * 2 + r.index;
                g.cell();
                ui.text(c, tasks[i], .{ .size = 13, .truncate = .ellipsis });
                g.cell();
                ui.text(c, if (i == 1) "Sam" else "Alex", .{ .size = 13 });
                g.cell();
                ui.text(c, c.print("{d}d", .{i + 1}), .{ .size = 13 });
            },
        };
        g.end();
    }
};

test "a grid's headings open for tags, a column sized by hand, light and dark" {
    var x: Tagged = .{};
    try expectView("grid-headings-open", .init(&x, Tagged.view), .{ .height = 150 });
    x = .{};
    try expectView("grid-headings-open-dark", .init(&x, Tagged.view), .{ .height = 150, .dark = true });
}

/// Sidebars whose counts are loading, narrowed to their icons and wide:
/// a plain count, a pill, a branch, and a count that has come.
fn loadingSidebars(_: *u8, c: *ui.Context) void {
    const root = ui.div(c).row().sizeFull().p(8).gap(8);
    defer root.end();
    for ([_]bool{ true, false }) |icons_only| {
        ui.keyInt(c, @intFromBool(icons_only));
        const col = ui.div(c).column().w(if (icons_only) 44 else 200).hFull();
        defer col.end();
        var sb = controls.sidebar(c, "mail", "inbox", .{ .icons_only = icons_only });
        sb.item("inbox", "Inbox", .{ .icon = "globe", .count = 3 });
        sb.heading("Accounts");
        sb.item("sent", "Sent", .{ .icon = "arrow.up", .loading = true });
        sb.item("unread", "Unread", .{ .icon = "doc.text", .count_style = .pill, .loading = true });
        var open = true;
        if (sb.branch("folders", "Folders", .{ .icon = "folder", .loading = true }, &open)) |g| {
            sb.item("archive", "Archive", .{ .icon = "doc" });
            g.end();
        }
        _ = sb.end();
    }
}

test "sidebars whose counts are loading, light and dark" {
    var x: u8 = 0;
    try expectView("sidebar-loading", .init(&x, loadingSidebars), .{ .height = 200 });
    try expectView("sidebar-loading-dark", .init(&x, loadingSidebars), .{ .height = 200, .dark = true });
}

/// Bars with a baseline and a fade, quiet readings still showing, and
/// stats keyed to their series.
fn keyedCharts(_: *u8, c: *ui.Context) void {
    const t = kit.tokens(c);
    const read = [_]f32{ 0, 0.4, 2.1, 0, 0, 3.2, 1.1, 0, 0.2, 2.6, 4.1, 0.8 };
    const write = [_]f32{ 0, 0, 0.6, 0.3, 0, 1.2, 0, 0, 0, 0.9, 1.4, 0.2 };
    const root = ui.div(c).column().sizeFull().p(10).gap(10);
    defer root.end();
    var b = controls.bars(c, .{ .count = 16, .readings = read.len, .units = true, .height = .{ .px = 56 }, .gap = 2, .baseline = 0.04, .fade = 0.35 });
    while (b.next()) |slot| {
        const i = slot.reading.?;
        slot.bar(&.{ .{ .value = read[i], .color = t.primary }, .{ .value = write[i], .color = t.success } });
    }
    b.end();
    const row = ui.div(c).row().wFull().gap(10).itemsStretch();
    defer row.end();
    controls.stat(c, "Read", "2.4", .{ .unit = "MB/s", .key = t.primary, .size = .sm });
    controls.stat(c, "Write", "0.9", .{ .unit = "MB/s", .key = t.success, .size = .sm, .card = null });
}

test "bars with a baseline and a fade, and stats with a key, light and dark" {
    var x: u8 = 0;
    try expectView("charts-keyed", .init(&x, keyedCharts), .{ .height = 170 });
    try expectView("charts-keyed-dark", .init(&x, keyedCharts), .{ .height = 170, .dark = true });
}

/// Pills in each status, lead and shape, and a size up; captions with an
/// aside, an open line and one cut short; and a row of compact readings.
fn pillsAndCaptions(_: *u8, c: *ui.Context) void {
    const t = kit.tokens(c);
    const root = ui.div(c).column().sizeFull().p(10).gap(10);
    defer root.end();
    {
        const row = ui.div(c).row().gap(6).itemsCenter();
        defer row.end();
        controls.pill(c, "LIVE", .{ .status = .success, .lead = .{ .dot = .{} } });
        controls.pill(c, "3 FAILED", .{ .status = .danger });
        controls.pill(c, "SYNCING", .{ .lead = .{ .icon = .{ .name = "arrow.clockwise" } } });
        controls.pill(c, "REC", .{ .status = .warning, .lead = .{ .dot = .{ .dim = true } } });
    }
    {
        const row = ui.div(c).row().gap(6).itemsCenter();
        defer row.end();
        controls.pill(c, "P", .{ .shape = .box });
        controls.pill(c, "ROSETTA", .{ .shape = .box, .status = .info });
        controls.pill(c, "0.42", .{ .mono = true, .status = .neutral });
        controls.pill(c, "Ready", .{ .size = .sm, .status = .success });
    }
    controls.caption(c, "MEMORY", .{ .aside = "16 GB" });
    {
        const h = controls.captionOpen(c, "LIGHTS", .{ .icon = "sun.max" });
        controls.pill(c, "3 ON", .{ .status = .warning });
        h.trailing();
        ui.text(c, "80%", .{ .size = 12, .color = t.muted });
        h.end();
    }
    {
        const h = controls.captionOpen(c, "/Users/someone/Documents/Projects/a-long-folder-name", .{ .cut = true });
        h.trailing();
        _ = kit.button(c, "Open", .{ .size = .xs });
        h.end();
    }
    var f = controls.flow(c, 100, .{ .gap = 12 });
    const reading: controls.StatOptions = .{ .size = .xs, .card = null, .mono = true };
    f.stat("FILES", "312", reading);
    f.stat("SIZE", "4.2 GB", reading);
    f.stat("TIME", "0:42", reading);
    f.end();
}

test "pills, captions and compact readings, light and dark" {
    var x: u8 = 0;
    try expectView("pills-captions", .init(&x, pillsAndCaptions), .{ .height = 230 });
    try expectView("pills-captions-dark", .init(&x, pillsAndCaptions), .{ .height = 230, .dark = true });
}

/// Panels: plain and titled, tinted by a status, folding (one open, one
/// folded), and notices with a button and loading.
const Panels = struct {
    open: bool = true,
    folded: bool = false,

    fn view(x: *Panels, c: *ui.Context) void {
        const t = kit.tokens(c);
        const root = ui.div(c).column().sizeFull().p(10).gap(10);
        defer root.end();
        {
            const row = ui.div(c).row().wFull().gap(10).itemsStart();
            defer row.end();
            {
                const p = controls.panel(c, .{ .title = "RETENTION", .card = .{ .width = .{ .px = 165 } } });
                defer p.end();
                ui.text(c, "Keep 10 snapshots", .{ .size = 12 });
            }
            {
                const p = controls.panel(c, .{ .title = "DANGER ZONE", .status = .danger, .card = .{ .width = .{ .px = 165 } } });
                defer p.end();
                ui.text(c, "Can't be undone.", .{ .size = 12, .color = t.muted });
            }
        }
        {
            const p = controls.panel(c, .{ .title = "ADVANCED", .open = &x.open });
            defer p.end();
            if (x.open) ui.text(c, "Compression: zstd", .{ .size = 12 });
        }
        controls.panel(c, .{ .title = "LOGS", .open = &x.folded }).end();
        {
            const n = controls.noticeOpen(c, .{ .icon = "network", .title = "Server stopped", .description = "Start it to back up again.", .status = .warning });
            defer n.end();
            _ = kit.button(c, "Start", .{ .size = .sm, .variant = .primary });
        }
        controls.notice(c, .{ .loading = true, .title = "Connecting", .description = "Asking the server.", .card = .{ .py = 16 } });
    }
};

test "panels and notices, light and dark" {
    var x: Panels = .{};
    try expectView("panels-notices", .init(&x, Panels.view), .{ .height = 520 });
    x = .{};
    try expectView("panels-notices-dark", .init(&x, Panels.view), .{ .height = 520, .dark = true });
}

/// Callouts in each status, with a title, plain, closable, and open with
/// a button.
fn callouts(_: *u8, c: *ui.Context) void {
    const root = ui.div(c).column().sizeFull().p(10).gap(8);
    defer root.end();
    _ = controls.callout(c, "Snapshots are kept for 30 days.", .{});
    _ = controls.callout(c, "Backed up 312 files.", .{ .status = .success, .announce = false });
    _ = controls.callout(c, "That folder doesn't exist any more, so it is skipped.", .{ .status = .warning, .title = "Missing folder", .announce = false });
    _ = controls.callout(c, "The disk is full.", .{ .status = .danger, .closable = true, .announce = false });
    {
        const r = controls.calloutOpen(c, "Couldn't reach the server.", .{ .status = .info });
        defer r.end();
        _ = kit.button(c, "Retry", .{ .size = .xs });
    }
    _ = controls.callout(c, "Everything is up to date.", .{ .plain = true, .status = .success, .announce = false });
}

test "callouts, light and dark" {
    var x: u8 = 0;
    try expectView("callouts", .init(&x, callouts), .{ .height = 330 });
    try expectView("callouts-dark", .init(&x, callouts), .{ .height = 330, .dark = true });
}

/// Segmented groups and tab strips: counts, a count loading, an alert, a
/// disabled option, icons, and an open strip with a button.
const Choosing = struct {
    range: usize = 1,
    mode: usize = 0,
    tab: usize = 0,
    other: usize = 2,

    fn view(x: *Choosing, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull().p(10).gap(12);
        defer root.end();
        _ = controls.segmented(c, &.{ .{ .label = "Today" }, .{ .label = "Week", .count = 12 }, .{ .label = "Month", .disabled = true } }, &x.range, .{});
        _ = controls.segmented(c, &.{ .{ .label = "List", .icon = "list.bullet" }, .{ .label = "Grid", .icon = "square.grid.2x2" } }, &x.mode, .{ .size = .xs });
        _ = controls.tabStrip(c, &.{ .{ .label = "Reviews", .count = 3 }, .{ .label = "Failed", .count = 2, .alert = true }, .{ .label = "Work", .loading = true } }, &x.tab, .{});
        var s = controls.tabStripOpen(c, &.{ .{ .label = "General" }, .{ .label = "Sync", .disabled = true }, .{ .label = "Archive", .count = 1500 } }, &x.other, .{ .size = .xs });
        _ = kit.button(c, "Manage", .{ .size = .xs, .variant = .ghost });
        _ = s.end();
    }
};

test "segmented groups and tab strips, light and dark" {
    var x: Choosing = .{};
    try expectView("choosing", .init(&x, Choosing.view), .{ .height = 190 });
    x = .{};
    try expectView("choosing-dark", .init(&x, Choosing.view), .{ .height = 190, .dark = true });
}

/// Toasts in the bottom right corner: a plain one, each status, a title,
/// and an action.
const Toasting = struct {
    list: controls.Toasts = .{},

    fn view(x: *Toasting, c: *ui.Context) void {
        if (x.list.n == 0) {
            _ = x.list.show("Saved.", .{ .seconds = 0 });
            _ = x.list.show("Restored 120 files.", .{ .status = .success, .action = "Undo", .seconds = 0 });
            _ = x.list.show("The repository is locked by another client.", .{ .status = .danger, .title = "Backup failed", .seconds = 0 });
        }
        ui.div(c).sizeFull().end();
        _ = controls.toasts(c, &x.list, .{ .width = 320, .margin = 12 });
    }
};

test "toasts in a corner, light and dark" {
    var x: Toasting = .{};
    try expectView("toasts", .init(&x, Toasting.view), .{ .height = 260 });
    x = .{};
    try expectView("toasts-dark", .init(&x, Toasting.view), .{ .height = 260, .dark = true });
}

/// A chip input with an inherited value and one that doesn't read, a
/// disabled one, and chips on and off, one with a swatch.
const Chipping = struct {
    field: ui.TextBuffer = .{},
    other: ui.TextBuffer = .{},
    grouped: bool = true,
    failing: bool = false,
    green: bool = true,

    fn view(x: *Chipping, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull().p(10).gap(10);
        defer root.end();
        _ = controls.chipInput(c, &.{ "9:00", "21:30", "noon" }, &x.field, .{ .inherited = &.{"3:00"}, .invalid = &.{ false, false, true }, .add_placeholder = "add a time" });
        _ = controls.chipInput(c, &.{ "*.tmp", "node_modules/" }, &x.other, .{ .disabled = true, .mono = true });
        const row = ui.div(c).row().gap(6);
        defer row.end();
        _ = controls.chip(c, "Grouped", &x.grouped, .{});
        _ = controls.chip(c, "Failing only", &x.failing, .{});
        _ = controls.chip(c, "Green", &x.green, .{ .swatch = .hex(0x22c55e) });
    }
};

test "chips to type into and chips on and off, light and dark" {
    var x: Chipping = .{};
    defer x.field.deinit();
    defer x.other.deinit();
    try expectView("chips", .init(&x, Chipping.view), .{ .height = 150 });
    try expectView("chips-dark", .init(&x, Chipping.view), .{ .height = 150, .dark = true });
}
