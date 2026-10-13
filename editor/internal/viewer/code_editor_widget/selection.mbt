///|
/// The selection as a view-coordinate range, the input the selection overlay
/// renders from. Mirrors the view selections Monaco's `SelectionsOverlay`
/// receives via `onCursorStateChanged`: the cursor already holds the selection
/// in view coordinates (its `viewState`), so the overlay never round-trips
/// through raw document offsets. Columns are one-based and local to each view
/// line (the convention `measure_line_selection` consumes).
fn CodeEditorWidget::selection_view_range(
  self : CodeEditorWidget,
) -> @base_common.Range? {
  guard self.is_code_presentation() else { return None }
  guard self.get_view_model() is Some(view_model) else { return None }
  let selection = view_model.cursor.get_view_selection()
  if selection.is_empty() {
    return None
  }
  Some(@base_common.Range::from_positions(selection.start(), selection.end()))
}

///|
/// The full view-space selection the render input carries for the cursor part
/// (Monaco's `ViewCursorStateChangedEvent.selections[0]`): unlike
/// `selection_view_range` it survives collapsing, so a caret-only
/// `set_position` still renders. `None` only without a model — the view
/// model's cursor always exists, collapsed at (1,1) like Monaco's.
fn CodeEditorWidget::view_selection(
  self : CodeEditorWidget,
) -> @core.Selection? {
  guard self.is_code_presentation() else { return None }
  match self.get_view_model() {
    Some(view_model) => Some(view_model.cursor.get_view_selection())
    None => None
  }
}

///|
/// Moves the primary cursor to `position`, collapsing the selection there —
/// Monaco's `setPosition` (`codeEditorWidget.ts:670-682`), which builds a
/// selection with `selectionStart == position` and routes it through the
/// selection path. No model → no-op, no event. Like every Monaco mutator this
/// never scrolls; "move and reveal" is a composition with `reveal_*` at the
/// call site (the `gotoLocation` pattern).
pub fn CodeEditorWidget::set_position(
  self : CodeEditorWidget,
  position : @base_common.Position,
  source~ : String = "api",
) -> Unit {
  self.apply_selection(Selection(position, position), source, NotSet)
}

///|
/// Sets the primary selection from an anchor+active pair — Monaco's
/// `setSelection`/`_setSelectionImpl` (`codeEditorWidget.ts:797-830`) →
/// `ViewModel.setSelections` (`viewModelImpl.ts:1185-1187`) →
/// `CursorsController.setSelections`/`setStates` (`cursor.ts:309-311,118-134`),
/// collapsed onto the viewer's single cursor. Monaco's five input overloads
/// reduce to the one `Selection` type: the anchor may sit before or after the
/// active position and the resulting direction is preserved; a caller with a
/// plain range builds `Selection::from_positions(start, end)`. No model →
/// no-op, no event. Never scrolls (see `set_position`).
pub fn CodeEditorWidget::set_selection(
  self : CodeEditorWidget,
  selection : @core.Selection,
  source~ : String = "api",
) -> Unit {
  self.apply_selection(selection, source, NotSet)
}

///|
/// Shared public-API transition adapter. Validation, equality, internal
/// version snapshots, view-state commit, and outgoing delivery all belong to
/// the ViewModel/controller spine; API setters contribute only source `api`
/// and neutral reason `NotSet`.
fn CodeEditorWidget::apply_selection(
  self : CodeEditorWidget,
  selection : @core.Selection,
  source : String,
  reason : @editor_api.CursorChangeReason,
) -> Unit {
  guard self.is_code_presentation() else { return }
  guard self.get_view_model() is Some(view_model) else { return }
  view_model.set_cursor_state(
    Some(@cursor.CursorState::from_model_selection(selection)),
    source,
    reason,
  )
  |> ignore
}

///|
/// Browser-owned DOM mounted through these view contracts is not part of the
/// model selection surface. The marker attributes are written by the browser
/// View when it mounts each caller node, so descendants can be recognized
/// without coupling input handling to any contribution registry.
let caller_owned_editor_dom_selector : String = "[monaco-view-zone], [data-content-widget], [data-overlay-widget-id]"

///|
fn CodeEditorWidget::handle_copy_event(
  self : CodeEditorWidget,
  event : @rdom.Event,
  input_surface : @rdom.Element,
) -> Bool {
  if @base_browser.event_target_has_matching_ancestor(
      event, input_surface, caller_owned_editor_dom_selector,
    ) ||
    @base_browser.native_selection_has_endpoint_in_matching_ancestor(
      input_surface, caller_owned_editor_dom_selector,
    ) {
    return false
  }
  guard event.to_clipboard_event() is Some(clipboard_event) else {
    return false
  }
  match (self.get_view_model(), self.get_model()) {
    (Some(view_model), Some(model)) => {
      let selection = view_model.cursor.get_model_selection()
      let snapshot = model.snapshot
      if selection.is_empty() {
        return false
      }
      let plain = selection_plain_text_to_copy(selection, snapshot)
      let html = self.get_rich_text_to_copy(selection, snapshot)
      write_selection_clipboard_data(clipboard_event, plain, html)
      true
    }
    _ => false
  }
}

