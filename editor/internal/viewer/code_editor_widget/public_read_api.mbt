///|
/// Read-only state-query surface, Monaco's `CodeEditorWidget` getter cluster
/// (`vs/editor/browser/widget/codeEditor/codeEditorWidget.ts`). These answer
/// "where is the viewport / where does this model position land / what is
/// selected", complementing the write-heavy `reveal_*` / `scroll_*` / `set_model`
/// surface. Each getter delegates to the backing piece the viewer already owns
/// (`ViewModel` / `ViewLayout` / `View`) and copies Monaco's no-model sentinel
/// (`''` / `[]` / `null` / `-1` / raw-column) verbatim — callers branch on them.
///
/// Public API is *model*-coordinate in/out; every vertical-offset and
/// visible-range path converts at the boundary through the `CoordinatesConverter`
/// before touching `ViewLayout`, never reaching layout with a model line number.

///|
/// Monaco's `Number.MAX_SAFE_INTEGER` column for `getBottomForLineNumber`: a
/// column past any line end, clamped down to the line's max column by
/// `validate_position`.
let max_safe_column : Int32 = 2147483647

///|
/// Full document text, Monaco's `CodeEditorWidget.getValue` (`cew:472`). No
/// model → `''`. The `{preserveBOM, lineEnding}` option is dropped: the snapshot
/// stores fixed-LF text, retains U+FEFF as ordinary content, and exposes no
/// separate BOM metadata or EOL preference/preservation switch.
pub fn CodeEditorWidget::get_value(self : CodeEditorWidget) -> String {
  match self.get_model() {
    None => ""
    Some(model) => model.get_value()
  }
}

///|
/// Model ranges currently fully visible on screen, Monaco's
/// `CodeEditorWidget.getVisibleRanges` (`cew:563`) → `viewModel.getVisibleRanges`
/// (`vmi:646`): the completely-visible *view* range (from the layout) converted
/// to model ranges, split around any hidden region. No model → `[]`.
pub fn CodeEditorWidget::get_visible_ranges(
  self : CodeEditorWidget,
) -> Array[@base_common.Range] {
  self.active_presentation_visible_ranges()
}

///|
fn CodeEditorWidget::active_presentation_visible_ranges(
  self : CodeEditorWidget,
) -> Array[@base_common.Range] {
  if self.is_code_presentation() {
    self.code_visible_ranges()
  } else {
    []
  }
}

///|
fn CodeEditorWidget::code_visible_ranges(
  self : CodeEditorWidget,
) -> Array[@base_common.Range] {
  guard self.get_view_model() is Some(view_model) else { return [] }
  let (start_view_line, end_view_line) = view_model.view_layout.completely_visible_line_range()
  view_model.to_model_visible_ranges({
    start_line_number: start_view_line,
    start_column: view_model.get_line_min_column(start_view_line),
    end_line_number: end_view_line,
    end_column: view_model.get_line_max_column(end_view_line),
  })
}

///|
/// Visible model ranges padded by a viewport's worth of lines above and below,
/// Monaco's `getVisibleRangesPlusViewportAboveBelow` (`cew:570`) →
/// `viewModel.getVisibleRangesPlusViewportAboveBelow` (`vmi:632`):
/// `linesAround = max(20, round(height / lineHeight))`, the completely-visible
/// view range grown by `linesAround` and clamped to `[1, lineCount]`, then split.
/// No model → `[]`.
fn CodeEditorWidget::get_visible_ranges_plus_viewport_above_below(
  self : CodeEditorWidget,
) -> Array[@base_common.Range] {
  guard self.is_code_presentation() else { return [] }
  guard self.get_view_model() is Some(view_model) else { return [] }
  let line_height = self.configuration.snapshot().font_info.line_height.to_double()
  let height = view_model.view_layout.dimensions().height
  // `Math.round` of a non-negative ratio is `floor(x + 0.5)`.
  let rounded = (height / line_height + 0.5).to_int()
  let lines_around = rounded.max(20)
  let (completely_start, completely_end) = view_model.view_layout.completely_visible_line_range()
  let start_view_line = (completely_start - lines_around).clamp(
    min=1,
    max=view_model.line_count(),
  )
  let end_view_line = (completely_end + lines_around).clamp(
    min=start_view_line,
    max=view_model.line_count(),
  )
  view_model.to_model_visible_ranges({
    start_line_number: start_view_line,
    start_column: view_model.get_line_min_column(start_view_line),
    end_line_number: end_view_line,
    end_column: view_model.get_line_max_column(end_view_line),
  })
}

