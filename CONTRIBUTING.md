# Contributing

## Workflow

1. Open an issue for the change.
2. Branch from `main` as `dev/<issue-number>-<description>`, e.g. `dev/1-initial-import`.
3. Run `zig fmt` and `zig build test` before committing.
4. Open a pull request that references the issue (`Closes #1`). CI must pass on macOS, Linux and Windows.
5. Pull requests are squash-merged: the pull request's title and description become the commit on `main`, and the branch is deleted.

## Writing a control

Controls follow the conventions of `nanoui.kit`, so any of them could move into nanoui unchanged:

- **One file per control** in `src/`, re-exported from `src/controls.zig` as `nanoui.kit` does: the function under the control's name (`grid`), and its types prefixed with it (`GridColumn`, `GridOptions`).
- **A call in a frame:** the control draws itself each frame and returns what happened, such as a click or a changed sort. It sets `c.changed` when the user changes something.
- **The caller keeps the state:** the control takes a pointer to it, such as a sort or a selection, and doesn't own data.
- **Styled from the theme** through `kit.tokens(c)`, never fixed colors, so it fits light, dark and each app's palette.
- **nanoui's public API only:** `nanoui.ui` and `nanoui.kit`, nothing from the app.
- **Tested next to its code** with `ui.Tester`, in `src/<control>_tests.zig` when the tests would make the file long. Files stay under 600 lines.
- **Drawn in a snapshot test** (`tests/snapshots.zig`), in light and dark, so a change to how it looks shows up in review.
- **Documented:** doc comments on every public declaration, and a row in the README's table of controls.

### Naming

- **nanoui's names where it has one:** `count`, `row_height`, `gap` and `scroll_to` as `ui.list` has them, `scroll_x` as `ui.Style`, `secondary_clicked` as `ui.Interaction`, `size` as the kit's controls, `min` and `max` as `ui.slider`, `label` for what a screen reader calls a control and `value_text` for what it says it shows (as the web's `aria-valuetext`), `width` and `height` as a `ui.Length` where a box takes one, and `start`, `center` and `end` for where things sit.
- **What happened this frame in the past tense:** `clicked`, `opened`, `sorted`, `drag_started`.
- **Null switches a feature off:** an option the caller keeps (`sort`, `selected`, `widths`) is a pointer or a slice that is null when the feature isn't wanted, so a plain control needs only what it can't do without.
- **Say what it is:** a look is `*_style` (`title_style`), a limit `max_*` (`max_rows`), a line `*_line` or `*_lines` (`header_line`, `row_lines`); a method that answers a question reads as one (`isShown`).
- **Fields callers read come first** in a control's struct; its own follow, under a comment saying so.

## Snapshot tests

`zig build test-snapshots` draws the controls with nanoui's own text and CPU renderer, in the DejaVu fonts in `tests/fonts`, and compares the drawings with the PNGs in `tests/snapshots`. A drawing that differs is written to `zig-out/snapshots`, and CI keeps those as an artifact of the run.

When a control is meant to look different, write the snapshots anew and commit them with the change, so the review shows the new drawings:

```sh
zig build test-snapshots -Dupdate-snapshots
```

## Releasing

1. In a pull request, set `.version` in `build.zig.zon`. While it is 0.x, bump the minor version for a change to the API and the patch version for a fix.
2. In the same pull request, rename the changelog's "Unreleased" section to the version, and update the version in the README's installation command.
3. After it is merged, tag `main` and push the tag:

   ```sh
   git tag -a vX.Y.Z -m "nanoui-controls X.Y.Z" && git push origin vX.Y.Z
   ```

The release workflow then checks that the tag is the version in `build.zig.zon` and is on `main`, runs the tests, and creates the GitHub release with the version's changelog section as its notes. A tag with a hyphen (`v0.2.0-rc.1`) makes a prerelease, with notes from its own section or else from `0.2.0`'s. Check the notes before tagging with `tools/release-notes.sh vX.Y.Z`.

## Upgrading nanoui

The library pins the latest nanoui release. Upgrade it with:

```sh
zig fetch --save "git+https://github.com/justrach/nanoui?ref=vX.Y.Z"
```

Update the README's requirements and say so in the changelog: apps must move to the same nanoui release.
