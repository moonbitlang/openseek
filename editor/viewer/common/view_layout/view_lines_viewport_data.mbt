///|
/// Line-renderer viewport data derived from the backend-neutral view model and
/// layout state.
pub(all) struct ViewportData {
  start_line_number : Int
  end_line_number : Int
  relative_vertical_offset : Array[Double]
  line_height : Int
  visible_range : @base_common.Range
  big_numbers_delta : Int
  lines : Array[ViewLineRenderingData]
  line_decorations : Array[Array[LineDecoration]]
  view_zones : Array[ViewWhitespaceViewportData]
} derive(Eq, Debug)

///|
/// Line-rendering data for a one-based line number inside this viewport.
pub fn ViewportData::line_data(
  self : ViewportData,
  line_number : Int,
) -> ViewLineRenderingData? {
  self.lines.get(line_number - self.start_line_number)
}

///|
/// Line decorations for a one-based line number inside this viewport.
pub fn ViewportData::decorations_for_line(
  self : ViewportData,
  line_number : Int,
) -> Array[LineDecoration] {
  self.line_decorations.get(line_number - self.start_line_number).unwrap_or([])
}

///|
/// Flattened decorations for every line in this viewport.
pub fn ViewportData::decorations_in_viewport(
  self : ViewportData,
) -> Array[LineDecoration] {
  self.line_decorations.flatten()
}

///|
pub extend ViewportData with Debug::{to_repr}

///|
pub extend ViewportData with Eq::{equal, not_equal}
