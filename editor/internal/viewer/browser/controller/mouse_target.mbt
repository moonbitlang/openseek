// Ported from `vscode/src/vs/editor/browser/controller/mouseTarget.ts`
// (checked-in vscode submodule): the
// DOM-fingerprint mouse hit test — `HitTestResult`,
// `PointerHandlerLastRenderData`, the `MouseTarget` static factories,
// `ElementPath`, `HitTestContext`, `BareHitTestRequest`/`HitTestRequest`,
// and `MouseTargetFactory` with its full dispatch chain and browser caret
// bridging.
//
// Shape notes:
//   * The `MouseTarget` static factories are package-private local methods on
//     the foreign enum owned by `viewer/browser`.
//   * `BareHitTestRequest`/`HitTestRequest` flatten into one struct (no
//     inheritance); `doHitTest` takes the full request.
//   * `Lazy(() => doHitTest(...))` is a `mut` option cache
//     (`hit_test_result()`).
//   * Monaco reaches the view model / view layout / editor options through
//     its `ViewContext`; this port reads them through `PointerHandlerHelper`
//     closures and the view model's own `view_layout` field (the helper's
//     header records the substitution).
//
// Omissions (beyond the enum-level ones recorded in
// `viewer/browser/editor_browser.mbt`):
//   * the shadow-DOM caret path (`shadowCaretRangeFromPoint`,
//     `CharWidthReader`, mouseTarget.ts:1116-1214) — the viewer never renders
//     into a shadow root;
//   * every `viewLinesGpu` branch (no GPU renderer);
//   * `_hitTestTextArea` (no textarea part → `ElementPath.isTextArea` can
//     never hold) and `lastTextareaPosition`;
//   * `_snapToSoftTabBoundary` + the `stickyTabStops` gate in
//     `createMouseTarget` (option absent from the viewer);
//   * the RTL arm of `_hitTestViewLines` (`getTextDirection` is unported;
//     the viewer renders LTR only, so `isRtl` is constant `false`);
//   * `IMouseTargetMarginData.glyphMarginLane` in `_hitTestMargin` (no glyph
//     margin lanes; the width-0 glyph arm itself is kept);
//   * `MouseTarget._typeToString`/`toString` (debug only) and
//     `createMouseTarget`'s `try/catch` (the caret externs return misses
//     instead of throwing).

///|
/// `HitTestResultType`/`UnknownHitTestResult`/`ContentHitTestResult`
/// (mouseTarget.ts:27-51).
priv enum HitTestResult {
  UnknownHitTestResult(hit_target~ : @rdom.Element?)
  ContentHitTestResult(
    position~ : @base_common.Position,
    span_node~ : @rdom.Element,
    injected_text~ : @view_model.InjectedText?
  )
}

///|
fn HitTestResult::hit_target(self : HitTestResult) -> @rdom.Element? {
  match self {
    UnknownHitTestResult(hit_target~) => hit_target
    ContentHitTestResult(span_node~, ..) => Some(span_node)
  }
}

///|
/// `HitTestResult.createFromDOMInfo` (mouseTarget.ts:53-61).
fn hit_test_result_from_dom_info(
  ctx : HitTestContext,
  span_node : @rdom.Element,
  offset : Int,
) -> HitTestResult {
  match ctx.get_position_from_dom_info(span_node, offset) {
    Some(position) =>
      ContentHitTestResult(position~, span_node~, injected_text=None)
    None => UnknownHitTestResult(hit_target=Some(span_node))
  }
}

///|
/// `PointerHandlerLastRenderData` (mouseTarget.ts:63-68).
/// `lastTextareaPosition` is omitted with the textarea part.
pub(all) struct PointerHandlerLastRenderData {
  last_view_cursors_render_data : Array[@view.ViewCursorRenderData]
}

///|
/// `MouseTarget._deduceRage` (mouseTarget.ts:72-80; the source's typo is kept
/// for grep-ability). Collapses a position into an empty range when no range
/// is given.
fn deduce_rage(
  position : @base_common.Position?,
  range? : @base_common.Range,
) -> @base_common.Range? {
  match (range, position) {
    (Some(range), _) => Some(range)
    (None, Some(position)) =>
      Some(
        Range(
          position.line_number,
          position.column,
          position.line_number,
          position.column,
        ),
      )
    (None, None) => None
  }
}

///|
/// `MouseTarget.createUnknown` (mouseTarget.ts:81-83).
fn @editor_browser.MouseTarget::create_unknown(
  element : @rdom.Element?,
  mouse_column : Int,
  position : @base_common.Position?,
) -> @editor_browser.MouseTarget {
  MouseTargetUnknown(
    element~,
    mouse_column~,
    position~,
    range=deduce_rage(position),
  )
}

///|
/// `MouseTarget.createMargin` (mouseTarget.ts:87-89). `type_` is one of the
/// three gutter margin types.
fn @editor_browser.MouseTarget::create_margin(
  type_ : @editor_browser.MouseTargetType,
  element : @rdom.Element?,
  mouse_column : Int,
  position : @base_common.Position,
  range : @base_common.Range,
  detail : @editor_browser.MouseTargetMarginData,
) -> @editor_browser.MouseTarget {
  MouseTargetMargin(type_~, element~, mouse_column~, position~, range~, detail~)
}

///|
/// `MouseTarget.createViewZone` (mouseTarget.ts:90-92). `type_` is
/// `GutterViewZone` or `ContentViewZone`.
fn @editor_browser.MouseTarget::create_view_zone(
  type_ : @editor_browser.MouseTargetType,
  element : @rdom.Element?,
  mouse_column : Int,
  position : @base_common.Position,
  detail : @editor_browser.MouseTargetViewZoneData,
) -> @editor_browser.MouseTarget {
  MouseTargetViewZone(
    type_~,
    element~,
    mouse_column~,
    position~,
    range=deduce_rage(Some(position)).unwrap(),
    detail~,
  )
}

///|
/// `MouseTarget.createContentText` (mouseTarget.ts:93-95).
fn @editor_browser.MouseTarget::create_content_text(
  element : @rdom.Element?,
  mouse_column : Int,
  position : @base_common.Position,
  range : @base_common.Range?,
  detail : @editor_browser.MouseTargetContentTextData,
) -> @editor_browser.MouseTarget {
  MouseTargetContentText(
    element~,
    mouse_column~,
    position~,
    range=deduce_rage(Some(position), range?).unwrap(),
    detail~,
  )
}

///|
/// `MouseTarget.createContentEmpty` (mouseTarget.ts:96-98).
fn @editor_browser.MouseTarget::create_content_empty(
  element : @rdom.Element?,
  mouse_column : Int,
  position : @base_common.Position,
  detail : @editor_browser.MouseTargetContentEmptyData,
) -> @editor_browser.MouseTarget {
  MouseTargetContentEmpty(
    element~,
    mouse_column~,
    position~,
    range=deduce_rage(Some(position)).unwrap(),
    detail~,
  )
}

