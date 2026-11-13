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
pub const GridLoading = grid_mod.Loading;
pub const GridHeading = grid_mod.Heading;
pub const GridHeadingRow = grid_mod.HeadingRow;
pub const GridTwoLines = grid_mod.TwoLines;
pub const GridRowLook = grid_mod.RowLook;
pub const GridGroups = @import("grid_groups.zig").Groups;
pub const GridGroup = @import("grid_groups.zig").Group;
pub const GridGroupItem = @import("grid_groups.zig").Item;
pub const GridGroupsOptions = @import("grid_groups.zig").Options;

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
/// Where a chart's axis goes, for `bars` and `line`.
pub const ChartAxis = chart_mod.Axis;
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
pub const BarListStyle = bar_list_mod.Style;

const meter_mod = @import("meter.zig");
pub const meter = meter_mod.meter;
pub const MeterOptions = meter_mod.Options;

const gauge_mod = @import("gauge.zig");
pub const gauge = gauge_mod.gauge;
pub const GaugeOptions = gauge_mod.Options;

const stat_mod = @import("stat.zig");
pub const stat = stat_mod.stat;
pub const statButton = stat_mod.statButton;
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
pub const SplitterPane = splitter_mod.Pane;

const legend_mod = @import("legend.zig");
pub const legend = legend_mod.legend;
pub const Legend = legend_mod.Legend;
pub const LegendOptions = legend_mod.Options;
/// A legend's swatch on its own; not `swatches`' `Swatch`.
pub const legendSwatch = legend_mod.swatch;
pub const LegendSwatchShape = legend_mod.SwatchShape;
pub const LegendSwatchOptions = legend_mod.SwatchOptions;

// Forms, pickers and layout: labels beside their controls, colors to
// pick, and cells that wrap.

const form_mod = @import("form.zig");
pub const form = form_mod.form;
pub const Form = form_mod.Form;
pub const FormOptions = form_mod.Options;
pub const FormAlign = form_mod.Align;
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

const surface_mod = @import("surface.zig");
pub const Surface = surface_mod.Surface;
pub const SurfaceGlow = surface_mod.Glow;

const pill_mod = @import("pill.zig");
pub const pill = pill_mod.pill;
pub const pillOpen = pill_mod.pillOpen;
pub const pillLengths = pill_mod.lengths;
pub const PillOptions = pill_mod.Options;
pub const PillLead = pill_mod.Lead;
pub const PillShape = pill_mod.Shape;
pub const PillLengths = pill_mod.Lengths;

const caption_mod = @import("caption.zig");
pub const caption = caption_mod.caption;
pub const captionOpen = caption_mod.captionOpen;
pub const CaptionOptions = caption_mod.Options;
pub const CaptionLine = caption_mod.CaptionLine;

const panel_mod = @import("panel.zig");
pub const panel = panel_mod.panel;
pub const PanelOptions = panel_mod.Options;

const callout_mod = @import("callout.zig");
pub const callout = callout_mod.callout;
pub const calloutOpen = callout_mod.calloutOpen;
pub const CalloutOptions = callout_mod.Options;

const notice_mod = @import("notice.zig");
pub const notice = notice_mod.notice;
pub const noticeOpen = notice_mod.noticeOpen;
pub const NoticeOptions = notice_mod.Options;

pub const Choice = @import("choices.zig").Choice;

const segmented_mod = @import("segmented.zig");
pub const segmented = segmented_mod.segmented;
pub const segmentedOf = segmented_mod.segmentedOf;
pub const SegmentedOptions = segmented_mod.Options;

const tab_strip_mod = @import("tab_strip.zig");
pub const tabStrip = tab_strip_mod.tabStrip;
pub const tabStripOf = tab_strip_mod.tabStripOf;
pub const tabStripOpen = tab_strip_mod.tabStripOpen;
pub const TabStripOptions = tab_strip_mod.Options;
pub const TabStripOpen = tab_strip_mod.TabStripOpen;

const toasts_mod = @import("toasts.zig");
pub const toasts = toasts_mod.toasts;
pub const Toasts = toasts_mod.Toasts;
pub const Toast = toasts_mod.Toast;
pub const ToastShow = toasts_mod.Show;
pub const ToastsOptions = toasts_mod.Options;
pub const ToastHit = toasts_mod.Hit;
pub const ToastCorner = toasts_mod.Corner;

const chips_mod = @import("chips.zig");
pub const chipInput = chips_mod.chipInput;
pub const ChipInputOptions = chips_mod.InputOptions;
pub const ChipInputResult = chips_mod.InputResult;
pub const chip = chips_mod.chip;
pub const ChipOptions = chips_mod.Options;

const icon_tile_mod = @import("icon_tile.zig");
pub const iconTile = icon_tile_mod.iconTile;
pub const iconTileOpen = icon_tile_mod.iconTileOpen;
pub const IconTileOptions = icon_tile_mod.Options;
pub const IconTileOpen = icon_tile_mod.IconTileOpen;

const header_mod = @import("header.zig");
pub const header = header_mod.header;
pub const HeaderOptions = header_mod.Options;

const input_box_mod = @import("input_box.zig");
pub const inputBox = input_box_mod.inputBox;
pub const InputBoxOptions = input_box_mod.Options;
pub const InputBoxResult = input_box_mod.Result;

/// Figures as people read them: sizes, rates, counts, clocks, spans of
/// time and paths (`format.zig`).
pub const format = @import("format.zig");

const focus_mod = @import("focus.zig");
/// When the controls' focus ring shows: whenever a control has the
/// keyboard (the default), or only while the keyboard is in use.
pub const FocusRingShows = focus_mod.RingShows;
pub const setFocusRingShows = focus_mod.setRingShows;

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
    _ = focus_mod;
    _ = surface_mod;
    _ = pill_mod;
    _ = caption_mod;
    _ = panel_mod;
    _ = callout_mod;
    _ = notice_mod;
    _ = format;
    _ = @import("choices.zig");
    _ = segmented_mod;
    _ = tab_strip_mod;
    _ = toasts_mod;
    _ = chips_mod;
    _ = icon_tile_mod;
    _ = header_mod;
    _ = input_box_mod;
    _ = @import("parts.zig");
    _ = @import("buttons.zig");
}
