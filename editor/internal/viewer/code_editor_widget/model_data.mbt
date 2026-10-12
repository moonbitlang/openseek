///|
/// CodeEditorWidget-lifetime owner of the currently attached model bundle and
/// the monotonic generation captured by swap-scoped callbacks.
priv struct ViewerModelSlot {
  mut generation : Int32
  mut current : ModelData?
}

///|
fn ViewerModelSlot::ViewerModelSlot() -> ViewerModelSlot {
  { generation: 0, current: None, }
}

///|
fn ViewerModelSlot::begin_attach_generation(self : ViewerModelSlot) -> Int32 {
  self.generation += 1
  self.generation
}

///|
fn ViewerModelSlot::invalidate_current_for_detach(
  self : ViewerModelSlot,
) -> ModelData? {
  guard self.current is Some(current) else { return None }
  self.generation += 1
  Some(current)
}

///|
fn ViewerModelSlot::install_current(
  self : ViewerModelSlot,
  model_data : ModelData,
) -> Unit {
  self.current = Some(model_data)
}

///|
fn ViewerModelSlot::clear_current_after_dispose(self : ViewerModelSlot) -> Unit {
  self.current = None
}

///|
fn ViewerModelSlot::is_current_generation(
  self : ViewerModelSlot,
  generation : Int32,
) -> Bool {
  self.current is Some(_) && self.generation == generation
}

///|
/// Monaco's model-scoped CodeEditorWidget ownership bundle. A mounted model
/// owns exactly one code View; headless white-box tests retain `None`.
priv struct ModelData {
  model : @model.TextModel
  view_model : @view_model.ViewModel
  browser : CodeBrowserData?
  attached_view : @model.AttachedViewImpl
  listeners_to_remove : Array[@base_common.Disposable]
}

///|
/// Complete code-presentation state for one attached model.
priv struct CodeBrowserData {
  view : @view.View
  mouse_handler : @controller.MouseHandler
  mut rendered_window : @view_layout.LineWindow?
  mut horizontal_reveal_request : HorizontalRevealRangeRequest?
}

///|
fn CodeBrowserData::CodeBrowserData(
  view : @view.View,
  mouse_handler : @controller.MouseHandler,
) -> CodeBrowserData {
  {
    view,
    mouse_handler,
    rendered_window: None,
    horizontal_reveal_request: None,
  }
}

///|
fn CodeBrowserData::cancel_mouse_selection(self : CodeBrowserData) -> Unit {
  self.mouse_handler.cancel_selection()
}

///|
fn CodeBrowserData::invalidate_rendered_window(self : CodeBrowserData) -> Unit {
  self.rendered_window = None
}

///|
fn CodeBrowserData::sync_rendered_window(
  self : CodeBrowserData,
  view_model : @view_model.ViewModel,
) -> @view_layout.LineWindow {
  let window = view_model.clamp_window(view_model.view_layout.visible_window())
  self.rendered_window = Some(window)
  window
}

///|
fn CodeBrowserData::root(self : CodeBrowserData) -> @rdom.Element {
  self.view.root
}

///|
fn CodeBrowserData::apply_theme(self : CodeBrowserData, theme : String) -> Unit {
  self.view.root.set_attribute("data-theme", theme)
  self.view.apply_squiggly_theme()
}

///|
fn CodeBrowserData::focus(self : CodeBrowserData) -> Unit {
  @base_browser.focus_prevent_scroll(self.view.root)
}

///|
fn CodeBrowserData::contains_active_element(self : CodeBrowserData) -> Bool {
  @base_browser.element_contains_active_element(self.view.root)
}

///|
fn CodeEditorWidget::current_code_browser_data(
  self : CodeEditorWidget,
) -> CodeBrowserData? {
  match self.model_slot.current {
    Some(model_data) => model_data.browser
    None => None
  }
}

///|
fn CodeEditorWidget::active_presentation_root(
  self : CodeEditorWidget,
) -> @rdom.Element? {
  self.current_code_browser_data().map(browser => browser.root())
}

///|
fn ModelData::dispose(
  self : ModelData,
  after_model_detached : () -> Unit,
) -> Unit {
  for listener in self.listeners_to_remove {
    listener.dispose()
  }
  self.model.on_before_detached(self.attached_view)
  after_model_detached()
  match self.browser {
    Some(browser) => browser.view.dispose()
    None => ()
  }
  self.view_model.dispose()
}