///|
/// Content-space top of a 1-based model line, Monaco's `getTopForLineNumber`
/// (`cew:593`). No model → `-1`.
pub fn CodeEditorWidget::get_top_for_line_number(
  self : CodeEditorWidget,
  line_number : Int32,
  include_view_zones~ : Bool = false,
) -> Double {
  self.get_vertical_offset_for_position(line_number, 1, include_view_zones~)
}

///|
/// Content-space box used by the vertical reveal pipeline for `model_range`.
/// This deliberately uses the first view line's rendered top, rather than the
/// top of any preceding ViewZone: it is the same box consumed by
/// `ViewLayout::compute_scroll_top_to_reveal_range`. ViewZones before or inside
/// the range still shift/expand these coordinates, and model-to-view conversion
/// keeps the result correct under wrapping.
pub fn CodeEditorWidget::get_vertical_reveal_bounds(
  self : CodeEditorWidget,
  model_range : @base_common.Range,
) -> (Double, Double)? {
  guard self.is_code_presentation() else { return None }
  guard self.get_view_model() is Some(view_model) else { return None }
  let view_range = view_model
    .coordinates_converter()
    .model_range_to_view_range(model_range)
  let start_line = view_range.start_line_number
  let end_line = view_range.end_line_number
  let top = view_model.view_layout.vertical_offset_for_line(start_line)
  let bottom = view_model.view_layout.vertical_offset_for_line(end_line) +
    view_model.view_layout.get_line_height_for_line_number(end_line).to_double()
  Some((top, bottom))
}

///|
/// 1-based "Col" value for a status bar (tabs snap to tab stops, code points),
/// Monaco's `getStatusbarColumn` (`cew:652`). No model → the raw input column.
fn CodeEditorWidget::get_statusbar_column(
  self : CodeEditorWidget,
  position : @base_common.Position,
) -> Int32 {
  guard self.get_model() is Some(model) else { return position.column }
  let position = model.validate_position(position)
  let tab_size = self.configuration.snapshot().options.tab_size
  @core.to_statusbar_column(
    model.get_line_content(position.line_number),
    position.column,
    tab_size,
  )
}

///|
/// Package-private geometry helpers are exercised only by root white-box
/// tests; anchor them in the ordinary library build without reopening the
/// public facade.
let _public_read_geometry_test_seams_anchor : Unit = ignore(
  (
    CodeEditorWidget::get_visible_ranges_plus_viewport_above_below,
    CodeEditorWidget::get_statusbar_column,
  ),
)

///|
/// The primary cursor's model position, Monaco's `getPosition` (`cew:663`) →
/// `viewModel.getPosition`. No model → `null`; the view model's cursor always
/// exists, starting collapsed at `(1,1)` like Monaco's.
pub fn CodeEditorWidget::get_position(
  self : CodeEditorWidget,
) -> @base_common.Position? {
  guard self.is_code_presentation() else { return None }
  guard self.get_view_model() is Some(view_model) else { return None }
  Some(view_model.cursor.model_state().position)
}

///|
/// The primary cursor's model selection, Monaco's `getSelection` (`cew:783`) →
/// `viewModel.getSelection`. No model → `null`.
pub fn CodeEditorWidget::get_selection(
  self : CodeEditorWidget,
) -> @core.Selection? {
  guard self.is_code_presentation() else { return None }
  guard self.get_view_model() is Some(view_model) else { return None }
  Some(view_model.cursor.get_model_selection())
}

///|
/// Widest content width (horizontal scroll extent before viewport clamping),
/// Monaco's `getContentWidth` (`cew:963`). No model → `-1`.
pub fn CodeEditorWidget::get_content_width(self : CodeEditorWidget) -> Double {
  self.active_content_width().unwrap_or(-1.0)
}

///|
/// Scrollable content width = `max(viewport width, content width)`, Monaco's
/// `getScrollWidth` (`cew:970`). No model → `-1`.
pub fn CodeEditorWidget::get_scroll_width(self : CodeEditorWidget) -> Double {
  self.active_scroll_width().unwrap_or(-1.0)
}

