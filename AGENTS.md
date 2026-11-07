# AGENTS.md

nanoui-controls is a Zig library of controls for [nanoui](https://github.com/justrach/nanoui) apps that `nanoui.kit` doesn't have. [README.md](README.md) says what it offers and how apps use it; [CONTRIBUTING.md](CONTRIBUTING.md) has the workflow and the conventions for writing a control.

## Commands

Requires Zig 0.17.1 or later.

```sh
zig fmt build.zig build.zig.zon src examples tests   # format
zig build test                                       # run the tests; must pass before every commit
zig build test-snapshots                             # compare drawings with tests/snapshots
zig build test-snapshots -Dupdate-snapshots          # write them anew, when a look changes on purpose
zig build docs                                       # build the API docs into zig-out/docs
zig build example                                    # run the example app
```

## Layout

- `src/controls.zig`: the module root, which re-exports each control.
- `src/<control>.zig`: one file per control (`grid.zig`, `pager.zig`, `sidebar.zig`, `splitter.zig`, `trend.zig`), with its tests at the bottom or in `src/<control>_tests.zig`; the grid's parts are in `src/grid_*.zig`, `focus.zig` takes the keyboard for the grid and the sidebar, and the charts share `chart.zig` (`BarPart`, ramps, value lines, inspecting with the pointer and the keys).
- `tests/snapshots.zig`, `tests/snapshots/*.png`, `tests/fonts`: the snapshot tests, their drawings and the fonts they draw with.
- `examples/gallery/`: the example app, a view for each kind of control picked from a sidebar (`grid.zig`, `charts.zig`).
- `build.zig.zon`: the version and the pinned nanoui release.
- `.github/workflows/ci.yml`: formatting, tests, docs and the example on macOS, Linux and Windows.
- `.github/workflows/release.yml` and `tools/release-notes.sh`: a pushed `vX.Y.Z` tag creates the GitHub release (see CONTRIBUTING.md).

## Rules

- Follow the control conventions in CONTRIBUTING.md: a call in a frame, state kept by the caller, colors from `kit.tokens(c)`, nanoui's public API only, tests with `ui.Tester` in the same file.
- Match the surrounding code's style: doc comments say what a thing is or does, in plain sentences.
- A new or changed control updates the README (its table and section) and `CHANGELOG.md`.
- A change to how a control looks updates its snapshots (`-Dupdate-snapshots`); look at the new PNGs before committing them.
- Branches are named `dev/<issue-number>-<description>`, and commits reference the issue.
