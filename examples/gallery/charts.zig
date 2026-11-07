//! The gallery's charts: a system monitor whose readings change four
//! times a second. Stats sum it up at the top. The CPU's load is a trend
//! with a line at half and a meter, and how it changed each time is bars
//! up and down from zero. Network traffic is a line chart of read and
//! write, filled under; point at it, or click it and use Left and Right,
//! to read a moment's figures. Memory is a donut and a breakdown by kind
//! with a legend that runs on to new lines in a narrow window, disk use
//! is a list of bars by folder (click one), the fan is a level that
//! glows, and a strip shows the heat ramp. "Running" pauses the readings,
//! "Heat" colors the load by the ramp instead of the accent, "Glow"
//! lights the meters up and "Fade" fades the older bars of the trend; the
//! slider sets how many segments the meter has. The histories are kept
//! in rings, which the charts read from their oldest reading on.
const std = @import("std");
const nanoui = @import("nanoui");
const controls = @import("nanoui_controls");
const ui = nanoui.ui;
const kit = nanoui.kit;

/// How many readings the histories keep, and how often one comes.
const capacity = 60;
const every = 0.25;

/// Readings in a ring: once it is full, a new one takes the oldest's
/// place, and `head` moves on to the next oldest.
const History = struct {
    values: [capacity]f32 = undefined,
    len: usize = 0,
    head: usize = 0,

    fn add(h: *History, v: f32) void {
        if (h.len < capacity) {
            h.values[h.len] = v;
            h.len += 1;
        } else {
            h.values[h.head] = v;
            h.head = (h.head + 1) % capacity;
        }
    }

    fn slice(h: *const History) []const f32 {
        return h.values[0..h.len];
    }

    /// The reading `back` before the newest.
    fn ago(h: *const History, back: usize) f32 {
        if (back >= h.len) return 0;
        return h.values[(h.head + h.len - 1 - back) % h.len];
    }

    /// Reading `i`, oldest first.
    fn at(h: *const History, i: usize) f32 {
        return h.values[(h.head + i) % h.len];
    }
};

/// Cool at the bottom, through amber, to hot at the top.
const heat = [_]ui.Color{ .hex(0x22d3ee), .hex(0xfbbf24), .hex(0xfb7185) };

const Folder = struct { name: []const u8, gb: f32 };
const folders = [_]Folder{
    .{ .name = "Photos", .gb = 41.2 },
    .{ .name = "Projects", .gb = 23.6 },
    .{ .name = "Music", .gb = 12.9 },
    .{ .name = "Mail", .gb = 6.1 },
    .{ .name = "Documents", .gb = 4.4 },
};

