///|
/// The Monaco `ViewLayout` role: combines the scroll truth (`Scrollable`)
/// with the line layout (`LinesLayout`) and derives the render viewport
/// from them via `get_lines_viewport_data`. Pure model state — input
/// capture and DOM application stay backend-side.
///
/// Like Monaco, the entire view layer is 1-based, so `ViewLayout` and the
/// `LinesLayout` it holds share one coordinate space — line-number arguments
/// pass straight through with no translation. View-zone whitespace carries
/// Monaco's `afterLineNumber` directly. The `LinesLayout` held here is exactly
/// the type the conformance suite validates.
pub struct ViewLayout {
  scrollable : EditorScrollable
  priv lines : LinesLayout
  priv mut line_height : Int
  priv mut line_count : Int
  priv mut max_line_width : Double
  priv mut is_viewport_wrapping : Bool
  priv vertical_scrollbar_width : Double
  priv horizontal_scrollbar_height : Double
}

///|
pub struct Viewport {
  top : Double
  left : Double
  width : Double
  height : Double
} derive(Eq, Debug)

///|
pub struct SavedScrollState {
  scroll_top : Double
  scroll_top_without_view_zones : Double
  scroll_left : Double
} derive(Eq, Debug)

///|
let smooth_scrolling_time : Double = 125.0

///|
/// Creates a view layout with a fixed line height and optional line count.
pub fn ViewLayout::ViewLayout(
  line_height~ : Int,
  line_count? : Int = 0,
  smooth_scrolling? : Bool = false,
  is_viewport_wrapping? : Bool = false,
  vertical_scrollbar_width? : Double = 14.0,
  horizontal_scrollbar_height? : Double = 12.0,
  schedule_at_next_animation_frame? : (() -> Unit) -> @base_common.Disposable = no_animation_scheduler,
  now? : () -> Double = zero_clock,
) -> ViewLayout {
  let line_count = line_count.max(0)
  let layout : ViewLayout = {
    // `forceIntegerValues: true` (viewLayout.ts): the editor's scroll truth is
    // whole pixels, so fractional trackpad deltas never render at a subpixel
    // transform offset.
    scrollable: EditorScrollable(
      if smooth_scrolling {
        smooth_scrolling_time
      } else {
        0.0
      },
      schedule_at_next_animation_frame,
      now,
    ),
    lines: LinesLayout(line_count, line_height, 0, 0),
    line_height,
    line_count,
    max_line_width: 0.0,
    is_viewport_wrapping,
    vertical_scrollbar_width,
    horizontal_scrollbar_height,
  }
  layout.update_height() |> ignore
  layout
}

///|
/// Replaces the document extent (line count) and re-derives the scroll
/// dimensions; the position re-clamps when the document shrank.
pub fn ViewLayout::set_line_count(
  self : ViewLayout,
  line_count : Int,
) -> ScrollChange? {
  self.line_count = line_count.max(0)
  // `LinesLayout.onFlushed` retains source-owned whitespaces. Model-scoped
  // ViewZones are cleared by their browser owner on an actual model swap.
  self.lines.on_flushed(self.line_count)
  self.update_height()
}

///|
/// The document was replaced — Monaco's `ViewLayout.onFlushed(lineCount)`:
/// `this._linesLayout.onFlushed(lineCount)`. Whitespaces (view zones)
/// survive a flush like the source's; the browser ViewZones owner recomputes
/// mutable mapping facts on its corresponding view-model event. The scroll
/// dimensions re-derive in `on_height_maybe_changed`, exactly the source split.
pub fn ViewLayout::on_flushed(self : ViewLayout, line_count : Int) -> Unit {
  self.line_count = line_count.max(0)
  self.lines.on_flushed(self.line_count)
}

///|
/// Re-derives the scroll dimensions after the content height may have
/// changed — Monaco's `ViewLayout.onHeightMaybeChanged` (`_updateHeight`);
/// a shrunken document clamps the scroll position here.
pub fn ViewLayout::on_height_maybe_changed(self : ViewLayout) -> ScrollChange? {
  self.update_height()
}

///|
/// Runs one source-shaped incremental whitespace transaction. A changed batch
/// updates the vertical extent before returning; empty batches return `false`.
/// The callback effect is polymorphic, so ordinary callers remain non-raising
/// while a raised callback still receives LinesLayout's `finally` commit.
pub fn ViewLayout::change_whitespace(
  self : ViewLayout,
  callback : (WhitespaceChangeAccessor) -> Unit raise?,
) -> Bool raise? {
  let had_a_change = self.lines.change_whitespace(callback)
  if had_a_change {
    self.on_height_maybe_changed() |> ignore
  }
  had_a_change
}

