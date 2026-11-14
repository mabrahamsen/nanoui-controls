//! The app's shape: how round the controls' corners are and how strongly
//! what glows in them glows, set once for every control, as a theme sets
//! their colors. It scales what a control chooses itself: a corner fixed
//! in it or taken from the kit's radius, and a glow fixed in it or an
//! option left to its default. A number the caller gives draws as given.
//! Shapes that are round by what they are (a dot, a capsule, a count's
//! badge) stay round, and a shadow under a box is not a glow.
//!
//!     controls.setShape(.{ .corner = 0.35, .glow = 1.4 });

/// How round and how glowing the controls are, over their own look.
pub const Shape = struct {
    /// The corners the controls choose themselves, times this: 0 is
    /// square.
    corner: f32 = 1,
    /// The glows the controls choose themselves, times this: 0 is none.
    glow: f32 = 1,
};

/// The app's, set with `setShape`.
var current: Shape = .{};

/// Sets the shape of every control, once or each frame from the app's
/// theme.
pub fn setShape(s: Shape) void {
    current = s;
}

/// The shape every control is drawn in.
pub fn shape() Shape {
    return current;
}

/// A corner a control chooses itself, `r` in its own look, in the app's
/// shape.
pub fn corner(r: f32) f32 {
    return @max(0, r * current.corner);
}

/// A glow's opacity a control chooses itself, `g` in its own look, in the
/// app's shape.
pub fn glow(g: f32) f32 {
    return @max(0, g * current.glow);
}

const std = @import("std");

test "a shape scales the corners and glows controls choose themselves, never below none" {
    defer setShape(.{});
    try std.testing.expectEqual(@as(f32, 8), corner(8));
    setShape(.{ .corner = 0.25, .glow = 0 });
    try std.testing.expectEqual(@as(f32, 2), corner(8));
    try std.testing.expectEqual(@as(f32, 0), glow(0.8));
    setShape(.{ .corner = -1 });
    try std.testing.expectEqual(@as(f32, 0), corner(8));
}

test {
    _ = @import("shape_tests.zig");
}