pub const Monitor = struct {
    load: History = .{},
    /// How the load changed at each reading.
    change: History = .{},
    /// Megabytes a second read and written.
    read: History = .{},
    write: History = .{},
    /// Gigabytes in use by kind, of `total`.
    memory: [3]f32 = .{ 9, 3, 1 },
    fan: f32 = 0.4,
    next: f64 = 0,
    random: std.Random.DefaultPrng = .init(17),
    running: bool = true,
    heat: bool = true,
    glow: bool = true,
    fade: bool = true,
    segments: f32 = 24,
    /// The folder last clicked in the disk list.
    opened: ?usize = null,

    const total = 24;
    const traffic_top = 40;

    pub fn view(m: *Monitor, c: *ui.Context) void {
        const t = kit.tokens(c);
        if (m.running) {
            if (c.time >= m.next) {
                m.tick();
                m.next = c.time + every;
            }
            c.animationFrame();
        }
        const scroll = ui.div(c).column().sizeFull().scrollY();
        defer scroll.end();
        const root = ui.div(c).column().wFull().p(16).gap(12);
        defer root.end();
        {
            const bar = ui.div(c).row().wFull().itemsCenter().gap(16);
            defer bar.end();
            ui.text(c, "Monitor", .{ .size = 16, .weight = .semibold });
            ui.spacer(c);
            _ = ui.toggle(c, "Running", &m.running);
            _ = ui.toggle(c, "Heat", &m.heat);
            _ = ui.toggle(c, "Glow", &m.glow);
            _ = ui.toggle(c, "Fade", &m.fade);
        }
        {
            const bar = ui.div(c).row().wFull().itemsCenter().gap(10);
            defer bar.end();
            ui.textf(c, .{ .size = 12, .color = t.muted }, "Segments {d}", .{@as(u32, @intFromFloat(m.segments))});
            _ = ui.slider(c, &m.segments, .{ .min = 4, .max = 48, .label = "Segments" });
        }
        const glow: f32 = if (m.glow) 0.6 else 0;
        const ramp: []const ui.Color = if (m.heat) &heat else &.{};
        const load = m.load.ago(0);
        const used = m.memory[0] + m.memory[1] + m.memory[2];
        const traffic = m.read.ago(0) + m.write.ago(0);

        {
            // Stretched, the tiles are one height, whatever is in them.
            const row = ui.div(c).row().wFull().gap(10).itemsStretch();
            defer row.end();
            // Since the oldest reading kept: a quarter of a minute ago, or less.
            const minute = (load - m.load.ago(m.load.len -| 1)) * 100;
            controls.stat(c, "CPU", c.print("{d:.0}%", .{load * 100}), .{
                .change = c.print("{s}{d:.0} pts", .{ if (minute >= 0) "+" else "−", @abs(minute) }),
                .status = if (minute > 5) .warning else .neutral,
                .history = m.load.slice(),
                .history_head = m.load.head,
                .size = .sm,
            });
            controls.stat(c, "Memory", c.print("{d:.1} GB", .{used}), .{ .change = c.print("{d:.0}% free", .{(total - used) / total * 100}), .size = .sm });
            controls.stat(c, "Network", c.print("{d:.1} MB/s", .{traffic}), .{
                .change = if (traffic > 30) "busy" else "quiet",
                .status = if (traffic > 30) .info else .neutral,
                .history = m.read.slice(),
                .history_head = m.read.head,
                .color = t.success,
                .size = .sm,
            });
        }

        section(c, "CPU", c.print("{d:.0}%", .{load * 100}));
        controls.trend(c, m.load.slice(), .{
            .capacity = capacity,
            .head = m.load.head,
            .height = .{ .px = 48 },
            .ramp = ramp,
            .fade = if (m.fade) 0.35 else null,
            .value_lines = &.{.{ .value = 0.5, .label = "50%" }},
            .label = "CPU history",
            .value_text = c.print("{d:.0}%", .{load * 100}),
        });
        controls.meter(c, load, .{ .segments = @intFromFloat(@round(m.segments)), .ramp = ramp, .glow = glow, .label = "CPU load" });
        {
            var b = controls.bars(c, .{ .count = capacity, .height = .{ .px = 36 }, .below = 0.5, .interactive = true, .label = "CPU load change" });
            const empty = capacity - m.change.len;
            while (b.next()) |slot| {
                if (slot.index < empty) continue;
                const d = m.change.at(slot.index - empty);
                slot.bar(&.{.{ .value = d * 2, .color = if (d < 0) t.success else t.warning }});
            }
            if (b.current) |i| b.tooltip(if (i >= empty) c.print("{s}{d:.1} pts", .{ if (m.change.at(i - empty) >= 0) "+" else "−", @abs(m.change.at(i - empty)) * 100 }) else "no reading");
            b.end();
        }

        section(c, "Network", c.print("{d:.1} MB/s", .{traffic}));
        {
            var l = controls.line(c, &.{
                .{ .values = m.read.slice(), .head = m.read.head, .area = 0.15 },
                .{ .values = m.write.slice(), .head = m.write.head, .color = t.success, .area = 0.1 },
            }, .{
                .capacity = capacity,
                .height = .{ .px = 72 },
                .max = traffic_top,
                .value_lines = &.{.{ .value = 20, .label = "20 MB/s" }},
                .interactive = true,
                .label = "Network traffic",
                .value_text = c.print("{d:.1} MB/s", .{traffic}),
            });
            const empty = capacity - m.read.len;
            if (l.current) |i| l.tooltip(if (i >= empty) c.print("read {d:.1} MB/s, write {d:.1} MB/s", .{ m.read.at(i - empty), m.write.at(i - empty) }) else "no reading");
            l.end();
            var g = controls.legend(c, .{ .mono = true });
            g.item(t.primary, "Read");
            g.item(t.success, "Write");
            g.trailing("point at the chart, or click it and use ← →");
            g.end();
        }

        section(c, "Memory", c.print("{d:.1} of {d} GB", .{ used, total }));
        const parts = [_]controls.BarPart{
            .{ .value = m.memory[0] / total, .color = t.primary },
            .{ .value = m.memory[1] / total, .color = t.warning },
            .{ .value = m.memory[2] / total, .color = t.info },
        };
        {
            const row = ui.div(c).row().wFull().gap(20).itemsCenter();
            defer row.end();
            controls.donut(c, &parts, .{
                .size = 104,
                .text = c.print("{d:.0}%", .{used / total * 100}),
                .caption = "used",
                .label = "Memory",
                .value_text = c.print("{d:.0}% used", .{used / total * 100}),
            });
            const right = ui.div(c).column().wFull().gap(10);
            defer right.end();
            controls.breakdown(c, &parts, .{ .height = 10, .label = "Memory by kind", .value_text = c.print("{d:.1} of {d} GB", .{ used, total }) });
            var l = controls.legend(c, .{ .mono = true });
            l.item(t.primary, c.print("App {d:.1} GB", .{m.memory[0]}));
            l.item(t.warning, c.print("Wired {d:.1} GB", .{m.memory[1]}));
            l.item(t.info, c.print("Compressed {d:.1} GB", .{m.memory[2]}));
            l.trailing(c.print("Free {d:.1} GB", .{total - used}));
            l.end();
        }

        section(c, "Disk", if (m.opened) |i| c.print("opened {s}", .{folders[i].name}) else "click a folder");
        {
            var items: [folders.len]controls.BarListItem = undefined;
            for (folders, &items) |f, *it| it.* = .{ .label = f.name, .value = f.gb, .value_text = c.print("{d:.1} GB", .{f.gb}) };
            if (controls.barList(c, &items, .{ .clickable = true })) |i| m.opened = i;
        }

        section(c, "Fan", c.print("{d:.0} rpm", .{1200 + m.fan * 4800}));
        const fan_color = if (ramp.len > 0) controls.rampColor(ramp, m.fan) else t.primary;
        controls.breakdown(c, &.{.{ .value = m.fan, .color = fan_color }}, .{ .part_radius = 3, .glow = glow, .label = "Fan", .value_text = c.print("{d:.0}%", .{m.fan * 100}) });

        section(c, "Heat ramp", "");
        controls.meter(c, 1, .{ .segments = 48, .ramp = &heat, .gap = 0, .radius = 0, .height = 6 });
    }

    /// How many readings kept were over 80%: the alerts, for the sidebar.
    pub fn alerts(m: *const Monitor) usize {
        var n: usize = 0;
        for (m.load.slice()) |v| n += @intFromBool(v > 0.8);
        return n;
    }

    /// A new reading for each chart, wandering from the last.
    fn tick(m: *Monitor) void {
        const r = m.random.random();
        const before = m.load.ago(0);
        m.load.add(std.math.clamp(before + (r.float(f32) - 0.48) * 0.25, 0.02, 1));
        m.change.add(m.load.ago(0) - before);
        m.read.add(@max(0, m.read.ago(0) * 0.6 + r.float(f32) * 14 + if (r.float(f32) < 0.1) 18 * r.float(f32) else 0));
        m.write.add(@max(0, m.write.ago(0) * 0.5 + r.float(f32) * 6));
        for (&m.memory, [_]f32{ 14, 5, 3 }) |*g, top| g.* = std.math.clamp(g.* + (r.float(f32) - 0.5) * 0.4, 0.5, top);
        m.fan = std.math.clamp(m.fan * 0.9 + m.load.ago(0) * 0.1 + (r.float(f32) - 0.5) * 0.05, 0, 1);
    }
};

