///|
pub(all) enum MarkdownResourceKind {
  OrdinaryMarkdown
  MoonBitMarkdown
} derive(Eq, Debug)

///|
pub(all) struct MarkdownViewerModel {
  model : @model.TextModel
  resource_kind : MarkdownResourceKind
}

///|
pub fn MarkdownViewerModel::MarkdownViewerModel(
  model : @model.TextModel,
  resource_kind : MarkdownResourceKind,
) -> MarkdownViewerModel {
  { model, resource_kind, }
}

///|
struct MarkdownViewerOptions {
  theme : String
  placeholder : String
  show_unused : Bool
} derive(Eq, Debug)

///|
pub fn MarkdownViewerOptions::MarkdownViewerOptions(
  theme? : String = "dark",
  placeholder? : String = "",
  show_unused? : Bool = true,
) -> MarkdownViewerOptions {
  { theme, placeholder, show_unused, }
}

///|
pub fn MarkdownViewerOptions::default() -> MarkdownViewerOptions {
  MarkdownViewerOptions()
}

///|
pub fn MarkdownViewerOptions::with_theme(
  self : MarkdownViewerOptions,
  theme : String,
) -> MarkdownViewerOptions {
  { ..self, theme, }
}

///|
pub fn MarkdownViewerOptions::with_placeholder(
  self : MarkdownViewerOptions,
  placeholder : String,
) -> MarkdownViewerOptions {
  { ..self, placeholder, }
}

///|
pub fn MarkdownViewerOptions::with_show_unused(
  self : MarkdownViewerOptions,
  show_unused : Bool,
) -> MarkdownViewerOptions {
  { ..self, show_unused, }
}

///|
struct MarkdownViewerViewState {
  inner : @markdown_viewer.MarkdownViewerWidgetViewState
} derive(Debug)

///|
struct MarkdownViewer {
  widget : @markdown_viewer.MarkdownViewerWidget
  borrowed_services : @markdown_viewer.MarkdownViewerServices?
}

///|
fn MarkdownResourceKind::internal(
  self : MarkdownResourceKind,
) -> @markdown_viewer.MarkdownResourceKind {
  match self {
    OrdinaryMarkdown => OrdinaryMarkdown
    MoonBitMarkdown => MoonBitMarkdown
  }
}

///|
fn MarkdownViewerOptions::internal(
  self : MarkdownViewerOptions,
) -> @markdown_viewer.MarkdownViewerWidgetOptions {
  MarkdownViewerWidgetOptions(
    theme=self.theme,
    placeholder=self.placeholder,
    show_unused=self.show_unused,
  )
}

///|
fn ViewerServices::markdown_services(
  self : ViewerServices,
  options : MarkdownViewerOptions,
) -> @markdown_viewer.MarkdownViewerServices {
  MarkdownViewerServices(
    languages=self.languages(),
    markers=Decorations(self.marker_decorations()),
    location_opener?=self.location_opener(),
    text_model_resolver?=self.text_model_resolver(),
    preview_factory=@code_widget.code_editor_references_preview_factory(
      self.code_services(),
      CodeEditorOptions(theme=options.theme),
    ),
    log_service=self.log_service(),
  )
}

///|
pub fn MarkdownViewer::create(
  host : @rdom.Element,
  services? : ViewerServices,
  options? : MarkdownViewerOptions = MarkdownViewerOptions::default(),
) -> MarkdownViewer {
  let markdown_services = services.map(services => {
    services.markdown_services(options)
  })
  {
    widget: @markdown_viewer.MarkdownViewerWidget::create(
      host,
      services?=markdown_services,
      options=options.internal(),
    ),
    borrowed_services: markdown_services,
  }
}

///|
pub fn MarkdownViewer::set_model(
  self : MarkdownViewer,
  model : MarkdownViewerModel?,
) -> MarkdownViewerModel? {
  self.widget
  .set_model(
    model.map(model => {
      model: model.model,
      resource_kind: model.resource_kind.internal(),
    }),
  )
  .map(previous => {
    model: previous.model,
    resource_kind: match previous.resource_kind {
      OrdinaryMarkdown => OrdinaryMarkdown
      MoonBitMarkdown => MoonBitMarkdown
    },
  })
}

