# Changelog

The version is in `build.zig.zon`. While it is 0.x, a minor release may change the API and a patch release won't, as nanoui's own releases go.

## Unreleased

### Added

- `pill` and `pillOpen`: a short label tinted in a status's color, led by a glowing dot or an icon, as a capsule or a badge, with a tooltip and `value_text` for a screen reader; `pillLengths` measures one.
- `caption` and `captionOpen`: a small heading in muted capitals, heard as a heading, with an aside, an icon, a line left open for a count or a button at its end, and cutting short.
- `panel`: a bordered box that groups what is in it under a caption, tinted by a status, and folding with `open`, its head one button that Tab reaches and a screen reader hears as expanded or collapsed.
- `callout` and `calloutOpen`: an icon and wrapping text in a tinted box, with a title, a ✕ that Tab reaches and is named, and said to a screen reader once when a danger or a warning one appears.
- `notice` and `noticeOpen`: a large icon, a title and a centered description in a panel, for a pane that is empty, stopped or waiting, with a spinner while loading and room for a button.
- `Surface`, the look of a box a control draws itself in, which `panel`, `notice` and `stat` take as `card`; `over` lays one over another.
- `format`: sizes, rates, grouped figures, clocks, spans, how long ago and paths in the home folder, for the frame or into a buffer, with the words for time replaceable.
- `stat`: `mono`, and at `.xs` without a tile a compact reading, a caption over a figure; `Flow.stat` puts one in a flow's next cell.
- `setFocusRingShows(.keyboard)`, called once by an app, shows the controls' ring only while the keyboard is in use, as on a Mac: a key shows it and the pointer hides it, the ring nanoui draws round a control's box included. A click on a control that is a button (the stat button, a bar list's row, the form's link rows and folding headings) then leaves the keyboard where it was. Controls with keys of their own still take the keyboard on a click. The default, `.focused`, is as before.
- Grid: `g.headingRow(opts)` makes a group's heading row with nothing drawn in it, for the caller's own chevron, title and lines, and says whether the group is `open` and its `depth`; the grid keeps folding it, its keys, the selection and what a screen reader hears. `indent_step` sets how far each level steps in, and `fade_in = false` shows a group's rows at once as it opens.

### Changed

- `stat`'s `card` is a `?Surface`: `.{}` is the tile as before, any of its fields can be set, and `null` replaces `card = false`. A stat at `.xs` without a tile is now a compact reading, its figure a point over the kit's text rather than twice it.

## 0.7.4

### Changed

- Built on nanoui 0.14.2, which an app using these controls must pin too. The controls work as before.

## 0.7.3

### Changed

- Built on nanoui 0.14.1, which an app using these controls must pin too. The controls work as before. A drag on a column's edge or title, or on a splitter, no longer stops when another mouse button is pressed partway through, and the pager's buttons hold still under a press with Reduce Motion on.

## 0.7.2

### Added

- Grid: with `widths`, every column resizes, flexible ones too: dragging or fitting a column without a `width` gives it the width it has on screen, kept in `widths`, and a 0 still means the column's own width or sharing the room by `flex`. `g.fitAll()`, or a double click on the header past the last title, fits every column in view to its widest title or cell; `g.resetWidths()` sends them all back. A hidden column keeps its width for when it shows again.
- Grid: `g.headingOpen(opts)` draws a group's heading and leaves it open after its detail for the caller's content, such as tags; `Heading.label` replaces what a screen reader hears of it.
- Sidebar: `loading` on a row shows a spinner where its count goes, so a count still loading never reads as 0, at the icon's corner when narrowed to icons; a screen reader hears `loading_text`.
- `bars`: `baseline`, the shortest bar as a share of the height, so a reading of zero still shows, and `fade`, the leftmost slot's opacity, rising to 1 at the rightmost. `trend` draws with them, and looks as before.
- `stat`: `key`, a dot before the label in the color of the series it reads in a chart beside it.

### Changed

- Grid: the edge between two titles resizes the column on its left, whether it has a `width` or not, instead of the one on its right when the left has none; the flexible columns before it keep their widths as it is dragged, so the edge follows the pointer, and a click that doesn't move changes nothing. Without `scroll_x`, a drag stops where the other columns would go under their `min_width`. When no shown column is left sharing the room, the last one takes what is left, so the rows still span the grid.