///|
fn CodeEditorWidget::get_rich_text_to_copy(
  self : CodeEditorWidget,
  selection : @core.Selection,
  snapshot : @model.TextSnapshot,
) -> String {
  match self.get_model() {
    Some(model) =>
      get_rich_text_to_copy(
        model,
        Range(
          selection.start().line_number,
          selection.start().column,
          selection.end().line_number,
          selection.end().column,
        ),
        self.configuration.snapshot().font_info,
      )
    None => selection_rich_text_to_copy(selection, snapshot)
  }
}

///|
/// Selection range normalized into ascending document offsets — the
/// model/clipboard boundary where the selection's view-`Position` geometry
/// crosses into raw document offsets. Monaco keeps this off the pure-geometry
/// `Selection` (`core/selection.ts`); the readonly viewer does the same, placing
/// it here in the controller layer. The offset round-trip is allowed only
/// because this is the model/clipboard boundary (the port's rule #3).
fn selection_normalized_range(
  selection : @core.Selection,
  snapshot : @model.TextSnapshot,
) -> @base_common.OffsetRange {
  OffsetRange(
    snapshot.get_offset_at(
      selection.start().line_number,
      selection.start().column,
    ),
    snapshot.get_offset_at(selection.end().line_number, selection.end().column),
  )
}

///|
/// Plain selected text for clipboard writes.
fn selection_plain_text_to_copy(
  selection : @core.Selection,
  snapshot : @model.TextSnapshot,
) -> String {
  snapshot.slice(selection_normalized_range(selection, snapshot))
}

///|
/// Minimal HTML clipboard payload preserving preformatted text, used as the
/// fallback when no model is available to produce styled spans.
fn selection_rich_text_to_copy(
  selection : @core.Selection,
  snapshot : @model.TextSnapshot,
) -> String {
  "<pre class=\"readonly-editor-copy\">\{escape_copy_html(selection_plain_text_to_copy(selection, snapshot))}</pre>"
}

///|
fn escape_copy_html(text : String) -> String {
  let out = StringBuilder()
  for ch in text {
    match ch {
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      '&' => out.write_string("&amp;")
      '"' => out.write_string("&quot;")
      _ => out.write_char(ch)
    }
  }
  out.to_string()
}

///|
/// Styled clipboard HTML for a model range, the faithful
/// `ViewModel.getRichTextToCopy` / `_getHTMLToCopy` pair
/// (`viewModelImpl.ts:1051-1134`): per model line, the model's `LineTokens`
/// render through `tokenize_line_to_html` (injected text never appears — it
/// lives in decorations, not the model tokens), wrapped in a styled `<div>`
/// carrying the default foreground/background and the configured `fontInfo`.
/// Deviation: no PLAINTEXT/multi-selection `null` arms (the viewer always
/// has a single selection and a concrete language).
fn get_rich_text_to_copy(
  model : @model.TextModel,
  model_range : @base_common.Range,
  font_info : @config.FontInfo,
) -> String {
  let color_map = @model.default_token_color_map()
  "<div style=\"color: \{color_map[1]};background-color: \{color_map[2]};font-family: \{font_info.bare().get_massaged_font_family()};font-weight: \{font_info.font_weight};font-size: \{font_info.font_size.to_string()}px;line-height: \{font_info.line_height.to_string()}px;white-space: pre;\">\{get_html_to_copy(model, model_range, color_map)}</div>"
}

///|
/// `ViewModelImpl._getHTMLToCopy` (`viewModelImpl.ts:1110-1134`): one
/// `tokenize_line_to_html` div per model line clipped to the range's
/// columns; an empty line contributes a `<br>`.
fn get_html_to_copy(
  model : @model.TextModel,
  model_range : @base_common.Range,
  color_map : Array[String],
) -> String {
  let start_line_number = model_range.start_line_number
  let start_column = model_range.start_column
  let end_line_number = model_range.end_line_number
  let end_column = model_range.end_column
  let tab_size = 2
  let result = StringBuilder()
  for line_number in start_line_number..<=end_line_number {
    let line_tokens = model.tokenization.get_line_tokens(line_number)
    let line_content = line_tokens.get_line_content()
    let start_offset = if line_number == start_line_number {
      start_column - 1
    } else {
      0
    }
    let end_offset = if line_number == end_line_number {
      end_column - 1
    } else {
      line_content.length()
    }
    if line_content == "" {
      result.write_string("<br>")
    } else {
      result.write_string(
        @languages.tokenize_line_to_html(
          line_content,
          line_tokens.inflate(),
          color_map,
          start_offset,
          end_offset,
          tab_size,
          false,
        ),
      )
    }
  }
  result.to_string()
}

///|
extern "js" fn write_selection_clipboard_data(
  event : @rdom.ClipboardEvent,
  plain : String,
  html : String,
) -> Unit =
  #| (event, plain, html) => {
  #|   const data = event?.clipboardData;
  #|   if (data?.setData) {
  #|     data.setData("text/plain", plain);
  #|     data.setData("text/html", html);
  #|   }
  #| }
