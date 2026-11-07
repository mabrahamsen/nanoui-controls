# Changelog

The version is in `build.zig.zon`. While it is 0.x, a minor release may change the API and a patch release won't, as nanoui's own releases go.

## 0.4.0

- `pager` is made of the kit's buttons, as `kit.pagination` is: they ease on hover, give under a press, and fade when disabled. Screen readers still name each button.
- `pager` keeps its width from page to page, so its arrows stay under the pointer: it always shows as many numbers and ellipses, each as wide as the widest number. Near an end, it numbers more pages where an ellipsis would be.
- `pager` takes `size`, a `kit.Size` as the kit's buttons do, in place of `scale`.
- `grid` options renamed, to say what they are: `rows` is `max_rows`, `multi` is `selection`, `rule` is `header_line`, and `title` (the titles' look) is `title_style`. `Grid.shows` is `isShown`.
- `grid` columns can sit in the center: `GridColumn.alignment = .center` centers a column's cells and its title.
- `Grid` lists the fields callers read (`first`, `last`, `sorted`, `typed`) first, apart from its own.
- `grid` takes the keyboard by focus, as the pager and text fields do: a click in it or Tab gives it the keyboard, and `c.focusNext` before `grid` does at the start. Its keys (arrows, Page Up and Down, Home, End, Enter, Cmd+A and typing) are its only while it has the keyboard, so two grids in a window, or a grid and a search field, no longer take the same keys. `Grid.focused` says it has it, and the selection is grey while it doesn't. A grid needs `selected` to take the keyboard.
- `pager` returns true when it moves a page past the last back to the last, as when a search leaves fewer pages, so a caller that loads a page on a change loads it.

## 0.3.0

- `pager`, a new control: numbered pages, "‹ 1 … 9 10 11 … 20 ›", with the page kept by the caller, clicked or moved with Left, Right, Home and End.
- `grid` jumps to a row as you type: `typed` is the text typed while the grid has the keyboard (a pause of a second starts it afresh), the caller finds the first row it begins, and `jump` selects that row and scrolls to it.
- `grid` columns fit their contents: a double click on the edge between two titles fits the column it resizes to its widest title or cell in view.
- `grid` columns move: with `order`, kept by the caller, dragging a title moves its column; cells keep their column numbers.
- `grid` columns scroll sideways: with `scroll_x`, columns that don't fit keep their widths and scroll with the wheel's or trackpad's sideways scroll or a bar under the rows, and `freeze_first` keeps the first in place.
- `grid` draws lines: `row_lines` between rows, which then meet them square, and `column_lines` down the gaps between columns, through the titles. A frozen column has a line at its edge while the others are scrolled.
- `grid` shows a cut-off cell's whole text in a tooltip when the pointer rests on it (`tooltips`, on by default).
- `grid` rows drag out: with `drag_rows`, a row held and moved reports `Row.drag_started`, and `dragOut` drags text out of the window for the selected rows. nanoui drags out on macOS so far.
- Fixed: `grid` kept a pointer to its state, where Shift-selection starts, across the building of its rows. When widget state made meanwhile (a cell's, the column edges') grew nanoui's store of it, the grid wrote to freed memory: a crash in a debug build. It now copies its state in at the start of a frame and writes it back in `end`.

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