///|
/// `MouseTarget.createContentWidget` (mouseTarget.ts:99-101).
fn @editor_browser.MouseTarget::create_content_widget(
  element : @rdom.Element?,
  mouse_column : Int,
  detail : String,
) -> @editor_browser.MouseTarget {
  MouseTargetContentWidget(element~, mouse_column~, detail~)
}

///|
/// `MouseTarget.createScrollbar` (mouseTarget.ts:102-104).
fn @editor_browser.MouseTarget::create_scrollbar(
  element : @rdom.Element?,
  mouse_column : Int,
  position : @base_common.Position,
) -> @editor_browser.MouseTarget {
  MouseTargetScrollbar(
    element~,
    mouse_column~,
    position~,
    range=deduce_rage(Some(position)).unwrap(),
  )
}

///|
/// `MouseTarget.createOverlayWidget` (mouseTarget.ts:105-107).
fn @editor_browser.MouseTarget::create_overlay_widget(
  element : @rdom.Element?,
  mouse_column : Int,
  detail : String,
) -> @editor_browser.MouseTarget {
  MouseTargetOverlayWidget(element~, mouse_column~, detail~)
}

///|
/// `MouseTarget.createOutsideEditor` (mouseTarget.ts:108-110).
fn @editor_browser.MouseTarget::create_outside_editor(
  mouse_column : Int,
  position : @base_common.Position,
  outside_position : @editor_browser.OutsidePosition,
  outside_distance : Double,
) -> @editor_browser.MouseTarget {
  MouseTargetOutsideEditor(
    mouse_column~,
    position~,
    range=deduce_rage(Some(position)).unwrap(),
    outside_position~,
    outside_distance~,
  )
}

///|
/// `ElementPath` (mouseTarget.ts:157-235): predicates over the root-first
/// fingerprint path bytes `PartFingerprint::collect` produces. The numeric
/// byte values are `PartFingerprint::to_int` (`view_part.mbt`).
#warnings("-struct_never_constructed")
priv struct ElementPath {}

///|
fn fp(fingerprint : @view.PartFingerprint) -> Byte {
  fingerprint.to_int().to_byte()
}

///|
#warnings("-unused_value")
fn ElementPath::is_text_area(path : Bytes) -> Bool {
  path.length() == 2 && path[0] == fp(OverflowGuard) && path[1] == fp(TextArea)
}

///|
fn ElementPath::is_child_of_view_lines(path : Bytes) -> Bool {
  path.length() >= 4 && path[0] == fp(OverflowGuard) && path[3] == fp(ViewLines)
}

///|
fn ElementPath::is_strict_child_of_view_lines(path : Bytes) -> Bool {
  path.length() > 4 && path[0] == fp(OverflowGuard) && path[3] == fp(ViewLines)
}

///|
fn ElementPath::is_child_of_scrollable_element(path : Bytes) -> Bool {
  path.length() >= 2 &&
  path[0] == fp(OverflowGuard) &&
  path[1] == fp(ScrollableElement)
}

///|
fn ElementPath::is_child_of_minimap(path : Bytes) -> Bool {
  path.length() >= 2 && path[0] == fp(OverflowGuard) && path[1] == fp(Minimap)
}

///|
fn ElementPath::is_child_of_content_widgets(path : Bytes) -> Bool {
  path.length() >= 4 &&
  path[0] == fp(OverflowGuard) &&
  path[3] == fp(ContentWidgets)
}

///|
fn ElementPath::is_child_of_overflow_guard(path : Bytes) -> Bool {
  path.length() >= 1 && path[0] == fp(OverflowGuard)
}

///|
fn ElementPath::is_child_of_overflowing_content_widgets(path : Bytes) -> Bool {
  path.length() >= 1 && path[0] == fp(OverflowingContentWidgets)
}

///|
fn ElementPath::is_child_of_overlay_widgets(path : Bytes) -> Bool {
  path.length() >= 2 &&
  path[0] == fp(OverflowGuard) &&
  path[1] == fp(OverlayWidgets)
}

///|
fn ElementPath::is_child_of_overflowing_overlay_widgets(path : Bytes) -> Bool {
  path.length() >= 1 && path[0] == fp(OverflowingOverlayWidgets)
}

///|
/// `HitTestContext` (mouseTarget.ts:237-390). Constructed per gesture; the
/// options snapshot (`layoutInfo`, `lineHeight`, `typicalHalfwidth…`) is read
/// through the helper's closures (see the header).
priv struct HitTestContext {
  view_model : @view_model.ViewModel
  layout_info : @config.EditorLayoutInfo
  view_dom_node : @rdom.Element
  line_height : Int
  typical_halfwidth_character_width : Double
  last_render_data : PointerHandlerLastRenderData
  view_helper : PointerHandlerHelper
}

///|
fn HitTestContext::HitTestContext(
  view_model : @view_model.ViewModel,
  view_helper : PointerHandlerHelper,
  last_render_data : PointerHandlerLastRenderData,
) -> HitTestContext {
  let font_info = (view_helper.get_font_info)()
  {
    view_model,
    layout_info: (view_helper.get_layout_info)(),
    view_dom_node: view_helper.view_dom_node,
    line_height: font_info.line_height,
    typical_halfwidth_character_width: font_info.typical_halfwidth_character_width,
    last_render_data,
    view_helper,
  }
}

///|
fn HitTestContext::get_zone_at_coord(
  self : HitTestContext,
  mouse_vertical_offset : Double,
) -> @editor_browser.MouseTargetViewZoneData? {
  hit_test_get_zone_at_coord(self.view_model, mouse_vertical_offset)
}

///|
/// static `HitTestContext.getZoneAtCoord` (mouseTarget.ts:269-308) — the
/// target is either a view zone or the empty space after the last view line.
/// Takes the view model directly (Monaco takes its `ViewContext`).
fn hit_test_get_zone_at_coord(
  view_model : @view_model.ViewModel,
  mouse_vertical_offset : Double,
) -> @editor_browser.MouseTargetViewZoneData? {
  guard view_model.view_layout.get_whitespace_at_vertical_offset(
      mouse_vertical_offset,
    )
    is Some(view_zone_whitespace) else {
    return None
  }
  let view_zone_middle = view_zone_whitespace.vertical_offset +
    view_zone_whitespace.height.to_double() / 2.0
  let line_count = view_model.line_count()
  let mut position_before : @base_common.Position? = None
  let mut position_after : @base_common.Position? = None
  if view_zone_whitespace.after_line_number != line_count {
    // There are more lines after this view zone
    position_after = Some(
      Position(view_zone_whitespace.after_line_number + 1, 1),
    )
  }
  if view_zone_whitespace.after_line_number > 0 {
    // There are more lines above this view zone
    position_before = Some(
      Position(
        view_zone_whitespace.after_line_number,
        view_model.get_line_max_column(view_zone_whitespace.after_line_number),
      ),
    )
  }
  let position = match (position_after, position_before) {
    (None, _) => position_before
    (_, None) => position_after
    (Some(_), Some(_)) =>
      if mouse_vertical_offset < view_zone_middle {
        position_before
      } else {
        position_after
      }
  }
  Some({
    view_zone_id: view_zone_whitespace.id,
    after_line_number: view_zone_whitespace.after_line_number,
    position_before,
    position_after,
    position: position.unwrap(),
  })
}

