// Monaco's `CurrentLineHighlightOverlay`
// (`viewParts/currentLineHighlight/currentLineHighlight.ts`): the content
// half of the abstract `AbstractLineHighlightOverlay.prepareRender`
// (`:126-171`) plus `CurrentLineHighlightOverlay._renderOne` (`:209-212`),
// as a pure per-line HTML builder. The overlay renders into
// `browser/view`'s `ContentViewOverlays` rows as the first registered
// dynamic overlay — before `SelectionsOverlay` (`view.ts:218-219`), which
// keeps the highlight painting under the selection. Its lifecycle preparation
// lives in `view_overlays_lifecycle.mbt`; the DOM-free predicates and class
// strings live in
// `viewer/common/view_layout` (`current_line_highlight.mbt`); the margin
// twin lives with the margin part.

///|
/// Retained state from Monaco's `AbstractLineHighlightOverlay`. Both concrete
/// overlays own one instance, just as the source's content and margin
/// subclasses each inherit an independent copy of these fields.
///
/// `read_configuration` is the local `ViewContext.configuration.options`
/// seam. It is read synchronously by `onConfigurationChanged`; render-time
/// input is deliberately not used to rewrite these caches because doing so
/// would collapse source event order into a frame-final snapshot.
priv struct CurrentLineHighlightState {
  mut render_line_highlight : @editor_api.RenderLineHighlight
  mut word_wrap : Bool
  mut content_left : Double
  mut content_width : Double
  mut selection_is_empty : Bool
  mut render_line_highlight_only_when_focus : Bool
  mut focused : Bool
  mut cursor_line_numbers : Array[Int]
  mut selections : Array[@core.Selection]
  mut read_configuration : () -> (
    @editor_api.RenderLineHighlight,
    Bool,
    Bool,
    Double,
    Double,
  )
}

///|
/// `AbstractLineHighlightOverlay` constructor defaults before a live
/// configuration reader is installed by the owning browser `View`.
fn CurrentLineHighlightState::CurrentLineHighlightState() -> CurrentLineHighlightState {
  let selection = @core.Selection(Position(1, 1), Position(1, 1))
  {
    render_line_highlight: Line,
    word_wrap: false,
    content_left: 0.0,
    content_width: 0.0,
    selection_is_empty: true,
    render_line_highlight_only_when_focus: false,
    focused: false,
    cursor_line_numbers: [1],
    selections: [selection],
    read_configuration: () => (Line, false, false, 0.0, 0.0),
  }
}

///|
/// Installs the local live-configuration seam and performs the constructor's
/// initial read. The tuple order is mode, focus-only, viewport wrapping,
/// content left, and content width.
fn CurrentLineHighlightState::install_configuration_reader(
  self : CurrentLineHighlightState,
  read_configuration : () -> (
    @editor_api.RenderLineHighlight,
    Bool,
    Bool,
    Double,
    Double,
  ),
) -> Unit {
  self.read_configuration = read_configuration
  self.on_configuration_changed()
}

///|
/// `AbstractLineHighlightOverlay.onConfigurationChanged` (`:87-96`): read
/// every retained option in source order and always let the caller dirty the
/// concrete overlay.
fn CurrentLineHighlightState::on_configuration_changed(
  self : CurrentLineHighlightState,
) -> Unit {
  let (
    render_line_highlight,
    render_line_highlight_only_when_focus,
    word_wrap,
    content_left,
    content_width,
  ) = (self.read_configuration)()
  self.render_line_highlight = render_line_highlight
  self.render_line_highlight_only_when_focus = render_line_highlight_only_when_focus
  self.word_wrap = word_wrap
  self.content_left = content_left
  self.content_width = content_width
}

///|
/// `onCursorStateChanged` plus `_readFromSelections` (`:60-81,:97-100`).
/// The complete selection array is retained even when the derived line-set
/// and empty/nonempty predicates do not change.
fn CurrentLineHighlightState::on_cursor_state_changed(
  self : CurrentLineHighlightState,
  selections : Array[@core.Selection],
) -> Bool {
  self.selections = selections.copy()
  self.read_from_selections()
}

///|
/// Recomputes the unique sorted cursor-line set and all-selections-empty bit,
/// updating each cache only when its equality branch detects a change.
fn CurrentLineHighlightState::read_from_selections(
  self : CurrentLineHighlightState,
) -> Bool {
  let line_numbers : Array[Int] = []
  let mut selection_is_empty = true
  for selection in self.selections {
    let line_number = selection.get_position().line_number
    if !line_numbers.contains(line_number) {
      line_numbers.push(line_number)
    }
    if !selection.is_empty() {
      selection_is_empty = false
    }
  }
  line_numbers.sort()
  let mut has_changed = false
  if self.cursor_line_numbers != line_numbers {
    self.cursor_line_numbers = line_numbers
    has_changed = true
  }
  if self.selection_is_empty != selection_is_empty {
    self.selection_is_empty = selection_is_empty
    has_changed = true
  }
  has_changed
}