### Fixed

- `stat`'s loading spinner follows `scale`, as the grid's does.

## 0.7.1

### Changed

- Built on nanoui 0.14.0, which an app using these controls must pin too.
- Enter and Space keep doing what each control says they do now that nanoui clicks a focusable box with them. The grid, the sidebar, the swatches, the charts, the pager and the splitter take those keys themselves or leave them for the app, as before. The stat button, a bar list's rows and the form's link rows and folding headings are clicked by nanoui.
- The keys a control takes are its own when nanoui offers them first as shortcuts, as it now does on the Mac for every key while no text field has the keyboard: Home, End, Page Up and Page Down, the arrows, Enter, Escape and Backspace, each where the control takes it. The app's shortcuts for them don't fire while a control with the keyboard takes them; with ⌘, ⌃ or ⌥ they are the app's, as before.
- An app that sets nanoui's `focus_ring` gets it on every control: the sidebar's, the swatches', the charts', the pager's, the splitter's, the form's, the stat button's and a bar list's rings take its color, and its width where the ring is a border, instead of the theme's accent.

## 0.7.0

### Changed: what callers write

- Every chart with a scale takes `min`, `max` and `fixed_max` the same way: `max` is where the top starts, rising to the data unless `fixed_max`, and a null `max` takes the data's largest. `line` and `trend` take `max: ?f32` (1 by default, as before); `bars` switches to units with `units = true`; a bar list's given `max` rises unless `fixed_max`.
- `breakdown`'s and `meter`'s `height`, and a bar list's `bar_height`, are a `ui.Length`: write `.height = .{ .px = 8 }`.
- A donut's and a gauge's `size` is `diameter`.
- `meter`'s `radius` is optional: null rounds the segments' ends, as `breakdown`'s does; a bar list's `bar_radius` means the same for its meters, which now have round ends.
- `gap = 0` on `bars` means no seams, the slots overlapping by a point, as on the other charts.
- A form row marked `required` says so in its control's name ("Name, required").
- `Grid.typed` lasts only for its frame: copy it to keep it.
- `selection` with `groups` panics, with a message saying so, instead of crashing when a group folds.

### Fixed

- A click on the pager gives it the keyboard. The pager, sidebar, splitter and a clickable bar list consume the keys they act on, so an app's own Enter or arrows don't fire as well.
- The sidebar's keys start at its first row when nothing is selected, and go back to the selected row when their own row is gone, instead of skipping the first row.
- A donut or gauge with no room no longer asks for a frame every frame.
- An interactive `line` with a short history no longer stops on empty slots.
- The grid: a heading's chevron follows `scale`; a double click on a heading folds it once; with `max_rows`, the selection and `jump` stay among the rows shown; sketched rows take cards' gap; an empty loading label isn't announced; `check` says what is wrong with a `scale` or row height of 0 or a `count` that isn't `groups.count()`.
- Meter zones keep their segments one width when they don't divide evenly; a meter with no value says nothing, not "0%".
- The swatches show where the keys start when the chosen index is past the colors; a form link keeps its keyboard when a row appears above it; `bars` on a fixed scale don't ask for frames as their data changes; a box's measured size is kept by the box.

### New

- Screen readers: an interactive chart is adjustable, so swipes step through its slots; grid column titles and sidebar group headings are headers; no fixed English (`ascending_text`, `descending_text`, `sort_hint_text` on the grid, `previous_text`, `next_text`, `page_text` on the pager, `chart_text` on interactive charts, `required_text` on the form).
- `meter` and `gauge` take `min` and `max`. `trend` takes `axis`, `start_text`, `end_text`, and `interactive` with `tips`. `Line.reading` gives a series' reading in a slot. `stat` takes `scale`, and its history a scale and a ramp. A legend's items take a `shape`.
- `splitter` takes `stacked`, `default` (a double click goes back to it), `big_step` (with Shift) and `disabled`; `swatches` take `disabled`, a `label`, and Up and Down. A sidebar with no rows and swatches with no colors don't take Tab.
- `flow` takes `fill`. Typing moves a sidebar's keys to the row it begins. A bar list item's `key` keeps its focus as the list re-sorts.
- Sidebar labels and form link values cut short show whole in a tooltip. Every control's focus ring looks the same.
- `FormAlign` and `SplitterPane` name the form's alignments and the splitter's pane. The legend's chip is `legendSwatch`.
- `GridGroups` costs what its groups do, not its rows.