///|
/// `getFullLineRangeAtCoord` (mouseTarget.ts:310-327): the whole line at a
/// vertical offset as `(range, is_after_lines)`.
fn HitTestContext::get_full_line_range_at_coord(
  self : HitTestContext,
  mouse_vertical_offset : Double,
) -> (@base_common.Range, Bool) {
  if self.view_model.view_layout.is_after_lines(mouse_vertical_offset) {
    // Below the last line
    let line_number = self.view_model.line_count()
    let max_line_column = self.view_model.get_line_max_column(line_number)
    return (
      Range(line_number, max_line_column, line_number, max_line_column),
      true,
    )
  }
  let line_number = self.view_model.view_layout.line_at_vertical_offset(
    mouse_vertical_offset,
  )
  let max_line_column = self.view_model.get_line_max_column(line_number)
  (Range(line_number, 1, line_number, max_line_column), false)
}

///|
fn HitTestContext::get_line_number_at_vertical_offset(
  self : HitTestContext,
  mouse_vertical_offset : Double,
) -> Int {
  self.view_model.view_layout.line_at_vertical_offset(mouse_vertical_offset)
}

///|
fn HitTestContext::is_after_lines(
  self : HitTestContext,
  mouse_vertical_offset : Double,
) -> Bool {
  self.view_model.view_layout.is_after_lines(mouse_vertical_offset)
}

///|
fn HitTestContext::is_in_top_padding(
  self : HitTestContext,
  mouse_vertical_offset : Double,
) -> Bool {
  self.view_model.view_layout.is_in_top_padding(mouse_vertical_offset)
}

///|
fn HitTestContext::is_in_bottom_padding(
  self : HitTestContext,
  mouse_vertical_offset : Double,
) -> Bool {
  self.view_model.view_layout.is_in_bottom_padding(mouse_vertical_offset)
}

///|
fn HitTestContext::get_vertical_offset_for_line_number(
  self : HitTestContext,
  line_number : Int,
) -> Double {
  self.view_model.view_layout.get_vertical_offset_for_line_number(line_number)
}

///|
/// `findAttribute` (mouseTarget.ts:349-364): the value of `attr` on the
/// element or its closest ancestor carrying it, stopping at the view DOM
/// node.
fn HitTestContext::find_attribute(
  self : HitTestContext,
  element : @rdom.Element,
  attr : String,
) -> String? {
  find_attribute_up_to(element, attr, self.view_dom_node)
}

///|
fn find_attribute_up_to(
  element : @rdom.Element,
  attr : String,
  stop_at : @rdom.Element,
) -> String? {
  for current = Some(element)
      current is Some(el) && !controller_is_document_body(el)
      current = controller_parent_element(el) {
    if element_has_attribute(el, attr) {
      return el.get_attribute(attr)
    }
    if el.is_same_node(stop_at.as_node()) {
      return None
    }
  }
  None
}

///|
fn HitTestContext::get_line_width(
  self : HitTestContext,
  line_number : Int,
) -> Double {
  (self.view_helper.get_line_width)(line_number)
}

///|
fn HitTestContext::visible_range_for_position(
  self : HitTestContext,
  line_number : Int,
  column : Int,
) -> @view.HorizontalPosition? {
  (self.view_helper.visible_range_for_position)(line_number, column)
}

///|
fn HitTestContext::get_position_from_dom_info(
  self : HitTestContext,
  span_node : @rdom.Element,
  offset : Int,
) -> @base_common.Position? {
  (self.view_helper.get_position_from_dom_info)(span_node, offset)
}

///|
fn HitTestContext::get_current_scroll_top(self : HitTestContext) -> Double {
  self.view_model.view_layout.get_current_scroll_top()
}

///|
fn HitTestContext::get_current_scroll_left(self : HitTestContext) -> Double {
  self.view_model.view_layout.get_current_scroll_left()
}

///|
/// `BareHitTestRequest` + `HitTestRequest` (mouseTarget.ts:392-502),
/// flattened (see the header). The coordinate-derived state is computed in
/// `HitTestRequest::HitTestRequest`.
priv struct HitTestRequest {
  ctx : HitTestContext
  editor_pos : @editor_browser.EditorPagePosition
  pos : @editor_browser.PageCoordinates
  relative_pos : @editor_browser.CoordinatesRelativeToEditor
  mouse_vertical_offset : Double
  is_in_margin_area : Bool
  is_in_content_area : Bool
  mouse_content_horizontal_offset : Double
  mouse_column : Int
  event_target : @rdom.Element?
  mut hit_test_result_cache : HitTestResult?
  mut use_hit_test_target : Bool
  mut target_path_cache_element : @rdom.Element?
  mut target_path_cache_value : Bytes
}

///|
fn HitTestRequest::HitTestRequest(
  ctx : HitTestContext,
  editor_pos : @editor_browser.EditorPagePosition,
  pos : @editor_browser.PageCoordinates,
  relative_pos : @editor_browser.CoordinatesRelativeToEditor,
  event_target : @rdom.Element?,
) -> HitTestRequest {
  let mouse_vertical_offset = 0.0.max(
    ctx.get_current_scroll_top() + relative_pos.y,
  )
  let mouse_content_horizontal_offset = ctx.get_current_scroll_left() +
    relative_pos.x -
    ctx.layout_info.content_left
  let is_in_margin_area = relative_pos.x < ctx.layout_info.content_left &&
    relative_pos.x >= ctx.layout_info.glyph_margin_left
  {
    ctx,
    editor_pos,
    pos,
    relative_pos,
    mouse_vertical_offset,
    mouse_content_horizontal_offset,
    is_in_margin_area,
    is_in_content_area: !is_in_margin_area,
    mouse_column: get_mouse_column_static(
      mouse_content_horizontal_offset,
      ctx.typical_halfwidth_character_width,
    ).max(0),
    // If no event target is passed in, we will use the hit test target
    event_target,
    hit_test_result_cache: None,
    use_hit_test_target: event_target is None,
    target_path_cache_element: None,
    target_path_cache_value: b"",
  }
}

///|
/// The lazy `hitTestResult` (mouseTarget.ts:420).
fn HitTestRequest::hit_test_result(self : HitTestRequest) -> HitTestResult {
  match self.hit_test_result_cache {
    Some(result) => result
    None => {
      let result = do_hit_test(self.ctx, self)
      self.hit_test_result_cache = Some(result)
      result
    }
  }
}

///|
fn HitTestRequest::target(self : HitTestRequest) -> @rdom.Element? {
  if self.use_hit_test_target {
    return self.hit_test_result().hit_target()
  }
  self.event_target
}

///|
fn HitTestRequest::target_path(self : HitTestRequest) -> Bytes {
  let target = self.target()
  let cache_valid = match (self.target_path_cache_element, target) {
    (Some(cached), Some(current)) => cached.is_same_node(current.as_node())
    (None, None) => true
    _ => false
  }
  if !cache_valid {
    self.target_path_cache_element = target
    self.target_path_cache_value = @view.PartFingerprint::collect(
      target,
      self.ctx.view_dom_node,
    )
  }
  self.target_path_cache_value
}