/// A chart's title, and what it reads at the end.
fn section(c: *ui.Context, title: []const u8, reading: []const u8) void {
    const t = kit.tokens(c);
    const row = ui.div(c).row().wFull().itemsCenter().pt(6);
    defer row.end();
    ui.text(c, title, .{ .size = 13, .weight = .semibold });
    ui.spacer(c);
    ui.text(c, reading, .{ .size = 12, .mono = true, .color = t.muted });
}

/// The monitor, with half a history to start with, so the charts aren't
/// empty.
pub fn init() Monitor {
    var m: Monitor = .{};
    for (0..capacity / 2) |_| m.tick();
    return m;
}

/// Each chart once, as figures that don't change: what each looks like,
/// side by side, in the theme's colors.
pub fn catalog(c: *ui.Context) void {
    const t = kit.tokens(c);
    const history = [_]f32{ 0.2, 0.35, 0.3, 0.5, 0.45, 0.7, 0.65, 0.9, 0.6, 0.8, 0.55, 0.75, 0.6, 0.7, 0.5, 0.65 };
    const other = [_]f32{ 0.1, 0.15, 0.2, 0.15, 0.3, 0.25, 0.4, 0.35, 0.3, 0.45, 0.4, 0.5, 0.45, 0.4, 0.35, 0.45 };
    const change = [_]f32{ 0.3, -0.2, 0.5, 0.1, -0.35, 0.2, -0.1, 0.4, -0.25, 0.15, 0.35, -0.05 };
    const scroll = ui.div(c).column().sizeFull().scrollY();
    defer scroll.end();
    const root = ui.div(c).column().wFull().p(16).gap(12);
    defer root.end();
    ui.text(c, "Every chart", .{ .size = 16, .weight = .semibold });
    {
        const row = ui.div(c).row().wFull().gap(10).itemsStretch();
        defer row.end();
        controls.stat(c, "stat", "12,480", .{ .change = "+8%", .status = .success, .history = &history, .size = .sm });
        controls.stat(c, "stat, without a history", "37", .{ .change = "+3", .status = .danger, .size = .sm });
    }
    section(c, "trend", "a history as bars");
    controls.trend(c, &history, .{ .capacity = 24, .height = .{ .px = 40 }, .ramp = &heat, .value_lines = &.{.{ .value = 0.5, .label = "50%" }} });
    section(c, "line", "histories as lines, filled under");
    {
        var l = controls.line(c, &.{ .{ .values = &history, .area = 0.15 }, .{ .values = &other, .color = t.success } }, .{ .capacity = 16, .height = .{ .px = 64 }, .interactive = true, .label = "Two histories" });
        if (l.current) |i| l.tooltip(c.print("{d:.0}% and {d:.0}%", .{ history[i] * 100, other[i] * 100 }));
        l.end();
    }
    section(c, "bars", "slots of parts, up from zero and down below it");
    {
        var b = controls.bars(c, .{ .count = change.len, .height = .{ .px = 48 }, .gap = 3, .below = 0.4, .interactive = true, .label = "Change" });
        while (b.next()) |slot| slot.bar(&.{.{ .value = change[slot.index], .color = if (change[slot.index] < 0) t.danger else t.success }});
        if (b.current) |i| b.tooltip(c.print("{d:.0}%", .{change[i] * 100}));
        b.end();
    }
    section(c, "breakdown", "a total by kind, a whole by source, a level");
    const parts = [_]controls.BarPart{ .{ .value = 0.4, .color = t.primary }, .{ .value = 0.2, .color = t.warning }, .{ .value = 0.1, .color = t.info } };
    controls.breakdown(c, &parts, .{ .height = 8 });
    controls.breakdown(c, &.{ .{ .value = 3, .color = t.primary }, .{ .value = 2, .color = t.warning }, .{ .value = 1, .color = t.info } }, .{ .height = 8, .whole = true });
    controls.breakdown(c, &.{.{ .value = 0.65, .color = t.danger }}, .{ .part_radius = 3, .glow = 0.6 });
    {
        var l = controls.legend(c, .{});
        l.item(t.primary, "App");
        l.itemDetail(t.warning, "Wired", "▲4.2");
        l.item(t.info, "Compressed");
        l.trailing("legend");
        l.end();
    }
    section(c, "donut and barList", "a ring of parts, and rows of bars");
    {
        const row = ui.div(c).row().wFull().gap(20).itemsCenter();
        defer row.end();
        controls.donut(c, &parts, .{ .size = 96, .text = "70%", .caption = "used" });
        const right = ui.div(c).column().wFull();
        defer right.end();
        _ = controls.barList(c, &.{
            .{ .label = "Photos", .value = 41.2, .value_text = "41.2 GB" },
            .{ .label = "Music", .value = 12.9, .value_text = "12.9 GB" },
            .{ .label = "Documents", .value = 4.4, .value_text = "4.4 GB" },
        }, .{});
    }
    section(c, "meter", "segments lit to a value, and a strip without gaps");
    controls.meter(c, 0.62, .{});
    controls.meter(c, 0.8, .{ .ramp = &heat, .glow = 0.6 });
    controls.meter(c, 1, .{ .segments = 48, .ramp = &heat, .gap = 0, .radius = 0, .height = 6 });
    section(c, "gauge and flow", "ticks lit to a value, in cells that wrap to the width");
    {
        var f = controls.flow(c, 110, .{ .gap = 16 });
        for ([_]struct { f32, []const u8, []const u8 }{ .{ 0.62, "B", "62 bits" }, .{ 0.25, "25%", "battery" }, .{ 0.9, "A", "strong" }, .{ 0.45, "45°", "heat" } }, 0..) |g, i| {
            const cell = f.cell();
            controls.gauge(c, g[0], .{ .size = 110, .ramp = if (i == 1) &.{} else if (i == 3) &heat else &strength, .text = g[1], .caption = g[2], .label = g[2] });
            cell.end();
        }
        {
            const cell = f.cell();
            controls.stat(c, "Thermal", "Nominal", .{ .card = false, .size = .xs, .value_color = t.success });
            cell.end();
        }
        f.end();
    }
}

/// From weak to strong.
const strength = [_]ui.Color{ .hex(0xf43f5e), .hex(0xfb923c), .hex(0xfacc15), .hex(0xa3e635), .hex(0x34d399) };
