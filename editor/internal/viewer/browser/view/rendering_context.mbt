///|
/// Inputs `Viewer` provides to `View` for one readonly browser render.
/// `pub(all)`: `Viewer::flush_render` (`view_host.mbt`, root `viewer`
/// package) builds this via a struct literal passed straight into
/// `View::render`. The internal view package does not import the root facade,
/// so this literal construction crosses the package boundary.
pub(all) struct ViewRenderInput {
  /// The rendered 1-based half-open view-line window: exactly the lines
  /// intersecting the viewport (already clamped to the document).
  window : @view_layout.LineWindow
  view_model : @view_model.ViewModel
  layout : @view_layout.ViewLayout
  selection_view_range : @base_common.Range?
  /// The full view-space selection (anchor + active position), Monaco's
  /// `ViewCursorStateChangedEvent.selections[0]`. Unlike
  /// `selection_view_range` (which is `None` when collapsed), this carries the
  /// caret position of an empty selection — the cursor part renders from it.
  view_selection : @core.Selection?
  gutter_width : Double
  /// Width of the line-decorations lane inside the gutter,
  /// `layoutInfo.decorationsWidth` (the margin part renders the lane at
  /// `left = gutter_width - line_decorations_width`).
  line_decorations_width : Double
  space_width : Double
  /// `fontInfo.typicalFullwidthCharacterWidth`: the content-widget layer's
  /// `_reduceAnchorCoordinates` clamp unit.
  typical_fullwidth_character_width : Double
  /// Whether the editor root has DOM focus (Monaco `ViewFocusChangedEvent`
  /// state; the root viewer sources it from its mounted focus owner).
  editor_has_focus : Bool
  /// Whether soft wrapping is in effect (Monaco `layoutInfo.isViewportWrapping`)
  /// — gates the current-line highlight's wrapped-line pass.
  word_wrap : Bool
  /// The current-line highlight options (`renderLineHighlight` /
  /// `renderLineHighlightOnlyWhenFocus`, Monaco defaults `'line'`/`false`).
  render_line_highlight : @editor_api.RenderLineHighlight
  render_line_highlight_only_when_focus : Bool
  /// Root-class flags from Monaco's `showUnused`/`showDeprecated` editor
  /// options (`EditorClassName.compute`, `editorOptions.ts:1680-1686`).
  show_unused : Bool
  show_deprecated : Bool
}

///|
/// Read/prepare context for view parts. It owns measured viewport data and
/// derived geometry so parts can prepare without recomputing shared inputs.
priv struct RenderingContext {
  view_context : ViewContext
  input : ViewRenderInput
  view_lines : ViewLines
  viewport : @view_layout.ViewportData
  gutter_width : Double
  position : @view_layout.ScrollPosition
  dimensions : @view_layout.ScrollDimensions
  translate_y : Double
}

///|
/// Write-phase render context for view parts — Monaco's
/// `RestrictedRenderingContext`, which carries the viewport data, scroll
/// state, and viewport decorations into `render`. The viewer's frame inputs
/// ride along as `input` (its stand-in for Monaco parts reading
/// `this._context` and event-tracked fields during render).
priv struct RestrictedRenderingContext {
  input : ViewRenderInput
  viewport : @view_layout.ViewportData
  gutter_width : Double
  position : @view_layout.ScrollPosition
  dimensions : @view_layout.ScrollDimensions
  margin_transform : String
}

///|
/// Source `prepareRenderText` viewport construction. Keeping this separate
/// lets `View::render` retain the exact viewport across text rendering while
/// deferring scroll/dimension snapshots until after that write phase.
fn RenderingContext::viewport_from_input(
  input : ViewRenderInput,
) -> @view_layout.ViewportData {
  // Pulled from the view model per render pass — Monaco's `view.ts` building
  // a fresh `ViewportData` over `viewLayout.getLinesViewportData()`.
  let partial_viewport = input.layout.get_lines_viewport_data()
  @view_model.viewport_data_from_view_model(
    input.view_model,
    input.window,
    line_height=input.layout.line_height(),
    layout=input.layout,
    partial_viewport~,
  )
}

///|
/// Source post-`renderText` RenderingContext construction: reuse the prepared
/// viewport, but snapshot current layout position/dimensions only after line
/// width feedback and any synchronous scroll events have completed.
fn RenderingContext::from_viewport(
  view_context : ViewContext,
  input : ViewRenderInput,
  view_lines : ViewLines,
  viewport : @view_layout.ViewportData,
) -> RenderingContext {
  let current_viewport = input.layout.get_current_viewport()
  let layout_dimensions = input.layout.dimensions()
  let position : @view_layout.ScrollPosition = {
    scroll_top: current_viewport.top,
    scroll_left: current_viewport.left,
  }
  let dimensions : @view_layout.ScrollDimensions = {
    width: current_viewport.width,
    scroll_width: layout_dimensions.scroll_width,
    height: current_viewport.height,
    scroll_height: layout_dimensions.scroll_height,
  }
  {
    view_context,
    input,
    view_lines,
    viewport,
    gutter_width: input.gutter_width,
    position,
    dimensions,
    translate_y: viewport.big_numbers_delta.to_double() - position.scroll_top,
  }
}