///|
fn HitTestRequest::would_benefit_from_hit_test_target_switch(
  self : HitTestRequest,
) -> Bool {
  guard !self.use_hit_test_target else { return false }
  guard self.hit_test_result().hit_target() is Some(hit_target) else {
    return false
  }
  match self.target() {
    Some(target) => !target.is_same_node(hit_target.as_node())
    None => true
  }
}

///|
fn HitTestRequest::switch_to_hit_test_target(self : HitTestRequest) -> Unit {
  self.use_hit_test_target = true
}

///|
/// `HitTestRequest._getMouseColumn` (mouseTarget.ts:466-472): on lines with
/// foreign decorations the clamped position under-reports, so re-derive the
/// visual column from the line content.
fn HitTestRequest::get_mouse_column(
  self : HitTestRequest,
  position? : @base_common.Position,
) -> Int {
  match position {
    Some(position) =>
      if position.column <
        self.ctx.view_model.get_line_max_column(position.line_number) {
        // Most likely, the line contains foreign decorations...
        return @core.visible_column_from_column(
            self.ctx.view_model.get_line_content(position.line_number),
            position.column,
            self.ctx.view_model.options.tab_size,
          ) +
          1
      }
    None => ()
  }
  self.mouse_column
}

///|
fn HitTestRequest::fulfill_unknown(
  self : HitTestRequest,
  position? : @base_common.Position,
) -> @editor_browser.MouseTarget {
  @editor_browser.MouseTarget::create_unknown(
    self.target(),
    self.get_mouse_column(position?),
    position,
  )
}

///|
fn HitTestRequest::fulfill_margin(
  self : HitTestRequest,
  type_ : @editor_browser.MouseTargetType,
  position : @base_common.Position,
  range : @base_common.Range,
  detail : @editor_browser.MouseTargetMarginData,
) -> @editor_browser.MouseTarget {
  @editor_browser.MouseTarget::create_margin(
    type_,
    self.target(),
    self.get_mouse_column(position~),
    position,
    range,
    detail,
  )
}

///|
fn HitTestRequest::fulfill_view_zone(
  self : HitTestRequest,
  type_ : @editor_browser.MouseTargetType,
  position : @base_common.Position,
  detail : @editor_browser.MouseTargetViewZoneData,
) -> @editor_browser.MouseTarget {
  // Always return the usual mouse column for a view zone.
  @editor_browser.MouseTarget::create_view_zone(
    type_,
    self.target(),
    self.get_mouse_column(),
    position,
    detail,
  )
}

///|
fn HitTestRequest::fulfill_content_text(
  self : HitTestRequest,
  position : @base_common.Position,
  range : @base_common.Range?,
  detail : @editor_browser.MouseTargetContentTextData,
) -> @editor_browser.MouseTarget {
  @editor_browser.MouseTarget::create_content_text(
    self.target(),
    self.get_mouse_column(position~),
    position,
    range,
    detail,
  )
}

///|
fn HitTestRequest::fulfill_content_empty(
  self : HitTestRequest,
  position : @base_common.Position,
  detail : @editor_browser.MouseTargetContentEmptyData,
) -> @editor_browser.MouseTarget {
  @editor_browser.MouseTarget::create_content_empty(
    self.target(),
    self.get_mouse_column(position~),
    position,
    detail,
  )
}

///|
fn HitTestRequest::fulfill_content_widget(
  self : HitTestRequest,
  detail : String,
) -> @editor_browser.MouseTarget {
  @editor_browser.MouseTarget::create_content_widget(
    self.target(),
    self.get_mouse_column(),
    detail,
  )
}

///|
fn HitTestRequest::fulfill_scrollbar(
  self : HitTestRequest,
  position : @base_common.Position,
) -> @editor_browser.MouseTarget {
  @editor_browser.MouseTarget::create_scrollbar(
    self.target(),
    self.get_mouse_column(position~),
    position,
  )
}

///|
fn HitTestRequest::fulfill_overlay_widget(
  self : HitTestRequest,
  detail : String,
) -> @editor_browser.MouseTarget {
  @editor_browser.MouseTarget::create_overlay_widget(
    self.target(),
    self.get_mouse_column(),
    detail,
  )
}

///|
/// `EMPTY_CONTENT_AFTER_LINES` (mouseTarget.ts:508).
fn empty_content_after_lines() -> @editor_browser.MouseTargetContentEmptyData {
  { is_after_lines: true, horizontal_distance_to_text: None, }
}

///|
/// `createEmptyContentDataInLines` (mouseTarget.ts:510-515).
fn create_empty_content_data_in_lines(
  horizontal_distance_to_text : Double,
) -> @editor_browser.MouseTargetContentEmptyData {
  {
    is_after_lines: false,
    horizontal_distance_to_text: Some(horizontal_distance_to_text),
  }
}

///|
/// `MouseTargetFactory` (mouseTarget.ts:517-1114). Monaco holds a
/// `ViewContext` + `IPointerHandlerHelper`; the helper substitutes for both
/// here.
priv struct MouseTargetFactory {
  view_helper : PointerHandlerHelper
}

///|
fn MouseTargetFactory::MouseTargetFactory(
  view_helper : PointerHandlerHelper,
) -> MouseTargetFactory {
  { view_helper, }
}

///|
/// `mouseTargetIsWidget` (mouseTarget.ts:527-542).
fn MouseTargetFactory::mouse_target_is_widget(
  self : MouseTargetFactory,
  e : @editor_browser.EditorDomMouseEvent,
) -> Bool {
  let path = @view.PartFingerprint::collect(
    e.target,
    self.view_helper.view_dom_node,
  )
  // Is it a content widget?
  if ElementPath::is_child_of_content_widgets(path) ||
    ElementPath::is_child_of_overflowing_content_widgets(path) {
    return true
  }
  // Is it an overlay widget?
  if ElementPath::is_child_of_overlay_widgets(path) ||
    ElementPath::is_child_of_overflowing_overlay_widgets(path) {
    return true
  }
  false
}

///|
/// `createMouseTarget` (mouseTarget.ts:544-565). The sticky-tab-stop snap and
/// the `try/catch` are omitted (header). The detached-viewer arm (`None`
/// view model) has no Monaco counterpart — the source's view always has a
/// model.
fn MouseTargetFactory::create_mouse_target(
  self : MouseTargetFactory,
  last_render_data : PointerHandlerLastRenderData,
  editor_pos : @editor_browser.EditorPagePosition,
  pos : @editor_browser.PageCoordinates,
  relative_pos : @editor_browser.CoordinatesRelativeToEditor,
  target : @rdom.Element?,
) -> @editor_browser.MouseTarget {
  guard (self.view_helper.view_model)() is Some(view_model) else {
    return @editor_browser.MouseTarget::create_unknown(target, 1, None)
  }
  let ctx = HitTestContext(view_model, self.view_helper, last_render_data)
  let request = HitTestRequest(ctx, editor_pos, pos, relative_pos, target)
  create_mouse_target_for_request(ctx, request)
}