///|
/// The uniform line height in pixels (`fontInfo.lineHeight`).
pub fn ViewLayout::line_height(self : ViewLayout) -> Int {
  self.line_height
}

///|
/// Applies a changed line height and re-derives the scroll dimensions —
/// Monaco's `ViewLayout.onConfigurationChanged` `lineHeight` branch
/// (`this._linesLayout.setLineHeight(...)`).
pub fn ViewLayout::set_line_height(
  self : ViewLayout,
  line_height : Int,
) -> ScrollChange? {
  if line_height == self.line_height {
    return None
  }
  self.line_height = line_height
  self.lines.set_default_line_height(line_height)
  self.update_height()
}

///|
/// Sets the viewport box measured by the backend.
pub fn ViewLayout::set_viewport_size(
  self : ViewLayout,
  width~ : Double,
  height~ : Double,
) -> ScrollChange? {
  let dimensions = self.scrollable.editor_dimensions()
  self.scrollable.set_editor_dimensions(
    EditorScrollDimensions(
      width,
      dimensions.content_width,
      height,
      self.compute_content_height(width, height, dimensions.content_width),
    ),
  )
}

///|
/// Updates the retained viewport-wrapping fact consumed by content-width
/// computation. The local configuration path is split across typed setters;
/// Monaco reads the same fact from `EditorOption.wrappingInfo`.
pub fn ViewLayout::set_is_viewport_wrapping(
  self : ViewLayout,
  is_viewport_wrapping : Bool,
) -> ScrollChange? {
  if self.is_viewport_wrapping == is_viewport_wrapping {
    return None
  }
  self.is_viewport_wrapping = is_viewport_wrapping
  self.update_content_width()
}

///|
/// Monaco `ViewLayout.setMaxLineWidth`: retain the measured widest rendered
/// line without clamping, update content width, then recompute height because
/// horizontal-scrollbar visibility contributes to the bottom extent.
pub fn ViewLayout::set_max_line_width(
  self : ViewLayout,
  max_line_width : Double,
) -> ScrollChange? {
  self.max_line_width = max_line_width
  self.update_content_width()
}

///|
/// Compatibility spelling for callers that predate ViewLayout's ownership of
/// the measured maximum. The value is a max-line-width input, not a final
/// content width; new ViewLines wiring should call `set_max_line_width`.
pub fn ViewLayout::set_content_width(
  self : ViewLayout,
  max_line_width : Double,
) -> ScrollChange? {
  self.set_max_line_width(max_line_width)
}

///|
/// Current number of lines.
pub fn ViewLayout::line_count(self : ViewLayout) -> Int {
  self.line_count
}

///|
/// Total retained content height, including view zones and the fixed product
/// horizontal scrollbar when horizontal overflow is present.
pub fn ViewLayout::get_content_height(self : ViewLayout) -> Double {
  self.scrollable.editor_dimensions().content_height
}

///|
/// The derived horizontal content extent (measured maximum plus the applicable
/// fixed layout additions), Monaco's `ViewLayout.getContentWidth` /
/// scroll-dimensions `contentWidth`. Read by `CodeEditorWidget.getContentWidth`.
pub fn ViewLayout::get_content_width(self : ViewLayout) -> Double {
  self.scrollable.editor_dimensions().content_width
}

///|
/// Scrollable content width = `max(viewport width, content width)`, Monaco's
/// `ViewLayout.getScrollWidth`. Backed by `sync_dimensions`' `scroll_width`.
pub fn ViewLayout::get_scroll_width(self : ViewLayout) -> Double {
  self.scrollable.dimensions().scroll_width
}

///|
/// Scrollable content height = `max(viewport height, content height)`, Monaco's
/// `ViewLayout.getScrollHeight`.
pub fn ViewLayout::get_scroll_height(self : ViewLayout) -> Double {
  self.scrollable.dimensions().scroll_height
}

///|
/// Current horizontal scroll offset, Monaco's `ViewLayout.getCurrentScrollLeft`.
pub fn ViewLayout::get_current_scroll_left(self : ViewLayout) -> Double {
  self.scrollable.position().scroll_left
}

///|
/// Current vertical scroll offset, Monaco's `ViewLayout.getCurrentScrollTop`.
pub fn ViewLayout::get_current_scroll_top(self : ViewLayout) -> Double {
  self.scrollable.position().scroll_top
}

