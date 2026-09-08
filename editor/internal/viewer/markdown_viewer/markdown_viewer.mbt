///|
/// The kind of Markdown resource being rendered. MoonBit Markdown enables the
/// semantic `mbt check`/`moonbit check` fence projection; ordinary Markdown
/// keeps every fence presentation-only. Selection is explicit and never
/// inferred from the model URI or language id.
pub(all) enum MarkdownResourceKind {
  OrdinaryMarkdown
  MoonBitMarkdown
} derive(Eq, Debug)

///|
/// One caller-owned source model together with its explicit Markdown resource
/// semantics. MarkdownViewerWidget owns neither value and never disposes the model.
pub(all) struct MarkdownViewerWidgetModel {
  model : @model.TextModel
  resource_kind : MarkdownResourceKind
} derive(Debug)

///|
pub fn MarkdownViewerWidgetModel::MarkdownViewerWidgetModel(
  model : @model.TextModel,
  resource_kind : MarkdownResourceKind,
) -> MarkdownViewerWidgetModel {
  { model, resource_kind, }
}

///|
fn MarkdownViewerWidgetModel::same(
  self : MarkdownViewerWidgetModel,
  other : MarkdownViewerWidgetModel,
) -> Bool {
  self.model.same(other.model) && self.resource_kind == other.resource_kind
}

///|
fn MarkdownResourceKind::to_internal(
  self : MarkdownResourceKind,
) -> @markdown_core.MarkdownResourceKind {
  match self {
    OrdinaryMarkdown => OrdinaryMarkdown
    MoonBitMarkdown => MoonBitMarkdown
  }
}

///|
/// Runtime options owned by the Markdown surface. Code-editor layout and input
/// options deliberately do not cross this API.
struct MarkdownViewerWidgetOptions {
  theme : String
  placeholder : String
  show_unused : Bool
} derive(Eq, Debug)

///|
pub fn MarkdownViewerWidgetOptions::MarkdownViewerWidgetOptions(
  theme? : String = "dark",
  placeholder? : String = "",
  show_unused? : Bool = true,
) -> MarkdownViewerWidgetOptions {
  { theme, placeholder, show_unused, }
}

///|
pub fn MarkdownViewerWidgetOptions::default() -> MarkdownViewerWidgetOptions {
  MarkdownViewerWidgetOptions()
}

///|
pub fn MarkdownViewerWidgetOptions::theme(
  self : MarkdownViewerWidgetOptions,
) -> String {
  self.theme
}

///|
pub fn MarkdownViewerWidgetOptions::placeholder(
  self : MarkdownViewerWidgetOptions,
) -> String {
  self.placeholder
}

///|
pub fn MarkdownViewerWidgetOptions::show_unused(
  self : MarkdownViewerWidgetOptions,
) -> Bool {
  self.show_unused
}

///|
pub fn MarkdownViewerWidgetOptions::with_theme(
  self : MarkdownViewerWidgetOptions,
  theme : String,
) -> MarkdownViewerWidgetOptions {
  { ..self, theme, }
}

///|
pub fn MarkdownViewerWidgetOptions::with_placeholder(
  self : MarkdownViewerWidgetOptions,
  placeholder : String,
) -> MarkdownViewerWidgetOptions {
  { ..self, placeholder, }
}

///|
pub fn MarkdownViewerWidgetOptions::with_show_unused(
  self : MarkdownViewerWidgetOptions,
  show_unused : Bool,
) -> MarkdownViewerWidgetOptions {
  { ..self, show_unused, }
}

///|
/// Host-restorable native Markdown viewport state.
struct MarkdownViewerWidgetViewState {
  scroll_top : Double
  scroll_left : Double
} derive(Eq, Debug)

///|
priv struct MarkdownViewerWidgetIdCounter {
  mut value : Int
}

///|
let markdown_viewer_id_counter : MarkdownViewerWidgetIdCounter = { value: 0, }

///|
fn next_markdown_viewer_id() -> Int {
  markdown_viewer_id_counter.value += 1
  markdown_viewer_id_counter.value
}

///|
priv struct MarkdownViewerWidgetPlaceholder {
  root : @rdom.Element
  text : @rdom.Element
}

///|
fn MarkdownViewerWidgetPlaceholder::MarkdownViewerWidgetPlaceholder(
  options : MarkdownViewerWidgetOptions,
) -> MarkdownViewerWidgetPlaceholder {
  let document = @rdom.document()
  let root = document.create_element("section")
  root.set_attribute("class", "moonbit-viewer-markdown-empty")
  root.set_attribute("data-theme", options.theme)
  let message = document.create_element("div")
  message.set_attribute("class", "source-message")
  let text = document.create_text_node(options.placeholder)
  message.append_child(text.as_node())
  root.append_child(message.as_node())
  { root, text, }
}