///|
/// `_createMouseTarget` (mouseTarget.ts:567-598): the dispatch chain. Order
/// matters.
fn create_mouse_target_for_request(
  ctx : HitTestContext,
  request : HitTestRequest,
) -> @editor_browser.MouseTarget {
  guard request.target() is Some(_) else {
    // No target
    return request.fulfill_unknown()
  }
  let path = request.target_path()
  if !ElementPath::is_child_of_overflow_guard(path) &&
    !ElementPath::is_child_of_overflowing_content_widgets(path) &&
    !ElementPath::is_child_of_overflowing_overlay_widgets(path) {
    // We only render dom nodes inside the overflow guard or in the
    // overflowing content widgets
    return request.fulfill_unknown()
  }
  let hit_tests : Array[
    (HitTestContext, HitTestRequest) -> @editor_browser.MouseTarget?,
  ] = [
    hit_test_content_widget, hit_test_overlay_widget, hit_test_minimap, hit_test_scrollbar_slider,
    hit_test_view_zone, hit_test_margin, hit_test_view_cursor, hit_test_view_lines,
    hit_test_scrollbar,
  ]
  for hit_test in hit_tests {
    if hit_test(ctx, request) is Some(result) {
      return result
    }
  }
  request.fulfill_unknown()
}

///|
/// `_hitTestContentWidget` (mouseTarget.ts:600-611).
fn hit_test_content_widget(
  ctx : HitTestContext,
  request : HitTestRequest,
) -> @editor_browser.MouseTarget? {
  // Is it a content widget?
  if ElementPath::is_child_of_content_widgets(request.target_path()) ||
    ElementPath::is_child_of_overflowing_content_widgets(request.target_path()) {
    guard request.target() is Some(target) else { return None }
    match ctx.find_attribute(target, "widgetId") {
      Some(widget_id) => return Some(request.fulfill_content_widget(widget_id))
      None => return Some(request.fulfill_unknown())
    }
  }
  None
}

///|
/// `_hitTestOverlayWidget` (mouseTarget.ts:613-624).
fn hit_test_overlay_widget(
  ctx : HitTestContext,
  request : HitTestRequest,
) -> @editor_browser.MouseTarget? {
  // Is it an overlay widget?
  if ElementPath::is_child_of_overlay_widgets(request.target_path()) ||
    ElementPath::is_child_of_overflowing_overlay_widgets(request.target_path()) {
    guard request.target() is Some(target) else { return None }
    match ctx.find_attribute(target, "widgetId") {
      Some(widget_id) => return Some(request.fulfill_overlay_widget(widget_id))
      None => return Some(request.fulfill_unknown())
    }
  }
  None
}

///|
/// `_hitTestViewCursor` (mouseTarget.ts:626-673).
fn hit_test_view_cursor(
  ctx : HitTestContext,
  request : HitTestRequest,
) -> @editor_browser.MouseTarget? {
  match request.target() {
    Some(target) => {
      // Check if we've hit a painted cursor
      let last_view_cursors_render_data = ctx.last_render_data.last_view_cursors_render_data
      for d in last_view_cursors_render_data {
        if target.is_same_node(d.dom_node.as_node()) {
          return Some(
            request.fulfill_content_text(d.position, None, {
              might_be_foreign_element: false,
              injected_text: None,
            }),
          )
        }
      }
    }
    None => ()
  }
  if request.is_in_content_area {
    // Edge has a bug when hit-testing the exact position of a cursor,
    // instead of returning the correct dom node, it returns the
    // first or last rendered view line dom node, therefore help it out
    // and first check if we are on top of a cursor
    let last_view_cursors_render_data = ctx.last_render_data.last_view_cursors_render_data
    let mouse_content_horizontal_offset = request.mouse_content_horizontal_offset
    let mouse_vertical_offset = request.mouse_vertical_offset
    for d in last_view_cursors_render_data {
      if mouse_content_horizontal_offset < d.content_left {
        // mouse position is to the left of the cursor
        continue
      }
      if mouse_content_horizontal_offset > d.content_left + d.width {
        // mouse position is to the right of the cursor
        continue
      }
      let cursor_vertical_offset = ctx.get_vertical_offset_for_line_number(
        d.position.line_number,
      )
      if cursor_vertical_offset <= mouse_vertical_offset &&
        mouse_vertical_offset <= cursor_vertical_offset + d.height.to_double() {
        return Some(
          request.fulfill_content_text(d.position, None, {
            might_be_foreign_element: false,
            injected_text: None,
          }),
        )
      }
    }
  }
  None
}

///|
/// `_hitTestViewZone` (mouseTarget.ts:675-683).
fn hit_test_view_zone(
  ctx : HitTestContext,
  request : HitTestRequest,
) -> @editor_browser.MouseTarget? {
  match ctx.get_zone_at_coord(request.mouse_vertical_offset) {
    Some(view_zone_data) => {
      let mouse_target_type : @editor_browser.MouseTargetType = if request.is_in_content_area {
        ContentViewZone
      } else {
        GutterViewZone
      }
      Some(
        request.fulfill_view_zone(
          mouse_target_type,
          view_zone_data.position,
          view_zone_data,
        ),
      )
    }
    None => None
  }
}

///|
/// `_hitTestMargin` (mouseTarget.ts:696-730). The glyph-margin lane lookup is
/// omitted (no glyph margin lanes; its width is 0 — header).
fn hit_test_margin(
  ctx : HitTestContext,
  request : HitTestRequest,
) -> @editor_browser.MouseTarget? {
  if request.is_in_margin_area {
    let (range, is_after_lines) = ctx.get_full_line_range_at_coord(
      request.mouse_vertical_offset,
    )
    let pos = range.get_start_position()
    let mut offset = request.relative_pos.x.abs()
    let detail : @editor_browser.MouseTargetMarginData = {
      is_after_lines,
      glyph_margin_left: ctx.layout_info.glyph_margin_left,
      glyph_margin_width: ctx.layout_info.glyph_margin_width,
      line_numbers_width: ctx.layout_info.line_numbers_width,
      offset_x: offset,
    }
    offset -= ctx.layout_info.glyph_margin_left
    if offset <= ctx.layout_info.glyph_margin_width {
      // On the glyph margin
      return Some(request.fulfill_margin(GutterGlyphMargin, pos, range, detail))
    }
    offset -= ctx.layout_info.glyph_margin_width
    if offset <= ctx.layout_info.line_numbers_width {
      // On the line numbers
      return Some(request.fulfill_margin(GutterLineNumbers, pos, range, detail))
    }
    // On the line decorations
    return Some(
      request.fulfill_margin(GutterLineDecorations, pos, range, detail),
    )
  }
  None
}

