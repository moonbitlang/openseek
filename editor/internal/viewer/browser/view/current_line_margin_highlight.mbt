// Monaco's `CurrentLineMarginHighlightOverlay`
// (`viewParts/currentLineHighlight/currentLineHighlight.ts:224-235` over the
// abstract `prepareRender`, `:126-171`), as a pure per-line HTML builder for
// `browser/view`'s `MarginViewOverlays` rows — the first registered margin
// dynamic overlay, before the line-number overlay (`view.ts:225-229`). Its
// lifecycle preparation lives in `view_overlays_lifecycle.mbt`; the DOM-free
// predicates and class strings live
// in `viewer/common/view_layout` (`current_line_highlight.mbt`); the content
// twin lives in this package's `current_line_highlight.mbt` source unit.

///|
/// The margin current-line dynamic overlay's independent inherited state plus
/// prepared per-line HTML (`_renderData`).
priv struct CurrentLineMarginHighlightOverlay {
  state : CurrentLineHighlightState
  mut render_result : Array[String]
}

///|
fn CurrentLineMarginHighlightOverlay::CurrentLineMarginHighlightOverlay() -> CurrentLineMarginHighlightOverlay {
  { state: CurrentLineHighlightState(), render_result: [], }
}

///|
/// `AbstractLineHighlightOverlay.prepareRender` (`:126-171`) over the margin
/// overlay's predicates. `_shouldRenderThis` is `true` for the margin overlay
/// (`:229-231`) — an unhighlighted mode simply produces pieces with the bare
/// `current-line` class (no `current-line-margin`), which no CSS rule paints.
/// `width` is `_contentLeft`, the margin width (`:227`).
fn prepare_current_line_margin_render(
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
  guard cursor_view_line is Some(cursor_line) else { return render_data }
  let in_margin = @view_layout.should_render_line_highlight_in_margin(
    render_line_highlight, render_line_highlight_only_when_focus, editor_has_focus,
  )
  // `_shouldRenderOther` for the margin overlay is `_shouldRenderInContent`
  // (`:232-234`) — it feeds the `current-line-margin-both` class.
  let other = @view_layout.should_render_line_highlight_in_content(
    render_line_highlight, render_line_highlight_only_when_focus, editor_has_focus,
    selection_is_empty,
  )
  // The wrapped pass spans the same view lines as the content overlay's
  // (`currentLineHighlight.ts:141-158` is shared by both subclasses).
  let (first_line, last_line) = current_line_span(
    view_model, cursor_line, word_wrap,
  )
  for view_line in first_line..<=last_line {
    let index = view_line - viewport.start_line_number
    if index < 0 || index >= render_data.length() {
      continue
    }
    // `CurrentLineMarginHighlightOverlay._renderOne` (`:225-228`): height
    // comes from the row (`height: 100%`), and the source writes no
    // trailing `;` after the margin width.
    let class_name = @view_layout.current_line_margin_class(
      in_margin~,
      other~,
      exact=view_line == cursor_line,
    )
    render_data[index] = "<div class=\"\{class_name}\" style=\"width:\{width.to_string()}px\"></div>"
  }
  render_data
}