///|
/// Content-space top of a 1-based view line, Monaco's
/// `ViewLayout.getVerticalOffsetForLineNumber` (delegates straight to
/// `LinesLayout`). `include_view_zones` controls whether the whitespace
/// immediately above the line counts toward the offset.
pub fn ViewLayout::get_vertical_offset_for_line_number(
  self : ViewLayout,
  line_number : Int,
  include_view_zones? : Bool = false,
) -> Double {
  self.lines.get_vertical_offset_for_line_number(
    line_number,
    include_view_zones~,
  )
}

///|
/// Content-space bottom of a 1-based view line (its top plus its height),
/// Monaco's `ViewLayout.getVerticalOffsetAfterLineNumber`.
pub fn ViewLayout::get_vertical_offset_after_line_number(
  self : ViewLayout,
  line_number : Int,
  include_view_zones? : Bool = false,
) -> Double {
  self.lines.get_vertical_offset_after_line_number(
    line_number,
    include_view_zones~,
  )
}

///|
/// The (uniform) height of a 1-based view line, Monaco's
/// `ViewLayout.getLineHeightForLineNumber`.
pub fn ViewLayout::get_line_height_for_line_number(
  self : ViewLayout,
  line_number : Int,
) -> Int {
  self.lines.get_line_height_for_line_number(line_number)
}

///|
/// All lines (and their relative vertical offsets) inside the current
/// viewport, Monaco's `ViewLayout.getLinesViewportData` (delegates to
/// `LinesLayout` with the viewport `[scrollTop, scrollTop + height]`).
pub fn ViewLayout::get_lines_viewport_data(
  self : ViewLayout,
) -> PartialViewLinesViewportData {
  let visible_box = self.get_current_viewport()
  self.lines.get_lines_viewport_data(
    visible_box.top,
    visible_box.top + visible_box.height,
  )
}

///|
/// Monaco `getLinesViewportDataAtScrollTop`: minimally clamps an explicit
/// scroll top against the current scroll dimensions, then derives the same
/// line viewport without mutating scroll state.
pub fn ViewLayout::get_lines_viewport_data_at_scroll_top(
  self : ViewLayout,
  scroll_top : Double,
) -> PartialViewLinesViewportData {
  let dimensions = self.scrollable.dimensions()
  let mut scroll_top = scroll_top
  if scroll_top + dimensions.height > dimensions.scroll_height {
    scroll_top = dimensions.scroll_height - dimensions.height
  }
  if scroll_top < 0.0 {
    scroll_top = 0.0
  }
  self.lines.get_lines_viewport_data(scroll_top, scroll_top + dimensions.height)
}

///|
/// The 1-based view line range fully on screen at the current scroll, Monaco's
/// `ViewLayout.getLinesViewportData().completelyVisible{Start,End}LineNumber`.
/// Returns `(1, 1)` for an empty document so callers never index a missing
/// line.
pub fn ViewLayout::completely_visible_line_range(
  self : ViewLayout,
) -> (Int, Int) {
  if self.line_count <= 0 {
    return (1, 1)
  }
  let data = self.get_lines_viewport_data()
  (
    data.completely_visible_start_line_number,
    data.completely_visible_end_line_number,
  )
}

///|
/// The top of a 1-based `line` in content space. Line numbers clamp to the
/// document so callers can probe one-past-the-end (`line_count + 1`) for a
/// bottom edge.
pub fn ViewLayout::vertical_offset_for_line(
  self : ViewLayout,
  line : Int,
) -> Double {
  let line = line.clamp(min=1, max=self.line_count + 1)
  self.lines.get_vertical_offset_for_line_number(line)
}

///|
/// The 1-based line whose band contains a content-space vertical offset,
/// clamped to the document (`1` for an empty one).
pub fn ViewLayout::line_at_vertical_offset(
  self : ViewLayout,
  offset : Double,
) -> Int {
  if self.line_count <= 0 {
    return 1
  }
  self.lines.get_line_number_at_or_after_vertical_offset(offset)
}

///|
/// Monaco `IViewLayout.getWhitespaceAtVerticalOffset` (viewLayout.ts): the
/// whitespace (view zone) whose band contains a content-space vertical
/// offset, forwarded to `LinesLayout`.
pub fn ViewLayout::get_whitespace_at_vertical_offset(
  self : ViewLayout,
  vertical_offset : Double,
) -> ViewWhitespaceViewportData? {
  self.lines.get_whitespace_at_vertical_offset(vertical_offset)
}

