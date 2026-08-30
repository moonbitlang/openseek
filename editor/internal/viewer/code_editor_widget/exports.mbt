///|
/// `getLineDecorations` (`codeEditorWidget.ts:1342-1348`): the model's line
/// query filtered by this viewer's editor id and its
/// `renderValidationDecorations` option.
pub fn CodeEditorWidget::get_line_decorations(
  self : CodeEditorWidget,
  line_number : Int,
) -> Array[@model.ModelDecoration] {
  guard self.get_model() is Some(model) else { return [] }
  model.get_line_decorations(
    line_number,
    owner_id=self.editor_id,
    filter_out_validation=@view_model.filter_validation_decorations(
      self.get_options().render_validation_decorations,
    ),
  )
}

///|
/// `getDecorationsInRange` (`codeEditorWidget.ts:1350-1356`).
pub fn CodeEditorWidget::get_decorations_in_range(
  self : CodeEditorWidget,
  range : @base_common.Range,
) -> Array[@model.ModelDecoration] {
  guard self.get_model() is Some(model) else { return [] }
  model.get_decorations_in_range(
    range,
    owner_id=self.editor_id,
    filter_out_validation=@view_model.filter_validation_decorations(
      self.get_options().render_validation_decorations,
    ),
  )
}

///|
/// Replaces all previous decorations with `new_decorations`; returns the new
/// ids.
pub fn EditorDecorationsCollection::set(
  self : EditorDecorationsCollection,
  new_decorations : Array[@model.ModelDeltaDecoration],
) -> Array[String] {
  self.decoration_ids = self.viewer.delta_decorations(
    self.decoration_ids,
    new_decorations,
  )
  self.decoration_ids
}

///|
/// Appends `new_decorations` to the collection; returns the appended ids.
pub fn EditorDecorationsCollection::append(
  self : EditorDecorationsCollection,
  new_decorations : Array[@model.ModelDeltaDecoration],
) -> Array[String] {
  let appended = self.viewer.delta_decorations([], new_decorations)
  self.decoration_ids += appended
  appended
}

///|
/// The decoration count.
pub fn EditorDecorationsCollection::length(
  self : EditorDecorationsCollection,
) -> Int {
  self.decoration_ids.length()
}

///|
/// The current model range of the `index`-th decoration, `None` when the
/// index is out of bounds or the decoration no longer resolves.
pub fn EditorDecorationsCollection::get_range(
  self : EditorDecorationsCollection,
  index : Int,
) -> @base_common.Range? {
  guard index >= 0 && index < self.decoration_ids.length() else { return None }
  guard self.viewer.get_model() is Some(model) else { return None }
  model.get_decoration_range(self.decoration_ids[index])
}

///|
/// The current model ranges of every decoration that still resolves.
pub fn EditorDecorationsCollection::get_ranges(
  self : EditorDecorationsCollection,
) -> Array[@base_common.Range] {
  guard self.viewer.get_model() is Some(model) else { return [] }
  let ranges = []
  for id in self.decoration_ids {
    match model.get_decoration_range(id) {
      Some(range) => ranges.push(range)
      None => ()
    }
  }
  ranges
}

