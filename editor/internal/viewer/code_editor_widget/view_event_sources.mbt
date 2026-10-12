///|
/// Emits one typed view event at its root CodeEditorWidget source. A headless CodeEditorWidget has
/// no browser View (and therefore no ViewPart consumer), so it deliberately
/// performs only the same ViewModel/cache mutations in that mode.
fn CodeEditorWidget::emit_view_event(
  self : CodeEditorWidget,
  event : @view.ViewEvent,
) -> Unit {
  match self.current_code_view() {
    Some(view) => view.emit_view_event(event)
    None => ()
  }
}

///|
/// Opens a source-shaped nested event batch on the current browser View. The
/// returned View is the exact dispatcher whose matching `end` must run even
/// if CodeEditorWidget state changes before the batch completes.
fn CodeEditorWidget::begin_view_event_batch(
  self : CodeEditorWidget,
) -> @view.View? {
  match self.current_code_view() {
    Some(view) => {
      view.begin_view_event_batch() |> ignore
      Some(view)
    }
    None => None
  }
}

///|
fn end_view_event_batch(view : @view.View?) -> Unit {
  match view {
    Some(view) => view.end_view_event_batch()
    None => ()
  }
}

///|
/// Preserves every inclusive grammar-token range in producer order. Semantic
/// token application is outside this readonly grammar-token child; the View
/// event's source payload intentionally carries only the line ranges consumed
/// by ViewLines and ViewCursors.
fn view_tokens_changed_event(
  changed_ranges : Array[(Int32, Int32)],
) -> @view.ViewTokensChangedEvent {
  let ranges : Array[@view.ViewTokenChangeRange] = []
  for range in changed_ranges {
    let (from_line_number, to_line_number) = range
    ranges.push(ViewTokenChangeRange(from_line_number, to_line_number))
  }
  ViewTokensChangedEvent(ranges)
}

///|
/// Emits the committed view-space cursor state before the public outgoing
/// cursor pair, as in Monaco.
fn CodeEditorWidget::emit_view_cursor_state_changed(
  self : CodeEditorWidget,
  view_model : @view_model.ViewModel,
) -> Unit {
  self.emit_view_event(
    ViewCursorStateChanged(view_cursor_state_changed_event(view_model)),
  )
}

///|
fn view_cursor_state_changed_event(
  view_model : @view_model.ViewModel,
) -> @view.ViewCursorStateChangedEvent {
  ViewCursorStateChangedEvent([view_model.cursor.get_view_selection()])
}

///|
/// Emits a mapping-only cursor reprojection only when the view-coordinate
/// selection actually changed. The model selection remains stable and the
/// source reason is `NotSet`.
fn CodeEditorWidget::emit_view_cursor_reprojection(
  self : CodeEditorWidget,
  view_model : @view_model.ViewModel,
  previous_view_selection : @core.Selection,
) -> Unit {
  let current_view_selection = view_model.cursor.get_view_selection()
  if current_view_selection == previous_view_selection {
    return
  }
  self.emit_view_event(
    ViewCursorStateChanged(
      ViewCursorStateChangedEvent([current_view_selection]),
    ),
  )
}

///|
/// Preserves the width needed by ViewLines and all four independent changed
/// flags from ViewLayout's source event.
fn CodeEditorWidget::emit_view_scroll_changed(
  self : CodeEditorWidget,
  change : @view_layout.ScrollChange,
) -> Unit {
  self.emit_view_event(ViewScrollChanged(view_scroll_changed_event(change)))
}

///|
fn view_scroll_changed_event(
  change : @view_layout.ScrollChange,
) -> @view.ViewScrollChangedEvent {
  ViewScrollChangedEvent(
    change.scroll_width,
    change.scroll_width_changed,
    change.scroll_left_changed,
    change.scroll_height_changed,
    change.scroll_top_changed,
  )
}
