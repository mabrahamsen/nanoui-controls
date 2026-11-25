//! Figures as people read them: sizes, rates, counts, a duration on a
//! clock, spans of time, how long ago and how long until, days and times
//! of day, and paths in the home folder.
//! Each comes two ways: for the frame (`size`), in its arena as `c.print`
//! is, and into the caller's buffer (`sizeBuf`), for use outside a frame.
//! A buffer too small for the text gives "?".
//!
//!     ui.text(c, controls.format.size(c, file.size), .{});        // "145.7 MB"
//!     ui.text(c, controls.format.ago(c, now - modified, .{}), .{}); // "12 min ago"
//!     ui.text(c, controls.format.dayTime(c, run.at, now, zone, .{}), .{}); // "Today 21:05"
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

/// "145.7 MB", "134 MB", "0 B": units of powers of 1000, as drive makers
/// and the system count, with at most one decimal, none when it is 0.
pub fn sizeBuf(buf: []u8, bytes: u64) []const u8 {
    const names = [_][]const u8{ "B", "KB", "MB", "GB", "TB", "PB", "EB" };
    if (bytes < 1000) return std.fmt.bufPrint(buf, "{d} B", .{bytes}) catch "?";
    var v: f64 = @floatFromInt(bytes);
    var u: usize = 0;
    // 999.96 rounds to 1000.0: the next unit says it.
    while (v >= 999.95 and u + 1 < names.len) : (u += 1) v /= 1000;
    const r = @round(v * 10) / 10;
    if (r == @floor(r)) return std.fmt.bufPrint(buf, "{d:.0} {s}", .{ r, names[u] }) catch "?";
    return std.fmt.bufPrint(buf, "{d:.1} {s}", .{ r, names[u] }) catch "?";
}

pub fn size(c: *ui.Context, bytes: u64) []const u8 {
    var buf: [32]u8 = undefined;
    return c.print("{s}", .{sizeBuf(&buf, bytes)});
}

/// "12.3 MB/s", "0 B/s": a size a second. Less than none, or not a
/// number, is 0; more than a `u64` counts is "?".
pub fn rateBuf(buf: []u8, bytes_per_second: f64) []const u8 {
    var tmp: [32]u8 = undefined;
    const r = @round(bytes_per_second);
    if (r >= 0x1p64) return "?";
    const n: u64 = if (std.math.isNan(r)) 0 else @intFromFloat(@max(0, r));
    return std.fmt.bufPrint(buf, "{s}/s", .{sizeBuf(&tmp, n)}) catch "?";
}

pub fn rate(c: *ui.Context, bytes_per_second: f64) []const u8 {
    var buf: [32]u8 = undefined;
    return c.print("{s}", .{rateBuf(&buf, bytes_per_second)});
}

/// "1,234,567": the digits in groups of three.
pub fn groupedBuf(buf: []u8, n: u64) []const u8 {
    var raw: [24]u8 = undefined;
    const digits = std.fmt.bufPrint(&raw, "{d}", .{n}) catch return "?";
    var len: usize = 0;
    for (digits, 0..) |ch, i| {
        const comma = i > 0 and (digits.len - i) % 3 == 0;
        if (len + @intFromBool(comma) + 1 > buf.len) return "?";
        if (comma) {
            buf[len] = ',';
            len += 1;
        }
        buf[len] = ch;
        len += 1;
    }
    return buf[0..len];
}

pub fn grouped(c: *ui.Context, n: u64) []const u8 {
    var buf: [32]u8 = undefined;
    return c.print("{s}", .{groupedBuf(&buf, n)});
}

/// "1:02:03" or "2:03": a duration as a clock shows it; less than none is
/// 0:00.
pub fn clockBuf(buf: []u8, secs: i64) []const u8 {
    const t: u64 = @intCast(@max(secs, 0));
    return (if (t >= 3600)
        std.fmt.bufPrint(buf, "{d}:{d:0>2}:{d:0>2}", .{ t / 3600, t % 3600 / 60, t % 60 })
    else
        std.fmt.bufPrint(buf, "{d}:{d:0>2}", .{ t / 60, t % 60 })) catch "?";
}

