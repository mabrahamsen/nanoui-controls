//! Controls for nanoui that its kit doesn't have, written to the kit's
//! conventions: a call in a frame, styled from `kit.tokens`, with what
//! the user changes (a sort, a selection) and the data drawn kept by the
//! caller. Each uses only nanoui's public API, so it could move into
//! nanoui's kit as is.
//!
//!     const controls = @import("nanoui_controls");
//!
//!     var g = controls.grid(c, &columns, .{ .count = files.len, .sort = &sort });
//!     controls.trend(c, load, .{ .capacity = 60, .label = "CPU load" });

const grid_mod = @import("grid.zig");
pub const grid = grid_mod.grid;
pub const Grid = grid_mod.Grid;
pub const GridColumn = grid_mod.Column;
pub const GridSort = grid_mod.Sort;
pub const GridOptions = grid_mod.Options;
pub const GridRow = grid_mod.Row;
pub const GridTitleStyle = grid_mod.TitleStyle;

const pager_mod = @import("pager.zig");
pub const pager = pager_mod.pager;
pub const PagerOptions = pager_mod.Options;

// The charts: bars, a history, a bar across, a meter and a legend.

const bars_mod = @import("bars.zig");
pub const bars = bars_mod.bars;
pub const Bars = bars_mod.Bars;
pub const BarsOptions = bars_mod.Options;
pub const BarsSlot = bars_mod.Slot;
pub const stack = bars_mod.stack;
/// A part of a bar, for `stack` and `split`: a share and a color.
pub const ChartPart = bars_mod.Part;

const trend_mod = @import("trend.zig");
pub const trend = trend_mod.trend;
pub const TrendOptions = trend_mod.Options;

const split_mod = @import("split.zig");
pub const split = split_mod.split;
pub const SplitOptions = split_mod.Options;

const meter_mod = @import("meter.zig");
pub const meter = meter_mod.meter;
pub const MeterOptions = meter_mod.Options;

const legend_mod = @import("legend.zig");
pub const legend = legend_mod.legend;
pub const Legend = legend_mod.Legend;
pub const LegendOptions = legend_mod.Options;

test {
    _ = grid_mod;
    _ = pager_mod;
    _ = bars_mod;
    _ = trend_mod;
    _ = split_mod;
    _ = meter_mod;
    _ = legend_mod;
}