///|
/// `_hitTestViewLines` (mouseTarget.ts:732-822), sans the RTL and
/// `viewLinesGpu` branches (header).
fn hit_test_view_lines(
  ctx : HitTestContext,
  request : HitTestRequest,
) -> @editor_browser.MouseTarget? {
  if !ElementPath::is_child_of_view_lines(request.target_path()) {
    return None
  }
  if ctx.is_in_top_padding(request.mouse_vertical_offset) {
    return Some(
      request.fulfill_content_empty(Position(1, 1), empty_content_after_lines()),
    )
  }
  // Check if it is below any lines and any view zones
  if ctx.is_after_lines(request.mouse_vertical_offset) ||
    ctx.is_in_bottom_padding(request.mouse_vertical_offset) {
    // This most likely indicates it happened after the last view-line
    let line_count = ctx.view_model.line_count()
    let max_line_column = ctx.view_model.get_line_max_column(line_count)
    return Some(
      request.fulfill_content_empty(
        Position(line_count, max_line_column),
        empty_content_after_lines(),
      ),
    )
  }
  // Check if we are hitting a view-line (can happen in the case of inline
  // decorations on empty lines)
  // See https://github.com/microsoft/vscode/issues/46942
  if ElementPath::is_strict_child_of_view_lines(request.target_path()) {
    let line_number = ctx.get_line_number_at_vertical_offset(
      request.mouse_vertical_offset,
    )
    let line_length = ctx.view_model.get_line_length(line_number)
    let line_width = ctx.get_line_width(line_number)
    if line_length == 0 {
      let detail = create_empty_content_data_in_lines(
        request.mouse_content_horizontal_offset - line_width,
      )
      return Some(
        request.fulfill_content_empty(Position(line_number, 1), detail),
      )
    }
    if request.mouse_content_horizontal_offset >= line_width {
      let detail = create_empty_content_data_in_lines(
        request.mouse_content_horizontal_offset - line_width,
      )
      let pos : @base_common.Position = Position(
        line_number,
        ctx.view_model.get_line_max_column(line_number),
      )
      return Some(request.fulfill_content_empty(pos, detail))
    }
  }
  // Do the hit test (if not already done)
  match request.hit_test_result() {
    ContentHitTestResult(position~, span_node~, injected_text~) =>
      return Some(
        create_mouse_target_from_hit_test_position(
          ctx, request, span_node, position, injected_text,
        ),
      )
    UnknownHitTestResult(_) => ()
  }
  // We didn't hit content...
  if request.would_benefit_from_hit_test_target_switch() {
    // We actually hit something different... Give it one last change by
    // trying again with this new target
    request.switch_to_hit_test_target()
    return Some(create_mouse_target_for_request(ctx, request))
  }
  // We have tried everything...
  Some(request.fulfill_unknown())
}

///|
/// `_hitTestMinimap` (mouseTarget.ts:824-831). Dead in this viewer (no
/// minimap part writes the fingerprint) but kept 1:1.
fn hit_test_minimap(
  ctx : HitTestContext,
  request : HitTestRequest,
) -> @editor_browser.MouseTarget? {
  if ElementPath::is_child_of_minimap(request.target_path()) {
    let possible_line_number = ctx.get_line_number_at_vertical_offset(
      request.mouse_vertical_offset,
    )
    let max_column = ctx.view_model.get_line_max_column(possible_line_number)
    return Some(
      request.fulfill_scrollbar(Position(possible_line_number, max_column)),
    )
  }
  None
}

///|
/// `_hitTestScrollbarSlider` (mouseTarget.ts:833-845).
fn hit_test_scrollbar_slider(
  ctx : HitTestContext,
  request : HitTestRequest,
) -> @editor_browser.MouseTarget? {
  if ElementPath::is_child_of_scrollable_element(request.target_path()) &&
    request.target() is Some(target) {
    let class_name = controller_element_class_name(target)
    if class_name_has_word(class_name, "slider") ||
      class_name_has_word(class_name, "scrollbar") {
      let possible_line_number = ctx.get_line_number_at_vertical_offset(
        request.mouse_vertical_offset,
      )
      let max_column = ctx.view_model.get_line_max_column(possible_line_number)
      return Some(
        request.fulfill_scrollbar(Position(possible_line_number, max_column)),
      )
    }
  }
  None
}

///|
/// `_hitTestScrollbar` (mouseTarget.ts:847-857).
fn hit_test_scrollbar(
  ctx : HitTestContext,
  request : HitTestRequest,
) -> @editor_browser.MouseTarget? {
  // Is it a child of the scrollable element?
  if ElementPath::is_child_of_scrollable_element(request.target_path()) {
    let possible_line_number = ctx.get_line_number_at_vertical_offset(
      request.mouse_vertical_offset,
    )
    let max_column = ctx.view_model.get_line_max_column(possible_line_number)
    return Some(
      request.fulfill_scrollbar(Position(possible_line_number, max_column)),
    )
  }
  None
}

///|
/// `getMouseColumn` (mouseTarget.ts:859-864).
fn MouseTargetFactory::get_mouse_column(
  self : MouseTargetFactory,
  relative_pos : @editor_browser.CoordinatesRelativeToEditor,
) -> Int {
  let layout_info = (self.view_helper.get_layout_info)()
  let font_info = (self.view_helper.get_font_info)()
  let scroll_left = match (self.view_helper.view_model)() {
    Some(view_model) => view_model.view_layout.get_current_scroll_left()
    None => 0.0
  }
  let mouse_content_horizontal_offset = scroll_left +
    relative_pos.x -
    layout_info.content_left
  get_mouse_column_static(
    mouse_content_horizontal_offset,
    font_info.typical_halfwidth_character_width,
  )
}

///|
/// static `MouseTargetFactory._getMouseColumn` (mouseTarget.ts:866-872).
fn get_mouse_column_static(
  mouse_content_horizontal_offset : Double,
  typical_halfwidth_character_width : Double,
) -> Int {
  if mouse_content_horizontal_offset < 0.0 {
    return 1
  }
  let chars = (mouse_content_horizontal_offset /
  typical_halfwidth_character_width +
  0.5).floor()
  chars.to_int() + 1
}