///|
/// Current horizontal scroll offset, Monaco's `getScrollLeft` (`cew:976`). No
/// model → `-1`.
pub fn CodeEditorWidget::get_scroll_left(self : CodeEditorWidget) -> Double {
  match self.active_scroll_position() {
    Some(position) => position.scroll_left
    None => -1.0
  }
}

///|
/// Total content height including view zones, Monaco's `getContentHeight`
/// (`cew:983`). No model → `-1`.
pub fn CodeEditorWidget::get_content_height(self : CodeEditorWidget) -> Double {
  self.active_content_height().unwrap_or(-1.0)
}

///|
/// Scrollable content height = `max(viewport height, content height)`, Monaco's
/// `getScrollHeight` (`cew:990`). No model → `-1`.
pub fn CodeEditorWidget::get_scroll_height(self : CodeEditorWidget) -> Double {
  self.active_scroll_height().unwrap_or(-1.0)
}

///|
/// Current vertical scroll offset, Monaco's `getScrollTop` (`cew:996`). No model
/// → `-1`.
pub fn CodeEditorWidget::get_scroll_top(self : CodeEditorWidget) -> Double {
  match self.active_scroll_position() {
    Some(position) => position.scroll_top
    None => -1.0
  }
}

///|
/// Validates a model position and converts it to a view position, the shared
/// front half of Monaco's `_getVerticalOffsetForPosition` /
/// `_getVerticalOffsetAfterPosition` (`cew:607` / `cew:584`). `None` when there
/// is no model (the no-model sentinel boundary).
fn CodeEditorWidget::model_to_view_position(
  self : CodeEditorWidget,
  line_number : Int32,
  column : Int32,
) -> @base_common.Position? {
  guard (self.get_model(), self.get_view_model())
    is (Some(model), Some(view_model)) else {
    return None
  }
  let model_position = model.validate_position(Position(line_number, column))
  Some(
    view_model
    .coordinates_converter()
    .model_position_to_view_position(model_position),
  )
}

///|
/// Monaco's `CodeEditorWidget._getVerticalOffsetForPosition` (`cew:607`):
/// validate → convert to view position → `viewLayout.getVerticalOffsetForLineNumber`.
/// No model → `-1`.
fn CodeEditorWidget::get_vertical_offset_for_position(
  self : CodeEditorWidget,
  line_number : Int32,
  column : Int32,
  include_view_zones~ : Bool,
) -> Double {
  guard self.get_view_model() is Some(view_model) else { return -1.0 }
  match self.model_to_view_position(line_number, column) {
    Some(view_position) =>
      view_model.view_layout.get_vertical_offset_for_line_number(
        view_position.line_number,
        include_view_zones~,
      )
    None => -1.0
  }
}

///|
/// Monaco's `CodeEditorWidget._getVerticalOffsetAfterPosition` (`cew:584`):
/// validate → convert → `viewLayout.getVerticalOffsetAfterLineNumber`. No model
/// → `-1`.
fn CodeEditorWidget::get_vertical_offset_after_position(
  self : CodeEditorWidget,
  line_number : Int32,
  column : Int32,
  include_view_zones~ : Bool,
) -> Double {
  guard self.get_view_model() is Some(view_model) else { return -1.0 }
  match self.model_to_view_position(line_number, column) {
    Some(view_position) =>
      view_model.view_layout.get_vertical_offset_after_line_number(
        view_position.line_number,
        include_view_zones~,
      )
    None => -1.0
  }
}

// --- DOM-measured read API (Monaco's `hasRealView`-gated getters) ------------
//
// These read real client rects, so they need the target line rendered. The
// `hasRealView` gate collapses to "model + view attached"; an off-screen line
// (not in the rendered window) measures to `-1`/`null`, mirroring Monaco's
// `visibleRangeForPosition` → `null`. They flush any pending render first, the
// analog of Monaco's `_flushAccumulatedAndRenderNow`.

///|
/// Reduced editor layout info, Monaco's `CodeEditorWidget.getLayoutInfo`
/// (`cew:1472`); the shape lives in `viewer/common/config/editor_options.mbt`.
/// Backed by the viewer's measured gutter width and content box;
/// `content_left` is the full margin (line numbers plus the line-decorations
/// lane; the glyph-margin terms are `0`). Like Monaco this does not gate on a
/// model.
pub fn CodeEditorWidget::get_layout_info(
  self : CodeEditorWidget,
) -> @config.EditorLayoutInfo {
  let model_line_count = match self.get_model() {
    Some(model) => model.snapshot.line_count()
    // EditorConfiguration retains its one-digit model environment before any
    // model is attached; `digit_count(0)` supplies the same minimum band.
    None => 0
  }
  self.configuration.snapshot().layout_info(model_line_count)
}