///|
fn RenderingContext::restricted(
  self : RenderingContext,
) -> RestrictedRenderingContext {
  {
    input: self.input,
    viewport: self.viewport,
    gutter_width: self.gutter_width,
    position: self.position,
    dimensions: self.dimensions,
    margin_transform: self.margin_transform(),
  }
}

///|
fn RenderingContext::margin_transform(self : RenderingContext) -> String {
  "transform:translateY(\{self.translate_y.to_string()}px)"
}

///|
/// Scoped `RestrictedRenderingContext.getVerticalOffsetForLineNumber`.
fn RenderingContext::vertical_offset_for_line(
  self : RenderingContext,
  line_number : Int,
  include_view_zones? : Bool = false,
) -> Double {
  self.input.layout.get_vertical_offset_for_line_number(
    line_number,
    include_view_zones~,
  )
}

///|
/// Scoped `RestrictedRenderingContext.getLineHeightForLineNumber`.
fn RenderingContext::line_height_for_line(
  self : RenderingContext,
  line_number : Int,
) -> Double {
  self.input.layout.get_line_height_for_line_number(line_number).to_double()
}

///|
/// Monaco `RenderingContext.visibleRangeForPosition` with the currently
/// available DOM ViewLines producer. A negative capability result is the
/// source's `null`; GPU fallback remains explicitly deferred.
fn RenderingContext::visible_range_for_position(
  self : RenderingContext,
  position : @base_common.Position,
) -> HorizontalPosition? {
  self.view_lines
  .raw_visible_range_for_position(position.line_number, position.column)
  .map(left => HorizontalPosition(left))
}

///|
/// Monaco `RenderingContext.linesVisibleRangesForRange`, DOM-only at this
/// approved phase. ViewLines owns DOM/range production; this facade converts
/// its raw tuples into the source rendering carriers. Optional GPU
/// concatenation/sorting remains explicitly deferred.
fn RenderingContext::lines_visible_ranges_for_range(
  self : RenderingContext,
  range : @base_common.Range,
  include_new_lines : Bool,
) -> Array[LineVisibleRanges]? {
  self.view_lines
  .raw_lines_visible_ranges_for_range(range, include_new_lines)
  .map(line_visible_ranges_from_raw)
}

///|
/// Internal tuple-carrier conversion at the ViewLines/RenderingContext
/// handoff. Input and per-line range order are preserved exactly.
fn line_visible_ranges_from_raw(
  raw_lines : Array[(Int, Array[(Int, Int)])],
) -> Array[LineVisibleRanges] {
  [
    for raw in raw_lines => {
      LineVisibleRanges(
        raw.0,
        [
          for range in raw.1 => { left: range.0, width: range.1, }
        ],
      )
    }
  ]
}

///|
/// Focused capability projection consumed by ContentWidgets. The measured
/// `HorizontalPosition.left` is intentionally rounded before the handoff,
/// matching the source anchor arithmetic.
fn RenderingContext::content_widgets_render_context(
  self : RenderingContext,
) -> ContentWidgetsRenderContext {
  {
    vertical_offset_for_line: line => self.vertical_offset_for_line(line),
    line_height_for_line: line => self.line_height_for_line(line),
    visible_range_for_position: position => {
      self
      .visible_range_for_position(position)
      .map(horizontal => horizontal.left.to_double())
    },
    typical_fullwidth_character_width: self.input.typical_fullwidth_character_width,
    scroll_top: self.position.scroll_top,
    scroll_left: self.position.scroll_left,
    viewport_width: self.dimensions.width,
    viewport_height: self.dimensions.height,
  }
}

///|
/// `HorizontalPosition` (`vscode/src/vs/editor/browser/view/renderingContext.ts:196-209`,
/// checked-in vscode submodule): a
/// measured caret x on a rendered line. The readonly consumers only use the
/// rounded `left`; Monaco's additional source carrier fields are intentionally
/// omitted because no current producer/consumer boundary observes them.
pub struct HorizontalPosition {
  left : Int
} derive(Eq, Debug)

///|
fn HorizontalPosition::HorizontalPosition(left : Double) -> HorizontalPosition {
  { left: (left + 0.5).floor().to_int(), }
}

///|
/// Measured horizontal ranges owned by one view line. The source's
/// continuation/outside-rendered facts are not carried because the readonly
/// selection renderer has no consumer for them.
priv struct LineVisibleRanges {
  line_number : Int
  ranges : Array[HorizontalRange]
}

///|
fn LineVisibleRanges::LineVisibleRanges(
  line_number : Int,
  ranges : Array[HorizontalRange],
) -> LineVisibleRanges {
  { line_number, ranges, }
}

///|
/// Monaco `HorizontalRange`: integerized DOM geometry.
priv struct HorizontalRange {
  left : Int
  width : Int
}

///|
pub extend HorizontalPosition with Debug::{to_repr}

///|
pub extend HorizontalPosition with Eq::{equal, not_equal}