///|
/// `createMouseTargetFromHitTestPosition` (mouseTarget.ts:874-948): the
/// sub-pixel refinement of a caret hit into an exact column (or a
/// content-empty target past the rendered width).
fn create_mouse_target_from_hit_test_position(
  ctx : HitTestContext,
  request : HitTestRequest,
  span_node : @rdom.Element,
  pos : @base_common.Position,
  injected_text : @view_model.InjectedText?,
) -> @editor_browser.MouseTarget {
  let line_number = pos.line_number
  let column = pos.column
  let line_width = ctx.get_line_width(line_number)
  if request.mouse_content_horizontal_offset > line_width {
    let detail = create_empty_content_data_in_lines(
      request.mouse_content_horizontal_offset - line_width,
    )
    return request.fulfill_content_empty(pos, detail)
  }
  guard ctx.visible_range_for_position(line_number, column)
    is Some(visible_range) else {
    return request.fulfill_unknown(position=pos)
  }
  let column_horizontal_offset = visible_range.left.to_double()
  if (request.mouse_content_horizontal_offset - column_horizontal_offset).abs() <
    1.0 {
    return request.fulfill_content_text(pos, None, {
      might_be_foreign_element: injected_text is Some(_),
      injected_text,
    })
  }
  // Let's define a, b, c and check if the offset is in between them...
  let points : Array[(Double, Int)] = [] // (offset, column)
  points.push((visible_range.left.to_double(), column))
  if column > 1 &&
    ctx.visible_range_for_position(line_number, column - 1)
    is Some(visible_range) {
    points.push((visible_range.left.to_double(), column - 1))
  }
  let line_max_column = ctx.view_model.get_line_max_column(line_number)
  if column < line_max_column &&
    ctx.visible_range_for_position(line_number, column + 1)
    is Some(visible_range) {
    points.push((visible_range.left.to_double(), column + 1))
  }
  points.sort_by_key(p => p.0)
  let mouse_coordinates = request.pos.to_client_coordinates()
  let span_node_client_rect = span_node.get_bounding_client_rect()
  let mouse_is_over_span_node = span_node_client_rect.get_left() <=
    mouse_coordinates.client_x &&
    mouse_coordinates.client_x <= span_node_client_rect.get_right()
  let mut rng : @base_common.Range? = None
  let mut resolved_pos = pos
  for i in 1..<points.length() {
    let prev = points[i - 1]
    let curr = points[i]
    if prev.0 <= request.mouse_content_horizontal_offset &&
      request.mouse_content_horizontal_offset <= curr.0 {
      rng = Some(Range(line_number, prev.1, line_number, curr.1))

      // See https://github.com/microsoft/vscode/issues/152819
      // Due to the use of zwj, the browser's hit test result is skewed
      // towards the left. Here we try to correct that if the mouse
      // horizontal offset is closer to the right than the left
      let prev_delta = (prev.0 - request.mouse_content_horizontal_offset).abs()
      let next_delta = (curr.0 - request.mouse_content_horizontal_offset).abs()
      resolved_pos = if prev_delta < next_delta {
        Position(line_number, prev.1)
      } else {
        Position(line_number, curr.1)
      }
      break
    }
  }
  request.fulfill_content_text(resolved_pos, rng, {
    might_be_foreign_element: !mouse_is_over_span_node ||
    injected_text is Some(_),
    injected_text,
  })
}

///|
/// `_doHitTestWithCaretRangeFromPoint` (mouseTarget.ts:953-987): adjust the
/// probe y to the line's vertical center first (Chrome on Linux can land
/// between lines), falling back to the unadjusted position.
fn do_hit_test_with_caret_range_from_point(
  ctx : HitTestContext,
  request : HitTestRequest,
) -> HitTestResult {
  let line_number = ctx.get_line_number_at_vertical_offset(
    request.mouse_vertical_offset,
  )
  let line_start_vertical_offset = ctx.get_vertical_offset_for_line_number(
    line_number,
  )
  let line_end_vertical_offset = line_start_vertical_offset +
    ctx.line_height.to_double()
  let is_below_last_line = line_number == ctx.view_model.line_count() &&
    request.mouse_vertical_offset > line_end_vertical_offset
  if !is_below_last_line {
    let line_centered_vertical_offset = ((
      line_start_vertical_offset + line_end_vertical_offset
    ) /
    2.0).floor()
    let mut adjusted_page_y = request.pos.y +
      (line_centered_vertical_offset - request.mouse_vertical_offset)
    if adjusted_page_y <= request.editor_pos.y {
      adjusted_page_y = request.editor_pos.y + 1.0
    }
    if adjusted_page_y >= request.editor_pos.y + request.editor_pos.height {
      adjusted_page_y = request.editor_pos.y + request.editor_pos.height - 1.0
    }
    let adjusted_page : @editor_browser.PageCoordinates = {
      x: request.pos.x,
      y: adjusted_page_y,
    }
    let r = actual_do_hit_test_with_caret_range_from_point(
      ctx,
      adjusted_page.to_client_coordinates(),
    )
    if r is ContentHitTestResult(_) {
      return r
    }
  }
  // Also try to hit test without the adjustment (for the edge cases that we
  // are near the top or bottom)
  actual_do_hit_test_with_caret_range_from_point(
    ctx,
    request.pos.to_client_coordinates(),
  )
}

///|
/// `_actualDoHitTestWithCaretRangeFromPoint` (mouseTarget.ts:989-1038), sans
/// the shadow-root branch (header). Chrome always hits a TEXT_NODE, while
/// Edge sometimes hits a token span.
fn actual_do_hit_test_with_caret_range_from_point(
  ctx : HitTestContext,
  coords : @editor_browser.ClientCoordinates,
) -> HitTestResult {
  let hit = native_caret_range_from_point(
    ctx.view_dom_node,
    coords.client_x,
    coords.client_y,
  )
  if !native_caret_hit_ok(hit) {
    return UnknownHitTestResult(hit_target=None)
  }
  let start_container = native_caret_hit_node(hit)
  if node_is_text(start_container) {
    // startContainer is expected to be the token text
    let parent1 = node_parent_element(start_container) // the token span
    // the view line container span
    let parent2 = parent1.bind(controller_parent_element)
    // the view line div
    let parent3 = parent2.bind(controller_parent_element)
    let parent3_class_name = parent3.map_or("", controller_element_class_name)
    if parent3_class_name == @view.VIEW_LINE_CLASS_NAME {
      return hit_test_result_from_dom_info(
        ctx,
        parent1.unwrap(),
        native_caret_hit_offset(hit),
      )
    } else {
      return UnknownHitTestResult(
        hit_target=node_parent_element(start_container),
      )
    }
  } else if node_is_element(start_container) {
    // startContainer is expected to be the token span
    let start_element = start_container.to_element().unwrap()
    let parent1 = controller_parent_element(start_element) // the view line container span
    // the view line div
    let parent2 = parent1.bind(controller_parent_element)
    let parent2_class_name = parent2.map_or("", controller_element_class_name)
    if parent2_class_name == @view.VIEW_LINE_CLASS_NAME {
      return hit_test_result_from_dom_info(
        ctx,
        start_element,
        controller_text_content_length(start_element),
      )
    } else {
      return UnknownHitTestResult(hit_target=Some(start_element))
    }
  }
  UnknownHitTestResult(hit_target=None)
}