///|
/// All ID-bearing whitespaces in the current viewport. The result uses
/// content-space vertical offsets and the source half-open viewport end.
pub fn ViewLayout::get_whitespace_viewport_data(
  self : ViewLayout,
) -> Array[ViewWhitespaceViewportData] {
  let visible_box = self.get_current_viewport()
  self.lines.get_whitespace_viewport_data(
    visible_box.top,
    visible_box.top + visible_box.height,
  )
}

///|
/// A shallow array snapshot of every whitespace. The returned array is
/// independent while its `EditorWhitespace` elements retain source identity.
pub fn ViewLayout::get_whitespaces(
  self : ViewLayout,
) -> Array[EditorWhitespace] {
  self.lines.get_whitespaces()
}

///|
/// Top offset of 1-based `line` relative to Monaco's `bigNumbersDelta` for the
/// rendered window (`linesLayout.ts:738-750`). Below 500000px this is the
/// absolute content offset; above it the large aligned delta is subtracted.
pub fn ViewLayout::relative_vertical_offset_for_line(
  self : ViewLayout,
  window : LineWindow,
  line : Int,
) -> Double {
  let start_top = self.vertical_offset_for_line(window.start)
  javascript_to_int32(start_top).to_double() +
  (self.vertical_offset_for_line(line) - start_top) -
  self.big_numbers_delta_for_window(window).to_double()
}

///|
/// Monaco `LinesLayout.getLinesViewportData`'s large-number rail origin. The
/// second alignment keeps the delta divisible by the default line height.
pub fn ViewLayout::big_numbers_delta_for_window(
  self : ViewLayout,
  window : LineWindow,
) -> Int {
  let start_vertical_offset = javascript_to_int32(
    self.vertical_offset_for_line(window.start),
  )
  let step_size = 500000
  if start_vertical_offset < step_size || self.line_height <= 0 {
    return 0
  }
  let delta = start_vertical_offset / step_size * step_size
  delta / self.line_height * self.line_height
}

///|
/// Sets the synthetic scroll position, preserving horizontal position unless
/// `scroll_left` is supplied.
pub fn ViewLayout::scroll_to(
  self : ViewLayout,
  scroll_top~ : Double,
  scroll_left? : Double,
) -> ScrollChange? {
  let position = self.scrollable.position()
  let scroll_left = scroll_left.unwrap_or(position.scroll_left)
  self.scrollable.set_position_now({
    scroll_left: Some(scroll_left),
    scroll_top: Some(scroll_top),
  })
}

///|
/// Applies a relative synthetic scroll delta.
pub fn ViewLayout::scroll_by(
  self : ViewLayout,
  delta_left? : Double = 0.0,
  delta_top? : Double = 0.0,
) -> ScrollChange? {
  self.scrollable.scroll_by(delta_left~, delta_top~)
}

///|
/// Current synthetic scroll position.
pub fn ViewLayout::position(self : ViewLayout) -> ScrollPosition {
  self.scrollable.position()
}

///|
/// Current viewport and content dimensions.
pub fn ViewLayout::dimensions(self : ViewLayout) -> ScrollDimensions {
  self.scrollable.dimensions()
}

///|
pub fn ViewLayout::get_scrollable(self : ViewLayout) -> Scrollable {
  self.scrollable.get_scrollable()
}

///|
pub fn ViewLayout::on_did_scroll(
  self : ViewLayout,
  listener : (ScrollChange) -> Unit,
) -> @base_common.Disposable {
  self.scrollable.on_did_scroll(listener)
}

///|
pub fn ViewLayout::on_did_content_size_change(
  self : ViewLayout,
  listener : (ContentSizeChange) -> Unit,
) -> @base_common.Disposable {
  self.scrollable.on_did_content_size_change(listener)
}

///|
pub fn ViewLayout::set_smooth_scrolling(
  self : ViewLayout,
  enabled : Bool,
) -> Unit {
  self.scrollable.set_smooth_scroll_duration(
    if enabled {
      smooth_scrolling_time
    } else {
      0.0
    },
  )
}

///|
pub fn ViewLayout::validate_scroll_position(
  self : ViewLayout,
  position : ScrollPositionUpdate,
) -> ScrollPosition {
  self.scrollable.validate_scroll_position(position)
}

///|
pub fn ViewLayout::future_position(self : ViewLayout) -> ScrollPosition {
  self.scrollable.future_position()
}