///|
fn MarkdownViewerWidgetPlaceholder::update(
  self : MarkdownViewerWidgetPlaceholder,
  options : MarkdownViewerWidgetOptions,
) -> Unit {
  self.root.set_attribute("data-theme", options.theme)
  self.text.set_node_value(@js.Nullable::from_option(Some(options.placeholder)))
}

///|
/// All resources whose lifetime is exactly one installed Markdown model.
priv struct MarkdownViewerWidgetAttachment {
  model : MarkdownViewerWidgetModel
  generation : Int
  view : @markdown_document.MarkdownDocumentView?
  hover_bridge : @hover_browser.MarkdownDocumentHoverBridge?
  definition_bridge : MarkdownViewerWidgetDefinitionBridge?
  fold : MarkdownViewerWidgetFoldState
  listeners : Array[@base_common.Disposable]
  mut disposed : Bool
}

///|
/// A first-class readonly Markdown surface. It directly owns one
/// MarkdownDocumentView and its model-scoped feature bridges; it does not
/// create, contain, or expose Viewer/CodeEditorWidget.
struct MarkdownViewerWidget {
  services : MarkdownViewerServices
  owns_services : Bool
  id : Int
  mut options : MarkdownViewerWidgetOptions
  mut host : @rdom.Element?
  mut placeholder : MarkdownViewerWidgetPlaceholder?
  mut resize_observer : @base_common.Disposable?
  mut generation : Int
  mut current : MarkdownViewerWidgetAttachment?
  mut focused : Bool
  mut disposed : Bool
  did_change_model : @base_common.Emitter[@editor_api.ModelChangedEvent]
  did_change_model_content : @base_common.Emitter[
    @model.ModelContentChangedEvent,
  ]
  did_scroll : @base_common.Emitter[Unit]
  did_change_content_size : @base_common.Emitter[Unit]
  did_dispose : @base_common.Emitter[Unit]
  did_detach_for_diagnostics : @base_common.Emitter[Unit]
}

///|
/// Package-private headless constructor used by deterministic lifecycle tests.
fn MarkdownViewerWidget::MarkdownViewerWidget(
  services? : MarkdownViewerServices,
  options? : MarkdownViewerWidgetOptions = MarkdownViewerWidgetOptions::default(),
) -> MarkdownViewerWidget {
  let (services, owns_services) = match services {
    Some(services) => (services, false)
    None => (MarkdownViewerServices(), true)
  }
  {
    services,
    owns_services,
    id: next_markdown_viewer_id(),
    options,
    host: None,
    placeholder: None,
    resize_observer: None,
    generation: 0,
    current: None,
    focused: false,
    disposed: false,
    did_change_model: Emitter(),
    did_change_model_content: Emitter(),
    did_scroll: Emitter(),
    did_change_content_size: Emitter(),
    did_dispose: Emitter(),
    did_detach_for_diagnostics: Emitter(),
  }
}

///|
/// Creates a mounted Markdown viewer. The caller owns `host` and must keep it
/// stable and otherwise child-free for the viewer lifetime.
pub fn MarkdownViewerWidget::create(
  host : @rdom.Element,
  services? : MarkdownViewerServices,
  options? : MarkdownViewerWidgetOptions = MarkdownViewerWidgetOptions::default(),
) -> MarkdownViewerWidget {
  let viewer = MarkdownViewerWidget(services?, options~)
  viewer.mount(host)
  viewer
}

///|
fn MarkdownViewerWidget::mount(
  self : MarkdownViewerWidget,
  host : @rdom.Element,
) -> Unit {
  guard !self.disposed && self.host is None else { return }
  let placeholder = MarkdownViewerWidgetPlaceholder(self.options)
  self.host = Some(host)
  self.placeholder = Some(placeholder)
  host.append_child(placeholder.root.as_node())
  self.resize_observer = @base_browser.observe_element_resize(host, () => {
    if !self.disposed {
      self.layout()
    }
  })
  self.layout()
}

///|
fn MarkdownViewerWidget::is_current_attachment(
  self : MarkdownViewerWidget,
  model : @model.TextModel,
  generation : Int,
) -> Bool {
  guard !self.disposed && self.generation == generation else { return false }
  self.current is Some(current) &&
  current.generation == generation &&
  current.model.model.same(model)
}

