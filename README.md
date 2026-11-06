# nanoui-controls

[![CI](https://github.com/mabrahamsen/nanoui-controls/actions/workflows/ci.yml/badge.svg)](https://github.com/mabrahamsen/nanoui-controls/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Controls for [nanoui](https://github.com/justrach/nanoui) apps that nanoui's own kit (`nanoui.kit`) doesn't have. They follow the kit's conventions: each is a call in a frame, styled from the app's theme, with what the user changes kept by the caller.

| Control | What it does |
|---|---|
| [`grid`](#grid) | Rows of cells under a header of column titles, with the columns lined up, sorting by a clicked title and building only the rows in view. |

## Requirements

| | Version |
|---|---|
| Zig | 0.17.1 or later |
| nanoui | 0.12.0 |

The app must pin the same nanoui release as this library, so both share one copy of nanoui. Otherwise nanoui's types don't match and the build fails.

## Installation

Add the library to the app's `build.zig.zon`:

```sh
zig fetch --save "git+https://github.com/mabrahamsen/nanoui-controls?ref=v0.2.0"
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

- **Columns** are fixed-width (`width`) or share the room the fixed ones leave (`width = null`), by their `flex` and never narrower than their `min_width`. Their contents sit at the `start` or the `end`, where numbers line up.
- **Resizing:** with `widths`, an array the caller keeps (one width a column, starting at 0), dragging the edge between two titles resizes the column on its left if it has a width, else the one on its right.
- **Sorting:** clicking a `sortable` column's title sorts by it, and clicking again reverses it. `g.sorted` says the sort changed this frame, so the caller sorts its rows before building them.
- **Selection:** with `selected`, a click selects a row and it is drawn highlighted. While nothing else has the keyboard, Up and Down move the selection a row, Page Up and Page Down a view, and Home and End to the ends, scrolling it into view. Enter or a double click opens it (`row.opened`). The selection is a row index, so a caller that sorts finds its row again.
- **Several rows:** with `multi` too, one flag a row kept by the caller, Cmd-click (Ctrl-click on Windows and Linux) adds or takes away a row, Shift-click and Shift with the keys select a run of rows, and Cmd+A (Ctrl+A) selects them all.
- **Context menus:** `row.secondary_clicked` is a right-click (or Control-click on the Mac) on a row, for the app's menu. It selects the row, unless the row is already selected, so the menu acts on the selection.
- **Screen readers** hear the rows as rows, read as their cells' text, with the selected ones marked, and the sortable titles as buttons that say which way the rows are sorted.
- **Long lists** cost what a screenful does: only the rows in view are built. The grid fills the room left in its parent, which needs a bounded height.
- **Loading as it scrolls:** `g.first` and `g.last` are the rows in view, so a caller whose rows come from a server fetches those pages, and the ones around them, and draws placeholders until they arrive. `scroll_to` brings a row into view.
- **Empty:** `empty` is text shown under the titles when there are no rows.
- **A set number of rows:** `rows = 5` shows at most five, without scrolling, and takes only their height.
- **Tables to read:** `clickable = false` makes rows that take no clicks, don't light up and show no pointing hand, for a summary or comparison; a screen reader still hears them as rows.
- **Hiding columns:** a column with `min_window_width` hides in narrower windows, and `hidden` hides columns on the caller's say. Build cells with `g.cellAt(i)`, which returns false for a hidden column, so columns keep their numbers.
- **Look:** `striped`, `hover`, `padding`, `rule`, `row_height` and the gaps, `title` (`GridTitleStyle`) for the column titles, and `scale` for apps that zoom their layout with `c.setZoom`. Colors come from the theme unless set.

See the doc comments in [`src/grid.zig`](src/grid.zig), or build the API docs.

## Example

[`examples/grid`](examples/grid/main.zig) is a window with a grid of ten thousand files: sort by a column's title, resize columns, search, narrow the window to hide columns, switch on stripes, show only the five largest files, select one or several files and open them with the mouse or the keyboard, right-click them for a menu to open, select or delete them, and have rows arrive a page at a time as they scroll into view.

```sh
zig build example
```

## Building

```sh
zig build                  # build the example into zig-out/bin
zig build test             # run the tests
zig build test-snapshots   # compare the grid's drawings with tests/snapshots
zig build docs             # build the API docs into zig-out/docs
zig build example          # run the example
```

## Versioning

While the library is 0.x, a minor release may change the API and a patch release won't. Each release is tagged `vX.Y.Z`, and [CHANGELOG.md](CHANGELOG.md) says what it changed.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE). The DejaVu fonts in [`tests/fonts`](tests/fonts), which only the snapshot tests use, have [their own license](tests/fonts/LICENSE).