///|
pub fn ViewLayout::get_current_viewport(self : ViewLayout) -> Viewport {
  let dimensions = self.scrollable.dimensions()
  let position = self.scrollable.position()
  {
    top: truncate_double(position.scroll_top),
    left: truncate_double(position.scroll_left),
    width: truncate_double(dimensions.width),
    height: truncate_double(dimensions.height),
  }
}

///|
pub fn ViewLayout::get_future_viewport(self : ViewLayout) -> Viewport {
  let dimensions = self.scrollable.dimensions()
  let position = self.scrollable.future_position()
  {
    top: truncate_double(position.scroll_top),
    left: truncate_double(position.scroll_left),
    width: truncate_double(dimensions.width),
    height: truncate_double(dimensions.height),
  }
}

///|
pub fn ViewLayout::save_state(self : ViewLayout) -> SavedScrollState {
  let position = self.scrollable.future_position()
  let first_line = self.lines.get_line_number_at_or_after_vertical_offset(
    position.scroll_top,
  )
  let whitespace_above = self.lines.get_whitespace_accumulated_height_before_line_number(
    first_line,
  )
  {
    scroll_top: position.scroll_top,
    scroll_top_without_view_zones: position.scroll_top - whitespace_above,
    scroll_left: position.scroll_left,
  }
}

///|
pub fn ViewLayout::scroll_to_smooth(
  self : ViewLayout,
  scroll_top~ : Double,
  scroll_left? : Double,
) -> Unit {
  self.scrollable.set_position_smooth({
    scroll_left,
    scroll_top: Some(scroll_top),
  })
}

///|
pub fn ViewLayout::has_pending_scroll_animation(self : ViewLayout) -> Bool {
  self.scrollable.has_pending_scroll_animation()
}

///|
pub fn ViewLayout::delta_scroll_now(
  self : ViewLayout,
  delta_scroll_left : Double,
  delta_scroll_top : Double,
) -> Unit {
  let position = self.scrollable.position()
  self.scrollable.set_position_now({
    scroll_left: Some(position.scroll_left + delta_scroll_left),
    scroll_top: Some(position.scroll_top + delta_scroll_top),
  })
  |> ignore
}

///|
pub fn ViewLayout::dispose(self : ViewLayout) -> Unit {
  self.scrollable.dispose()
}

///|
/// The half-open window of view lines intersecting the current viewport —
/// the `[startLineNumber, endLineNumber]` band of Monaco's
/// `ViewLayout.getLinesViewportData()`, partially visible edge lines
/// included. Recomputed every frame; the view renders exactly these lines.
pub fn ViewLayout::visible_window(self : ViewLayout) -> LineWindow {
  if self.line_count <= 0 {
    return { start: 1, end: 1 }
  }
  let data = self.get_lines_viewport_data()
  { start: data.start_line_number, end: data.end_line_number + 1 }
}

///|
/// The content-space top of a window's first line: the translation the
/// view applies to the lines layer (`window_origin - scroll_top`).
pub fn ViewLayout::window_origin(
  self : ViewLayout,
  window : LineWindow,
) -> Double {
  self.vertical_offset_for_line(window.start)
}

///|
fn ViewLayout::horizontal_scrollbar_height(
  self : ViewLayout,
  width : Double,
  content_width : Double,
) -> Double {
  // Product-fixed ScrollbarVisibility.Auto: the approved Hidden option axis
  // remains deferred and equality stays on the no-overflow path.
  if width >= content_width {
    0.0
  } else {
    self.horizontal_scrollbar_height
  }
}

///|
fn ViewLayout::compute_content_height(
  self : ViewLayout,
  width : Double,
  _height : Double,
  content_width : Double,
) -> Double {
  // Product-fixed `scrollBeyondLastLine=false` and
  // `ignoreHorizontalScrollbarInContentHeight=false` select this source arm.
  self.lines.get_lines_total_height() +
  self.horizontal_scrollbar_height(width, content_width)
}

///|
fn ViewLayout::update_height(self : ViewLayout) -> ScrollChange? {
  let dimensions = self.scrollable.editor_dimensions()
  self.scrollable.set_editor_dimensions(
    EditorScrollDimensions(
      dimensions.width,
      dimensions.content_width,
      dimensions.height,
      self.compute_content_height(
        dimensions.width,
        dimensions.height,
        dimensions.content_width,
      ),
    ),
  )
}

