///|
pub fn Viewer::set_model(self : Viewer, model : @model.TextModel?) -> Unit {
  self.widget.set_model(model)
}

///|
pub fn Viewer::get_model(self : Viewer) -> @model.TextModel? {
  self.widget.get_model()
}

///|
pub fn Viewer::set_value(self : Viewer, value : String) -> Unit {
  self.widget.set_value(value)
}

///|
pub fn Viewer::get_value(self : Viewer) -> String {
  self.widget.get_value()
}

///|
pub fn Viewer::update_options(self : Viewer, options : ViewerOptions) -> Unit {
  self.options = options
  self.widget.update_host_options(options.code_options())
}

///|
pub fn Viewer::get_options(self : Viewer) -> ViewerOptions {
  self.options
}

///|
pub fn Viewer::layout(self : Viewer) -> Unit {
  self.widget.layout()
}

///|
pub fn Viewer::focus(self : Viewer) -> Unit {
  self.widget.focus()
}

///|
pub fn Viewer::dispose(self : Viewer) -> Unit {
  self.widget.dispose()
}

///|
pub fn Viewer::handle_initialized(self : Viewer) -> Unit {
  self.widget.handle_initialized()
}

///|
pub fn Viewer::get_id(self : Viewer) -> String {
  self.widget.get_id()
}

///|
pub fn Viewer::get_dom_node(self : Viewer) -> @rdom.Element? {
  self.widget.get_dom_node()
}

///|
pub fn Viewer::get_container_dom_node(self : Viewer) -> @rdom.Element {
  self.widget.get_container_dom_node()
}

///|
pub fn Viewer::has_text_focus(self : Viewer) -> Bool {
  self.widget.has_text_focus()
}

///|
pub fn Viewer::has_widget_focus(self : Viewer) -> Bool {
  self.widget.has_widget_focus()
}

///|
pub fn Viewer::get_editor_type(self : Viewer) -> String {
  self.widget.get_editor_type()
}

