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

// The charts: bars, a history as bars or lines, a bar across, a donut, a
// list of bars, a meter, a gauge, a stat and a legend.

const chart_mod = @import("chart.zig");
/// A part of a bar, for `Slot.bar`, `breakdown` and `donut`: a share and
/// a color.
pub const BarPart = chart_mod.Part;
/// A line across a chart at a value, with an optional label.
pub const ValueLine = chart_mod.ValueLine;
/// The color at a place (0 to 1) along a ramp of colors, as the charts
/// take it: for the same color elsewhere, such as in a legend.
pub const rampColor = chart_mod.rampColor;

const bars_mod = @import("bars.zig");
pub const bars = bars_mod.bars;
pub const Bars = bars_mod.Bars;
pub const BarsOptions = bars_mod.Options;
pub const BarsSlot = bars_mod.Slot;

const trend_mod = @import("trend.zig");
pub const trend = trend_mod.trend;
pub const TrendOptions = trend_mod.Options;

const line_mod = @import("line.zig");
pub const line = line_mod.line;
pub const Line = line_mod.Line;
pub const LineOptions = line_mod.Options;
pub const LineSeries = line_mod.Series;

const breakdown_mod = @import("breakdown.zig");
pub const breakdown = breakdown_mod.breakdown;
pub const BreakdownOptions = breakdown_mod.Options;

const donut_mod = @import("donut.zig");
pub const donut = donut_mod.donut;
pub const DonutOptions = donut_mod.Options;

const bar_list_mod = @import("bar_list.zig");
pub const barList = bar_list_mod.barList;
pub const BarListItem = bar_list_mod.Item;
pub const BarListOptions = bar_list_mod.Options;

const meter_mod = @import("meter.zig");
pub const meter = meter_mod.meter;
pub const MeterOptions = meter_mod.Options;

const gauge_mod = @import("gauge.zig");
pub const gauge = gauge_mod.gauge;
pub const GaugeOptions = gauge_mod.Options;

const stat_mod = @import("stat.zig");
pub const stat = stat_mod.stat;
pub const StatOptions = stat_mod.Options;

const sidebar_mod = @import("sidebar.zig");
pub const sidebar = sidebar_mod.sidebar;
pub const Sidebar = sidebar_mod.Sidebar;
pub const SidebarOptions = sidebar_mod.Options;
pub const SidebarItem = sidebar_mod.Item;
pub const SidebarGroup = sidebar_mod.Group;

const splitter_mod = @import("splitter.zig");
pub const splitter = splitter_mod.splitter;
pub const SplitterOptions = splitter_mod.Options;

const legend_mod = @import("legend.zig");
pub const legend = legend_mod.legend;
pub const Legend = legend_mod.Legend;
pub const LegendOptions = legend_mod.Options;

// Forms, pickers and layout: labels beside their controls, colors to
// pick, and cells that wrap.

const form_mod = @import("form.zig");
pub const form = form_mod.form;
pub const Form = form_mod.Form;
pub const FormOptions = form_mod.Options;
pub const FormRow = form_mod.Row;
pub const FormRowOptions = form_mod.RowOptions;
pub const FormPropertyOptions = form_mod.PropertyOptions;
pub const FormHeadingOptions = form_mod.HeadingOptions;
pub const FormLinkOptions = form_mod.LinkOptions;

const swatches_mod = @import("swatches.zig");
pub const swatches = swatches_mod.swatches;
pub const Swatch = swatches_mod.Swatch;
pub const SwatchesOptions = swatches_mod.Options;

const flow_mod = @import("flow.zig");
pub const flow = flow_mod.flow;
pub const Flow = flow_mod.Flow;
pub const FlowOptions = flow_mod.Options;

test {
    _ = grid_mod;
    _ = pager_mod;
    _ = chart_mod;
    _ = bars_mod;
    _ = trend_mod;
    _ = line_mod;
    _ = breakdown_mod;
    _ = donut_mod;
    _ = bar_list_mod;
    _ = meter_mod;
    _ = stat_mod;
    _ = legend_mod;
    _ = sidebar_mod;
    _ = splitter_mod;
    _ = form_mod;
    _ = swatches_mod;
    _ = flow_mod;
    _ = gauge_mod;
    _ = @import("focus.zig");
}