### Grid groups, richer charts and sidebar branches

- `grid` groups that fold (`groups`, with `GridGroups`): headings with a chevron, a title and a detail, or the title in the first cell with the group's totals in the others; rows stepped in a level, groups in groups, and a group of one shown without its heading if wanted. A click folds or opens a group and its rows fade in; Left, Right, Enter and Space fold, open and move between a heading and its rows. The selection stays on its row as groups above it fold, and goes to its heading when folded away. A screen reader hears a heading with its detail and whether it is open.
- `grid` `loading`, told apart from empty: with no rows yet, a spinner, a label and a progress bar over sketched rows; with rows in, a thin progress line under the titles. A screen reader hears the label as loading starts.
- `grid` columns hide by the grid's own width (`min_grid_width`), so a pane beside the grid can make room.
- `grid` rows of two lines (`lines`, `twoLines`), rows as cards (`rows = .cards`), no titles (`header = false`), and a status on a row's edge (`row.status`).
- `grid` reports Backspace or Cmd+Up (`back`) and Escape (`escaped`) while it has the keyboard.
- `grid` can be shorter than its rows in a column that grows, without the caller setting its minimum height.
- The gallery has a Grouped view under Grid: pull requests in groups that fold, as cards or rows of two lines, reloading with sketched rows and loading more with a line under the titles. The file grid shows the line while its pages arrive.
- `bars` in units (`units`, `min`, `max`, `fixed_max`), on a scale that rises to the tallest bar unless fixed, with room below zero for a `min` under it; a history shorter than the slots at the right (`readings`, `slot.reading`), only its slots pointed at; and an `axis` with the value lines' labels in a gutter, overlapping ones left out, and `start_text` and `end_text` under the chart. `line` takes the same axis and texts.
- `barList` rows can lead with an `icon` or a `badge`, end with a `detail`, and color their figure; the list takes `min`, a `ramp`, `track`, `glow`, `bar_radius`, and `style = .meter` for levels read in steps.
- `stat` takes a `unit`, a `detail` line and `loading`, a spinner in place of the figure; `statButton` is a stat that can be clicked, with the pointer or the keys.
- `legend` can fit its items (`width = .fit`); `legendSwatch` draws a legend's swatch on its own, as a square, a dot or a line.
- `meter` without gaps rounds only its ends, and `zones` label runs of its segments.
- The gallery's Every chart shows each of these, and its Monitor uses units, axes and times under its charts. The Parts page no longer shows the histories too.
- `sidebar` branches (`branch`): a row with rows under it, to any depth, as an option. A branch has an item's icon, label and count, can be chosen and selected, and folds by the chevron at its end; its rows are indented a step, and ease open and closed as a group's do. A click on the chevron folds or opens it, and a click elsewhere chooses it and opens it if folded. Folded with the selected row in it, it shows in the selection's tint. Left and Right fold and open branches and move between a branch and its rows, at each level, as a tree's keys do. A screen reader hears a branch as a row, with its count and whether it is open. Groups and headings inside a branch are indented with it. With `null` for `open`, a branch is fixed: always open, without a chevron, for a tree that doesn't fold. A sidebar without branches looks and behaves as it did.
- The gallery puts the charts of histories and of parts under Every chart, a branch, and has a Sidebar view: the sidebar's options in a form, which the gallery's own sidebar takes as they change, fixed branches among them.

## 0.6.0

