# Changelog

The version is in `build.zig.zon`. While it is 0.x, a minor release may change the API and a patch release won't, as nanoui's own releases go.

## Unreleased

- An example app, `examples/grid`, run with `zig build example`.
- Pushing a version tag creates the GitHub release, with the version's section of this changelog as its notes.
- `grid` selects: with `selected`, a click selects a row and it is drawn highlighted. Up, Down, Page Up, Page Down, Home and End move the selection while nothing else has the keyboard, scrolling it into view, and Enter or a double click opens it. `Row` says whether a row is `selected` and `opened`.
- `grid` fails the same way in every build when it is used wrongly: `cell()` on a hidden column, or `hidden` without one flag a column, panics.
- Snapshot tests compare the grid's drawings, in light and dark, with the PNGs in `tests/snapshots` (`zig build test-snapshots`).

## 0.1.0

- Initial version, with the `grid` control.