pub fn clock(c: *ui.Context, secs: i64) []const u8 {
    var buf: [32]u8 = undefined;
    return c.print("{s}", .{clockBuf(&buf, secs)});
}

/// The words for spans of time: the units, and how a span reads in the
/// past and to come, `{}` standing for the span ("{} ago", "in {}"), as
/// word order differs between languages. `.{}` is English.
pub const TimeWords = struct {
    seconds: []const u8 = "s",
    minutes: []const u8 = "min",
    hours: []const u8 = "h",
    days: []const u8 = "days",
    /// From 60 days, of 30 days each.
    months: []const u8 = "months",
    /// From two years, of 365 days each.
    years: []const u8 = "years",
    ago: []const u8 = "{} ago",
    /// Under a minute ago.
    just_now: []const u8 = "just now",
    in: []const u8 = "in {}",
    /// Under a minute to come.
    soon: []const u8 = "in a moment",
};

/// "45 s", "12 min", "36 h", "20 days", "5 months", "3 years": a span in
/// its largest whole unit; less than none is 0 s.
pub fn spanBuf(buf: []u8, secs: i64, words: TimeWords) []const u8 {
    const s = @max(secs, 0);
    const n: i64, const unit = if (s < 60)
        .{ s, words.seconds }
    else if (s < 3600)
        .{ @divFloor(s, 60), words.minutes }
    else if (s < 2 * 86400)
        .{ @divFloor(s, 3600), words.hours }
    else if (s < 60 * 86400)
        .{ @divFloor(s, 86400), words.days }
    else if (s < 730 * 86400)
        .{ @divFloor(s, 30 * 86400), words.months }
    else
        .{ @divFloor(s, 365 * 86400), words.years };
    return std.fmt.bufPrint(buf, "{d} {s}", .{ n, unit }) catch "?";
}

pub fn span(c: *ui.Context, secs: i64, words: TimeWords) []const u8 {
    var buf: [64]u8 = undefined;
    return c.print("{s}", .{spanBuf(&buf, secs, words)});
}

/// "just now", "12 min ago", "20 days ago": `secs` before now, in
/// `words.ago`; under a minute, or in the future, `words.just_now`.
pub fn agoBuf(buf: []u8, secs: i64, words: TimeWords) []const u8 {
    if (secs < 60) return std.fmt.bufPrint(buf, "{s}", .{words.just_now}) catch "?";
    return phrase(buf, words.ago, secs, words, true);
}

pub fn ago(c: *ui.Context, secs: i64, words: TimeWords) []const u8 {
    var buf: [128]u8 = undefined;
    return c.print("{s}", .{agoBuf(&buf, secs, words)});
}

/// "in 12 min", "in 20 days": `secs` from now, in `words.in`; under a
/// minute, or in the past, `words.soon`. For what is due, or runs next.
pub fn inBuf(buf: []u8, secs: i64, words: TimeWords) []const u8 {
    if (secs < 60) return std.fmt.bufPrint(buf, "{s}", .{words.soon}) catch "?";
    return phrase(buf, words.in, secs, words, false);
}

pub fn in(c: *ui.Context, secs: i64, words: TimeWords) []const u8 {
    var buf: [128]u8 = undefined;
    return c.print("{s}", .{inBuf(&buf, secs, words)});
}

/// The span of `secs` put where `pattern` has `{}`; a pattern without one
/// goes after the span (`span_first`, "12 min ago") or before it ("in 12
/// min").
fn phrase(buf: []u8, pattern: []const u8, secs: i64, words: TimeWords, span_first: bool) []const u8 {
    var tmp: [64]u8 = undefined;
    const sp = spanBuf(&tmp, secs, words);
    const at = std.mem.indexOf(u8, pattern, "{}") orelse {
        const parts = if (span_first) .{ sp, pattern } else .{ pattern, sp };
        return std.fmt.bufPrint(buf, "{s} {s}", parts) catch "?";
    };
    return std.fmt.bufPrint(buf, "{s}{s}{s}", .{ pattern[0..at], sp, pattern[at + 2 ..] }) catch "?";
}