///|
fn ViewLayout::compute_content_width(self : ViewLayout) -> Double {
  if self.is_viewport_wrapping {
    // The source's overflow threshold only selects a right-side minimap
    // adjustment. Viewer has no minimap axis, so both applicable outcomes are
    // the measured maximum itself.
    return self.max_line_width
  }
  // `.view-line-content` measurement already includes the product-fixed 16px
  // right padding. Do not invent a scrollBeyondLastColumn option or add that
  // padding twice. The vertical scrollbar and whitespace minimum remain the
  // two source-owned extent candidates available in this product.
  (self.max_line_width + self.vertical_scrollbar_width).max(
    self.lines.get_whitespace_min_width().to_double(),
  )
}

///|
fn ViewLayout::update_content_width(self : ViewLayout) -> ScrollChange? {
  let dimensions = self.scrollable.editor_dimensions()
  let width_change = self.scrollable.set_editor_dimensions(
    EditorScrollDimensions(
      dimensions.width,
      self.compute_content_width(),
      dimensions.height,
      dimensions.content_height,
    ),
  )
  // Preserve source ordering: publish the width first, then recompute height.
  let height_change = self.update_height()
  match (width_change, height_change) {
    (Some(width_change), Some(height_change)) =>
      Some(merge_scroll_changes(width_change, height_change))
    (Some(change), None) | (None, Some(change)) => Some(change)
    (None, None) => None
  }
}

///|
/// `update_content_width` intentionally performs two source-ordered dimension
/// writes so content-size listeners observe width before scrollbar-dependent
/// height. Its compatibility return value still describes the complete
/// transition, rather than dropping the flags from the first emitted event.
fn merge_scroll_changes(
  first : ScrollChange,
  second : ScrollChange,
) -> ScrollChange {
  let width_changed = first.old_width != second.width
  let scroll_width_changed = first.old_scroll_width != second.scroll_width
  let scroll_left_changed = first.old_scroll_left != second.scroll_left
  let height_changed = first.old_height != second.height
  let scroll_height_changed = first.old_scroll_height != second.scroll_height
  let scroll_top_changed = first.old_scroll_top != second.scroll_top
  {
    position: second.position,
    delta_left: second.scroll_left - first.old_scroll_left,
    delta_top: second.scroll_top - first.old_scroll_top,
    left_changed: scroll_left_changed,
    top_changed: scroll_top_changed,
    dimensions_changed: width_changed ||
    scroll_width_changed ||
    height_changed ||
    scroll_height_changed,
    in_smooth_scrolling: first.in_smooth_scrolling || second.in_smooth_scrolling,
    old_width: first.old_width,
    old_scroll_width: first.old_scroll_width,
    old_scroll_left: first.old_scroll_left,
    width: second.width,
    scroll_width: second.scroll_width,
    scroll_left: second.scroll_left,
    old_height: first.old_height,
    old_scroll_height: first.old_scroll_height,
    old_scroll_top: first.old_scroll_top,
    height: second.height,
    scroll_height: second.scroll_height,
    scroll_top: second.scroll_top,
    width_changed,
    scroll_width_changed,
    scroll_left_changed,
    height_changed,
    scroll_height_changed,
    scroll_top_changed,
  }
}

///|
/// Monaco `IViewLayout.isAfterLines`: whether a content-space vertical offset
/// sits below every line (and every trailing view zone), forwarded to
/// `LinesLayout`.
pub fn ViewLayout::is_after_lines(
  self : ViewLayout,
  vertical_offset : Double,
) -> Bool {
  self.lines.is_after_lines(vertical_offset)
}

///|
/// Monaco `IViewLayout.isInTopPadding`, forwarded to `LinesLayout` (the
/// viewer carries no padding options, so its paddings are 0).
pub fn ViewLayout::is_in_top_padding(
  self : ViewLayout,
  vertical_offset : Double,
) -> Bool {
  self.lines.is_in_top_padding(vertical_offset)
}

///|
/// Monaco `IViewLayout.isInBottomPadding`, forwarded to `LinesLayout`.
pub fn ViewLayout::is_in_bottom_padding(
  self : ViewLayout,
  vertical_offset : Double,
) -> Bool {
  self.lines.is_in_bottom_padding(vertical_offset)
}

///|
pub extend SavedScrollState with Debug::{to_repr}

///|
pub extend SavedScrollState with Eq::{equal, not_equal}

///|
pub extend Viewport with Debug::{to_repr}

///|
pub extend Viewport with Eq::{equal, not_equal}
