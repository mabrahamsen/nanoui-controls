//! The parts the controls are built with, for a control of the app's own
//! that acts and looks as they do beside them: a box that is a button, a
//! stop for Tab whose clicks go to what is in it, keys taken before the
//! app's shortcuts, the keyboard's ring when theirs shows, something
//! disabled dimmed as they dim it, a box's size from the last frame, text
//! cut short, and a box in a `Surface`'s look. They keep their names as
//! the rest of the API does.
//!
//!     var box = controls.custom.surface(c, opts.card, .{ .fill = t.surface, .px = 10, .py = 8 });
//!     defer box.end();
//!     const it = controls.custom.button(c, box.index, true);
//!     if (controls.custom.showRing(c, it.focused)) box = box.border(controls.custom.ring(c)).borderW(controls.custom.ringWidth(c));
const focus = @import("focus.zig");
const measure = @import("measure.zig");
const surface_mod = @import("surface.zig");

// The keyboard and its ring.

/// Interacts with a box that is a button: Tab reaches it when
/// `focusable`, and Enter or Space clicks it. While the app shows rings
/// only for the keyboard (`setFocusRingShows(.keyboard)`), a click leaves
/// the keyboard where it was, as the controls' buttons do; draw the ring
/// when `showRing` says.
pub const button = focus.button;
/// A box of no size in the open `box` that takes the keyboard for it, for
/// a control whose own box mustn't take clicks from what is in it (rows,
/// a scrollbar): Tab, `c.focusNext` just before `box`, or a click the
/// control passes on with `c.focus = own.id`.
pub const take = focus.take;
/// As `take`, only while the control wants the keyboard: not while it is
/// disabled or has nothing in it.
pub const takeIf = focus.takeIf;
/// Makes the shortcut nanoui offers for one of `keys` that key, before
/// the app's shortcuts see it: for a control with the keyboard that moves
/// with the arrows, Home and End, the page keys, Enter, Escape or
/// Backspace.
pub const keysOf = focus.keysOf;
/// A key, as `c.input.key` has it, for `keysOf`.
pub const Key = focus.Key;
/// Whether a control that has the keyboard (`focused`) shows its ring
/// now: as `setFocusRingShows` says.
pub const showRing = focus.showRing;
/// The ring's color: the app's (`c.focus_ring`), or the theme's accent.
pub const ring = focus.ring;
/// The ring's color for a control tinted its own way: the app's, or
/// `color`.
pub const ringIn = focus.ringIn;
/// The ring's width: the app's, or a point.
pub const ringWidth = focus.ringWidth;
/// The opacity of something disabled, as the controls dim it.
pub const dimmed = focus.dimmed;

// Measuring.

/// A box's size as the last frame laid it out, or null in its first
/// frame; then, or when it changes, another frame is drawn at once.
pub const lastSize = measure.lastSize;
/// Whether the text just drawn was cut short, for a tooltip with the
/// whole of it; call it right after `ui.text`.
pub const cutOff = measure.cutOff;

// Surfaces.

/// A box in the caller's `Surface` over the control's own look
/// (`SurfaceOwn`), a column open for what goes in it; the caller ends it.
/// The boxed controls take their `card` this way.
pub const surface = surface_mod.open;
/// A control's own look where the caller's `Surface` leaves a field null:
/// its fill and border, corners, padding, gap, width and `scale`.
pub const SurfaceOwn = surface_mod.Own;
/// A length with `scale` applied: one in points grows, one relative to
/// the parent doesn't.
pub const scaled = surface_mod.scaled;

test {
    _ = @import("custom_tests.zig");
}
