//! Controls for nanoui that its kit doesn't have, written to the kit's
//! conventions: a call in a frame, styled from `kit.tokens`, with what
//! the user changes (a sort, a selection) kept by the caller. Each uses
//! only nanoui's public API, so it could move into nanoui's kit as is.
//!
//!     const controls = @import("nanoui_controls");
//!
//!     var g = controls.grid(c, &columns, .{ .count = files.len, .sort = &sort });

const grid_mod = @import("grid.zig");
pub const grid = grid_mod.grid;
pub const Grid = grid_mod.Grid;
pub const GridColumn = grid_mod.Column;
pub const GridSort = grid_mod.Sort;
pub const GridOptions = grid_mod.Options;
pub const GridRow = grid_mod.Row;
pub const GridTitleStyle = grid_mod.TitleStyle;

test {
    _ = grid_mod;
}
