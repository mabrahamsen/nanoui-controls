# Changelog

The version is in `build.zig.zon`. While it is 0.x, a minor release may change the API and a patch release won't, as nanoui's own releases go.

## Unreleased

- Fixed: `grid` kept a pointer to its state, where Shift-selection starts, across the building of its rows. When widget state made meanwhile (a cell's, the column edges') grew nanoui's store of it, the grid wrote to freed memory: a crash in a debug build. It now copies its state in at the start of a frame and writes it back in `end`.
- `grid` jumps to a row as you type: `typed` is the text typed while the grid has the keyboard (a pause of a second starts it afresh), the caller finds the first row it begins, and `jump` selects that row and scrolls to it.

## 0.2.0

- `grid` selects: with `selected`, a click selects a row and it is drawn highlighted. Up, Down, Page Up, Page Down, Home and End move the selection while nothing else has the keyboard, scrolling it into view, and Enter or a double click opens it. `Row` says whether a row is `selected` and `opened`.
- `grid` selects several rows: with `multi` too, Cmd-click (Ctrl-click) adds or takes away a row, Shift-click and Shift with the keys select a run, and Cmd+A (Ctrl+A) selects them all.
- `Row.secondary_clicked` is a right-click on a row, for a context menu; it selects the row unless it is already selected.
- Screen readers hear a `grid`'s rows as rows, with the selected ones marked, and its sortable titles as buttons that say how the rows are sorted.
- `grid` columns without a `width` share the room left by their `flex`, and never get narrower than their `min_width`.
- `grid` columns resize: with `widths`, kept by the caller, dragging the edge between two titles resizes the column on its left if it has a width, else the one on its right.
- `grid` says which rows are in view (`first`, `last`), for apps that load rows as they scroll, and `scroll_to` brings a row into view.
- `grid` shows `empty` text under its titles when it has no rows.
- `grid` makes tables to read: with `clickable = false`, its rows take no clicks, don't light up and show no pointing hand.
- A scrolling `grid`'s scrollbar can be dragged and its track clicked: its rows stop short of the bar, which a row under it took the press from. The titles keep in line with them.
- `grid` fails the same way in every build when it is used wrongly: `cell()` on a hidden column, `hidden` or `widths` without one entry a column, or `multi` without one flag a row or without `selected`, panics.
- An example app, `examples/grid`, run with `zig build example`.
- Snapshot tests compare the grid's drawings, in light and dark, with the PNGs in `tests/snapshots` (`zig build test-snapshots`).
- Pushing a version tag creates the GitHub release, with the version's section of this changelog as its notes.

## 0.1.0

- Initial version, with the `grid` control.
