# Contributing

## Workflow

1. Open an issue for the change.
2. Branch from `main` as `dev/<issue-number>-<description>`, e.g. `dev/1-initial-import`.
3. Run `zig fmt` and `zig build test` before committing.
4. Open a pull request that references the issue (`Closes #1`). CI must pass on macOS, Linux and Windows.

## Writing a control

Controls follow the conventions of `nanoui.kit`, so any of them could move into nanoui unchanged:

- **One file per control** in `src/`, re-exported from `src/controls.zig` as `nanoui.kit` does: the function under the control's name (`grid`), and its types prefixed with it (`GridColumn`, `GridOptions`).
- **A call in a frame:** the control draws itself each frame and returns what happened, such as a click or a changed sort. It sets `c.changed` when the user changes something.
- **The caller keeps the state:** the control takes a pointer to it, such as a sort or a selection, and doesn't own data.
- **Styled from the theme** through `kit.tokens(c)`, never fixed colors, so it fits light, dark and each app's palette.
- **nanoui's public API only:** `nanoui.ui` and `nanoui.kit`, nothing from the app.
- **Tested next to its code** with `ui.Tester`.
- **Documented:** doc comments on every public declaration, and a row in the README's table of controls.

## Releasing

1. Set `.version` in `build.zig.zon`. While it is 0.x, bump the minor version for a change to the API and the patch version for a fix.
2. Add the release to `CHANGELOG.md`, and update the version in the README's installation command.
3. Tag the commit on `main` as `vX.Y.Z` and push the tag.

## Upgrading nanoui

The library pins the latest nanoui release. Upgrade it with:

```sh
zig fetch --save "git+https://github.com/justrach/nanoui?ref=vX.Y.Z"
```

Update the README's requirements and say so in the changelog: apps must move to the same nanoui release.
