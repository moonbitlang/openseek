// Renderer-neutral mapping values used by both the built-in Line provider and
// external providers. They intentionally expose their representation: a
// provider package must be able to construct validated output without a
// viewer-layer adapter.

///|
/// Maps a half-open line range in the original document to one in the
/// modified document.
#derive(Eq, Debug)
pub(all) struct LineRangeMapping {
  original : @base_common.LineRange
  modified : @base_common.LineRange
}

///|
pub fn LineRangeMapping::LineRangeMapping(
  original : @base_common.LineRange,
  modified : @base_common.LineRange,
) -> LineRangeMapping {
  { original, modified, }
}

///|
/// Maps a one-based UTF-16 range in the original document to one in the
/// modified document.
#derive(Eq, Debug)
pub(all) struct RangeMapping {
  original : @base_common.Range
  modified : @base_common.Range
}

///|
pub fn RangeMapping::RangeMapping(
  original : @base_common.Range,
  modified : @base_common.Range,
) -> RangeMapping {
  { original, modified, }
}

///|
/// Maps a line range in the original text model to a line range in the
/// modified text model, together with the character-level inner range
/// mappings — `DetailedLineRangeMapping` (`rangeMapping.ts:196`). The source
/// class extends `LineRangeMapping`; MoonBit has no inheritance, so the
/// struct is flat and repeats the two line ranges.
#derive(Eq, Debug)
pub(all) struct DetailedLineRangeMapping {
  original : @base_common.LineRange
  modified : @base_common.LineRange
  /// If inner changes have not been computed, this is `None`. Otherwise it
  /// represents the character-level diff in this line range.
  inner_changes : Array[RangeMapping]?
}

///|
pub fn DetailedLineRangeMapping::DetailedLineRangeMapping(
  original : @base_common.LineRange,
  modified : @base_common.LineRange,
  inner_changes : Array[RangeMapping]?,
) -> DetailedLineRangeMapping {
  { original, modified, inner_changes, }
}

///|
/// Character-level changes inside this line mapping, or `None` when the
/// refinement budget was exceeded. This pair projection is convenient for
/// consumers that do not need the named `RangeMapping` fields.
pub fn DetailedLineRangeMapping::get_inner_changes(
  self : DetailedLineRangeMapping,
) -> Array[(@base_common.Range, @base_common.Range)]? {
  self.inner_changes.map(changes => {
    changes.map(change => (change.original, change.modified))
  })
}

///|
pub fn DetailedLineRangeMapping::line_mapping(
  self : DetailedLineRangeMapping,
) -> LineRangeMapping {
  LineRangeMapping(self.original, self.modified)
}

///|
// Port of VS Code's `getLineRangeMapping` (`rangeMapping.ts`). Character
// refinement can include the newline immediately before an EOF-only change;
// derive the final line hunk from that mapping so both coordinate layers use
// the same anchor.
fn line_range_mapping_from_range_mapping(
  range_mapping : RangeMapping,
  original_lines : Array[String],
  modified_lines : Array[String],
) -> LineRangeMapping {
  let mut line_start_delta = 0
  let mut line_end_delta = 0
  if range_mapping.modified.end_column == 1 &&
    range_mapping.original.end_column == 1 &&
    range_mapping.original.start_line_number + line_start_delta <=
    range_mapping.original.end_line_number &&
    range_mapping.modified.start_line_number + line_start_delta <=
    range_mapping.modified.end_line_number {
    line_end_delta = -1
  }
  if range_mapping.modified.start_column - 1 >=
    modified_lines[range_mapping.modified.start_line_number - 1].length() &&
    range_mapping.original.start_column - 1 >=
    original_lines[range_mapping.original.start_line_number - 1].length() &&
    range_mapping.original.start_line_number <=
    range_mapping.original.end_line_number + line_end_delta &&
    range_mapping.modified.start_line_number <=
    range_mapping.modified.end_line_number + line_end_delta {
    line_start_delta = 1
  }
  LineRangeMapping(
    LineRange(
      range_mapping.original.start_line_number + line_start_delta,
      range_mapping.original.end_line_number + 1 + line_end_delta,
    ),
    LineRange(
      range_mapping.modified.start_line_number + line_start_delta,
      range_mapping.modified.end_line_number + 1 + line_end_delta,
    ),
  )
}

///|
fn line_range_mapping_from_inner_changes(
  inner_changes : Array[RangeMapping],
  original_lines : Array[String],
  modified_lines : Array[String],
) -> LineRangeMapping? {
  if inner_changes.is_empty() {
    return None
  }
  let first = line_range_mapping_from_range_mapping(
    inner_changes[0],
    original_lines,
    modified_lines,
  )
  let last = line_range_mapping_from_range_mapping(
    inner_changes[inner_changes.length() - 1],
    original_lines,
    modified_lines,
  )
  Some(
    LineRangeMapping(
      first.original.join(last.original),
      first.modified.join(last.modified),
    ),
  )
}

///|
pub extend LineRangeMapping with Debug::{to_repr}

///|
pub extend LineRangeMapping with Eq::{equal, not_equal}

///|
pub extend RangeMapping with Debug::{to_repr}

///|
pub extend RangeMapping with Eq::{equal, not_equal}

///|
pub extend DetailedLineRangeMapping with Debug::{to_repr}

///|
pub extend DetailedLineRangeMapping with Eq::{equal, not_equal}
