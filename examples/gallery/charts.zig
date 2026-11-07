//! The gallery's charts, with readings that change four times a second, as from a
//! system monitor. The CPU's load is a trend and a meter, network traffic
//! is bars of read and write that say a slot's figures under the
//! pointer, memory is a bar split by kind with a legend that stacks in a
//! narrow window, the fan is a level that glows, and a strip shows the
//! heat ramp. "Running" pauses the readings, "Heat" colors the load by
//! the ramp instead of the accent, "Glow" lights the meters up, and
//! "Fade" fades the older bars of the trend; the slider sets how many
//! segments the meters have.
const std = @import("std");
const nanoui = @import("nanoui");
const controls = @import("nanoui_controls");
const ui = nanoui.ui;
const kit = nanoui.kit;

/// How many readings the histories keep, and how often one comes.
const capacity = 60;
const every = 0.25;

/// Readings, oldest first, the oldest dropped when full.
const History = struct {
    values: [capacity]f32 = undefined,
    len: usize = 0,

    fn add(h: *History, v: f32) void {
        if (h.len == capacity) {
            std.mem.copyForwards(f32, h.values[0 .. capacity - 1], h.values[1..]);
            h.len -= 1;
        }
        h.values[h.len] = v;
        h.len += 1;
    }

    fn slice(h: *const History) []const f32 {
        return h.values[0..h.len];
    }

    fn last(h: *const History) f32 {
        return if (h.len > 0) h.values[h.len - 1] else 0;
    }
};

pub const Monitor = struct {
    load: History = .{},
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
        const root = ui.div(c).column().sizeFull().p(16).gap(14);
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
        const segments: usize = @intFromFloat(@round(m.segments));
        const ramp: ?*const fn (f32) ui.Color = if (m.heat) heat else null;

        const load = m.load.last();
        section(c, "CPU", c.print("{d:.0}%", .{load * 100}));
        controls.trend(c, m.load.slice(), .{
            .capacity = capacity,
            .height = .{ .px = 48 },
            .ramp = ramp,
            .fade = if (m.fade) 0.35 else null,
            .label = "CPU history",
            .value = c.print("{d:.0}%", .{load * 100}),
        });
        controls.meter(c, load, .{ .segments = segments, .ramp = ramp, .glow = glow, .label = "CPU load" });

        section(c, "Network", "");
        var b = controls.bars(c, .{ .count = capacity, .height = .{ .px = 56 }, .hover = true, .label = "Network traffic" });
        const shown = b.hovered orelse capacity - 1;
        const empty = capacity - m.read.len;
        const figures = if (shown >= empty) c.print("read {d:.1} MB/s, write {d:.1} MB/s", .{ m.read.values[shown - empty], m.write.values[shown - empty] }) else "no reading";
        while (b.next()) |slot| {
            if (slot.hovered) _ = slot.box.bg(t.surface_hover);
            if (slot.index < empty) continue;
            const i = slot.index - empty;
            controls.stack(c, &.{
                .{ .value = m.read.values[i] / traffic_top, .color = t.primary },
                .{ .value = m.write.values[i] / traffic_top, .color = t.success },
            });
        }
        b.end();
        {
            var l = controls.legend(c, .{ .row_from = 520, .mono = true });
            l.item(t.primary, "Read");
            l.item(t.success, "Write");
            if (l.wide) ui.spacer(c);
            ui.text(c, figures, .{ .size = 11, .mono = true, .color = t.muted });
            l.end();
        }

        const used = m.memory[0] + m.memory[1] + m.memory[2];
        section(c, "Memory", c.print("{d:.1} of {d} GB", .{ used, total }));
        const parts = [_]controls.ChartPart{
            .{ .value = m.memory[0] / total, .color = t.primary },
            .{ .value = m.memory[1] / total, .color = t.warning },
            .{ .value = m.memory[2] / total, .color = t.info },
        };
        controls.split(c, &parts, .{ .height = 10, .label = "Memory", .value = c.print("{d:.1} of {d} GB", .{ used, total }) });
        {
            var l = controls.legend(c, .{ .row_from = 520, .mono = true });
            l.item(t.primary, c.print("App {d:.1} GB", .{m.memory[0]}));
            l.item(t.warning, c.print("Wired {d:.1} GB", .{m.memory[1]}));
            l.item(t.info, c.print("Compressed {d:.1} GB", .{m.memory[2]}));
            if (l.wide) ui.spacer(c);
            ui.text(c, c.print("Free {d:.1} GB", .{total - used}), .{ .size = 11, .mono = true, .color = t.muted });
            l.end();
        }

        section(c, "Fan", c.print("{d:.0} rpm", .{1200 + m.fan * 4800}));
        const fan_color = if (ramp) |f| f(m.fan) else t.primary;
        controls.split(c, &.{.{ .value = m.fan, .color = fan_color }}, .{ .part_radius = 3, .glow = glow, .label = "Fan", .value = c.print("{d:.0}%", .{m.fan * 100}) });

        section(c, "Heat ramp", "");
        controls.meter(c, 1, .{ .segments = 48, .ramp = heat, .gap = 0, .radius = 0, .height = 6 });
    }

    /// A new reading for each chart, wandering from the last.
    fn tick(m: *Monitor) void {
        const r = m.random.random();
        m.load.add(std.math.clamp(m.load.last() + (r.float(f32) - 0.48) * 0.25, 0.02, 1));
        m.read.add(@max(0, m.read.last() * 0.6 + r.float(f32) * 14 + if (r.float(f32) < 0.1) 18 * r.float(f32) else 0));
        m.write.add(@max(0, m.write.last() * 0.5 + r.float(f32) * 6));
        for (&m.memory, [_]f32{ 14, 5, 3 }) |*g, top| g.* = std.math.clamp(g.* + (r.float(f32) - 0.5) * 0.4, 0.5, top);
        m.fan = std.math.clamp(m.fan * 0.9 + m.load.last() * 0.1 + (r.float(f32) - 0.5) * 0.05, 0, 1);
    }
};

/// A chart's title, and what it reads at the end.
fn section(c: *ui.Context, title: []const u8, reading: []const u8) void {
    const t = kit.tokens(c);
    const row = ui.div(c).row().wFull().itemsCenter().pt(4);
    defer row.end();
    ui.text(c, title, .{ .size = 13, .weight = .semibold });
    ui.spacer(c);
    ui.text(c, reading, .{ .size = 12, .mono = true, .color = t.muted });
}

/// Cool at the bottom, through amber, to hot at the top.
fn heat(at: f32) ui.Color {
    const cool: ui.Color = .hex(0x22d3ee);
    const amber: ui.Color = .hex(0xfbbf24);
    const hot: ui.Color = .hex(0xfb7185);
    if (at < 0.5) return cool.mix(amber, at * 2);
    return amber.mix(hot, (at - 0.5) * 2);
}

/// The monitor, with half a history to start with, so the charts aren't
/// empty.
pub fn init() Monitor {
    var m: Monitor = .{};
    for (0..capacity / 2) |_| m.tick();
    return m;
}
