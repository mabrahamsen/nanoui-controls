//! The gallery's grouped grid: pull requests by repository, in groups
//! that fold (click a heading, or Left and Right on it, Enter or Space),
//! "docs" a group in "nanoui". "Grouped" lists them flat when off, "Cards"
//! draws them as cards, "Two lines" shows each one's branch under its
//! title, "One-row groups" shows a heading over a repository's only
//! pull request, and "Own headings" draws the headings the app's way (a
//! chevron in a well, how many fail on a second line, a smaller step, no
//! fade); a failing one's row is tinted. Narrow the window, or
//! widen the sidebar, and the Repository column gives way when the grid
//! is narrow. "Reload" asks for them again, their rows sketched until
//! they arrive; "Load more" adds a repository while a thin line runs
//! under the titles. Backspace goes to the first row, Escape clears the
//! selection.
const std = @import("std");
const nanoui = @import("nanoui");
const controls = @import("nanoui_controls");
const ui = nanoui.ui;
const kit = nanoui.kit;

const Pull = struct {
    title: []const u8,
    branch: []const u8,
    age: u32,
    failing: bool = false,
};

const Repo = struct {
    name: []const u8,
    depth: u8 = 0,
    pulls: []const Pull,
};

const repos = [_]Repo{
    .{ .name = "nanoui", .pulls = &.{
        .{ .title = "Fix the scroll on a trackpad", .branch = "dev/88-scroll", .age = 1 },
        .{ .title = "Faster text layout", .branch = "dev/91-text", .age = 2, .failing = true },
        .{ .title = "A dark theme for the kit's menus", .branch = "dev/92-menus", .age = 4 },
    } },
    .{ .name = "docs", .depth = 1, .pulls = &.{
        .{ .title = "A guide to the layout", .branch = "dev/12-layout", .age = 3 },
        .{ .title = "Fix links in the README", .branch = "dev/13-links", .age = 6 },
    } },
    .{ .name = "controls", .pulls = &.{
        .{ .title = "Grid: groups that fold", .branch = "dev/35-grid", .age = 0 },
        .{ .title = "Charts: an axis for bars", .branch = "dev/37-charts", .age = 1, .failing = true },
        .{ .title = "Pills and panels", .branch = "dev/38-pills", .age = 2 },
        .{ .title = "Sidebar: branches", .branch = "dev/34-sidebar", .age = 5 },
    } },
    .{ .name = "gallery", .pulls = &.{
        .{ .title = "A view of every chart", .branch = "dev/7-charts", .age = 9 },
    } },
    .{ .name = "website", .pulls = &.{
        .{ .title = "A page for each control", .branch = "dev/3-pages", .age = 1 },
        .{ .title = "Screenshots in dark", .branch = "dev/4-dark", .age = 2 },
    } },
};

const columns = [_]controls.GridColumn{
    .{ .title = "Title" },
    .{ .title = "Repository", .width = 110, .min_grid_width = 520 },
    .{ .title = "Checks", .width = 70, .alignment = .center },
    .{ .title = "Age", .width = 56, .alignment = .end },
};

/// How long a reload or a load of more takes, as from a server.
const wait = 1.5;