///|
/// `onFocusChanged` (`:116-123`): the disabled focus-only option is an early
/// return. When enabled, the source stores the event and returns true even if
/// the boolean equals the previous value.
fn CurrentLineHighlightState::on_focus_changed(
  self : CurrentLineHighlightState,
  is_focused : Bool,
) -> Bool {
  if !self.render_line_highlight_only_when_focus {
    return false
  }
  self.focused = is_focused
  true
}

///|
/// The package-private content current-line dynamic overlay state: source
/// event caches plus the prepared per-line HTML (`_renderData`).
priv struct CurrentLineHighlightOverlay {
  state : CurrentLineHighlightState
  mut render_result : Array[String]
}

///|
fn CurrentLineHighlightOverlay::CurrentLineHighlightOverlay() -> CurrentLineHighlightOverlay {
  { state: CurrentLineHighlightState(), render_result: [], }
}

///|
/// `AbstractLineHighlightOverlay.prepareRender` (`:126-171`) over the content
/// overlay's predicates: every line starts empty; when the highlight should
/// render in content, the wrapped pass (`:141-158`) fills the cursor's whole
/// model-line span with the non-exact div and the exact pass (`:160-168`)
/// claims the cursor's own view line. `width` is
/// `max(ctx.scrollWidth, contentWidth)` (`_renderOne`, `:211`).
fn prepare_current_line_render(
  viewport : @view_layout.ViewportData,
  view_model : @view_model.ViewModel?,
  cursor_view_line : Int?,
  selection_is_empty : Bool,
  editor_has_focus : Bool,
  word_wrap : Bool,
  render_line_highlight : @editor_api.RenderLineHighlight,
  render_line_highlight_only_when_focus : Bool,
  width : Double,
) -> Array[String] {
  let render_data = Array::make(viewport.lines.length(), "")
  // `_shouldRenderThis` (`:213-215`) → `_shouldRenderInContent` (`:191-197`).
  if !@view_layout.should_render_line_highlight_in_content(
      render_line_highlight, render_line_highlight_only_when_focus, editor_has_focus,
      selection_is_empty,
    ) {
    return render_data
  }
  guard cursor_view_line is Some(cursor_line) else { return render_data }
  let in_margin = @view_layout.should_render_line_highlight_in_margin(
    render_line_highlight, render_line_highlight_only_when_focus, editor_has_focus,
  )
  // Wrapped pass (`:141-158`), gated on word wrap like the source's
  // `_wordWrap`; then the exact pass (`:160-168`).
  let (first_line, last_line) = current_line_span(
    view_model, cursor_line, word_wrap,
  )
  for view_line in first_line..<=last_line {
    let index = view_line - viewport.start_line_number
    if index < 0 || index >= render_data.length() {
      continue
    }
    render_data[index] = render_one(
      in_margin~,
      exact=view_line == cursor_line,
      width~,
    )
  }
  render_data
}

///|
/// `CurrentLineHighlightOverlay._renderOne` (`:209-212`); the class string
/// comes from the ported `current_line_content_class`, height from the row
/// (`height: 100%` in `current_line_highlight.css`).
fn render_one(in_margin~ : Bool, exact~ : Bool, width~ : Double) -> String {
  let class_name = @view_layout.current_line_content_class(in_margin~, exact~)
  "<div class=\"\{class_name}\" style=\"width:\{width.to_string()}px;\"></div>"
}

///|
/// The view-line span the highlight covers: the wrapped-line pass's model-line
/// span when wrapping (`currentLineHighlight.ts:141-158`), else just the
/// cursor line.
fn current_line_span(
  view_model : @view_model.ViewModel?,
  cursor_view_line : Int,
  word_wrap : Bool,
) -> (Int, Int) {
  if !word_wrap {
    return (cursor_view_line, cursor_view_line)
  }
  match view_model {
    Some(view_model) => {
      let lines = view_model.lines()
      @view_layout.view_line_span_of_model_line(
        cursor_view_line,
        lines.get_view_line_count(),
        view_line => lines.model_line_number_of_view_line(view_line),
      )
    }
    None => (cursor_view_line, cursor_view_line)
  }
}
