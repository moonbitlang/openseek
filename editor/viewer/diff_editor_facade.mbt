///|
/// The two caller-owned models installed as one atomic diff-editor pair.
pub(all) struct DiffEditorModel {
  original : @model.TextModel
  modified : @model.TextModel
}

///|
pub fn DiffEditorModel::DiffEditorModel(
  original : @model.TextModel,
  modified : @model.TextModel,
) -> DiffEditorModel {
  { original, modified, }
}

///|
pub(all) enum DiffEditorLayout {
  SideBySide
  Inline
} derive(Eq, Debug)

///|
pub(all) enum DiffWordWrap {
  Inherit
  Off
} derive(Eq, Debug)

///|
/// Public construction options for the comparison widget. Standalone editor
/// presentation remains an opaque ViewerOptions value; diff policy is mapped
/// explicitly into the internal package.
struct DiffEditorOptions {
  editor_options : ViewerOptions
  layout : DiffEditorLayout
  automatic_inline : Bool
  automatic_inline_width : Double
  sash_enabled : Bool
  split_ratio : Double
  diff_word_wrap : DiffWordWrap
  overview_ruler : Bool
  render_indicators : Bool
  ignore_trim_whitespace : Bool
}

///|
pub fn DiffEditorOptions::DiffEditorOptions(
  editor_options? : ViewerOptions = ViewerOptions::default().with_soft_wrap(
    true,
  ),
  layout? : DiffEditorLayout = SideBySide,
  automatic_inline? : Bool = true,
  automatic_inline_width? : Double = 900.0,
  sash_enabled? : Bool = true,
  split_ratio? : Double = 0.5,
  diff_word_wrap? : DiffWordWrap = Inherit,
  overview_ruler? : Bool = true,
  render_indicators? : Bool = true,
  ignore_trim_whitespace? : Bool = true,
) -> DiffEditorOptions {
  {
    editor_options,
    layout,
    automatic_inline,
    automatic_inline_width: automatic_inline_width.max(0.0),
    sash_enabled,
    split_ratio: split_ratio.clamp(min=0.1, max=0.9),
    diff_word_wrap,
    overview_ruler,
    render_indicators,
    ignore_trim_whitespace,
  }
}

///|
pub fn DiffEditorOptions::default() -> DiffEditorOptions {
  DiffEditorOptions()
}

///|
pub fn DiffEditorOptions::with_layout(
  self : DiffEditorOptions,
  layout : DiffEditorLayout,
) -> DiffEditorOptions {
  { ..self, layout, }
}

///|
pub fn DiffEditorOptions::with_editor_options(
  self : DiffEditorOptions,
  editor_options : ViewerOptions,
) -> DiffEditorOptions {
  { ..self, editor_options, }
}

///|
/// Controls only the add/remove Codicons. Diff line, character, and complete
/// gutter backgrounds remain visible when indicators are disabled.
pub fn DiffEditorOptions::with_render_indicators(
  self : DiffEditorOptions,
  render_indicators : Bool,
) -> DiffEditorOptions {
  { ..self, render_indicators, }
}

///|
pub fn DiffEditorOptions::layout(self : DiffEditorOptions) -> DiffEditorLayout {
  self.layout
}

///|
fn DiffEditorLayout::internal(
  self : DiffEditorLayout,
) -> @diff_editor.DiffEditorLayout {
  match self {
    SideBySide => SideBySide
    Inline => Inline
  }
}

///|
fn DiffWordWrap::internal(self : DiffWordWrap) -> @diff_editor.DiffWordWrap {
  match self {
    Inherit => Inherit
    Off => Off
  }
}

///|
fn DiffEditorOptions::internal(
  self : DiffEditorOptions,
) -> @diff_editor.DiffEditorOptions {
  DiffEditorOptions(
    layout=self.layout.internal(),
    automatic_inline=self.automatic_inline,
    automatic_inline_width=self.automatic_inline_width,
    sash_enabled=self.sash_enabled,
    split_ratio=self.split_ratio,
    diff_word_wrap=self.diff_word_wrap.internal(),
    overview_ruler=self.overview_ruler,
    render_indicators=self.render_indicators,
    ignore_trim_whitespace=self.ignore_trim_whitespace,
  )
}

///|
/// Public opaque façade. It owns no child public Viewer; the internal widget
/// directly owns two CodeEditorWidget kernels and the shared diff ViewModel.
struct DiffEditor {
  widget : @diff_editor.DiffEditorWidget
  owned_core_provider : @diff.CoreDocumentDiffProvider?
}