///|
/// Horizontal pixel offset of a model position on its rendered line, Monaco's
/// `getOffsetForColumn` (`cew:1687`) → `view.getOffsetForColumn`. No real view →
/// `-1`; line not in the rendered window → `-1`.
pub fn CodeEditorWidget::get_offset_for_column(
  self : CodeEditorWidget,
  line_number : Int32,
  column : Int32,
) -> Double {
  guard (self.get_model(), self.get_view_model(), self.current_code_view())
    is (Some(model), Some(view_model), Some(view)) else {
    return -1.0
  }
  let model_position = model.validate_position(Position(line_number, column))
  let view_position = view_model
    .coordinates_converter()
    .model_position_to_view_position(model_position)
  self.flush_accumulated_and_render_now()
  view.offset_for_column(view_position.line_number, view_position.column)
}

///|
/// Rendered width of a model line, Monaco's `getWidthOfLine` (`cew:1694`) →
/// `view.getLineWidth`: convert the line's max-column model position to its view
/// line (the last wrapped segment), then measure that view line's width. No real
/// view → `-1`; line not in the rendered window → `-1`.
pub fn CodeEditorWidget::get_width_of_line(
  self : CodeEditorWidget,
  line_number : Int32,
) -> Double {
  guard (self.get_model(), self.get_view_model(), self.current_code_view())
    is (Some(model), Some(view_model), Some(view)) else {
    return -1.0
  }
  let line_count = model.get_line_count()
  let clamped_line = line_number.clamp(min=1, max=line_count)
  let max_column = model.get_line_max_column(clamped_line)
  let view_position = view_model
    .coordinates_converter()
    .model_position_to_view_position(Position(clamped_line, max_column))
  self.flush_accumulated_and_render_now()
  view.line_width(
    view_position.line_number,
    view_model.get_line_max_column(view_position.line_number),
  )
}

///|
/// A model position projected to scrolled viewport pixels, Monaco's
/// `getScrolledVisiblePosition` (`cew:1668`): `top` is the vertical offset minus
/// scrollTop, `left` is the column offset plus the content-left gutter minus
/// scrollLeft, `height` is the line height. No real view → `null`.
pub fn CodeEditorWidget::get_scrolled_visible_position(
  self : CodeEditorWidget,
  position : @base_common.Position,
) -> @editor_api.ScrolledVisiblePosition? {
  guard (self.get_model(), self.get_view_model(), self.current_code_view())
    is (Some(model), Some(view_model), Some(view)) else {
    return None
  }
  let position = model.validate_position(position)
  let content_left = self.read_api_content_left()
  let top = self.get_vertical_offset_for_position(
      position.line_number,
      position.column,
      include_view_zones=false,
    ) -
    view_model.view_layout.get_current_scroll_top()
  let view_position = view_model
    .coordinates_converter()
    .model_position_to_view_position(position)
  self.flush_accumulated_and_render_now()
  let offset = view.offset_for_column(
    view_position.line_number,
    view_position.column,
  )
  let left = offset +
    content_left -
    view_model.view_layout.get_current_scroll_left()
  let height = self.get_line_height_for_position(position)
  Some({ top, left, height, })
}

///|
/// The content-left gutter width (Monaco's `glyphMarginWidth + lineNumbersWidth +
/// decorationsWidth`), the offset DOM-measured line x's are relative to. Backed
/// by the view model's measured `gutter_width`; `0` with no model.
fn CodeEditorWidget::read_api_content_left(self : CodeEditorWidget) -> Double {
  match self.get_model() {
    Some(model) =>
      self.configuration.snapshot().gutter_width(model.snapshot.line_count())
    None => 0.0
  }
}

///|
/// Flushes a pending render so DOM-measured getters read current client rects,
/// Monaco's `_flushAccumulatedAndRenderNow`. A no-op when nothing is pending (the
/// DOM already reflects the latest content) or when there is no view.
fn CodeEditorWidget::flush_accumulated_and_render_now(
  self : CodeEditorWidget,
) -> Unit {
  if self.mount.has_pending_render() && !self.disposed {
    self.cancel_render_frame()
    self.flush_render()
  }
}