///|
fn MarkdownViewerWidget::attach_model(
  self : MarkdownViewerWidget,
  model : MarkdownViewerWidgetModel,
) -> Unit {
  self.generation += 1
  let generation = self.generation
  let listeners : Array[@base_common.Disposable] = []
  listeners.push(self.services.marker_decorations().acquire_model(model.model))
  listeners.push(
    model.model.on_did_change_content(event => {
      guard self.is_current_attachment(model.model, generation) &&
        self.current is Some(current) else {
        return
      }
      current.replace_source(model.model.get_value(), event.version_id)
      self.did_change_model_content.fire(event)
      self.did_change_content_size.fire(())
    }),
  )
  listeners.push(
    model.model.on_will_dispose(() => {
      if self.is_current_attachment(model.model, generation) {
        self.set_model(None) |> ignore
      }
    }),
  )
  let fold = MarkdownViewerWidgetFoldState()
  let (view, hover_bridge, definition_bridge) = match self.host {
    None => (None, None, None)
    Some(host) => {
      let view = @markdown_document.MarkdownDocumentView(
        model.model.get_value(),
        model.model.get_version_id(),
        model.model.get_language_id(),
        model.model.uri,
        model.resource_kind.to_internal(),
        self.options.theme,
        () => {
          if self.is_current_attachment(model.model, generation) {
            self.did_scroll.fire(())
          }
        },
        focused => {
          if self.is_current_attachment(model.model, generation) {
            self.focused = focused
          }
        },
        () => {
          if self.is_current_attachment(model.model, generation) {
            self.did_change_content_size.fire(())
          }
        },
        show_unused=self.options.show_unused,
      )
      self.hide_placeholder()
      host.append_child(view.root().as_node())
      let computer = @hover.ContentHoverComputer({
        languages: self.services.languages(),
        marker_decorations: self.services.marker_decorations(),
      })
      let hover_bridge = @hover_browser.MarkdownDocumentHoverBridge(
        view,
        model.model,
        computer,
        self.services.marker_decorations(),
        generation,
        () => self.is_current_attachment(model.model, generation),
        task => self.services.launch_async_task(task),
      )
      let definition_bridge = MarkdownViewerWidgetDefinitionBridge(
        self,
        view,
        model.model,
        generation,
      )
      (Some(view), Some(hover_bridge), Some(definition_bridge))
    }
  }
  let attachment : MarkdownViewerWidgetAttachment = {
    model,
    generation,
    view,
    hover_bridge,
    definition_bridge,
    fold,
    listeners,
    disposed: false,
  }
  self.current = Some(attachment)
  attachment.initialize_folding()
  if hover_bridge is Some(bridge) {
    bridge.activate()
  }
  if definition_bridge is Some(bridge) {
    bridge.activate()
  }
  self.layout()
}

///|
/// The bridge quiesce shared by `replace_source` and `apply_theme`:
/// definition first on the way down, hover first on the way back up.
fn MarkdownViewerWidgetAttachment::before_projection_replaced(
  self : MarkdownViewerWidgetAttachment,
) -> Unit {
  if self.definition_bridge is Some(bridge) {
    bridge.before_projection_replaced()
  }
  if self.hover_bridge is Some(bridge) {
    bridge.before_projection_replaced()
  }
}

///|
/// The rebind half of `MarkdownViewerWidgetAttachment::before_projection_replaced`.
fn MarkdownViewerWidgetAttachment::after_projection_replaced(
  self : MarkdownViewerWidgetAttachment,
) -> Unit {
  if self.hover_bridge is Some(bridge) {
    bridge.after_projection_replaced()
  }
  if self.definition_bridge is Some(bridge) {
    bridge.after_projection_replaced()
  }
}

///|
fn MarkdownViewerWidgetAttachment::replace_source(
  self : MarkdownViewerWidgetAttachment,
  source : String,
  source_model_version : Int,
) -> Unit {
  guard !self.disposed && self.view is Some(view) else { return }
  self.before_projection_replaced()
  view.replace_source(source, source_model_version)
  self.reconcile_folding(source)
  self.after_projection_replaced()
}

///|
fn MarkdownViewerWidgetAttachment::apply_theme(
  self : MarkdownViewerWidgetAttachment,
  theme : String,
) -> Unit {
  guard !self.disposed && self.view is Some(view) else { return }
  self.before_projection_replaced()
  view.apply_theme(theme)
  self.reconcile_folding(self.fold.source)
  self.after_projection_replaced()
}