///|
pub fn DiffEditor::create(
  host : @rdom.Element,
  services? : ViewerServices,
  options? : DiffEditorOptions = DiffEditorOptions::default(),
  provider? : &@diff.DocumentDiffProvider,
) -> DiffEditor {
  let (provider, owned_core_provider) = match provider {
    Some(provider) => (provider, None)
    None => {
      let core = @diff.CoreDocumentDiffProvider()
      let provider : &@diff.DocumentDiffProvider = core
      (provider, Some(core))
    }
  }
  let widget = match services {
    Some(services) =>
      @diff_editor.DiffEditorWidget::create(
        host,
        provider,
        services=services.code_services(),
        editor_options=options.editor_options.code_options(),
        options=options.internal(),
      )
    None =>
      @diff_editor.DiffEditorWidget::create(
        host,
        provider,
        editor_options=options.editor_options.code_options(),
        options=options.internal(),
      )
  }
  { widget, owned_core_provider, }
}

///|
pub fn DiffEditor::set_model(
  self : DiffEditor,
  model : DiffEditorModel?,
) -> DiffEditorModel? {
  self.widget
  .set_model(
    model.map(model => { original: model.original, modified: model.modified, }),
  )
  .map(previous => { original: previous.original, modified: previous.modified, })
}

///|
pub fn DiffEditor::get_model(self : DiffEditor) -> DiffEditorModel? {
  self.widget
  .get_model()
  .map(model => { original: model.original, modified: model.modified, })
}

///|
pub fn DiffEditor::set_diff_provider(
  self : DiffEditor,
  provider : &@diff.DocumentDiffProvider,
) -> Unit {
  self.widget.set_diff_provider(provider)
}

///|
pub fn DiffEditor::update_options(
  self : DiffEditor,
  options : DiffEditorOptions,
) -> Unit {
  self.widget.update_options(
    options.editor_options.code_options(),
    options.internal(),
  )
}

///|
pub fn DiffEditor::get_layout(self : DiffEditor) -> DiffEditorLayout {
  match self.widget.get_layout() {
    SideBySide => SideBySide
    Inline => Inline
  }
}

///|
pub fn DiffEditor::get_diff(self : DiffEditor) -> @diff.DocumentDiff? {
  self.widget.get_diff()
}

///|
pub fn DiffEditor::is_diff_up_to_date(self : DiffEditor) -> Bool {
  self.widget.is_diff_up_to_date()
}

///|
pub fn DiffEditor::on_did_update_diff(
  self : DiffEditor,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.widget.on_did_update_diff(listener)
}

///|
/// Reveal the first raw diff mapping once the current comparison is ready.
/// The request is one-shot and model-bound, matching VS Code's
/// `IDiffEditor.revealFirstDiff` rather than cursor-relative F7 navigation.
pub fn DiffEditor::reveal_first_diff(self : DiffEditor) -> Unit {
  self.widget.reveal_first_diff()
}

///|
pub fn DiffEditor::reveal_next_change(self : DiffEditor) -> Bool {
  self.widget.reveal_next_change()
}

///|
pub fn DiffEditor::reveal_previous_change(self : DiffEditor) -> Bool {
  self.widget.reveal_previous_change()
}

///|
pub fn DiffEditor::layout(self : DiffEditor) -> Unit {
  self.widget.layout()
}

///|
/// Keep code panes live during a continuous host-width resize while deferring
/// derived diff, Markdown, and overview work until the host passes `false`.
pub fn DiffEditor::set_continuous_width_resize(
  self : DiffEditor,
  active : Bool,
) -> Unit {
  self.widget.set_continuous_width_resize(active)
}

///|
pub fn DiffEditor::focus(self : DiffEditor) -> Unit {
  self.widget.focus()
}

///|
pub fn DiffEditor::dispose(self : DiffEditor) -> Unit {
  self.widget.dispose()
  // The empty Core provider has no disposal work; touching the field here
  // documents and preserves its lifetime until after the ViewModel is gone.
  match self.owned_core_provider {
    Some(_) => ()
    None => ()
  }
}

///|
pub extend DiffEditorLayout with Eq::{equal, not_equal}

///|
pub extend DiffEditorLayout with Debug::{to_repr}

///|
pub extend DiffWordWrap with Eq::{equal, not_equal}

///|
pub extend DiffWordWrap with Debug::{to_repr}
