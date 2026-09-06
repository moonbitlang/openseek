///|
/// Computes the current partial viewport in model coordinates for attached
/// tokenization priority (`viewModelImpl.ts:222-232`). Hidden model ranges are
/// removed by the already source-shaped `to_model_visible_ranges` split.
fn ViewModel::model_visible_ranges_for_tokenization(
  self : ViewModel,
) -> Array[@model.VisibleLineRange] {
  let viewport = self.view_layout.get_lines_viewport_data()
  let visible_view_range = @base_common.Range(
    viewport.start_line_number,
    self.get_line_min_column(viewport.start_line_number),
    viewport.end_line_number,
    self.get_line_max_column(viewport.end_line_number),
  )
  let model_ranges = self.to_model_visible_ranges(visible_view_range)
  model_ranges.map(model_range => {
    start_line_number: model_range.start_line_number,
    end_line_number: model_range.end_line_number,
  })
}

///|
/// Publishes the current model-visible ranges as stabilized. Only the
/// host's explicit `handle_initialized` boundary and view-state restore call
/// this source method (`viewModelImpl.ts:234-237`). Model attach itself
/// deliberately does not own the initialization publication.
pub fn ViewModel::visible_lines_stabilized(self : ViewModel) -> Unit {
  if self.attached_view is Some(attached_view) {
    attached_view.set_visible_lines(
      self.model_visible_ranges_for_tokenization(),
      true,
    )
  }
}

///|
/// Publishes ordinary scroll/content mapping changes as unstable
/// (`viewModelImpl.ts:239-242`). Horizontal-only scroll is filtered by the
/// constructor listener before this method is called.
fn ViewModel::handle_visible_lines_changed(self : ViewModel) -> Unit {
  if self.attached_view is Some(attached_view) {
    attached_view.set_visible_lines(
      self.model_visible_ranges_for_tokenization(),
      false,
    )
  }
}
