//! Figures as people read them: sizes, rates, counts, a duration on a
//! clock, spans of time and how long ago, and paths in the home folder.
//! Each comes two ways: for the frame (`size`), in its arena as `c.print`
//! is, and into the caller's buffer (`sizeBuf`), for use outside a frame.
//! A buffer too small for the text gives "?".
//!
//!     ui.text(c, controls.format.size(c, file.size), .{});        // "145.7 MB"
//!     ui.text(c, controls.format.ago(c, now - modified, .{}), .{}); // "12 min ago"
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
/// past, `{}` standing for the span ("{} ago"), as word order differs
/// between languages. `.{}` is English.
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
    var tmp: [64]u8 = undefined;
    const sp = spanBuf(&tmp, secs, words);
    const at = std.mem.indexOf(u8, words.ago, "{}") orelse return std.fmt.bufPrint(buf, "{s} {s}", .{ sp, words.ago }) catch "?";
    return std.fmt.bufPrint(buf, "{s}{s}{s}", .{ words.ago[0..at], sp, words.ago[at + 2 ..] }) catch "?";
}

pub fn ago(c: *ui.Context, secs: i64, words: TimeWords) []const u8 {
    var buf: [128]u8 = undefined;
    return c.print("{s}", .{agoBuf(&buf, secs, words)});
}

/// "~/Documents": `path` with the home folder `home` as ~; `path` as it
/// is when it isn't in it.
pub fn tildeBuf(buf: []u8, path: []const u8, home: []const u8) []const u8 {
    if (home.len < 2 or !std.mem.startsWith(u8, path, home)) return path;
    const rest = path[home.len..];
    if (rest.len > 0 and rest[0] != '/' and rest[0] != '\\') return path;
    return std.fmt.bufPrint(buf, "~{s}", .{rest}) catch path;
}

pub fn tilde(c: *ui.Context, path: []const u8, home: []const u8) []const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    return c.print("{s}", .{tildeBuf(&buf, path, home)});
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

test "paths in the home folder start with ~, and others are as they are" {
    var b: [64]u8 = undefined;
    try std.testing.expectEqualStrings("~/Documents", tildeBuf(&b, "/Users/ann/Documents", "/Users/ann"));
    try std.testing.expectEqualStrings("~", tildeBuf(&b, "/Users/ann", "/Users/ann"));
    try std.testing.expectEqualStrings("/Users/anna/x", tildeBuf(&b, "/Users/anna/x", "/Users/ann"));
    try std.testing.expectEqualStrings("/tmp", tildeBuf(&b, "/tmp", "/Users/ann"));
}

test "each also writes into the frame's memory" {
    const T = struct {
        fn view(_: *@This(), c: *ui.Context) void {
            ui.text(c, size(c, 145_700_000), .{});
            ui.text(c, ago(c, 12 * 60, .{}), .{});
            ui.text(c, grouped(c, 1_234), .{});
        }
    };
    var x: T = .{};
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&x, T.view), .{ .width = 200, .height = 100 });
    defer t.deinit();
    t.frame();
    try std.testing.expect(t.hasText("145.7 MB") and t.hasText("12 min ago") and t.hasText("1,234"));
}