///|
pub fn MarkdownViewer::get_model(self : MarkdownViewer) -> MarkdownViewerModel? {
  self.widget
  .get_model()
  .map(model => {
    model: model.model,
    resource_kind: match model.resource_kind {
      OrdinaryMarkdown => OrdinaryMarkdown
      MoonBitMarkdown => MoonBitMarkdown
    },
  })
}

///|
pub fn MarkdownViewer::on_did_change_model(
  self : MarkdownViewer,
  listener : (@editor_api.ModelChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.widget.on_did_change_model(listener)
}

///|
pub fn MarkdownViewer::on_did_change_model_content(
  self : MarkdownViewer,
  listener : (@model.ModelContentChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.widget.on_did_change_model_content(listener)
}

///|
pub fn MarkdownViewer::on_did_scroll_change(
  self : MarkdownViewer,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.widget.on_did_scroll(listener)
}

///|
pub fn MarkdownViewer::on_did_dispose(
  self : MarkdownViewer,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.widget.on_did_dispose(listener)
}

///|
pub fn MarkdownViewer::handle_initialized(self : MarkdownViewer) -> Unit {
  self.widget.layout()
}

///|
pub fn MarkdownViewer::update_options(
  self : MarkdownViewer,
  options : MarkdownViewerOptions,
) -> Unit {
  self.widget.update_options(options.internal())
}

///|
pub fn MarkdownViewer::get_options(
  self : MarkdownViewer,
) -> MarkdownViewerOptions {
  let options = self.widget.get_options()
  MarkdownViewerOptions(
    theme=options.theme(),
    placeholder=options.placeholder(),
    show_unused=options.show_unused(),
  )
}

///|
pub fn MarkdownViewer::save_view_state(
  self : MarkdownViewer,
) -> MarkdownViewerViewState? {
  self.widget.save_view_state().map(inner => { inner, })
}

///|
pub fn MarkdownViewer::restore_view_state(
  self : MarkdownViewer,
  state : MarkdownViewerViewState?,
) -> Unit {
  self.widget.restore_view_state(state.map(state => state.inner))
}

///|
pub fn MarkdownViewer::reveal_range_in_center(
  self : MarkdownViewer,
  range : @base_common.Range,
) -> Unit {
  guard self.get_model() is Some(model) else { return }
  self.widget.reveal_source_offset(
    model.model.snapshot.get_offset_at(
      range.start_line_number,
      range.start_column,
    ),
  )
}

///|
pub fn MarkdownViewer::collapsed_sections(self : MarkdownViewer) -> Array[Int] {
  self.widget.collapsed_sections()
}

///|
pub fn MarkdownViewer::toggle_section_at(
  self : MarkdownViewer,
  section_index : Int,
) -> Bool {
  self.widget.toggle_section_at(section_index)
}

///|
pub fn MarkdownViewer::get_dom_node(self : MarkdownViewer) -> @rdom.Element? {
  self.widget.get_dom_node()
}

///|
pub fn MarkdownViewer::get_container_dom_node(
  self : MarkdownViewer,
) -> @rdom.Element {
  self.widget.get_container_dom_node()
}

///|
pub fn MarkdownViewer::get_id(self : MarkdownViewer) -> String {
  self.widget.get_id()
}

///|
pub fn MarkdownViewer::get_content_height(self : MarkdownViewer) -> Double {
  self.widget.get_content_height()
}

///|
pub fn MarkdownViewer::get_content_width(self : MarkdownViewer) -> Double {
  self.widget.get_content_width()
}

///|
pub fn MarkdownViewer::layout(self : MarkdownViewer) -> Unit {
  self.widget.layout()
}

///|
pub fn MarkdownViewer::focus(self : MarkdownViewer) -> Unit {
  self.widget.focus()
}

///|
pub fn MarkdownViewer::has_text_focus(self : MarkdownViewer) -> Bool {
  self.widget.has_text_focus()
}

///|
pub fn MarkdownViewer::dispose(self : MarkdownViewer) -> Unit {
  self.widget.dispose()
  if self.borrowed_services is Some(services) {
    services.dispose()
  }
}

///|
pub extend MarkdownResourceKind with Eq::{equal, not_equal}

///|
pub extend MarkdownResourceKind with Debug::{to_repr}

///|
pub extend MarkdownViewerOptions with Debug::{to_repr}

///|
pub extend MarkdownViewerOptions with Eq::{equal, not_equal}

///|
pub extend MarkdownViewerViewState with Debug::{to_repr}
