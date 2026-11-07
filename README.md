# nanoui-controls

[![CI](https://github.com/mabrahamsen/nanoui-controls/actions/workflows/ci.yml/badge.svg)](https://github.com/mabrahamsen/nanoui-controls/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Controls for [nanoui](https://github.com/justrach/nanoui) apps that nanoui's own kit (`nanoui.kit`) doesn't have. They follow the kit's conventions: each is a call in a frame, styled from the app's theme, with what the user changes kept by the caller.

| Control | What it does |
|---|---|
| [`grid`](#grid) | Rows of cells under a header of column titles, with the columns lined up, sorting by a clicked title and building only the rows in view. |
| [`pager`](#pager) | "‹ 1 … 9 10 11 … 20 ›": numbered pages, for an app that shows a page at a time. |
| [`trend`](#trend) | A history drawn as bars, scaled to its peak, the older bars fainter: a CPU's load, a temperature. |
| [`bars`, `stack`](#bars-and-stack) | A row of slots for any bar chart, which can follow the pointer, and a bar of colored parts stacked in a slot. |
| [`split`](#split) | A bar across, split into colored parts: a total by kind, a whole by source, or a level against a maximum. |
| [`meter`](#meter) | A row of segments, like LEDs, lit up to a value; without gaps, a strip of colors in steps. |
| [`legend`](#legend) | What a chart's colors stand for, in a row in wide windows and a column in narrow ones. |

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

## Charts

The charts draw what the caller keeps, a history or a few figures, and take no input; only `bars` follows the pointer. What they share:

- **Sizes:** `width` and `height` are a `ui.Length`, as `kit.progress`'s width is. `.fill`, the default width, takes the parent's width, or in a row the room the rest leaves, so a chart sits beside a label as is.
- **Colors** come from the theme: bars in its accent, tracks as the kit's progress bar, legend labels muted. A `ramp`, a function from a place or height (0 to 1) to a color, colors a trend or a meter from cool to hot.
- **Screen readers:** with a `label` ("CPU history"), a chart is one image, and its `value` ("62 °C, peak 81 °C") is what it shows; a meter says its value as a percentage unless given one. Without a label, a chart is a decoration and is left out.
- **Bad figures:** a part that is negative or not a number counts as nothing, a reading that is not a number or is infinite leaves its slot empty, and parts that add up to more than their bar are squeezed to fit.
- **`scale`** multiplies a chart's lengths for apps that zoom their layout with `c.setZoom`, as the grid's does: the kit has no sizes for charts. `legend` takes the kit's `size` for its labels.

## trend

A history drawn as bars, oldest first, right-aligned in `capacity` slots, so a history that isn't full yet fills from the right.

```zig
controls.trend(c, temps, .{ .capacity = 60, .min = 20, .max = 110, .label = "Temperature", .value = "62 °C" });
```

- Bars are scaled from `min` to `max`, or to the peak if the history goes higher, so a quiet history doesn't fill the chart.
- `color` colors every bar, or `ramp` each by its height.
- `baseline` keeps a reading at `min` showing as a line, and `fade` is the oldest bar's opacity, rising to 1 at the newest (null for none).
- With more readings than slots, it shows the newest, scaled to them.

## bars and stack

`bars` opens a row of `count` slots, built with `next` and `end` as the grid's rows are; `stack` draws a bar of parts in a slot, from the bottom up, each `value` of the slot's height. A slot can be left empty, and its `box` styled.

```zig
var b = controls.bars(c, .{ .count = 60, .height = .{ .px = 64 }, .hover = true });
while (b.next()) |slot| {
    if (slot.hovered) _ = slot.box.bg(t.surface_hover);
    controls.stack(c, &.{
        .{ .value = read[slot.index], .color = t.primary },
        .{ .value = write[slot.index], .color = t.success },
    });
}
b.end();
```

- With `hover`, `Bars.hovered` and `slot.hovered` say which slot is under the pointer, to say its figures; the chart keeps the arrow cursor.
- What is drawn before the first `next`, such as grid lines, sits behind the bars.
- `gap` is the room between slots, a hairline of one point by default.
- A `ChartPart` is a `value` and a `color`, for `stack` and `split`.

## split

A bar across, split into parts from the left.

```zig
controls.split(c, &.{
    .{ .value = app / total, .color = t.primary },
    .{ .value = wired / total, .color = t.warning },
}, .{ .label = "Memory", .value = "15 of 24 GB" });
```

- By default each part is `value` of the bar (0 to 1), and what they leave shows the track.
- With `whole`, the parts are the whole bar, each its share of their sum: traffic by source, say.
- One part with a `part_radius` and a `glow` is a level against a maximum, such as a fan's speed.
- `height`, `radius` (null rounds the ends), `gap` (a hairline by default; 0 for none) and `track`.

## meter

A row of `segments`, like LEDs, lit up to a value from 0 to 1: segment `i` of `n` lights when its middle, `(i + 0.5) / n`, is at most the value.

```zig
controls.meter(c, load, .{ .ramp = heat, .glow = 0.6, .label = "CPU load" });
controls.meter(c, 1, .{ .ramp = hues, .gap = 0, .radius = 0, .segments = 48 }); // a strip of the hues
```

- Lit segments take `color`, or `ramp` by their place, and `glow` in it; unlit ones are the `track`.
- With a `gap` of 0, lit all the way, it is a strip of colors in steps, for the gradients nanoui can't fill, such as under a slider. Its segments overlap by a point, so no seams show.
- `height`, `gap` and `radius` set its look.

## legend

What a chart's colors stand for: a swatch and a label each, side by side in windows at least `row_from` wide and one under another in narrower ones.

```zig
var l = controls.legend(c, .{ .row_from = 560 });
l.item(t.primary, "App 9.6 GB");
l.item(t.warning, "Wired 2.7 GB");
if (l.wide) ui.spacer(c);
ui.text(c, "Free 10.5 GB", .{ .size = 11, .color = t.muted });
l.end();
```

- `Legend.wide` says the items are in a row, so a caller can push what follows them to the end.
- `itemOpen` leaves an item open after its label for more, such as a peak; end it.
- `size` (`.xs` by default) sizes the labels and swatches, `mono` lines up figures, and `color` is the labels' color.

## Example

[`examples/gallery`](examples/gallery/main.zig) is a window with a sidebar that picks a view for each kind of control.

- **Grid** is a grid of ten thousand files ([`grid.zig`](examples/gallery/grid.zig)). Sort by a column's title, move, resize and fit columns, show two more columns and scroll them sideways past the names, draw lines between rows and columns, read cut-off names in tooltips, search, narrow the window to hide columns, switch on stripes, show only the five largest files, select one or several files and open them with the mouse or the keyboard, right-click them for a menu to open, select or delete them, drag them out of the window, type a name to jump to it, page through them with a pager, and have rows arrive a page at a time as they scroll into view.
- **Charts** is a system monitor whose readings change four times a second ([`charts.zig`](examples/gallery/charts.zig)): the CPU's load as a trend and a meter, network traffic as stacked bars that say a slot's figures under the pointer, memory as a split with a legend that stacks in a narrow window, the fan as a glowing level, and the heat ramp as a strip. Pause it, switch the ramp, the glow and the fade, and set the meters' segments.

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