- `form`, a new control: rows with a label beside a control (`row`) or a value (`property`), the labels in one column as wide as the widest, so what follows lines up. Rows are the kit's controls' height for the form's `size`; a row can have a hint or an error under its control and mark its label as required, as the kit's `field`; `heading` heads the rows after it, with a description under its title and a status color if wanted; `foldingHeading` folds its rows, eased; `grouped` puts each heading's rows in a card under it; `control_align = .end` puts controls at the rows' ends; `link` is a row that leads somewhere; `note` says more under a section; and `row_lines` draws lines between rows. A row's label names its control to a screen reader. A row can say more in a tooltip on an ⓘ (`info`) and be dimmed (`disabled`); a property's value can be selectable, or kept to a line with the whole in a tooltip; and with `stack_below`, a narrow form puts its labels above their controls. A screen reader hears a property as one.
- `swatches`, a new control: a row of round colors to pick one from, by click or with Left, Right, Home and End once it has the keyboard, each named in a tooltip and to a screen reader as a radio button.
- `gauge`, a new chart: a ring of ticks lit up to a value, in one color or a ramp's, with a figure and a caption in its middle. It eases to a new value, and its ticks keep within its box at any size.
- `flow`, a new control: cells of one width, as many to a row as fit the parent's width, wrapping onto more rows as the window narrows.
- `stat` takes `value_color`, for a figure whose color says how something stands.
- Charts, flows and legends that measure their box ask for the frame that lays it out, instead of waiting for something else to draw one; a donut and a gauge draw in it as soon as they have a size.
- `sidebar` no longer crashes when what its rows draw, such as a row's tooltip, makes enough new state to move nanoui's store while the sidebar is open: it looks its state up when it needs it, as the grid does.

## 0.5.1

- Pins nanoui 0.13.0; an app using these controls pins the same release.

## 0.5.0

- `sidebar`, a new control: rows to pick what a window shows, with an icon, a label and a count, under headings and in groups that fold. The selected row is named by a key the caller keeps. The selection slides from row to row, rows ease into a hover, and groups open and close as the kit's do. It takes the keyboard as the grid does: Up, Down, Home and End move between rows and group headings, Left and Right fold and open groups, and the keys choose as they go or, with `choose_on_enter`, on Enter or Space. A screen reader hears each row, the selected one selected, and whether a group is open.
- `sidebar` rows can be shown as icons only (`icons_only`), their labels in tooltips, for a sidebar narrowed to a strip; be `disabled`; report a right-click (`secondary_clicked`) for a menu; and show a count as a pill (`count_style = .pill`).
- `splitter`, a new control: a handle between two panes that resizes one of them, by dragging within `min` and `max` or with Left, Right, Home and End, heard by a screen reader as a splitter it can step.
- Charts, new controls for figures that change, which nanoui's kit only shows one at a time (`progress`, `ring`):
  - `trend`: a history drawn as bars, right-aligned in its slots, scaled to its peak, the older bars fainter, in one color or by a ramp.
  - `line`: histories drawn as lines with `ui.canvas`, each filled under as an area if wanted; a reading that is not a number breaks its line.
  - `bars`: a row of slots for any bar chart, built with `next` as the grid's rows, each a bar of colored parts (`slot.bar`, `BarPart`), up from zero or, with room `below` it, down.
  - `breakdown`: a bar across in parts: a total by kind, the whole bar by source (`whole`), or a level that can glow.
  - `donut`: a ring of parts with a figure and a caption in its middle, drawn with `ui.canvas`.
  - `barList`: rows of a label, a bar and a figure, scaled to the largest, which can be clicked, or reached with Tab and clicked with Enter.
  - `meter`: a row of segments lit up to a value, in one color or by a ramp, that can glow; without gaps, a strip of colors in steps without seams.
  - `stat`: a figure in a tile, with how it changed (a kit tag colored by its status) and a trend of its history.
  - `legend`: what a chart's colors stand for, running on to new lines where its width ends, with a detail after a label (`itemDetail`) and text at the end (`trailing`).
- What the charts share:
  - Widths and heights are `ui.Length`, as `kit.progress`'s, colors come from the theme, and a `ramp` is a list of colors blended between (`rampColor`).
  - Histories can be kept in a ring, read from their oldest reading with `head`, and scaled from `min` to `max` or to their peak above it (`fixed_max` keeps the top).
  - `value_lines` draws lines across at values, with labels.
  - `interactive` bars and lines follow the pointer and take the keyboard (Left, Right, Home, End): `current` is the slot pointed at, and `tooltip` says what it shows, there and to a screen reader.
  - A chart with a `label` is one image to a screen reader, with its `value_text`; without one, it is left out as a decoration.
  - `breakdown`, `donut` and `meter` ease to new values, as the kit's progress bar does.
- The example is a gallery (`zig build example`): the library's `sidebar` picks the grid of files, a live system monitor of charts or a page of every chart. A `splitter` resizes the sidebar, which shows only its icons when dragged narrow, and a right-click on a row opens a menu.

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
