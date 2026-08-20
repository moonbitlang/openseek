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
  let index = line_number - self.start_line_number
  if index >= 0 && index < self.lines.length() {
    Some(self.lines[index])
  } else {
    None
  }
}

///|
/// Line decorations for a one-based line number inside this viewport.
pub fn ViewportData::decorations_for_line(
  self : ViewportData,
  line_number : Int,
) -> Array[LineDecoration] {
  let index = line_number - self.start_line_number
  match self.line_decorations.get(index) {
    Some(decorations) => decorations
    None => []
  }
}

///|
/// Flattened decorations for every line in this viewport.
pub fn ViewportData::decorations_in_viewport(
  self : ViewportData,
) -> Array[LineDecoration] {
  let out : Array[LineDecoration] = []
  for line in self.line_decorations {
    for decoration in line {
      out.push(decoration)
    }
  }
  out
}

///|
#deprecated
pub extend ViewportData with Debug::{to_repr}

///|
pub extend ViewportData with Eq::{equal, not_equal}