pub const Pulls = struct {
    open: [repos.len]bool = @splat(true),
    grouped: bool = true,
    cards: bool = false,
    two_lines: bool = true,
    singles: bool = false,
    own_headings: bool = false,
    selected: ?usize = null,
    /// The repositories loaded so far: "Load more" adds the last.
    shown: usize = repos.len - 1,
    loading: enum { none, reload, more } = .none,
    since: f64 = 0,
    started: bool = false,

    pub fn view(p: *Pulls, c: *ui.Context) void {
        const t = kit.tokens(c);
        const page = ui.div(c).column().wFull().hFull().p(16).gap(12);
        defer page.end();
        {
            const bar = ui.div(c).row().wFull().itemsCenter().gap(16);
            defer bar.end();
            ui.text(c, "Pull requests", .{ .size = 16, .weight = .semibold });
            ui.spacer(c);
            if (kit.button(c, "Reload", .{ .size = .sm, .disabled = p.loading != .none }).clicked) p.start(c, .reload);
            if (kit.button(c, "Load more", .{ .size = .sm, .disabled = p.loading != .none or p.shown == repos.len }).clicked) p.start(c, .more);
        }
        {
            const bar = ui.div(c).row().wFull().itemsCenter().gap(16);
            defer bar.end();
            _ = ui.toggle(c, "Grouped", &p.grouped);
            _ = ui.toggle(c, "Cards", &p.cards);
            _ = ui.toggle(c, "Two lines", &p.two_lines);
            _ = ui.toggle(c, "One-row groups", &p.singles);
            _ = ui.toggle(c, "Own headings", &p.own_headings);
        }
        p.arrive(c);

        // The groups, as many as are loaded, and how the rows map to them.
        var groups: [repos.len]controls.GridGroup = undefined;
        var total: usize = 0;
        for (repos[0..p.shown], 0..) |r, i| {
            groups[i] = .{ .size = r.pulls.len, .depth = r.depth };
            total += r.pulls.len;
        }
        const gs = controls.GridGroups.init(c, groups[0..p.shown], p.open[0..p.shown], .{ .singles = p.singles });
        const reloading = p.loading == .reload;
        const count = if (reloading) 0 else if (p.grouped) gs.count() else total;
        const elapsed = c.time - p.since;
        const loading: ?controls.GridLoading = switch (p.loading) {
            .none => null,
            .reload => .{ .label = "Asking for pull requests…", .done = @intFromFloat(@min(1, elapsed / wait) * @as(f64, @floatFromInt(p.shown))), .total = p.shown },
            .more => .{ .label = "Loading more" },
        };
        if (!p.started) c.focusNext(false);
        p.started = true;
        var g = controls.grid(c, &columns, .{
            .count = count,
            .groups = if (p.grouped and !reloading) gs else null,
            .selected = &p.selected,
            .loading = loading,
            .rows = if (p.cards) .cards else .plain,
            .lines = if (p.two_lines) 2 else 1,
            .header = !p.cards,
            .empty = "No pull requests.",
            .indent_step = if (p.own_headings) 12 else 18,
            .fade_in = !p.own_headings,
        });
        if (g.back and count > 0) p.selected = 0;
        if (g.escaped) p.selected = null;
        while (g.next()) |row| {
            const at = if (p.grouped) gs.at(row.index) else flat(row.index);
            switch (at) {
                .heading => |h| {
                    const repo = repos[h.group];
                    var failing: usize = 0;
                    for (repo.pulls) |pull| failing += @intFromBool(pull.failing);
                    const detail = c.print("{d} pull request{s}", .{ repo.pulls.len, if (repo.pulls.len == 1) "" else "s" });
                    if (p.own_headings) {
                        ownHeading(&g, repo.name, detail, failing, p.two_lines);
                        continue;
                    }
                    // Open after its detail for a tag counting the failing.
                    const box = g.headingOpen(.{ .title = repo.name, .detail = detail, .label = if (failing > 0) c.print("{s}, {s}, {d} failing", .{ repo.name, detail, failing }) else "" });
                    if (failing > 0) kit.tag(c, c.print("{d} FAILING", .{failing}), .{ .status = .danger, .size = .xs, .pill = true });
                    box.end();
                },
                .row => |r| {
                    const pull = repos[r.group].pulls[r.index];
                    if (pull.failing) row.status(.danger);
                    g.cell();
                    if (p.two_lines) {
                        g.twoLines(pull.title, pull.branch, .{ .mono_detail = true });
                    } else ui.text(c, pull.title, .{ .truncate = .ellipsis });
                    if (g.cellAt(1)) ui.text(c, repos[r.group].name, .{ .color = t.muted, .truncate = .ellipsis });
                    _ = g.cellAt(2);
                    ui.text(c, if (pull.failing) "failing" else "passing", .{ .size = 12, .color = if (pull.failing) t.danger else t.success });
                    _ = g.cellAt(3);
                    ui.text(c, if (pull.age == 0) "today" else c.print("{d}d", .{pull.age}), .{ .color = t.muted });
                },
            }
        }
        g.end();
        ui.text(c, if (p.selected) |i| c.print("Row {d} selected: Left goes to its heading, Backspace to the first row, Escape clears it.", .{i}) else "Click a heading to fold it, or a row to select it, then use the arrow keys.", .{ .color = t.muted });
    }

    fn start(p: *Pulls, c: *ui.Context, what: @TypeOf(p.loading)) void {
        p.loading = what;
        p.since = c.time;
        c.frameIn(wait);
    }

    /// Ends the loading once its time is up.
    fn arrive(p: *Pulls, c: *ui.Context) void {
        if (p.loading == .none) return;
        if (c.time - p.since < wait) {
            c.frameIn(0.1);
            return;
        }
        if (p.loading == .more) p.shown = @min(repos.len, p.shown + 1);
        p.loading = .none;
        c.changed = true;
    }
};

/// Row `i` of the pull requests listed flat, as a group's row.
fn flat(i: usize) controls.GridGroupItem {
    var n = i;
    for (repos, 0..) |r, g| {
        if (n < r.pulls.len) return .{ .row = .{ .group = g, .index = n, .depth = 0 } };
        n -= r.pulls.len;
    }
    unreachable;
}

/// A heading drawn the app's way in the row the grid gives it: a chevron
/// in a round well, the title, and with two lines how many fail under it.
fn ownHeading(g: *controls.Grid, name: []const u8, detail: []const u8, failing: usize, two_lines: bool) void {
    const c = g.c;
    const t = kit.tokens(c);
    const head = g.headingRow(.{ .title = name, .detail = detail, .label = if (failing > 0) c.print("{s}, {s}, {d} failing", .{ name, detail, failing }) else "" });
    defer head.box.end();
    {
        const well = ui.div(c).w(16).h(16).roundedFull().bg(t.surface_hover).center();
        defer well.end();
        ui.icon(c, if (head.open) "chevron.down" else "chevron.right", .{ .size = 8, .color = t.foreground });
    }
    const lines = ui.div(c).column().gap(1);
    defer lines.end();
    ui.text(c, name, .{ .size = 12, .weight = .semibold });
    if (two_lines) ui.text(c, if (failing > 0) c.print("{d} failing of {s}", .{ failing, detail }) else detail, .{ .size = 11, .color = if (failing > 0) t.danger else t.muted });
}