/// The words for days: the ones near today, and the weekdays' and
/// months' short names. `.{}` is English.
pub const DayWords = struct {
    today: []const u8 = "Today",
    yesterday: []const u8 = "Yesterday",
    tomorrow: []const u8 = "Tomorrow",
    /// From Sunday.
    weekdays: [7][]const u8 = .{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" },
    months: [12][]const u8 = .{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" },
};

/// "Today", "Yesterday", "Tomorrow", or "2026-03-01": the day `unix`
/// falls on, seen from `now`, both in seconds since 1970 (UTC), read in
/// a zone `offset` seconds east of UTC (3600 in Oslo in winter, -18000 in
/// New York); for a list's day headings. The app gives the offset, from
/// its system, as nanoui doesn't say it; near a change to or from summer
/// time a time on the other side of it reads an hour off.
pub fn dayBuf(buf: []u8, unix: i64, now: i64, offset: i32, words: DayWords) []const u8 {
    const at = civil(unix, offset);
    if (near(at.day, civil(now, offset).day, words)) |w| return std.fmt.bufPrint(buf, "{s}", .{w}) catch "?";
    return std.fmt.bufPrint(buf, "{d}-{d:0>2}-{d:0>2}", .{ at.year, at.month, at.date }) catch "?";
}

pub fn day(c: *ui.Context, unix: i64, now: i64, offset: i32, words: DayWords) []const u8 {
    var buf: [64]u8 = undefined;
    return c.print("{s}", .{dayBuf(&buf, unix, now, offset, words)});
}

/// "Today 21:05", "Yesterday 23:40", "Mon 9 Nov 14:02", "9 Nov 2025
/// 14:02": `unix` as `day` sees it, with its time on a 24-hour clock; a
/// weekday and a date past the days near today, and the year when it
/// isn't `now`'s. For a list of times in the last weeks.
pub fn dayTimeBuf(buf: []u8, unix: i64, now: i64, offset: i32, words: DayWords) []const u8 {
    const at = civil(unix, offset);
    const today = civil(now, offset);
    if (near(at.day, today.day, words)) |w| return std.fmt.bufPrint(buf, "{s} {d:0>2}:{d:0>2}", .{ w, at.hour, at.minute }) catch "?";
    const month = words.months[at.month - 1];
    if (at.year == today.year) return std.fmt.bufPrint(buf, "{s} {d} {s} {d:0>2}:{d:0>2}", .{ words.weekdays[at.weekday], at.date, month, at.hour, at.minute }) catch "?";
    return std.fmt.bufPrint(buf, "{d} {s} {d} {d:0>2}:{d:0>2}", .{ at.date, month, at.year, at.hour, at.minute }) catch "?";
}

pub fn dayTime(c: *ui.Context, unix: i64, now: i64, offset: i32, words: DayWords) []const u8 {
    var buf: [64]u8 = undefined;
    return c.print("{s}", .{dayTimeBuf(&buf, unix, now, offset, words)});
}

/// A moment as a calendar and a clock read it: its day since 1970, the
/// date, the weekday (0 is Sunday) and the time of day.
const Civil = struct { day: i64, year: u16, month: u8, date: u8, weekday: u3, hour: u8, minute: u8 };

/// `unix` read `offset` seconds east of UTC; a moment before 1970 there
/// reads as its first second.
fn civil(unix: i64, offset: i32) Civil {
    const local: u64 = @intCast(@max(0, unix +| offset));
    const secs: std.time.epoch.EpochSeconds = .{ .secs = local };
    const d = secs.getEpochDay();
    const yd = d.calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = secs.getDaySeconds();
    return .{
        .day = @intCast(d.day),
        .year = yd.year,
        .month = md.month.numeric(),
        .date = @as(u8, md.day_index) + 1,
        // 1 January 1970 was a Thursday.
        .weekday = @intCast((d.day + 4) % 7),
        .hour = ds.getHoursIntoDay(),
        .minute = ds.getMinutesIntoHour(),
    };
}

/// The word for day `d` seen from `today`, when it is one of the days
/// near it.
fn near(d: i64, today: i64, words: DayWords) ?[]const u8 {
    if (d == today) return words.today;
    if (d == today - 1) return words.yesterday;
    if (d == today + 1) return words.tomorrow;
    return null;
}

/// "~/Documents": `path` with the home folder `home` as ~ (given with a
/// separator at its end or not); `path` as it is when it isn't in it.
pub fn tildeBuf(buf: []u8, path: []const u8, home: []const u8) []const u8 {
    const rest = inHome(path, home) orelse return path;
    return std.fmt.bufPrint(buf, "~{s}", .{rest}) catch "?";
}

pub fn tilde(c: *ui.Context, path: []const u8, home: []const u8) []const u8 {
    const rest = inHome(path, home) orelse return path;
    return c.print("~{s}", .{rest});
}

/// What follows `home` in `path`, from its separator on; null when `path`
/// isn't in it.
fn inHome(path: []const u8, home: []const u8) ?[]const u8 {
    const h = std.mem.trimEnd(u8, home, "/\\");
    if (h.len == 0 or !std.mem.startsWith(u8, path, h)) return null;
    const rest = path[h.len..];
    if (rest.len > 0 and rest[0] != '/' and rest[0] != '\\') return null;
    return rest;
}

test "sizes in units of 1000, with one decimal at most" {
    var b: [32]u8 = undefined;
    try std.testing.expectEqualStrings("0 B", sizeBuf(&b, 0));
    try std.testing.expectEqualStrings("999 B", sizeBuf(&b, 999));
    try std.testing.expectEqualStrings("1 KB", sizeBuf(&b, 1000));
    try std.testing.expectEqualStrings("640.5 KB", sizeBuf(&b, 640_500));
    try std.testing.expectEqualStrings("134 MB", sizeBuf(&b, 134_000_000));
    try std.testing.expectEqualStrings("145.7 MB", sizeBuf(&b, 145_700_000));
    try std.testing.expectEqualStrings("1 MB", sizeBuf(&b, 999_960));
    try std.testing.expectEqualStrings("18.4 EB", sizeBuf(&b, std.math.maxInt(u64)));
    try std.testing.expectEqualStrings("?", sizeBuf(b[0..3], 145_700_000));
}

test "rates, grouped figures and clocks" {
    var b: [32]u8 = undefined;
    try std.testing.expectEqualStrings("12.3 MB/s", rateBuf(&b, 12_300_000));
    try std.testing.expectEqualStrings("0 B/s", rateBuf(&b, -3));
    try std.testing.expectEqualStrings("0 B/s", rateBuf(&b, std.math.nan(f64)));
    try std.testing.expectEqualStrings("?", rateBuf(&b, std.math.inf(f64)));
    try std.testing.expectEqualStrings("1,234,567", groupedBuf(&b, 1_234_567));
    try std.testing.expectEqualStrings("999", groupedBuf(&b, 999));
    try std.testing.expectEqualStrings("0", groupedBuf(&b, 0));
    try std.testing.expectEqualStrings("18,446,744,073,709,551,615", groupedBuf(&b, std.math.maxInt(u64)));
    try std.testing.expectEqualStrings("?", groupedBuf(b[0..4], 1_234_567));
    try std.testing.expectEqualStrings("0:00", clockBuf(&b, -5));
    try std.testing.expectEqualStrings("2:03", clockBuf(&b, 123));
    try std.testing.expectEqualStrings("1:02:03", clockBuf(&b, 3723));
}

test "spans in their largest whole unit, and how long ago" {
    var b: [64]u8 = undefined;
    try std.testing.expectEqualStrings("0 s", spanBuf(&b, -10, .{}));
    try std.testing.expectEqualStrings("45 s", spanBuf(&b, 45, .{}));
    try std.testing.expectEqualStrings("12 min", spanBuf(&b, 12 * 60 + 5, .{}));
    try std.testing.expectEqualStrings("36 h", spanBuf(&b, 36 * 3600, .{}));
    try std.testing.expectEqualStrings("20 days", spanBuf(&b, 20 * 86400, .{}));
    try std.testing.expectEqualStrings("2 months", spanBuf(&b, 60 * 86400, .{}));
    try std.testing.expectEqualStrings("2 years", spanBuf(&b, 730 * 86400, .{}));
    try std.testing.expectEqualStrings("just now", agoBuf(&b, 59, .{}));
    try std.testing.expectEqualStrings("just now", agoBuf(&b, -400, .{}));
    try std.testing.expectEqualStrings("12 min ago", agoBuf(&b, 12 * 60, .{}));
}

test "the words for time can be another language's, the span where it puts it" {
    var b: [64]u8 = undefined;
    const norsk: TimeWords = .{ .seconds = "s", .minutes = "min", .hours = "t", .days = "dager", .ago = "for {} siden", .just_now = "nå nettopp" };
    try std.testing.expectEqualStrings("for 12 min siden", agoBuf(&b, 12 * 60, norsk));
    try std.testing.expectEqualStrings("3 dager", spanBuf(&b, 3 * 86400, norsk));
    try std.testing.expectEqualStrings("nå nettopp", agoBuf(&b, 5, norsk));
}

test "how long until, and under a minute or past, soon" {
    var b: [64]u8 = undefined;
    try std.testing.expectEqualStrings("in 12 min", inBuf(&b, 12 * 60 + 5, .{}));
    try std.testing.expectEqualStrings("in 20 days", inBuf(&b, 20 * 86400, .{}));
    try std.testing.expectEqualStrings("in a moment", inBuf(&b, 59, .{}));
    try std.testing.expectEqualStrings("in a moment", inBuf(&b, -400, .{}));
    const norsk: TimeWords = .{ .hours = "t", .in = "om {}", .soon = "straks" };
    try std.testing.expectEqualStrings("om 3 t", inBuf(&b, 3 * 3600, norsk));
    try std.testing.expectEqualStrings("straks", inBuf(&b, 5, norsk));
    // Without {}, before the span, as "ago" goes after it.
    try std.testing.expectEqualStrings("om 3 t", inBuf(&b, 3 * 3600, .{ .hours = "t", .in = "om" }));
    try std.testing.expectEqualStrings("3 h ago", agoBuf(&b, 3 * 3600, .{ .ago = "ago" }));
}

test "days near today in words, and others as dates, in the zone given" {
    var b: [64]u8 = undefined;
    // Wednesday 25 November 2026, 21:05 UTC.
    const now: i64 = 1795640700;
    try std.testing.expectEqualStrings("Today", dayBuf(&b, now - 3600, now, 0, .{}));
    try std.testing.expectEqualStrings("Yesterday", dayBuf(&b, now - 86400, now, 0, .{}));
    try std.testing.expectEqualStrings("Tomorrow", dayBuf(&b, now + 86400, now, 0, .{}));
    try std.testing.expectEqualStrings("2026-11-22", dayBuf(&b, now - 3 * 86400, now, 0, .{}));
    // Three hours east of UTC, now is 00:05 on Thursday: an hour before
    // is Wednesday there, and the next evening is today's.
    try std.testing.expectEqualStrings("Yesterday", dayBuf(&b, now - 3600, now, 3 * 3600, .{}));
    try std.testing.expectEqualStrings("Today", dayBuf(&b, now + 20 * 3600, now, 3 * 3600, .{}));
    try std.testing.expectEqualStrings("I dag", dayBuf(&b, now, now, 0, .{ .today = "I dag" }));
    try std.testing.expectEqualStrings("1970-01-01", dayBuf(&b, -86400 * 10, now, 0, .{}));
    try std.testing.expectEqualStrings("?", dayBuf(b[0..4], now - 3 * 86400, now, 0, .{}));
}

test "times of day with their day, a weekday and date further back, and a year when it differs" {
    var b: [64]u8 = undefined;
    const now: i64 = 1795640700; // Wednesday 25 November 2026, 21:05 UTC
    try std.testing.expectEqualStrings("Today 21:05", dayTimeBuf(&b, now, now, 0, .{}));
    try std.testing.expectEqualStrings("Today 22:05", dayTimeBuf(&b, now, now, 3600, .{}));
    try std.testing.expectEqualStrings("Yesterday 23:40", dayTimeBuf(&b, now - 21 * 3600 - 25 * 60, now, 0, .{}));
    try std.testing.expectEqualStrings("Tomorrow 07:00", dayTimeBuf(&b, now + 9 * 3600 + 55 * 60, now, 0, .{}));
    try std.testing.expectEqualStrings("Mon 9 Nov 14:02", dayTimeBuf(&b, now - 16 * 86400 - 7 * 3600 - 3 * 60, now, 0, .{}));
    try std.testing.expectEqualStrings("31 Dec 2025 23:59", dayTimeBuf(&b, 1767225540, now, 0, .{}));
    try std.testing.expectEqualStrings("16:05", dayTimeBuf(&b, now, now, -5 * 3600, .{})[6..]);
    const norsk: DayWords = .{ .weekdays = .{ "søn", "man", "tir", "ons", "tor", "fre", "lør" }, .months = .{ "jan", "feb", "mar", "apr", "mai", "jun", "jul", "aug", "sep", "okt", "nov", "des" } };
    try std.testing.expectEqualStrings("man 9 nov 14:02", dayTimeBuf(&b, now - 16 * 86400 - 7 * 3600 - 3 * 60, now, 0, norsk));
}

test "paths in the home folder start with ~, and others are as they are" {
    var b: [64]u8 = undefined;
    try std.testing.expectEqualStrings("~/Documents", tildeBuf(&b, "/Users/ann/Documents", "/Users/ann/"));
    try std.testing.expectEqualStrings("?", tildeBuf(b[0..4], "/Users/ann/Documents", "/Users/ann"));
    try std.testing.expectEqualStrings("~/Documents", tildeBuf(&b, "/Users/ann/Documents", "/Users/ann"));
    try std.testing.expectEqualStrings("~", tildeBuf(&b, "/Users/ann", "/Users/ann"));
    try std.testing.expectEqualStrings("/Users/anna/x", tildeBuf(&b, "/Users/anna/x", "/Users/ann"));
    try std.testing.expectEqualStrings("/tmp", tildeBuf(&b, "/tmp", "/Users/ann"));
}

test {
    std.testing.refAllDecls(@This());
}

test "each also writes into the frame's memory" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            ui.text(c, size(c, 145_700_000), .{});
            ui.text(c, ago(c, 12 * 60, .{}), .{});
            ui.text(c, grouped(c, 1_234), .{});
            ui.text(c, rate(c, 12_300_000), .{});
            ui.text(c, clock(c, 123), .{});
            ui.text(c, span(c, 45, .{}), .{});
            ui.text(c, tilde(c, "/Users/ann/Documents", "/Users/ann"), .{});
            ui.text(c, in(c, 12 * 60, .{}), .{});
            ui.text(c, day(c, 1795640700, 1795640700, 0, .{}), .{});
            ui.text(c, dayTime(c, 1795640700, 1795640700, 0, .{}), .{});
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 200, .height = 100 });
    defer t.deinit();
    t.frame();
    try std.testing.expect(t.hasText("145.7 MB") and t.hasText("12 min ago") and t.hasText("1,234"));
    try std.testing.expect(t.hasText("12.3 MB/s") and t.hasText("2:03") and t.hasText("45 s") and t.hasText("~/Documents"));
    try std.testing.expect(t.hasText("in 12 min") and t.hasText("Today") and t.hasText("Today 21:05"));
}
