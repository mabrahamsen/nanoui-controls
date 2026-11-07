# nanoui-controls

[![CI](https://github.com/mabrahamsen/nanoui-controls/actions/workflows/ci.yml/badge.svg)](https://github.com/mabrahamsen/nanoui-controls/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Controls for [nanoui](https://github.com/justrach/nanoui) apps that nanoui's own kit (`nanoui.kit`) doesn't have. They follow the kit's conventions: each is a call in a frame, styled from the app's theme, with what the user changes kept by the caller.

| Control | What it does |
|---|---|
| [`grid`](#grid) | Rows of cells under a header of column titles, with the columns lined up, sorting by a clicked title and building only the rows in view. |
| [`pager`](#pager) | "‹ 1 … 9 10 11 … 20 ›": numbered pages, for an app that shows a page at a time. |
| [`sidebar`](#sidebar) | Rows to pick what a window shows, under headings and in groups that fold, chosen by key, with the keyboard. |
| [`trend`](#trend) | A history drawn as bars, scaled to its peak, the older bars fainter: a CPU's load, a temperature. |
| [`line`](#line) | Histories drawn as lines, filled under as areas if wanted, which the user can point at or step through. |
| [`bars`](#bars) | A row of slots for any bar chart, each a bar of colored parts, up from zero or down below it, which the user can point at or step through. |
| [`breakdown`](#breakdown) | A bar across, broken down into colored parts: a total by kind, a whole by source, or a level against a maximum. |
| [`donut`](#donut) | A ring split into colored parts, with a figure in its middle. |
| [`barList`](#barlist) | Rows of a label, a bar and a figure, scaled to the largest: the busiest processes, disk use by folder. |
| [`meter`](#meter) | A row of segments, like LEDs, lit up to a value; without gaps, a strip of colors in steps. |
| [`stat`](#stat) | A figure in a tile, with how it changed and a trend of its history. |
| [`legend`](#legend) | What a chart's colors stand for, running on to new lines where its width ends. |

## Requirements

| | Version |
|---|---|
| Zig | 0.17.1 or later |
| nanoui | 0.12.0 |

The app must pin the same nanoui release as this library, so both share one copy of nanoui. Otherwise nanoui's types don't match and the build fails.

## Installation

Add the library to the app's `build.zig.zon`:

```sh
zig fetch --save "git+https://github.com/mabrahamsen/nanoui-controls?ref=v0.4.0"
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
- **Resizing:** with `widths`, an array the caller keeps (one width a column, starting at 0), dragging the edge between two titles resizes the column on its left if it has a width, else the one on its right, and a double click fits that column to its widest title or cell in view.
- **Reordering:** with `order`, an array the caller keeps (the column numbers in the order they show), dragging a title moves its column. Cells keep their column numbers, so the code that builds them doesn't change.
- **Scrolling sideways:** with `scroll_x`, columns that don't fit keep their widths and scroll sideways, with the wheel's or trackpad's sideways scroll or the bar under the rows; `freeze_first` keeps the first column in place, as a spreadsheet's names are.
- **Tooltips:** a cell whose text is cut off shows all of it when the pointer rests on it (`tooltips`, on by default).
- **Sorting:** clicking a `sortable` column's title sorts by it, and clicking again reverses it. `g.sorted` says the sort changed this frame, so the caller sorts its rows before building them.
- **Selection:** with `selected`, a click selects a row and it is drawn highlighted. The grid takes the keyboard as a text field does: a click in it or Tab gives it the keyboard (`g.focused`), and `c.focusNext(false)` just before `grid` gives it the keyboard at the start. While it has the keyboard, Up and Down move the selection a row, Page Up and Page Down a view, and Home and End to the ends, scrolling it into view. Enter or a double click opens it (`row.opened`). The selection is grey while something else has the keyboard, so two grids in a window, or a grid under a search field, take the keys in turn. The selection is a row index, so a caller that sorts finds its row again.
- **Several rows:** with `selection` too, one flag a row kept by the caller, Cmd-click (Ctrl-click on Windows and Linux) adds or takes away a row, Shift-click and Shift with the keys select a run of rows, and Cmd+A (Ctrl+A) selects them all.
- **Typing to jump:** typing while the grid has the keyboard gives `g.typed`, the text so far (a pause of a second starts it afresh). The caller finds the first row it begins, as only it knows what the rows hold, and `g.jump(i)` selects that row and scrolls to it.
- **Dragging rows out:** with `drag_rows`, a row held and moved a few points reports `row.drag_started`, and `g.dragOut(text)` drags that text out of the window, for the rows selected (the row is selected first, unless it is already). nanoui drags text out on macOS so far.
- **Context menus:** `row.secondary_clicked` is a right-click (or Control-click on the Mac) on a row, for the app's menu. It selects the row, unless the row is already selected, so the menu acts on the selection.
- **Screen readers** hear the rows as rows, read as their cells' text, with the selected ones marked, and the sortable titles as buttons that say which way the rows are sorted.
- **Long lists** cost what a screenful does: only the rows in view are built. The grid fills the room left in its parent, which needs a bounded height.
- **Loading as it scrolls:** `g.first` and `g.last` are the rows in view, so a caller whose rows come from a server fetches those pages, and the ones around them, and draws placeholders until they arrive. `scroll_to` brings a row into view.
- **Empty:** `empty` is text shown under the titles when there are no rows.
- **A set number of rows:** `max_rows = 5` shows at most five, without scrolling, and takes only their height.
- **Tables to read:** `clickable = false` makes rows that take no clicks, don't light up and show no pointing hand, for a summary or comparison; a screen reader still hears them as rows.
- **Hiding columns:** a column with `min_window_width` hides in narrower windows, and `hidden` hides columns on the caller's say. Build cells with `g.cellAt(i)`, which returns false for a hidden column, so columns keep their numbers.
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
- Once the pager has the keyboard (a click on it, or Tab), Left and Right move a page, and Home and End go to the first and last.
- When the pages grow fewer than the current page, as after a search, the pager moves it to the last and returns true, so a caller that loads a page on a change loads that one.
- It keeps its width from page to page, so the arrows stay under the pointer: it always shows as many numbers and ellipses (near an end, the pages run on where an ellipsis would be), each as wide as the widest number. Only a change in the number of pages changes its width.
- `around` sets how many pages either side of the current one are numbered, and `size` is the buttons' size, as the kit's (`.sm` by default).
- With a grid's `max_rows`, it shows a page at a time: the grid's rows are the page's.

## sidebar

Rows to pick what a window shows: a mail app's mailboxes, a settings window's panes. Each row has an optional icon, a label and an optional count, under headings and in groups that fold. One row is selected by a key the caller keeps, never by position, so the selection stays on its row as rows come and go.

```zig
var sb = controls.sidebar(c, "nav", selected, .{});
sb.heading("Mailboxes");
sb.item("inbox", "Inbox", .{ .icon = "doc.text", .count = unread });
sb.item("sent", "Sent", .{ .icon = "arrow.up" });
if (sb.group("folders", "Folders", &folders_open)) |g| {
    for (folders) |f| sb.item(f.id, f.name, .{ .icon = "folder" });
    g.end();
}
if (sb.end()) |key| selected = key;
```

- `end` returns the key chosen this frame, by a click or the keys. Keep it: it must outlive the frame, as the rows' keys usually do.
- It takes the room left in its parent, and scrolls when its rows need more, keeping the keys' row in view.
- **Motion,** as the kit's: the selection slides from row to row as `kit.tabs`' marker does, a row eases into a wash under the pointer, and a group opens to its rows' height and closes back as `kit.collapsible` does. Reduced motion moves at once.
- **Keyboard,** as the grid's: a click or Tab gives it the keyboard, and `c.focusNext` before it does at the start. Up and Down move between rows and group headings, past folded rows; Home and End go to the ends; Left folds a group (or goes from a row to its group's heading) and Right opens it. The keys choose a row as they reach it, or with `choose_on_enter` only on Enter or Space, for an app where showing another view is slow.
- **Screen readers** hear each row as a tab with its count as its value, the selected one selected; headings as headings; and group headings with whether they are open (`expanded_text`, `collapsed_text`).
- `size` sets the rows as the kit's controls at that size; `color` tints the selection, `background` goes behind the rows, and `scale` is for apps that zoom their layout.
- A selected key that matches no row, or a row in a folded group, shows nothing selected until it shows.

## Charts

The charts draw what the caller keeps, a history or a few figures. What they share:

- **Sizes:** `width` and `height` are a `ui.Length`, as `kit.progress`'s width is. `.fill`, the default width, takes the parent's width, or in a row the room the rest leaves, so a chart sits beside a label as is. A bar across (`breakdown`, `meter`) takes a `height` in points, as the kit's progress bar does.
- **Colors** come from the theme: bars and lines in its accent, tracks as the kit's progress bar's, legend labels muted. A `ramp` is a list of colors from the bottom to the top (or the first segment to the last), blended between, such as cool to hot; `rampColor` gives the color at a place on one, for a legend or a label in the same color.
- **Histories** (`trend`, `line`, `stat`) are oldest first. One kept in a ring, where a new reading takes the oldest's place, is read from its oldest reading with `head`, without copying it. With fewer readings than slots, they sit on the right.
- **Scale:** `min` is the value at the bottom and `max` at the top, unless a reading goes higher: then the top rises to it, so a quiet history doesn't fill the chart and a loud one isn't cut off. `fixed_max` keeps the top at `max`.
- **Lines at values:** `value_lines` (`ValueLine`) draws lines across at values, such as half or a limit, with a label each, behind the bars or lines.
- **Inspecting:** an `interactive` chart (`bars`, `line`) follows the pointer, and takes the keyboard on a click or Tab: Left, Right, Home and End move on from the slot pointed at, until the pointer moves again. `current` is the slot it points at; call `tooltip` with what it shows, and the chart says it in a tooltip there and to a screen reader.
- **Screen readers:** with a `label` ("CPU history"), a chart is one image, and its `value_text` ("62 °C, peak 81 °C") is what it shows; a meter says its value as a percentage unless given one. Without a label, a chart is a decoration and is left out, unless it is interactive: then it is called "Chart", so give it a label.
- **Motion:** `breakdown`, `donut` and `meter` ease to new values, as the kit's progress bar does, unless the system asks for reduced motion.
- **Bad figures:** a part that is negative (where there is no room below zero) or not a number counts as nothing, a reading that is not a number or is infinite leaves its slot empty or breaks its line, and parts that add up to more than their bar are squeezed to fit.
- **`scale`** multiplies a chart's lengths for apps that zoom their layout with `c.setZoom`, as the grid's does: the kit has no sizes for charts. Charts with text (`legend`, `barList`, `stat`) take the kit's `size` for it.

## trend

A history drawn as bars, right-aligned in `capacity` slots, scaled to its peak, the older bars fainter. A compact chart for a row or a tile; for one to point at, use `line` or `bars`.

```zig
controls.trend(c, temps, .{ .capacity = 60, .min = 20, .max = 110, .label = "Temperature", .value_text = "62 °C" });
```

- `color` colors every bar, or `ramp` each by its height.
- `baseline` keeps a reading at `min` showing as a line, and `fade` is the oldest bar's opacity, rising to 1 at the newest (null for none).
- With more readings than slots, it shows the newest, scaled to them.

## line

One or more histories (`LineSeries`) drawn as lines across `capacity` places, each filled under as an area with `area`, its opacity. A reading that is not a number breaks its line. It is drawn with `ui.canvas`, and ends with `end`, after a tooltip if one is wanted.

```zig
var l = controls.line(c, &.{
    .{ .values = read, .head = read_head, .area = 0.15 },
    .{ .values = write, .head = write_head, .color = t.success },
}, .{ .capacity = 60, .max = 40, .interactive = true, .label = "Network traffic" });
if (l.current) |i| l.tooltip(c.print("read {d:.1} MB/s", .{readAt(i)}));
l.end();
```

- With `interactive`, the current reading is marked by a line down through it and a dot on each series.
- `line_width` is the lines' width.

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
- `gap` is the room between slots, a hairline of one point by default.
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
- `height`, `radius` (null rounds the ends), `gap` (a hairline by default; 0 for none) and `track`.

## donut

A ring of parts, clockwise from the top, with a figure (`text`) and a word under it (`caption`) in its middle. Its parts take a share of the ring as a breakdown's do, `whole` included. It is drawn with `ui.canvas`.

```zig
controls.donut(c, &parts, .{ .size = 104, .text = "56%", .caption = "used", .label = "Memory", .value_text = "56% used" });
```

- `size` is its width across, `thickness` the ring's, and `gap` the room between parts.

## barList

Rows (`BarListItem`) of a label, a bar across and a figure (`value_text`), the bars scaled to the largest value or to `max`. With `clickable`, rows light up under the pointer and take the keyboard as buttons do (Tab, then Enter), and it returns the row clicked.

```zig
if (controls.barList(c, &folders, .{ .clickable = true })) |i| open(folders[i]);
```

- `label_width` and `value_width` are the columns either side of the bars, and `bar_height` the bars' height; labels too long are cut short.

## meter

A row of `segments`, like LEDs, lit up to a value from 0 to 1: segment `i` of `n` lights when its middle, `(i + 0.5) / n`, is at most the value.

```zig
controls.meter(c, load, .{ .ramp = &heat, .glow = 0.6, .label = "CPU load" });
controls.meter(c, 1, .{ .ramp = &hues, .gap = 0, .radius = 0, .segments = 48 }); // a strip of the hues
```

- Lit segments take `color`, or `ramp` by their place, and `glow` in it; unlit ones are the `track`.
- With a `gap` of 0, lit all the way, it is a strip of colors in steps, for the gradients nanoui can't fill, such as under a slider. Its segments overlap by a point, so no seams show.

## stat

A figure to read at a glance, in a tile: its label, the figure large, how it changed in a kit tag colored by its `status`, and a trend of its `history` under it.

```zig
controls.stat(c, "Requests", "12,480", .{ .change = "+8%", .status = .success, .history = per_minute });
```

- `size` (`.md` by default) sizes the figure at twice the kit's text at that size; `card = false` leaves out the tile.
- A row of stats shares it, each `.fill` wide; with the row's `itemsStretch`, the tiles are one height.

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

## Example

[`examples/gallery`](examples/gallery/main.zig) is a window whose `sidebar` picks a view for each kind of control: Grid, and in a Charts group, a live Monitor and Every chart, each chart once with fixed figures.

- **Grid** is a grid of ten thousand files ([`grid.zig`](examples/gallery/grid.zig)). Sort by a column's title, move, resize and fit columns, show two more columns and scroll them sideways past the names, draw lines between rows and columns, read cut-off names in tooltips, search, narrow the window to hide columns, switch on stripes, show only the five largest files, select one or several files and open them with the mouse or the keyboard, right-click them for a menu to open, select or delete them, drag them out of the window, type a name to jump to it, page through them with a pager, and have rows arrive a page at a time as they scroll into view.
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