///|
/// Fires on editor mouseup with the hit-tested target — Monaco's
/// `onMouseUp`.
pub fn CodeEditorWidget::on_mouse_up(
  self : CodeEditorWidget,
  listener : (@editor_browser.EditorMouseEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_mouse_up.event(listener)
}

///|
/// Fires on editor mousemove with the hit-tested target — Monaco's
/// `onMouseMove`.
pub fn CodeEditorWidget::on_mouse_move(
  self : CodeEditorWidget,
  listener : (@editor_browser.EditorMouseEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_mouse_move.event(listener)
}

///|
/// Fires on an editor context-menu gesture with the hit-tested target —
/// Monaco's `onContextMenu`.
pub fn CodeEditorWidget::on_context_menu(
  self : CodeEditorWidget,
  listener : (@editor_browser.EditorMouseEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_context_menu.event(listener)
}

///|
/// Fires when the pointer leaves the editor — Monaco's `onMouseLeave`
/// (`IPartialEditorMouseEvent`; the target is always `None` for leaves).
pub fn CodeEditorWidget::on_mouse_leave(
  self : CodeEditorWidget,
  listener : (@editor_browser.PartialEditorMouseEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_mouse_leave.event(listener)
}

///|
/// Fires after a changed hidden-area mapping has completed its internal view
/// events, cursor/decorations reprojection, layout, and viewport recovery.
pub fn CodeEditorWidget::on_did_change_hidden_areas(
  self : CodeEditorWidget,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.did_change_hidden_areas.event(_ => listener())
}

///|
/// The editor type marker, Monaco's `getEditorType()` →
/// `EditorType.ICodeEditor`.
pub fn CodeEditorWidget::get_editor_type(self : CodeEditorWidget) -> String {
  ignore(self)
  "vs.editor.ICodeEditor"
}

///|
/// Whether focus is anywhere inside the editor widget, including hover
/// widgets — `hasWidgetFocus()`.
pub fn CodeEditorWidget::has_widget_focus(self : CodeEditorWidget) -> Bool {
  match self.current_code_browser_data() {
    Some(presentation) =>
      self.has_text_focus() || presentation.contains_active_element()
    None => false
  }
}

///|
/// Sets all cursor selections — Monaco's `setSelections`
/// (`codeEditorWidget.ts:832-849`). The viewer is single-selection (a
/// documented scope cut, see `get_selections`), so the primary selection is
/// applied and any secondaries are dropped. Like Monaco, an empty array is
/// rejected as a no-op (Monaco throws an "Invalid arguments" error there; the
/// readonly viewer's mutators never throw).
pub fn CodeEditorWidget::set_selections(
  self : CodeEditorWidget,
  selections : Array[@core.Selection],
  source? : String = "api",
  reason? : @editor_api.CursorChangeReason = NotSet,
) -> Unit {
  guard selections.length() > 0 else { return }
  guard self.is_code_presentation() else { return }
  guard self.get_view_model() is Some(view_model) else { return }
  let states = @cursor.CursorState::from_model_selections(selections)
  // The source converts every selection in order before `setStates`; this
  // readonly viewer then applies the first and drops secondaries at its
  // documented single-cursor boundary.
  view_model.set_cursor_state(Some(states[0]), source, reason) |> ignore
}

///|
/// Content-space top of a 1-based model position, Monaco's `getTopForPosition`
/// (`cew:600`) — always excludes the view zone directly above the line. No model
/// → `-1`.
pub fn CodeEditorWidget::get_top_for_position(
  self : CodeEditorWidget,
  line_number : Int,
  column : Int,
) -> Double {
  self.get_vertical_offset_for_position(
    line_number,
    column,
    include_view_zones=false,
  )
}

///|
/// Content-space bottom of a 1-based model line, Monaco's
/// `getBottomForLineNumber` (`cew:616`): the offset after the line, computed at
/// the line's max column (`Number.MAX_SAFE_INTEGER`, validated down). No model →
/// `-1`.
pub fn CodeEditorWidget::get_bottom_for_line_number(
  self : CodeEditorWidget,
  line_number : Int,
) -> Double {
  self.get_vertical_offset_after_position(
    line_number,
    max_safe_column,
    include_view_zones=false,
  )
}

///|
/// Pixel height of a 1-based model position's line, Monaco's
/// `getLineHeightForPosition` (`cew:623`). No model → `-1`; a position inside a
/// hidden region → `0`; otherwise the configured uniform line height.
/// Like Monaco the raw position is not validated before the visibility test.
pub fn CodeEditorWidget::get_line_height_for_position(
  self : CodeEditorWidget,
  position : @base_common.Position,
) -> Double {
  guard (self.get_model(), self.get_view_model()) is (Some(_), Some(view_model)) else {
    return -1.0
  }
  if view_model.model_position_is_visible(position) {
    let view_position = view_model
      .coordinates_converter()
      .model_position_to_view_position(position)
    view_model.view_layout
    .get_line_height_for_line_number(view_position.line_number)
    .to_double()
  } else {
    0.0
  }
}

///|
/// 1-based visible column of a model position (tabs expand to tab stops,
/// full-width/emoji count as two), Monaco's `getVisibleColumnFromPosition`
/// (`cew:641`): `visibleColumnFromColumn(...) + 1`. No model → the raw input
/// column (the load-bearing no-model sentinel, not `-1`).
pub fn CodeEditorWidget::get_visible_column_from_position(
  self : CodeEditorWidget,
  position : @base_common.Position,
) -> Int {
  guard self.get_model() is Some(model) else { return position.column }
  let position = model.validate_position(position)
  let tab_size = self.configuration.snapshot().options.tab_size
  @core.visible_column_from_column(
    model.get_line_content(position.line_number),
    position.column,
    tab_size,
  ) +
  1
}

///|
/// All cursor model selections, Monaco's `getSelections` (`cew:790`). The viewer
/// is single-selection, so this is a 1-element array (a documented prior scope
/// cut). No model → `null`.
pub fn CodeEditorWidget::get_selections(
  self : CodeEditorWidget,
) -> Array[@core.Selection]? {
  match self.get_selection() {
    Some(selection) => Some([selection])
    None => None
  }
}

///|
/// Reveals a 1-based model line, aligning its top into view (`Simple`).
pub fn CodeEditorWidget::reveal_line(
  self : CodeEditorWidget,
  line_number : Int,
) -> Unit {
  self.reveal_line_with(line_number, Simple)
}

///|
/// Reveals a 1-based model line, centering it (`Center`).
pub fn CodeEditorWidget::reveal_line_in_center(
  self : CodeEditorWidget,
  line_number : Int,
) -> Unit {
  self.reveal_line_with(line_number, Center)
}

///|
/// Reveals a 1-based model line near the top of the viewport (`NearTop`).
pub fn CodeEditorWidget::reveal_line_near_top(
  self : CodeEditorWidget,
  line_number : Int,
) -> Unit {
  self.reveal_line_with(line_number, NearTop)
}

///|
/// Reveals a 1-based model line centered only if it is currently outside the
/// viewport (`CenterIfOutsideViewport`).
pub fn CodeEditorWidget::reveal_line_in_center_if_outside_viewport(
  self : CodeEditorWidget,
  line_number : Int,
) -> Unit {
  self.reveal_line_with(line_number, CenterIfOutsideViewport)
}

///|
/// Reveals a model line span `[start, end]` (1-based), aligning its top
/// (`Simple`). Like Monaco's `revealLines`, this is a line-only reveal:
/// horizontal scroll is not adjusted.
pub fn CodeEditorWidget::reveal_lines(
  self : CodeEditorWidget,
  start_line_number : Int,
  end_line_number : Int,
) -> Unit {
  self.reveal_lines_with(start_line_number, end_line_number, Simple)
}

///|
/// Reveals a model line span `[start, end]` (1-based), centering it (`Center`).
pub fn CodeEditorWidget::reveal_lines_in_center(
  self : CodeEditorWidget,
  start_line_number : Int,
  end_line_number : Int,
) -> Unit {
  self.reveal_lines_with(start_line_number, end_line_number, Center)
}

///|
/// Reveals a model line span `[start, end]` (1-based) near the top (`NearTop`).
pub fn CodeEditorWidget::reveal_lines_near_top(
  self : CodeEditorWidget,
  start_line_number : Int,
  end_line_number : Int,
) -> Unit {
  self.reveal_lines_with(start_line_number, end_line_number, NearTop)
}

///|
/// Reveals a model line span `[start, end]` (1-based) centered only if it is
/// currently outside the viewport (`CenterIfOutsideViewport`).
pub fn CodeEditorWidget::reveal_lines_in_center_if_outside_viewport(
  self : CodeEditorWidget,
  start_line_number : Int,
  end_line_number : Int,
) -> Unit {
  self.reveal_lines_with(
    start_line_number,
    end_line_number,
    CenterIfOutsideViewport,
  )
}

///|
/// Reveals a 1-based model position centered (`Center`), horizontally too.
pub fn CodeEditorWidget::reveal_position_in_center(
  self : CodeEditorWidget,
  position : @base_common.Position,
) -> Unit {
  self.reveal_position_with(position, Center)
}

///|
/// Reveals a 1-based model position near the top (`NearTop`), horizontally too.
pub fn CodeEditorWidget::reveal_position_near_top(
  self : CodeEditorWidget,
  position : @base_common.Position,
) -> Unit {
  self.reveal_position_with(position, NearTop)
}

///|
/// Reveals a model `Range`, aligning its top (`Simple`) and revealing it
/// horizontally.
pub fn CodeEditorWidget::reveal_range(
  self : CodeEditorWidget,
  range : @base_common.Range,
) -> Unit {
  self.send_reveal_range(range, Simple, reveal_horizontal=true)
}

///|
/// Reveals a model `Range` centered (`Center`), horizontally too.
pub fn CodeEditorWidget::reveal_range_in_center(
  self : CodeEditorWidget,
  range : @base_common.Range,
) -> Unit {
  self.send_reveal_range(range, Center, reveal_horizontal=true)
}

///|
/// Reveals a model `Range` centered only if it is currently outside the
/// viewport (`CenterIfOutsideViewport`), horizontally too.
pub fn CodeEditorWidget::reveal_range_in_center_if_outside_viewport(
  self : CodeEditorWidget,
  range : @base_common.Range,
) -> Unit {
  self.send_reveal_range(range, CenterIfOutsideViewport, reveal_horizontal=true)
}

///|
/// Reveals a model `Range` near the top (`NearTop`), horizontally too.
pub fn CodeEditorWidget::reveal_range_near_top(
  self : CodeEditorWidget,
  range : @base_common.Range,
) -> Unit {
  self.send_reveal_range(range, NearTop, reveal_horizontal=true)
}

///|
/// Reveals a model `Range` near the top only if it is currently outside the
/// viewport (`NearTopIfOutsideViewport`), horizontally too.
pub fn CodeEditorWidget::reveal_range_near_top_if_outside_viewport(
  self : CodeEditorWidget,
  range : @base_common.Range,
) -> Unit {
  self.send_reveal_range(
    range,
    NearTopIfOutsideViewport,
    reveal_horizontal=true,
  )
}

///|
/// Reveals a model `Range` at the very top of the viewport (`Top`),
/// horizontally too.
pub fn CodeEditorWidget::reveal_range_at_top(
  self : CodeEditorWidget,
  range : @base_common.Range,
) -> Unit {
  self.send_reveal_range(range, Top, reveal_horizontal=true)
}
