///|
/// Keeps the measured editor outer width invariant when a changed model-line
/// digit band moves `layoutInfo.contentLeft`. Monaco's
/// `EditorConfiguration.setModelLineCount` recomputes layout options before it
/// publishes the resulting Configuration event. The local CodeEditorWidget retains the
/// last measured outer client width as its source fact, so it can derive the
/// new content width synchronously without another DOM read:
///
/// `newContentWidth = max(0, measuredOuterWidth - newContentLeft)`
///
/// Returns whether the content-left band changed. The caller emits LayoutInfo
/// only after this helper, so ContentWidgets' live configuration read observes
/// the matching `contentLeft`/`contentWidth` pair.
fn CodeEditorWidget::sync_content_box_for_model_line_count(
  self : CodeEditorWidget,
  view_model : @view_model.ViewModel,
  current_model_line_count : Int32,
) -> Bool {
  if !self.configuration.adjust_content_width_for_model_line_count(
      current_model_line_count,
    ) {
    return false
  }
  let configuration = self.configuration.snapshot()
  view_model.view_layout.set_viewport_size(
    width=configuration.content_width,
    height=configuration.height,
  )
  |> ignore
  self.sync_content_width()
  // A real View rechecks the DOM box in the next read phase. This does not
  // delay the configuration fact above; it catches an independent host resize
  // and lets wrapping react before the same frame writes.
  if self.current_code_view() is Some(_) {
    self.configuration.request_measure()
  }
  true
}
