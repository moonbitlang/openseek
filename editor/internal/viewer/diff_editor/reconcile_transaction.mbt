// Adapters from kernel-owned geometry to the VS Code-shaped alignment engine.

///|
fn pane_geometry_from_code_editor_parts(
  line_height : Double,
  model_line_heights : Array[@code_widget.CodeEditorModelLineHeight],
  foreign_zone_heights : Array[@code_widget.CodeEditorForeignZoneHeight],
  line_max_columns : Array[Int],
  viewport_width : Double,
) -> PaneGeometrySnapshot {
  PaneGeometrySnapshot(
    model_line_heights.length(),
    line_height,
    model_line_heights=model_line_heights.map(item => {
      (
        { line_number: item.line_number, height_in_px: item.height_in_px, } :
        PaneModelLineHeight)
    }),
    foreign_zone_heights=foreign_zone_heights.map(item => {
      (
        {
          after_line_number: item.after_line_number,
          height_in_px: item.height_in_px,
        } : PaneForeignZoneHeight)
    }),
    line_max_columns~,
    viewport_width~,
  )
}

///|
fn pane_geometry_from_code_editor(
  snapshot : @code_widget.CodeEditorGeometrySnapshot,
) -> PaneGeometrySnapshot {
  pane_geometry_from_code_editor_parts(
    snapshot.line_height(),
    snapshot.model_line_heights(),
    snapshot.foreign_zone_heights(),
    snapshot.line_max_columns(),
    snapshot.scroll_content().viewport_width,
  )
}

///|
fn same_alignment_geometry(
  left : PaneGeometrySnapshot,
  right : PaneGeometrySnapshot,
) -> Bool {
  // Viewport width is an observation source, not an alignment input. Wrapped
  // line heights and foreign-zone heights already carry every width-dependent
  // geometry change that can alter the paired vertical axis.
  left.line_height == right.line_height &&
  left.line_heights == right.line_heights &&
  left.line_max_columns == right.line_max_columns &&
  left.foreign_zone_heights == right.foreign_zone_heights &&
  left.cumulative_pixels == right.cumulative_pixels
}

///|
fn same_optional_alignment_geometry(
  left : PaneGeometrySnapshot?,
  right : PaneGeometrySnapshot?,
) -> Bool {
  match (left, right) {
    (None, None) => true
    (Some(left), Some(right)) => same_alignment_geometry(left, right)
    _ => false
  }
}

///|
fn alignment_geometry_pair_changed(
  original : PaneGeometrySnapshot?,
  modified : PaneGeometrySnapshot?,
  previous_original : PaneGeometrySnapshot?,
  previous_modified : PaneGeometrySnapshot?,
) -> Bool {
  !same_optional_alignment_geometry(original, previous_original) ||
  !same_optional_alignment_geometry(modified, previous_modified)
}

///|