///|
pub fn Viewer::on_did_change_model(
  self : Viewer,
  listener : (@editor_api.ModelChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.widget.on_did_change_model(listener)
}

///|
pub fn Viewer::on_did_change_model_content(
  self : Viewer,
  listener : (@model.ModelContentChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.widget.on_did_change_model_content(listener)
}

///|
pub fn Viewer::on_did_change_cursor_position(
  self : Viewer,
  listener : (@editor_api.CursorPositionChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.widget.on_did_change_cursor_position(listener)
}

///|
pub fn Viewer::on_did_change_cursor_selection(
  self : Viewer,
  listener : (@editor_api.CursorSelectionChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.widget.on_did_change_cursor_selection(listener)
}

///|
pub fn Viewer::on_did_scroll_change(
  self : Viewer,
  listener : (@editor_api.ScrollEvent) -> Unit,
) -> @base_common.Disposable {
  self.widget.on_did_scroll_change(listener)
}

///|
pub fn Viewer::on_did_change_view_zones(
  self : Viewer,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.widget.on_did_change_view_zones(listener)
}

///|
pub fn Viewer::on_did_change_hidden_areas(
  self : Viewer,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.widget.on_did_change_hidden_areas(listener)
}

///|
pub fn Viewer::on_did_dispose(
  self : Viewer,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.widget.on_did_dispose(listener)
}

///|
pub fn Viewer::on_mouse_down(
  self : Viewer,
  listener : (@editor_browser.EditorMouseEvent) -> Unit,
) -> @base_common.Disposable {
  self.widget.on_mouse_down(listener)
}

///|
pub fn Viewer::on_mouse_up(
  self : Viewer,
  listener : (@editor_browser.EditorMouseEvent) -> Unit,
) -> @base_common.Disposable {
  self.widget.on_mouse_up(listener)
}

///|
pub fn Viewer::on_mouse_move(
  self : Viewer,
  listener : (@editor_browser.EditorMouseEvent) -> Unit,
) -> @base_common.Disposable {
  self.widget.on_mouse_move(listener)
}

///|
pub fn Viewer::on_context_menu(
  self : Viewer,
  listener : (@editor_browser.EditorMouseEvent) -> Unit,
) -> @base_common.Disposable {
  self.widget.on_context_menu(listener)
}

///|
pub fn Viewer::on_mouse_leave(
  self : Viewer,
  listener : (@editor_browser.PartialEditorMouseEvent) -> Unit,
) -> @base_common.Disposable {
  self.widget.on_mouse_leave(listener)
}

///|
pub fn Viewer::save_view_state(self : Viewer) -> ViewerViewState? {
  self.widget.save_view_state().map(inner => { inner, })
}

///|
pub fn Viewer::restore_view_state(
  self : Viewer,
  state : ViewerViewState?,
) -> Unit {
  self.widget.restore_view_state(state.map(state => state.inner))
}

///|
pub fn Viewer::fold_top_level(self : Viewer) -> Unit {
  self.widget.fold_top_level()
}

///|
pub fn Viewer::show_references(
  self : Viewer,
  position : @base_common.Position,
  locations : Array[@language.Location],
) -> Unit {
  self.widget.show_references(position, locations)
}

///|
pub fn Viewer::change_view_zones(
  self : Viewer,
  update : (@editor_browser.ViewZoneChangeAccessor) -> Unit raise,
) -> Unit {
  self.widget.change_view_zones(update)
}

///|
pub fn Viewer::add_overlay_widget(
  self : Viewer,
  widget : @editor_browser.OverlayWidget,
) -> Unit {
  self.widget.add_overlay_widget(widget)
}

///|
pub fn Viewer::remove_overlay_widget(
  self : Viewer,
  widget : @editor_browser.OverlayWidget,
) -> Unit {
  self.widget.remove_overlay_widget(widget)
}

///|
pub fn Viewer::delta_decorations(
  self : Viewer,
  old_decorations : Array[String],
  new_decorations : Array[@model.ModelDeltaDecoration],
) -> Array[String] {
  self.widget.delta_decorations(old_decorations, new_decorations)
}

///|
pub fn Viewer::remove_decorations(
  self : Viewer,
  decoration_ids : Array[String],
) -> Unit {
  self.widget.remove_decorations(decoration_ids)
}

///|
pub fn Viewer::create_decorations_collection(
  self : Viewer,
  decorations? : Array[@model.ModelDeltaDecoration] = [],
) -> EditorDecorationsCollection {
  { inner: self.widget.create_decorations_collection(decorations~), }
}

///|
pub fn EditorDecorationsCollection::set(
  self : EditorDecorationsCollection,
  decorations : Array[@model.ModelDeltaDecoration],
) -> Array[String] {
  self.inner.set(decorations)
}

///|
pub fn EditorDecorationsCollection::append(
  self : EditorDecorationsCollection,
  decorations : Array[@model.ModelDeltaDecoration],
) -> Array[String] {
  self.inner.append(decorations)
}

///|
pub fn EditorDecorationsCollection::clear(
  self : EditorDecorationsCollection,
) -> Unit {
  self.inner.clear()
}

///|
pub fn EditorDecorationsCollection::length(
  self : EditorDecorationsCollection,
) -> Int {
  self.inner.length()
}

///|
pub fn EditorDecorationsCollection::get_range(
  self : EditorDecorationsCollection,
  index : Int,
) -> @base_common.Range? {
  self.inner.get_range(index)
}

///|
pub fn EditorDecorationsCollection::get_ranges(
  self : EditorDecorationsCollection,
) -> Array[@base_common.Range] {
  self.inner.get_ranges()
}

///|
pub fn Viewer::get_line_decorations(
  self : Viewer,
  line_number : Int,
) -> Array[@model.ModelDecoration] {
  self.widget.get_line_decorations(line_number)
}

///|
pub fn Viewer::get_decorations_in_range(
  self : Viewer,
  range : @base_common.Range,
) -> Array[@model.ModelDecoration] {
  self.widget.get_decorations_in_range(range)
}
