///|
/// One view-line segment produced from a model line after projection/wrapping.
/// `wrapped_text_indent_length` is the continuation indent applied to this
/// segment's rendered view line (Monaco's `getMinOutputOffset`): `0` for a model
/// line's first segment, the model line's wrapped indent for continuations.
pub struct ModelLineProjectionSegment {
  model_line_number : Int32
  start_offset : Int32
  end_offset : Int32
  start_column : Int32
  end_column : Int32
  /// Monaco `breakOffsetsVisibleColumn[k - 1]` for segment `k` (`0` for the
  /// first): fractional when `columnsForFullWidthChar` is (full-width
  /// advance / half-width advance) of a measured font.
  start_visible_column : Double
  continues_with_wrapped_line : Bool
  wrapped_text_indent_length : Int32
} derive(Eq, Debug)

///|
/// Projection data for one model line.
pub struct ModelLineProjectionData {
  model_line_number : Int32
  line_length : Int32
  projected_line : ProjectedTextLine
  segments : Array[ModelLineProjectionSegment]
} derive(Eq, Debug)

///|
/// Builds projection data for one model line.
pub fn ModelLineProjectionData::ModelLineProjectionData(
  model_line_number : Int32,
  line_length : Int32,
  projected_line : ProjectedTextLine,
  segments : Array[ModelLineProjectionSegment],
) -> ModelLineProjectionData {
  { model_line_number, line_length, projected_line, segments, }
}

///|
/// Number of view-line segments for this model line.
pub fn ModelLineProjectionData::view_line_count(
  self : ModelLineProjectionData,
) -> Int32 {
  self.segments.length()
}

///|
/// Segment at a zero-based view-line index, clamped into range.
pub fn ModelLineProjectionData::segment_at_view_line_index(
  self : ModelLineProjectionData,
  index : Int32,
) -> ModelLineProjectionSegment {
  let index = index.clamp(min=0, max=self.segments.length() - 1)
  self.segments[index]
}

///|
/// View-line index containing the given model column.
pub fn ModelLineProjectionData::view_line_index_for_model_column(
  self : ModelLineProjectionData,
  column : Int32,
) -> Int32 {
  let column = column.clamp(min=0, max=self.line_length)
  let projected_column = self.projected_line.model_column_to_projected_column(
    column,
  )
  self.view_line_index_for_projected_column(projected_column)
}

///|
/// View-line index containing the given projected display column.
///
/// The break-offset search of `offsetInInputWithInjectionsToOutputPosition`
/// (`modelLineProjectionData.ts:130-167`): only `Left` treats a break offset
/// as belonging to the segment that ends there (`(start, end]` bounds); every
/// other affinity starts the next segment with it (`[start, end)`).
pub fn ModelLineProjectionData::view_line_index_for_projected_column(
  self : ModelLineProjectionData,
  column : Int32,
  affinity? : @model.PositionAffinity,
) -> Int32 {
  let column = column.clamp(min=0, max=self.projected_line.text.length())
  let owns_break_offset = affinity is Some(Left)
  for index in 0..<self.segments.length() {
    let segment = self.segments[index]
    let inside = if owns_break_offset {
      column <= segment.end_offset
    } else {
      column < segment.end_offset
    }
    if inside || index + 1 == self.segments.length() {
      return index
    }
  }
  self.segments.length() - 1
}

///|
fn model_line_projection_segment(
  model_line_number : Int32,
  start_offset : Int32,
  end_offset : Int32,
  start_visible_column : Double,
  continues_with_wrapped_line : Bool,
  wrapped_text_indent_length : Int32,
) -> ModelLineProjectionSegment {
  {
    model_line_number,
    start_offset,
    end_offset,
    start_column: start_offset + 1,
    end_column: end_offset + 1,
    start_visible_column,
    continues_with_wrapped_line,
    wrapped_text_indent_length,
  }
}

///|
pub extend ModelLineProjectionData with Debug::{to_repr}

///|
pub extend ModelLineProjectionData with Eq::{equal, not_equal}

///|
pub extend ModelLineProjectionSegment with Debug::{to_repr}

///|
pub extend ModelLineProjectionSegment with Eq::{equal, not_equal}