///|
fn MarkdownViewerWidgetAttachment::layout_changed(
  self : MarkdownViewerWidgetAttachment,
) -> Unit {
  if self.hover_bridge is Some(bridge) {
    bridge.layout_changed()
  }
  if self.definition_bridge is Some(bridge) {
    bridge.layout_changed()
  }
}

///|
fn MarkdownViewerWidgetAttachment::dispose(
  self : MarkdownViewerWidgetAttachment,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  if self.definition_bridge is Some(bridge) {
    bridge.dispose()
  }
  if self.hover_bridge is Some(bridge) {
    bridge.dispose()
  }
  if self.view is Some(view) {
    view.dispose()
  }
  while self.listeners.length() > 0 {
    self.listeners.remove(self.listeners.length() - 1).dispose()
  }
}

///|
fn MarkdownViewerWidget::detach_model(
  self : MarkdownViewerWidget,
) -> MarkdownViewerWidgetModel? {
  guard self.current is Some(current) else { return None }
  self.generation += 1
  self.current = None
  self.focused = false
  let root = current.view.map(view => view.root())
  current.dispose()
  if root is Some(root) {
    @base_browser.remove_element(root)
  }
  if !self.disposed {
    self.restore_placeholder()
  }
  self.did_detach_for_diagnostics.fire(())
  Some(current.model)
}

///|
fn MarkdownViewerWidget::hide_placeholder(self : MarkdownViewerWidget) -> Unit {
  if self.placeholder is Some(placeholder) {
    @base_browser.remove_element(placeholder.root)
  }
}

///|
fn MarkdownViewerWidget::restore_placeholder(
  self : MarkdownViewerWidget,
) -> Unit {
  if self.host is Some(host) &&
    self.placeholder is Some(placeholder) &&
    !@base_browser.element_contains(host, placeholder.root) {
    host.append_child(placeholder.root.as_node())
  }
}

///|
/// Atomically swaps the explicit Markdown model. The returned previous model is
/// already fully detached: all browser bridges, model listeners, marker lease,
/// and presentation DOM have been retired before this call returns.
pub fn MarkdownViewerWidget::set_model(
  self : MarkdownViewerWidget,
  model : MarkdownViewerWidgetModel?,
) -> MarkdownViewerWidgetModel? {
  if self.disposed {
    return None
  }
  match (self.current, model) {
    (None, None) => return None
    (Some(current), Some(next)) if current.model.same(next) => return None
    _ => ()
  }
  let old_model_url = self.current.map(current => current.model.model.uri)
  let new_model_url = model.map(next => next.model.uri)
  let old = self.detach_model()
  if model is Some(next) {
    self.attach_model(next)
  }
  self.did_change_model.fire({ old_model_url, new_model_url, })
  old
}

///|
pub fn MarkdownViewerWidget::get_model(
  self : MarkdownViewerWidget,
) -> MarkdownViewerWidgetModel? {
  self.current.map(current => current.model)
}

