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
zig fetch --save "git+https://github.com/mabrahamsen/nanoui-controls?ref=v0.1.0"
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

// In the frame:
var g = controls.grid(c, &columns, .{ .count = files.len, .sort = &sort });
if (g.sorted) sortFiles(files, sort);
while (g.next()) |row| {
    g.cell();
    ui.text(c, files[row.index].name, .{});
    g.cell();
    ui.text(c, files[row.index].size, .{});
}
g.end();
```

- **Columns** are fixed-width (`width`) or take the room the fixed ones leave (`width = null`, on one column). Their contents sit at the `start` or the `end`, where numbers line up.
- **Sorting:** clicking a `sortable` column's title sorts by it, and clicking again reverses it. `g.sorted` says the sort changed this frame, so the caller sorts its rows before building them.
- **Long lists** cost what a screenful does: only the rows in view are built. The grid fills the room left in its parent, which needs a bounded height.
- **A set number of rows:** `rows = 5` shows at most five, without scrolling, and takes only their height.
- **Hiding columns:** a column with `min_window_width` hides in narrower windows, and `hidden` hides columns on the caller's say. Build cells with `g.cellAt(i)`, which returns false for a hidden column, so columns keep their numbers.
- **Look:** `striped`, `hover`, `padding`, `rule`, `row_height` and the gaps, `title` (`GridTitleStyle`) for the column titles, and `scale` for apps that zoom their layout with `c.setZoom`. Colors come from the theme unless set.

See the doc comments in [`src/grid.zig`](src/grid.zig), or build the API docs.

## Example

[`examples/grid`](examples/grid/main.zig) is a window with a grid of ten thousand files: sort by a column's title, narrow the window to hide columns, switch on stripes, or show only the five largest files.

```sh
zig build example
```

## Building

```sh
zig build           # build the example into zig-out/bin
zig build test      # run the tests
zig build docs      # build the API docs into zig-out/docs
zig build example   # run the example
```

## Versioning

While the library is 0.x, a minor release may change the API and a patch release won't. Each release is tagged `vX.Y.Z`, and [CHANGELOG.md](CHANGELOG.md) says what it changed.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
