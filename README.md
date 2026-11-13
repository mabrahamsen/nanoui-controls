# nanoui-controls

[![CI](https://github.com/mabrahamsen/nanoui-controls/actions/workflows/ci.yml/badge.svg)](https://github.com/mabrahamsen/nanoui-controls/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Controls for [nanoui](https://github.com/justrach/nanoui) apps that nanoui's own kit (`nanoui.kit`) doesn't have. They follow the kit's conventions: each is a call in a frame, styled from the app's theme, with what the user changes kept by the caller.

| Control | What it does |
|---|---|
| [`grid`](#grid) | Rows of cells under a header of column titles, with the columns lined up, sorting by a clicked title and building only the rows in view; in groups that fold, as cards, and sketched while they load. |
| [`pager`](#pager) | "‹ 1 … 9 10 11 … 20 ›": numbered pages, for an app that shows a page at a time. |
| [`sidebar`](#sidebar) | Rows to pick what a window shows, under headings, in groups that fold and in branches nested to any depth, chosen by key, with the keyboard. |
| [`splitter`](#splitter) | A handle between two panes that resizes one of them, by dragging or with the keys. |
| [`form`](#form) | Rows with a label beside a control or a value, the labels in one column, for a settings pane or an inspector. |
| [`swatches`](#swatches) | A row of round colors to pick one from, with the mouse or the keys. |
| [`flow`](#flow) | Cells of one width, as many to a row as fit, wrapping onto more rows. |
| [`pill`](#pill) | A short label tinted in a status's color, led by a glowing dot or an icon: "● LIVE", "3 FAILED", a badge. |
| [`caption`](#caption) | A small heading in muted capitals, with an aside, or a count or a button at the end of its line. |
| [`panel`](#panel) | A bordered box that groups what is in it, under a caption, tinted by a status, folding if wanted. |
| [`callout`](#callout) | An icon and text in a box tinted in a status's color: a warning, a finding, a note. |
| [`notice`](#notice) | What a pane shows in place of its content when it is empty, stopped or waiting. |
| [`trend`](#trend) | A history drawn as bars, scaled to its peak, the older bars fainter: a CPU's load, a temperature. |
| [`line`](#line) | Histories drawn as lines, filled under as areas if wanted, which the user can point at or step through. |
| [`bars`](#bars) | A row of slots for any bar chart, each a bar of colored parts, up from zero or down below it, which the user can point at or step through. |
| [`breakdown`](#breakdown) | A bar across, broken down into colored parts: a total by kind, a whole by source, or a level against a maximum. |
| [`donut`](#donut) | A ring split into colored parts, with a figure in its middle. |
| [`barList`](#barlist) | Rows of a label, a bar and a figure, scaled to the largest: the busiest processes, disk use by folder. |
| [`meter`](#meter) | A row of segments, like LEDs, lit up to a value; without gaps, a strip of colors in steps. |
| [`gauge`](#gauge) | A ring of ticks lit up to a value, with a figure in its middle: a score, a level. |
| [`stat`](#stat) | A figure in a tile, with how it changed and a trend of its history. |
| [`legend`](#legend) | What a chart's colors stand for, running on to new lines where its width ends. |

## Requirements

| | Version |
|---|---|
| Zig | 0.17.1 or later |
| nanoui | 0.14.2 |

The app must pin the same nanoui release as this library, so both share one copy of nanoui. Otherwise nanoui's types don't match and the build fails.

## Installation

Add the library to the app's `build.zig.zon`:

```sh
zig fetch --save "git+https://github.com/mabrahamsen/nanoui-controls?ref=v0.7.4"
```

Then import its module next to nanoui's in `build.zig`:

```zig
const nanoui = b.dependency("nanoui", .{ .target = target, .optimize = optimize }).module("nanoui");
const controls = b.dependency("nanoui_controls", .{ .target = target, .optimize = optimize }).module("nanoui_controls");

const exe = b.addExecutable(.{
    .name = "app",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "nanoui", .module = nanoui },
            .{ .name = "nanoui_controls", .module = controls },
        },
    }),
});
```

## The keyboard's ring

A control that has the keyboard draws a ring, in the app's `c.focus_ring` if it sets one, else in the accent. By default the ring shows whenever a control has the keyboard, as nanoui rings a focusable box. An app can show it only while the keyboard is in use, as on a Mac, by calling this once, where it sets `focus_ring`:

```zig
controls.setFocusRingShows(.keyboard);
```

Then a key shows the ring and the pointer hides it, as nanoui's `c.keyboard_modality` says, and the ring nanoui draws round the controls' own boxes comes off with it. A click on a control that is a button (the stat button, a bar list's row, the form's link rows and folding headings) acts and leaves the keyboard where it was, such as in a text field being typed in; Tab still reaches it. A control with keys of its own (the grid, the sidebar, the swatches, the pager, the charts, the splitter) still takes the keyboard on a click, so its keys work at once, and rings once a key is used.

## grid

Rows of cells under a header of column titles, each column lined up from row to row.

```zig
const controls = @import("nanoui_controls");

const columns = [_]controls.GridColumn{
    .{ .title = "Name", .sortable = true },
    .{ .title = "Size", .width = 80, .alignment = .end, .sortable = true, .descending_first = true },
};

// Kept by the caller, across frames.
var sort: controls.GridSort = .{};
var selected: ?usize = null;

// In the frame:
var g = controls.grid(c, &columns, .{ .count = files.len, .sort = &sort, .selected = &selected });
if (g.sorted) sortFiles(files, sort);
while (g.next()) |row| {
    if (row.opened) openFile(files[row.index]);
    g.cell();
    ui.text(c, files[row.index].name, .{});
    g.cell();
    ui.text(c, files[row.index].size, .{});
}
g.end();
```

- **Columns** are fixed-width (`width`) or share the room the fixed ones leave (`width = null`), by their `flex` and never narrower than their `min_width`. Their contents and titles sit at the `start`, in the `center`, or at the `end`, where numbers line up.
- **Resizing:** with `widths`, an array the caller keeps (one width a column, starting at 0), dragging the edge after a title resizes its column, from the width it has on screen, and a double click fits it to its widest title or cell in view; a column without a `width` resized or fitted keeps its width in `widths` from then on. A 0 is the column's own: its `width`, or sharing the room by `flex`. As an edge is dragged, the flexible columns before it keep their widths, so it follows the pointer; without `scroll_x`, it stops where the other columns would go under their `min_width`. When no column is left sharing the room, the last takes what is left, so the rows span the grid. A double click on the header past the last title, or `g.fitAll()` before the rows, fits every column in view; `g.resetWidths()` writes the 0s back. A hidden column keeps its width for when it shows again. Keep `widths` across launches to keep the user's columns.
- **Reordering:** with `order`, an array the caller keeps (the column numbers in the order they show), dragging a title moves its column. Cells keep their column numbers, so the code that builds them doesn't change.
- **Scrolling sideways:** with `scroll_x`, columns that don't fit keep their widths and scroll sideways, with the wheel's or trackpad's sideways scroll or the bar under the rows; `freeze_first` keeps the first column in place, as a spreadsheet's names are.
- **Tooltips:** a cell whose text is cut off shows all of it when the pointer rests on it (`tooltips`, on by default).
- **Sorting:** clicking a `sortable` column's title sorts by it, and clicking again reverses it. `g.sorted` says the sort changed this frame, so the caller sorts its rows before building them.
- **Selection:** with `selected`, a click selects a row and it is drawn highlighted. The grid takes the keyboard as a text field does: a click in it or Tab gives it the keyboard (`g.focused`), and `c.focusNext(false)` just before `grid` gives it the keyboard at the start. While it has the keyboard, Up and Down move the selection a row, Page Up and Page Down a view, and Home and End to the ends, scrolling it into view. Enter or a double click opens it (`row.opened`). The selection is grey while something else has the keyboard, so two grids in a window, or a grid under a search field, take the keys in turn. The selection is a row index, so a caller that sorts finds its row again.
- **Several rows:** with `selection` too, one flag a row kept by the caller, Cmd-click (Ctrl-click on Windows and Linux) adds or takes away a row, Shift-click and Shift with the keys select a run of rows, and Cmd+A (Ctrl+A) selects them all.
- **Typing to jump:** typing while the grid has the keyboard gives `g.typed`, the text so far (a pause of a second starts it afresh), for this frame only: copy it to keep it. The caller finds the first row it begins, as only it knows what the rows hold, and `g.jump(i)` selects that row and scrolls to it.
- **Dragging rows out:** with `drag_rows`, a row held and moved a few points reports `row.drag_started`, and `g.dragOut(text)` drags that text out of the window, for the rows selected (the row is selected first, unless it is already). nanoui drags text out on macOS so far.
- **Context menus:** `row.secondary_clicked` is a right-click (or Control-click on the Mac) on a row, for the app's menu. It selects the row, unless the row is already selected, so the menu acts on the selection.
- **Screen readers** hear the rows as rows, read as their cells' text, with the selected ones marked, and the column titles as headers, the sortable ones saying which way the rows are sorted and what a click does, in the caller's words if wanted (`ascending_text`, `descending_text`, `sort_hint_text`).
- **Long lists** cost what a screenful does: only the rows in view are built. The grid fills the room left in its parent, which needs a bounded height, and can be shorter than its rows, which then scroll. In a row beside another pane, put it in a column that shares the row and is as tall as it (`.w(0).grow().hFull()`).
- **Loading as it scrolls:** `g.first` and `g.last` are the rows in view, so a caller whose rows come from a server fetches those pages, and the ones around them, and draws placeholders until they arrive. `scroll_to` brings a row into view.
- **Empty:** `empty` is text shown under the titles when there are no rows, once they have loaded.
- **Loading:** `loading` (`GridLoading`: a `label`, and `done` of `total` pages or sources) tells loading apart from empty. With no rows yet, the grid shows a spinner, the label and a progress bar over rows sketched in its columns, which pulse gently (still with reduced motion); with rows in, a thin progress line under the titles that doesn't move them. While `total` is 0 the bars sweep, as how far along isn't known. A screen reader hears the label as loading starts.
- **Groups that fold:** with `groups`, a `GridGroups` made each frame from the groups' sizes (`GridGroup`, with a `depth` for a group in a group) and their open flags, kept by the caller, rows sit under headings. `groups.at(i)` says whether row `i` in view is a heading or which group's row it is, and `count` is `groups.count()`. Draw a heading's row with `g.heading(.{ .title, .detail })`: a chevron, the title and a muted detail across the columns, or with `cells` the title in the first column's cell and the caller's `cellAt` in the others, for a group's totals. Rows step in a level in the first column. A click on a heading folds or opens it, and its rows fade in as it opens; Left on an open heading folds it, and on a row goes to its heading; Right opens a folded heading, and on an open one goes to its first row; Enter or Space folds or opens one. The selection stays on its row as groups above it fold, and goes to the nearest heading over it when it is folded away; `selection`, one flag a row in view, doesn't go with `groups`, and the grid says so. A grid of many grouped rows costs what its groups do. `singles = false` shows a group of one row without its heading. `g.headingOpen(opts)` draws the heading and leaves it open after its detail for the caller's content, such as tags counting what is in the group, then ended by the caller; a click on the content folds the group, unless the content takes the click, as a button does. A screen reader hears a heading with its detail, or its `label` where the content says more, and whether it is open (`expanded_text`, `collapsed_text`). For a heading drawn the app's way, `g.headingRow(opts)` makes the row a heading with nothing in it, placed as `heading` places its own, and returns its `box`, whether the group is `open` (after this frame's click) and its `depth`; the caller draws its chevron, title and anything else, a second line too with `lines = 2`, and ends `box`. The grid still folds it on a click and with the keys, selects it, and says `opts`' title and detail, or `label`, to a screen reader. `indent_step` (18) is how far each level steps in, and `fade_in = false` shows a group's rows at once as it opens.
- **Two lines:** `lines = 2` makes rows tall enough for two lines of text, and `g.twoLines(title, detail, .{})` draws a title over a muted detail in a cell, each cut short with an ellipsis and whole in the cell's tooltip.
- **Cards:** `rows = .cards` draws each row as a card, in the theme's surface with a border and its corners and room between them, the selected one tinted in the accent. `header = false` leaves out the column titles. `row.status(.danger)` tints a row's edge in a status's color: a card's border, or a bar at a plain row's leading edge.
- **Back and Escape:** while the grid has the keyboard, Backspace or Cmd+Up (Alt+Up on Windows and Linux) sets `g.back`, for a browser to go to the parent folder, and Escape sets `g.escaped`, for an app that clears a search or closes a pane.
- **A set number of rows:** `max_rows = 5` shows at most five, without scrolling, and takes only their height.
- **Tables to read:** `clickable = false` makes rows that take no clicks, don't light up and show no pointing hand, for a summary or comparison; a screen reader still hears them as rows.
- **Hiding columns:** a column with `min_window_width` hides in narrower windows, one with `min_grid_width` while the grid itself is narrower, as when a pane beside it narrows it, and `hidden` hides columns on the caller's say. Build cells with `g.cellAt(i)`, which returns false for a hidden column, so columns keep their numbers.
- **Lines:** `row_lines` draws a line between rows, which then meet it square, and `column_lines` one down the middle of each gap between columns, through the titles. With `freeze_first`, the frozen column has a line at its edge while the others are scrolled.
- **Look:** `striped`, `hover`, `padding`, `header_line`, `row_height` and the gaps, `title_style` (`GridTitleStyle`) for the column titles, and `scale` for apps that zoom their layout with `c.setZoom`. The grid takes `scale` rather than the kit's `size`, as the pager does, because the kit has no sizes for a grid: `scale` multiplies all its lengths. Colors come from the theme unless set.

See the doc comments in [`src/grid.zig`](src/grid.zig), or build the API docs.

## pager

Numbered pages: the first and the last, the ones around the current page, and an ellipsis for the rest. The caller keeps the page, counted from 0.

It is made of the kit's buttons, as `kit.pagination` is, and looks and moves as it does. It adds the keyboard, a name for each button that a screen reader says ("Previous page", "Page 5", "Next page"), and `around`.

```zig
var page: usize = 0;

// In the frame:
if (controls.pager(c, &page, pages, .{})) loadPage(page);
```

- Clicking a number goes to its page, and the arrows to the page before or after; past the ends they are disabled.
- Once the pager has the keyboard (a click on it, or Tab), Left and Right move a page, and Home and End go to the first and last; the keys it moves by are its own.
- `previous_text`, `next_text` and `page_text` are what a screen reader calls its buttons, in English by default.
- When the pages grow fewer than the current page, as after a search, the pager moves it to the last and returns true, so a caller that loads a page on a change loads that one.
- It keeps its width from page to page, so the arrows stay under the pointer: it always shows as many numbers and ellipses (near an end, the pages run on where an ellipsis would be), each as wide as the widest number. Only a change in the number of pages changes its width.
- `around` sets how many pages either side of the current one are numbered, and `size` is the buttons' size, as the kit's (`.sm` by default).
- With a grid's `max_rows`, it shows a page at a time: the grid's rows are the page's.

## sidebar

Rows to pick what a window shows: a mail app's mailboxes, a settings window's panes. Each row has an optional icon, a label and an optional count, under headings, in groups that fold, and, if wanted, in branches: rows with rows under them, to any depth. One row is selected by a key the caller keeps, never by position, so the selection stays on its row as rows come and go.

```zig
var sb = controls.sidebar(c, "nav", selected, .{});
sb.heading("Mailboxes");
sb.item("inbox", "Inbox", .{ .icon = "doc.text", .count = unread });
sb.item("sent", "Sent", .{ .icon = "arrow.up" });
if (sb.group("folders", "Folders", &folders_open)) |g| {
    for (folders) |f| sb.item(f.id, f.name, .{ .icon = "folder" });
    g.end();
}
if (sb.branch("archive", "Archive", .{ .icon = "folder" }, &archive_open)) |g| {
    for (years) |y| sb.item(y.id, y.name, .{});
    g.end();
}
if (sb.end()) |key| selected = key;
```

- `end` returns the key chosen this frame, by a click or the keys. Keep it: it must outlive the frame, as the rows' keys usually do.
- It takes the room left in its parent, and scrolls when its rows need more, keeping the keys' row in view.
- **Branches:** `branch` is a row with rows under it, as `group` is a heading with rows under it: draw them, then `end` the group it returns. It has an `item`'s options, can be chosen and selected, and has a chevron at its end; its rows are indented a step, so their icons sit under its label, and can be branches, headings or groups in turn. The caller keeps whether it is open. A click on the chevron folds or opens it without choosing it; a click elsewhere on it chooses it and opens it if folded. Folded with the selected row in it, it shows in the selection's tint, so the selection can be found. A disabled branch can't be chosen, but still folds.
- **Fixed trees:** with `null` for `open`, a branch is fixed: its rows always show, it has no chevron, and it doesn't fold, so there is nothing for the caller to keep. A tree of only fixed branches is a fixed tree, such as a docs site's contents; fixed and folding branches can also be mixed. Right and Left still move into and out of a fixed branch.
- **Motion,** as the kit's: the selection slides from row to row as `kit.tabs`' marker does, a row eases into a wash under the pointer, and a group opens to its rows' height and closes back as `kit.collapsible` does. Reduced motion moves at once.
- **Keyboard,** as the grid's: a click or Tab gives it the keyboard, and `c.focusNext` before it does at the start. Up and Down move between rows, branches and group headings, past folded rows; Home and End go to the ends. Left folds an open group or branch, or goes to the group or branch a row is in; Right opens a folded one, or goes from an open branch to its first row. The keys choose a row as they reach it, or with `choose_on_enter` only on Enter or Space, for an app where showing another view is slow. With nothing selected, the first row shows where the keys start. Typing a row's first letters moves to it, and a letter typed again to the next that begins with it. The keys it acts on are its own, so an app's Enter doesn't fire too. A sidebar with no rows doesn't take Tab.
- **Screen readers** hear each row as a tab with its count as its value, the selected one selected; headings as headings; group headings with whether they are open (`expanded_text`, `collapsed_text`), and branches as rows whose value is their count and whether they are open.
- `size` sets the rows as the kit's controls at that size; `color` tints the selection, `background` goes behind the rows, and `scale` is for apps that zoom their layout.
- A selected key that matches no row, or a row in a folded group, shows nothing selected until it shows; in a folded branch, the branch shows it.
- **Icons only:** with `icons_only`, rows show just their icons, centered, for a sidebar narrowed to a strip; labels show in tooltips and are still what a screen reader says. Headings become lines, a group's heading a chevron that folds it, and counts dots; a branch's rows aren't indented, and only the keys fold it. With a `splitter`, an app can switch to it when the sidebar is dragged narrow.
- **Rows** can be `disabled`: dimmed, not chosen by a click, passed by the keys, and said as disabled. A label cut short shows whole in a tooltip. A count can be a filled pill in the selection's tint (`count_style = .pill`), for what waits to be seen. A row whose count isn't known yet is `loading`: a spinner where the count goes, so the label doesn't move when it comes and the count never reads as 0, at the icon's corner with `icons_only`; a screen reader hears `loading_text`.
- **Menus:** a right-click (Control-click on the Mac) on a row sets `secondary_clicked` to its key, for the app to open a menu, such as the kit's; it doesn't choose the row.

## splitter

A handle between two panes side by side that resizes one of them: the one before it (`pane = .start`, the default), or the one after it (`.end`). The caller keeps the width and draws the panes; the handle is as tall as its parent.

```zig
const row = ui.div(c).row().sizeFull();
const side = ui.div(c).w(width).hFull();
sidebar(c);
side.end();
_ = controls.splitter(c, &width, .{ .min = 160, .max = 400, .label = "Sidebar width" });
content(c);
row.end();
```

- Dragging it moves the width within `min` and `max`, with the resize cursor; it returns true when the width changed.
- It takes the keyboard on a click or Tab: Left and Right move it by `step`, or with Shift by `big_step`, and Home and End to the ends; the keys it moves by are its own. A double click puts it back at `default`, if given.
- `stacked` is for panes above and below each other: the handle runs across, the width is the pane's height, and Up and Down move it.
- `disabled` dims it: it doesn't move, take the keyboard, or say it can.
- A screen reader hears a splitter called `label`, with the width as its value, and steps it.
- `grab_width` is where the pointer can grab it, and `center_line` draws a line down its middle; `scale` is for apps that zoom their layout, its lines too. `pane` is a `SplitterPane`.

## form

Rows with a label beside a control or a value, the labels in one column, so what follows them lines up row under row. The kit's `field` puts its label above its control, which suits a dialog of a few fields; a form suits a settings pane or an inspector of many rows.

```zig
var f = controls.form(c, .{ .row_lines = true });
f.heading("Snapshots", .{ .description = "How often, and how many to keep." });
{
    const r = f.row("Keep latest", .{ .hint = "Snapshots to keep, newest first." });
    _ = kit.numberInput(c, &keep, .{});
    r.end();
}
f.property("Hostname", host, .{ .mono = true });
f.end();
```

- `row` puts its label in the column and leaves the row open for a control. A `hint` sits under the control, muted, or an `err` in its place in the theme's danger color, and `required` marks the label with "*", as the kit's field has them. `info` adds an ⓘ after the label that says more in a tooltip; `disabled` dims the label and hint beside a control the caller disables; `label_top` puts the label at the top, beside a control taller than a line. An empty label leaves just the control column, for a checkbox with its own title or buttons under the controls.
- A row's label names its control to a screen reader, whole even when it is cut short, as nanoui names a control by the text before it on its line. A required row's name says so ("Name, required"; `required_text`), as the "*" isn't said.
- `property` shows a label and a value that wraps within the room left, the label beside its first line; a screen reader hears them as one ("Hostname, studio.local"). With `selectable`, the value can be selected and copied; with `wrap = false`, it keeps to a line, ends in "…" and shows whole in a tooltip.
- `heading` titles the rows after it, with a muted `description` under the title if wanted, and a `status` (danger for what can't be undone) that colors its title and its card. With `grouped`, each heading's rows are in a card of their own under it, in the theme's surface, as a settings window groups them. `row_lines` draws a line between rows.
- `foldingHeading` folds the rows after it and opens them again, eased, on a click or Enter or Space; the caller keeps whether it is open and draws its rows while it returns true. A screen reader hears it as a button that says whether it is expanded (`expanded_text`, `collapsed_text`).
- `link` is a row that leads somewhere, such as another pane: its label, its value and a chevron at its end, clicked as a whole or with Enter or Space; it returns true when it is. A value cut short shows whole in a tooltip, and a row appearing above it doesn't take its keyboard.
- `note` puts muted text under the rows before it, under their card when grouped.
- `control_align = .end` puts controls, values and hints at the rows' ends, as a settings window's cards have them.
- The column is as wide as the widest label, up to `max_label_width`, and labels longer than that are cut short; `label_width` sets it instead, so forms side by side line up. `label_align = .end` puts the labels by their controls (both alignments are a `FormAlign`).
- Every row is at least the height of the kit's controls at its `size`, so selects, inputs and toggles keep one rhythm; `gap` is the room after the labels and `row_gap` between rows.
- With `stack_below`, a form narrower than that puts its labels above what they name, as the kit's field has them, for a narrow pane; `stacked` says it did.

## swatches

A row of round colors (`Swatch`, a color and its name) to pick one from. The caller keeps the one chosen as an index, as the kit's `radioGroup` keeps its option, and it is ringed.

```zig
if (controls.swatches(c, &colors, &chosen, .{})) apply(colors[chosen.?].color);
```

- A click chooses one, and so do Left, Right (or Up and Down, as a radio group's keys), Home and End once the row has the keyboard, which it takes as the grid does: from a click, from Tab, or from `c.focusNext`. While it has the keyboard, the ring is the accent, or the app's `focus_ring` when it sets one.
- Each is named in a tooltip and to a screen reader, as a radio button, the chosen one selected, with the row's `label` ("Accent color") said after it.
- `disabled` dims them: no clicks or keys, and said as disabled. Swatches with no colors don't take Tab.
- `size` is a `kit.Size`, in step with the kit's controls; `border` and `selected_border` color the edges.

## flow

Cells of one width, as many to a row as fit its parent, wrapping onto more rows instead of running off, as nanoui's rows would. It takes its parent's width as the last frame laid it out, as the legend does, so it wraps anew when the window is resized.

```zig
var f = controls.flow(c, 180, .{ .gap = 16 });
for (readings) |r| {
    const cell = f.cell();
    controls.stat(c, r.label, r.value, .{});
    cell.end();
}
f.end();
```

- `breakRow` starts the next cell on a new row; `per_row` and `rows` say how it laid them out.
- `fill` stretches the cells to share each row's width, the cell width the narrowest they get, for cards that span their pane; a last row of fewer cells keeps their width.
- `f.stat(label, value, opts)` puts a stat in the next cell. With `.size = .xs, .card = null` it is a compact reading, so a row of them ("FILES 312 · SIZE 4.2 GB · TIME 0:42") wraps as the window narrows.

## pill

A short label in a box tinted in its color: a status in a capsule, or a badge in a box at least as wide as it is tall. The kit's `tag` with a lead, a tooltip, a height, and the tint's strength to set.

```zig
controls.pill(c, "LIVE", .{ .status = .success, .lead = .{ .dot = .{} } });
controls.pill(c, "P", .{ .shape = .box, .tooltip = "Performance cores" });
```

- `status` takes the kit's status colors, neutral the accent; `color` goes over it.
- `lead` is a dot that glows (`dim` draws it faint, the off beat of a blink) or an icon. `shape` is `.capsule` or `.box`.
- `size` (`.xs`) sets the label a point under the kit's text, and its padding, gap and corners follow it; `text_size`, `px`, `py`, `gap`, `radius` and `height` set them one by one. `pillLengths(opts)` gives them, to measure a pill before drawing it.
- `mono` writes the label in the monospaced font, so figures line up from pill to pill; `weight`, and `fill` and `edge`, the tint's and border's opacity.
- `pillOpen` leaves it open after its label, for a button in it; the caller ends it.
- A screen reader hears its label, or `value_text` in its place for a symbol or an abbreviation, and its `tooltip` after it. It takes no keyboard.

## caption

A small heading in muted capitals, semibold, heard as a heading so a screen reader can move from section to section. A panel's title is one.

```zig
controls.caption(c, "MEMORY", .{ .aside = "16 GB" });

const h = controls.captionOpen(c, "LIGHTS", .{});
controls.pill(c, "3 ON", .{});
h.trailing();
ui.text(c, "80%", .{});
h.end();
```

- `aside` is a muted note after it, heard after it; `icon` an SF Symbol before it, in its color.
- `captionOpen` leaves its line open for what goes right after it, then, after `trailing()`, at the line's end.
- `cut` cuts it short with an ellipsis where the room its line leaves ends, so what follows keeps its room: a path before buttons.
- `size` (`.xs`) or `text_size`, `color` (the muted text by default), `mono`, and `heading = false` for one that only labels a value beside it.

## panel

A rounded box with a border that groups what is in it, headed by a caption if it has a `title`. It is open for its content, which the caller ends; it isn't an element to a screen reader, so what it holds is reached as it is.

```zig
const p = controls.panel(c, .{ .title = "RETENTION" });
defer p.end();

const adv = controls.panel(c, .{ .title = "ADVANCED", .open = &advanced });
defer adv.end();
if (advanced) drawAdvanced(c);
```

- `status`, other than neutral, tints its border and caption, as the form's danger heading does its card.
- With `open`, its head is one button, the caption and a chevron: a click, or Space or Enter once Tab reaches it, folds or opens it, and a screen reader hears its title and `expanded_text` or `collapsed_text`. The caller draws what it holds only while it is open.
- `card` is its `Surface`: the theme's surface, border and radius, 14 points of padding and 10 between, as wide as its parent, unless it says. A width of `.auto` takes its content's, for panels side by side.

## callout

An icon and text that wraps, in a box tinted in the icon's color, in the flow of a page. The kit's `alert` with its title optional, the text in the theme's text color, and the icon, tint and padding the caller's to set.

```zig
controls.callout(c, "That folder doesn't exist.", .{ .status = .warning });
if (controls.callout(c, "The disk is full.", .{ .status = .danger, .closable = true })) dismissed = true;
```

- `status` sets the icon and tint (neutral: the accent and an info icon); `color` and `icon` go over them, and `title` is a line above the text.
- `closable` adds a ✕ at its end, named `close_text` to a screen reader and reached by Tab; `callout` returns true when it is clicked.
- `calloutOpen` leaves it open after its text for a button ("Retry"); the caller ends it, and draws its own ✕ if it wants one.
- A screen reader hears its title and text as one. `announce` says them when it appears or changes, once; by default a danger or a warning callout is said, and others aren't.
- `width` (`.fill`, or `.auto` for as wide as its text), `plain` for the icon and text without the box, `icon_align`, `text_color`, `size` or `text_size`, `icon_size`, `fill`, `edge`, `px`, `py`, `gap`, `radius` and `scale`.

## notice

What a pane shows in place of its content when it is empty, stopped or waiting: a large icon, a title and a description, centered in a panel. The kit's `empty` with a status, a spinner, and room for a button.

```zig
controls.notice(c, .{ .icon = "tray", .title = "No snapshots yet", .description = "They show here once the first backup runs." });

const n = controls.noticeOpen(c, .{ .icon = "network", .title = "Server stopped", .status = .warning });
if (kit.button(c, "Start", .{ .variant = .primary }).clicked) start();
n.end();
```

- `status` colors the icon and title; `color` and `icon_color` go over it. `loading` puts a spinner where the icon goes, without moving the title.
- A short description sits on one line; a long one wraps into lines of about one length, centered.
- A screen reader hears the title as a heading, then the description; `announce` says them once when it appears or changes.
- `card` goes over the panel's look, with 32 points of room above and below by default; `mono`, `size` or `text_size`, `icon_size` and `scale`.

## Surface

The look of a box a control draws itself in, which `panel`, `notice` and `stat` take as their `card`: `fill`, `border`, `border_width`, `radius`, `px`, `py`, `gap`, `width`, `height` and a `glow`. A field left null takes the control's own, so an app keeps its look as a preset and passes it in; `a.over(b)` lays one look over another, field by field.

```zig
const card: controls.Surface = .{ .radius = 12, .px = 16 };
const p = controls.panel(c, .{ .title = "RETENTION", .card = (controls.Surface{ .glow = .{} }).over(card) });
```

## format

Figures as people read them, each for the frame (`format.size(c, …)`, in its arena as `c.print` is) and into a buffer (`format.sizeBuf(buf, …)`, for use outside a frame):

- `size`: "145.7 MB", "0 B", in units of 1000, as drive makers and the system count, with at most one decimal; `rate`: "12.3 MB/s".
- `grouped`: "1,234,567"; `clock`: "1:02:03" or "2:03".
- `span`: "45 s", "12 min", "20 days", in its largest whole unit; `ago`: "just now", "12 min ago".
- `tilde`: "~/Documents", the home folder shown as ~.

`span` and `ago` take `TimeWords`, the units and how a span reads in the past ("{} ago"), so an app can put them in its own language.

## Charts

The charts draw what the caller keeps, a history or a few figures. What they share:

- **Sizes:** `width` and `height` are a `ui.Length`, as `kit.progress`'s width is. `.fill`, the default width, takes the parent's width, or in a row the room the rest leaves, so a chart sits beside a label as is. A bar across (`breakdown`, `meter`, a bar list's bars) takes its `height` as a `ui.Length` too, in points before `scale` for most. Round charts (`donut`, `gauge`) take a `diameter`, as `size` is a `kit.Size` wherever a chart has one.
- **Colors** come from the theme: bars and lines in its accent, tracks as the kit's progress bar's, legend labels muted. A `ramp` is a list of colors from the bottom to the top (or the first segment to the last), blended between, such as cool to hot; `rampColor` gives the color at a place on one, for a legend or a label in the same color.
- **Histories** (`trend`, `line`, `stat`) are oldest first. One kept in a ring, where a new reading takes the oldest's place, is read from its oldest reading with `head`, without copying it. With fewer readings than slots, they sit on the right.
- **Scale:** every chart with a scale (`trend`, `line`, `bars` with `units`, `barList`) takes it the same way. `min` is the value at the bottom and `max` at the top, unless the data goes higher: then the top rises to it, so a quiet history doesn't fill the chart and a loud one isn't cut off. `fixed_max` keeps the top at `max`, and a null `max` takes the data's largest. `meter` and `gauge` take a `min` and `max` too, for a value in its own units.
- **Lines at values:** `value_lines` (`ValueLine`) draws lines across at values, such as half or a limit, with a label each, behind the bars or lines.
- **Inspecting:** an `interactive` chart (`bars`, `line`) follows the pointer, and takes the keyboard on a click or Tab: Left, Right, Home and End move on from the slot pointed at, until the pointer moves again. `current` is the slot it points at; call `tooltip` with what it shows, and the chart says it in a tooltip there and to a screen reader. It is adjustable to a screen reader: swiping up and down steps through its slots, saying each.
- **Screen readers:** with a `label` ("CPU history"), a chart is one image, and its `value_text` ("62 °C, peak 81 °C") is what it shows; a meter and a gauge say their value as a percentage unless given one. Without a label, a chart is a decoration and is left out, unless it is interactive: then it is called its `chart_text` ("Chart"), so give it a label.
- **Motion:** `breakdown`, `donut`, `gauge` and `meter` ease to new values, as the kit's progress bar does, unless the system asks for reduced motion.
- **Bad figures:** a part that is negative (where there is no room below zero) or not a number counts as nothing, a reading that is not a number or is infinite leaves its slot empty or breaks its line, and parts that add up to more than their bar are squeezed to fit. `gap = 0` means no gap and no seams on every chart that has one.
- **`scale`** multiplies a chart's lengths for apps that zoom their layout with `c.setZoom`, as the grid's does: the kit has no sizes for charts. Charts with text (`legend`, `barList`, `stat`) take the kit's `size` for it.

## trend

A history drawn as bars, right-aligned in `capacity` slots, scaled to its peak, the older bars fainter. A compact chart for a row or a tile; for one to point at, use `line` or `bars`.

```zig
controls.trend(c, temps, .{ .capacity = 60, .min = 20, .max = 110, .label = "Temperature", .value_text = "62 °C" });
```

- `color` colors every bar, or `ramp` each by its height.
- `baseline` keeps a reading at `min` showing as a line, and `fade` is the oldest bar's opacity, rising to 1 at the newest (null for none).
- With more readings than slots, it shows the newest, scaled to them.
- It is drawn with `bars`, so it takes their `axis`, `start_text` and `end_text`, and `interactive` with `tips`, one a reading shown, oldest first, said in a tooltip and to a screen reader.

## line

One or more histories (`LineSeries`) drawn as lines across `capacity` places, each filled under as an area with `area`, its opacity. A reading that is not a number breaks its line. It is drawn with `ui.canvas`, and ends with `end`, after a tooltip if one is wanted.

```zig
var l = controls.line(c, &.{
    .{ .values = read, .head = read_head, .area = 0.15 },
    .{ .values = write, .head = write_head, .color = t.success },
}, .{ .capacity = 60, .max = 40, .interactive = true, .label = "Network traffic" });
if (l.current) |i| if (l.reading(0, i)) |r| l.tooltip(c.print("read {d:.1} MB/s", .{r}));
l.end();
```

- With `interactive`, the current reading is marked by a line down through it and a dot on each series; with a history shorter than the chart, only slots with a reading are stopped on. `l.reading(series, slot)` is a series' reading in a slot, ring or not.
- `line_width` is the lines' width.
- `axis`, `start_text` and `end_text`, as `bars` takes them: the value lines' labels beside the chart, and times under it.

## bars

A row of `count` slots, built with `next` and `end` as the grid's rows are. `slot.bar` draws a bar of parts (`BarPart`, a `value` and a `color`) in a slot, each `value` of the slot's height; a slot can be left empty, and its `box` styled.

```zig
var b = controls.bars(c, .{ .count = 60, .height = .{ .px = 64 }, .interactive = true, .label = "Disk" });
while (b.next()) |slot| slot.bar(&.{
    .{ .value = read[slot.index], .color = t.primary },
    .{ .value = write[slot.index], .color = t.success },
});
if (b.current) |i| b.tooltip(c.print("{d:.1} MB/s", .{read[i] + write[i]}));
b.end();
```

- Parts stack up from zero, the first nearest it. With room `below` zero (a share of the height), negative parts go down from it: a loss, a change down.
- **Units:** with `units`, parts are values on a scale from `min` to `max` (a bar of 40 on a scale of 0 to 100 is 40% of the height), and value lines are placed on it. Unless `fixed_max`, the top rises to the tallest bar, so none is cut off, and a null `max` takes it. A `min` below zero leaves room for negative parts at the same scale; one above zero starts the bars there, as a temperature from 20 does.
- **A short history:** with `readings`, fewer readings than slots sit at the right, the newest last. `next` gives only their slots, `slot.reading` is the reading in each, and with `interactive`, only they can be pointed at or stepped through, `current` being a reading.
- **An axis:** `axis = .start` or `.end` puts the value lines' labels in a gutter beside the chart, level with their lines, leaving out one that would overlap the one above it; `start_text` and `end_text` go under the chart at its ends ("−60 s", "now").
- `gap` is the room between slots, a hairline of one point by default.
- `baseline` is the shortest bar, as a share of the height: a bar shorter than it is drawn that tall, so a reading of zero still shows as a line in its first part's color. `fade` is the leftmost slot's opacity, rising to 1 at the rightmost, for a history whose older bars are fainter.
- What is drawn before the first `next` (absolute) sits behind the bars.

## breakdown

A bar across, broken down into parts from the left.

```zig
controls.breakdown(c, &.{
    .{ .value = app / total, .color = t.primary },
    .{ .value = wired / total, .color = t.warning },
}, .{ .label = "Memory", .value_text = "15 of 24 GB" });
```

- By default each part is `value` of the bar (0 to 1), and what they leave shows the track.
- With `whole`, the parts are the whole bar, each its share of their sum: traffic by source, say.
- One part with a `part_radius` and a `glow` is a level against a maximum, such as a fan's speed.
- `height` (a `ui.Length`), `radius` (null rounds the ends), `gap` (a hairline by default; 0 for none) and `track`.

## donut

A ring of parts, clockwise from the top, with a figure (`text`) and a word under it (`caption`) in its middle. Its parts take a share of the ring as a breakdown's do, `whole` included. It is drawn with `ui.canvas`.

```zig
controls.donut(c, &parts, .{ .diameter = 104, .text = "56%", .caption = "used", .label = "Memory", .value_text = "56% used" });
```

- `diameter` is its width across, `thickness` the ring's, and `gap` the room between parts.

## barList

Rows (`BarListItem`) of a label, a bar across and a figure (`value_text`), the bars scaled to the largest value or to `max`. With `clickable`, rows light up under the pointer and take the keyboard as buttons do (Tab, then Enter), and it returns the row clicked.

```zig
if (controls.barList(c, &folders, .{ .clickable = true })) |i| open(folders[i]);
```

- `label_width` and `value_width` are the columns either side of the bars, and `bar_height` the bars' height; labels too long are cut short. The bars scale to `max`, rising to the largest item unless `fixed_max`; a null `max` takes the largest.
- An item's `key` keeps its row's keyboard focus and easing on it as the list re-sorts. A clickable row takes Enter or Space.
- **Richer rows:** an item can lead with an `icon`, in a slot of its own so labels line up, or a `badge` ("P", "GPU") in a small tinted tag; end with a muted `detail` after its figure ("max 94"), in a `detail_width` column; and color its figure (`value_color`). A screen reader hears the figure and the detail.
- **Levels:** `min` starts the scale above zero (a temperature from 20); `ramp` colors each bar by its level, `track`, `glow` and `bar_radius` (null rounds the ends) style them, and `style = .meter` draws each row's bar as a meter of `segments`, lit to its level.

## meter

A row of `segments`, like LEDs, lit up to a value from 0 to 1: segment `i` of `n` lights when its middle, `(i + 0.5) / n`, is at most the value.

```zig
controls.meter(c, load, .{ .ramp = &heat, .glow = 0.6, .label = "CPU load" });
controls.meter(c, 1, .{ .ramp = &hues, .gap = 0, .radius = 0, .segments = 48 }); // a strip of the hues
```

- Lit segments take `color`, or `ramp` by their place, and `glow` in it; unlit ones are the `track`.
- With a `gap` of 0, lit all the way, it is a strip of colors in steps, for the gradients nanoui can't fill, such as under a slider. Its segments overlap by a point, so no seams show, and a `radius` rounds only the strip's ends.
- `zones` labels equal runs of the segments, one a run ("<20", "<40", "80+"), with a wider `zone_gap` between runs: a scale in bands.
- `min` and `max` take a value in its own units (a temperature from 20 to 110). `height` is a `ui.Length`, and a null `radius` rounds the segments' ends.

## gauge

A ring of ticks from the bottom left round to the bottom right, lit up to a value from 0 to 1, with a figure (`text`) and a word under it (`caption`) in its middle, as the donut has. It is drawn with `ui.canvas`.

```zig
controls.gauge(c, score, .{ .ramp = &strength, .text = "B", .caption = "62 bits", .label = "Strength" });
```

- Lit ticks take `color`, or `ramp` by their place, with a `glow` behind them; unlit ones are the `track`. The figure is in the value's color.
- `diameter` is its width across and `ticks` how many; their length, width and glow keep in proportion to the diameter, within its box. `min` and `max` take a value in its own units. `inner_line` draws a thin circle inside them.
- A screen reader hears its value as a percentage, unless given a `value_text`.

## stat

A figure to read at a glance, in a tile: its label, the figure large, how it changed in a kit tag colored by its `status`, and a trend of its `history` under it.

```zig
controls.stat(c, "Requests", "12,480", .{ .change = "+8%", .status = .success, .history = per_minute });
```

- `size` (`.md` by default) sizes the figure at twice the kit's text at that size. `card` is the tile's `Surface` (the theme's surface, border and radius by default), and `null` leaves it out.
- At `.xs` without a tile, it is a compact reading: the label a caption, and the figure a point over the kit's text, for readings packed in rows with `flow`'s `stat`. `mono` writes the figure in the monospaced font.
- `value_color` colors the figure, for one that says how something stands: without a tile, a reading such as "Thermal: Nominal" in the success color.
- A row of stats shares it, each `.fill` wide; with the row's `itemsStretch`, the tiles are one height.
- `unit` follows the figure, smaller and muted ("87" then "%"); `detail` is a muted line under it ("over the last hour"); and `loading` shows a spinner in place of a figure not yet known, so it never reads as 0 (a screen reader hears `loading_text`).
- `key` puts a dot before the label in the color of the series the stat reads in a chart beside it.
- `scale` multiplies its lengths, as the charts'. Its history takes a scale as a trend does (`history_min`, `history_max`, `history_fixed_max`) and `history_ramp`.
- `statButton` draws a stat that can be clicked, to lead to more: it lightens under the pointer, takes the keyboard as a button does (Tab, then Enter or Space), is a button to a screen reader, and returns its `ui.Interaction`.

## legend

What a chart's colors stand for: a swatch and a label each, side by side, running on to a new line where the legend's width ends, as text wraps.

```zig
var l = controls.legend(c, .{});
l.item(t.primary, "App 9.6 GB");
l.itemDetail(t.warning, "Wired 2.7 GB", "▲4.2");
l.trailing("Free 10.5 GB");
l.end();
```

- `itemDetail` adds a smaller, fainter detail after the label, such as a peak.
- `trailing` puts text at the end of the last line, such as what the items leave.
- `size` (`.xs` by default) sizes the labels and swatches, `mono` lines up figures, and `color` is the labels' color. `gap` is the room between items, `row_gap` between lines.
- `shape` draws its items' swatches as squares, dots or lines, for a line chart's series.
- `width = .fit` makes it only as wide as its items, for a legend beside a chart's title; they still run on where the parent's width ends.
- `controls.legendSwatch(c, color, .{ .shape = .square | .dot | .line })` draws a legend's swatch on its own, in a chart's title, a table's cell or a tooltip.

## Example

[`examples/gallery`](examples/gallery/main.zig) is a window whose `sidebar` picks a view for each kind of control: Grid, and under it Grouped (pull requests in groups that fold, their headings tagged with how many fail or drawn the gallery's own way, as cards or rows of two lines, reloading with sketched rows), Form, Sidebar (the sidebar's own options in a form, which the sidebar takes as they change: size, tint, background, gap, scale, icons only, counts loading, choosing on Enter and fixed branches), and in a Charts group, a live Monitor (its alerts in a pill) and Every chart, each chart once with fixed figures, the gauges in a flow, a branch with the charts of histories and of parts under it. A `splitter` resizes the sidebar, which shows only its icons when dragged narrow; a right-click on a row opens a menu; its counts load for a moment at launch. Status is a backup service at a glance ([`status.zig`](examples/gallery/status.zig)): pills, compact readings written by `format`, callouts to close and bring back, panels side by side and one that folds, and a notice while its server is stopped or connecting. The controls ring only while the keyboard is in use.

- **Grid** is a grid of ten thousand files ([`grid.zig`](examples/gallery/grid.zig)). Sort by a column's title, move, resize and fit columns, fit them all or reset them, show two more columns and scroll them sideways past the names, draw lines between rows and columns, read cut-off names in tooltips, search, narrow the window to hide columns, switch on stripes, show only the five largest files, select one or several files and open them with the mouse or the keyboard, right-click them for a menu to open, select or delete them, drag them out of the window, type a name to jump to it, page through them with a pager, and have rows arrive a page at a time as they scroll into view.
- **Form** is a settings pane ([`form.zig`](examples/gallery/form.zig)) in cards, its controls at the rows' ends: a text field, swatches, a number input, a select and toggles in rows under headings with descriptions, with hints, an ⓘ, an error when the name is empty, rows dimmed while backups are off, a note, an "Advanced" section that folds, properties to read, copy, or read whole in a tooltip, a row that leads somewhere, and a danger zone. Narrow the window and its labels go above their controls; switch off the cards, the lines between rows, and the controls at the ends, or put the labels by their controls.
- **Charts** is a system monitor whose readings change four times a second ([`charts.zig`](examples/gallery/charts.zig)): stats with their trends at the top, the CPU's load as a trend with a line at half, a meter, and bars up and down for how it changed; network traffic as a line chart to point at or step through with the keys; memory as a donut and a breakdown with a legend that runs on to new lines; disk use as a list of bars by folder to click; the fan as a glowing level; and the heat ramp as a strip. Pause it, switch the ramp, the glow and the fade, and set the meter's segments.

```sh
zig build example
```

## Building

```sh
zig build                  # build the example into zig-out/bin
zig build test             # run the tests
zig build test-snapshots   # compare the controls' drawings with tests/snapshots
zig build docs             # build the API docs into zig-out/docs
zig build example          # run the example
```

## Versioning

While the library is 0.x, a minor release may change the API and a patch release won't. Each release is tagged `vX.Y.Z`, and [CHANGELOG.md](CHANGELOG.md) says what it changed.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE). The DejaVu fonts in [`tests/fonts`](tests/fonts), which only the snapshot tests use, have [their own license](tests/fonts/LICENSE).