///|
/// `_doHitTestWithCaretPositionFromPoint` (mouseTarget.ts:1043-1082) —
/// Gecko.
fn do_hit_test_with_caret_position_from_point(
  ctx : HitTestContext,
  coords : @editor_browser.ClientCoordinates,
) -> HitTestResult {
  let hit = native_caret_position_from_point(
    ctx.view_dom_node,
    coords.client_x,
    coords.client_y,
  )
  if !native_caret_hit_ok(hit) {
    return UnknownHitTestResult(hit_target=None)
  }
  let offset_node = native_caret_hit_node(hit)
  if node_is_text(offset_node) {
    // offsetNode is expected to be the token text
    let parent1 = node_parent_element(offset_node) // the token span
    // the view line container span
    let parent2 = parent1.bind(controller_parent_element)
    // the view line div
    let parent3 = parent2.bind(controller_parent_element)
    let parent3_class_name = parent3.map_or("", controller_element_class_name)
    if parent3_class_name == @view.VIEW_LINE_CLASS_NAME {
      return hit_test_result_from_dom_info(
        ctx,
        parent1.unwrap(),
        native_caret_hit_offset(hit),
      )
    } else {
      return UnknownHitTestResult(hit_target=node_parent_element(offset_node))
    }
  }
  // For inline decorations, Gecko sometimes returns the `<span>` of the line
  // and the offset is the `<span>` with the inline decoration. Some other
  // times, it returns the `<span>` with the inline decoration
  if node_is_element(offset_node) {
    let offset_element = offset_node.to_element().unwrap()
    let parent1 = controller_parent_element(offset_element)
    let parent1_class_name = parent1.map_or("", controller_element_class_name)
    let parent2 = parent1.bind(controller_parent_element)
    let parent2_class_name = parent2.map_or("", controller_element_class_name)
    if parent1_class_name == @view.VIEW_LINE_CLASS_NAME {
      // it returned the `<span>` of the line and the offset is the `<span>`
      // with the inline decoration
      let child_count = offset_node.get_child_count()
      let child_index = native_caret_hit_offset(hit).min(child_count - 1)
      if child_index >= 0 &&
        offset_node.get_child(child_index).to_element() is Some(token_span) {
        return hit_test_result_from_dom_info(ctx, token_span, 0)
      }
    } else if parent2_class_name == @view.VIEW_LINE_CLASS_NAME {
      // it returned the `<span>` with the inline decoration
      return hit_test_result_from_dom_info(ctx, offset_element, 0)
    }
  }
  UnknownHitTestResult(hit_target=offset_node.to_element())
}

///|
/// `doHitTest` (mouseTarget.ts:1094-1113): feature-detect the caret API,
/// then normalize the answer through the view model (injected text snaps to
/// a cursor stop with affinity `None`).
fn do_hit_test(ctx : HitTestContext, request : HitTestRequest) -> HitTestResult {
  let mut result : HitTestResult = UnknownHitTestResult(hit_target=None)
  if caret_range_from_point_supported(ctx.view_dom_node) {
    result = do_hit_test_with_caret_range_from_point(ctx, request)
  } else if caret_position_from_point_supported(ctx.view_dom_node) {
    result = do_hit_test_with_caret_position_from_point(
      ctx,
      request.pos.to_client_coordinates(),
    )
  }
  match result {
    ContentHitTestResult(position~, span_node~, ..) => {
      let injected_text = ctx.view_model.get_injected_text_at(position)
      let affinity : @model.PositionAffinity = None
      let normalized_position = ctx.view_model.normalize_position(
        position, affinity,
      )
      if injected_text is Some(_) || !normalized_position.equals(position) {
        result = ContentHitTestResult(
          position=normalized_position,
          span_node~,
          injected_text~,
        )
      }
    }
    UnknownHitTestResult(_) => ()
  }
  result
}

///|
/// The source's `/\b(slider|scrollbar)\b/` test (mouseTarget.ts:837), as a
/// word-boundary check over space-separated class names.
fn class_name_has_word(class_name : String, word : String) -> Bool {
  for candidate in class_name.split(" ") {
    if candidate.to_owned() == word {
      return true
    }
  }
  false
}

///|
/// FFI gap-fills. The caret hit wrappers return a plain `{ok, node, offset}`
/// object; the DOM-tree classification walks stay in MoonBit above, 1:1 with
/// the source.
#external
priv type NativeCaretHit

///|
extern "js" fn caret_range_from_point_supported(el : @rdom.Element) -> Bool =
  #| (el) => typeof el.ownerDocument.caretRangeFromPoint === "function"

///|
extern "js" fn caret_position_from_point_supported(el : @rdom.Element) -> Bool =
  #| (el) => !!el.ownerDocument.caretPositionFromPoint

///|
extern "js" fn native_caret_range_from_point(
  el : @rdom.Element,
  client_x : Double,
  client_y : Double,
) -> NativeCaretHit =
  #| (el, x, y) => {
  #|   const range = el.ownerDocument.caretRangeFromPoint(x, y);
  #|   if (!range || !range.startContainer) {
  #|     return { ok: 0, node: null, offset: 0 };
  #|   }
  #|   return { ok: 1, node: range.startContainer, offset: range.startOffset };
  #| }

///|
extern "js" fn native_caret_position_from_point(
  el : @rdom.Element,
  client_x : Double,
  client_y : Double,
) -> NativeCaretHit =
  #| (el, x, y) => {
  #|   const pos = el.ownerDocument.caretPositionFromPoint(x, y);
  #|   if (!pos || !pos.offsetNode) {
  #|     return { ok: 0, node: null, offset: 0 };
  #|   }
  #|   return { ok: 1, node: pos.offsetNode, offset: pos.offset };
  #| }

///|
extern "js" fn native_caret_hit_ok(hit : NativeCaretHit) -> Bool =
  #| (h) => h.ok === 1

///|
extern "js" fn native_caret_hit_node(hit : NativeCaretHit) -> @rdom.Node =
  #| (h) => h.node

///|
extern "js" fn native_caret_hit_offset(hit : NativeCaretHit) -> Int =
  #| (h) => h.offset | 0

///|
extern "js" fn node_is_text(node : @rdom.Node) -> Bool =
  #| (n) => n.nodeType === 3

///|
extern "js" fn node_is_element(node : @rdom.Node) -> Bool =
  #| (n) => n.nodeType === 1

///|
extern "js" fn node_parent_element_raw(node : @rdom.Node) -> @rdom.Element =
  #| (n) => n.parentElement

///|
extern "js" fn node_has_parent_element(node : @rdom.Node) -> Bool =
  #| (n) => !!n.parentElement

///|
fn node_parent_element(node : @rdom.Node) -> @rdom.Element? {
  if node_has_parent_element(node) {
    Some(node_parent_element_raw(node))
  } else {
    None
  }
}

///|
extern "js" fn controller_parent_element_raw(
  el : @rdom.Element,
) -> @rdom.Element =
  #| (el) => el.parentElement

///|
extern "js" fn controller_has_parent_element(el : @rdom.Element) -> Bool =
  #| (el) => !!el.parentElement

///|
fn controller_parent_element(el : @rdom.Element) -> @rdom.Element? {
  if controller_has_parent_element(el) {
    Some(controller_parent_element_raw(el))
  } else {
    None
  }
}

///|
extern "js" fn controller_element_class_name(el : @rdom.Element) -> String =
  #| (el) => typeof el.className === "string" ? el.className : ""

///|
extern "js" fn controller_text_content_length(el : @rdom.Element) -> Int =
  #| (el) => (el.textContent || "").length

///|
extern "js" fn controller_is_document_body(el : @rdom.Element) -> Bool =
  #| (el) => el === el.ownerDocument.body

///|
extern "js" fn element_has_attribute(el : @rdom.Element, attr : String) -> Bool =
  #| (el, attr) => !!el.hasAttribute && el.hasAttribute(attr)