///|
pub fn MarkdownViewerWidget::on_did_change_model(
  self : MarkdownViewerWidget,
  listener : (@editor_api.ModelChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_change_model.event(listener)
}

///|
pub fn MarkdownViewerWidget::on_did_change_model_content(
  self : MarkdownViewerWidget,
  listener : (@model.ModelContentChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_change_model_content.event(listener)
}

///|
pub fn MarkdownViewerWidget::on_did_scroll(
  self : MarkdownViewerWidget,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.did_scroll.event(_ => listener())
}

///|
pub fn MarkdownViewerWidget::on_did_change_content_size(
  self : MarkdownViewerWidget,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.did_change_content_size.event(_ => listener())
}

///|
pub fn MarkdownViewerWidget::on_did_dispose(
  self : MarkdownViewerWidget,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.did_dispose.event(_ => listener())
}

///|
fn MarkdownViewerWidget::on_did_detach_for_diagnostics(
  self : MarkdownViewerWidget,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.did_detach_for_diagnostics.event(_ => listener())
}

///|
let _markdown_viewer_widget_test_seam : Unit = ignore(
  MarkdownViewerWidget::on_did_detach_for_diagnostics,
)

///|
pub fn MarkdownViewerWidget::get_options(
  self : MarkdownViewerWidget,
) -> MarkdownViewerWidgetOptions {
  self.options
}

///|
pub fn MarkdownViewerWidget::update_options(
  self : MarkdownViewerWidget,
  options : MarkdownViewerWidgetOptions,
) -> Unit {
  if self.disposed || self.options == options {
    return
  }
  let previous = self.options
  self.options = options
  if self.placeholder is Some(placeholder) {
    placeholder.update(options)
  }
  if self.current is Some(current) {
    if previous.theme != options.theme {
      current.apply_theme(options.theme)
    }
    if previous.show_unused != options.show_unused && current.view is Some(view) {
      view.apply_marker_unused_visibility(options.show_unused)
    }
  }
}

///|
pub fn MarkdownViewerWidget::get_id(self : MarkdownViewerWidget) -> String {
  "markdown.viewer:\{self.id}"
}

///|
pub fn MarkdownViewerWidget::get_dom_node(
  self : MarkdownViewerWidget,
) -> @rdom.Element? {
  guard self.current is Some(current) && current.view is Some(view) else {
    return None
  }
  Some(view.root())
}

///|
pub fn MarkdownViewerWidget::get_container_dom_node(
  self : MarkdownViewerWidget,
) -> @rdom.Element {
  match self.host {
    Some(host) => host
    None => abort("MarkdownViewerWidget is not attached")
  }
}

///|
pub fn MarkdownViewerWidget::focus(self : MarkdownViewerWidget) -> Unit {
  if self.get_dom_node() is Some(root) {
    @base_browser.focus_prevent_scroll(root)
  }
}

///|
pub fn MarkdownViewerWidget::has_text_focus(
  self : MarkdownViewerWidget,
) -> Bool {
  self.focused
}

///|
pub fn MarkdownViewerWidget::layout(self : MarkdownViewerWidget) -> Unit {
  guard !self.disposed &&
    self.host is Some(host) &&
    self.current is Some(current) &&
    current.view is Some(view) else {
    return
  }
  view.layout(
    @base_browser.element_client_width(host),
    @base_browser.element_client_height(host),
  )
  current.layout_changed()
}

///|
pub fn MarkdownViewerWidget::save_view_state(
  self : MarkdownViewerWidget,
) -> MarkdownViewerWidgetViewState? {
  guard self.current is Some(current) && current.view is Some(view) else {
    return None
  }
  Some({ scroll_top: view.scroll_top(), scroll_left: view.scroll_left(), })
}

///|
pub fn MarkdownViewerWidget::restore_view_state(
  self : MarkdownViewerWidget,
  state : MarkdownViewerWidgetViewState?,
) -> Unit {
  guard state is Some(state) &&
    self.current is Some(current) &&
    current.view is Some(view) else {
    return
  }
  view.set_scroll_position(
    scroll_top=state.scroll_top,
    scroll_left=state.scroll_left,
  )
  current.layout_changed()
}

///|
pub fn MarkdownViewerWidget::reveal_source_offset(
  self : MarkdownViewerWidget,
  source_offset : Int,
) -> Unit {
  guard self.current is Some(current) && current.view is Some(view) else {
    return
  }
  view.reveal_source_offset(source_offset, "center")
  current.layout_changed()
}

///|
pub fn MarkdownViewerWidget::get_content_height(
  self : MarkdownViewerWidget,
) -> Double {
  guard self.current is Some(current) && current.view is Some(view) else {
    return 0.0
  }
  view.content_height()
}

///|
pub fn MarkdownViewerWidget::get_content_width(
  self : MarkdownViewerWidget,
) -> Double {
  guard self.current is Some(current) && current.view is Some(view) else {
    return 0.0
  }
  view.content_width()
}

///|
pub fn MarkdownViewerWidget::dispose(self : MarkdownViewerWidget) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  if self.resize_observer is Some(observer) {
    observer.dispose()
  }
  self.resize_observer = None
  self.detach_model() |> ignore
  self.hide_placeholder()
  self.placeholder = None
  self.did_dispose.fire(())
  self.did_change_model.dispose()
  self.did_change_model_content.dispose()
  self.did_scroll.dispose()
  self.did_change_content_size.dispose()
  self.did_dispose.dispose()
  self.did_detach_for_diagnostics.dispose()
  if self.owns_services {
    self.services.dispose()
  }
}

///|
pub extend MarkdownResourceKind with Debug::{to_repr}

///|
pub extend MarkdownResourceKind with Eq::{equal, not_equal}

///|
pub extend MarkdownViewerWidgetModel with Debug::{to_repr}

///|
pub extend MarkdownViewerWidgetOptions with Debug::{to_repr}

///|
pub extend MarkdownViewerWidgetOptions with Eq::{equal, not_equal}

///|
pub extend MarkdownViewerWidgetViewState with Debug::{to_repr}

///|
pub extend MarkdownViewerWidgetViewState with Eq::{equal, not_equal}
