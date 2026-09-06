// Character-level refinement for one line-level diff hunk. Line diff compares
// Unicode scalar values so a supplementary character remains atomic, while
// the parallel boundary table retains the Viewer's one-based UTF-16 columns.
// Newline sentinels let matching continue across a multi-line replacement.

///|
/// Avoid turning a large whole-file replacement into two additional scalar
/// arrays plus a potentially expensive character diff. The line-level result
/// remains complete when this refinement returns `None`.
const MaxInnerDiffCodeUnits = 20000

///|
priv struct InnerDiffSequence {
  values : Array[Int]
  start_boundaries : Array[@base_common.Position]
  end_boundaries : Array[@base_common.Position]
}

///|
priv struct InnerDiffLine {
  values : Array[Int]
  start_right : @base_common.Position
  start_left : @base_common.Position
  ends : Array[@base_common.Position]
}

///|
fn line_range_code_units(
  lines : Array[String],
  range : @base_common.LineRange,
) -> Int {
  let mut length = 0
  for line_number in range.start_line_number..<range.end_line_number_exclusive {
    length += lines[line_number - 1].length()
    if line_number + 1 < range.end_line_number_exclusive {
      length += 1
    }
  }
  length
}

///|
fn empty_line_range_anchor(
  lines : Array[String],
  line_number : Int,
) -> @base_common.Position {
  if lines.is_empty() {
    Position(1, 1)
  } else if line_number <= lines.length() {
    Position(line_number.max(1), 1)
  } else {
    let last_line_number = lines.length()
    Position(last_line_number, lines[last_line_number - 1].length() + 1)
  }
}

///|
fn flatten_inner_diff_line(
  line : String,
  line_number : Int,
  ignore_trim_whitespace : Bool,
) -> InnerDiffLine {
  let values : Array[Int] = []
  let whitespace : Array[Bool] = []
  let starts : Array[Int] = []
  let ends : Array[Int] = []
  let mut column = 1
  for character in line {
    values.push(character.to_int())
    whitespace.push(character.is_whitespace())
    starts.push(column)
    column += character.utf16_len()
    ends.push(column)
  }
  let mut start = 0
  let mut end = values.length()
  if ignore_trim_whitespace {
    while start < end && whitespace[start] {
      start += 1
    }
    while end > start && whitespace[end - 1] {
      end -= 1
    }
  }
  let normalized : Array[Int] = []
  let start_right_column = if start < end {
    starts[start]
  } else if ignore_trim_whitespace {
    column
  } else {
    1
  }
  let ends_in_range : Array[@base_common.Position] = []
  for index in start..<end {
    normalized.push(values[index])
    ends_in_range.push(Position(line_number, ends[index]))
  }
  {
    values: normalized,
    start_right: Position(line_number, start_right_column),
    start_left: Position(line_number, 1),
    ends: ends_in_range,
  }
}

///|
fn flatten_inner_diff_sequence(
  lines : Array[String],
  range : @base_common.LineRange,
  ignore_trim_whitespace : Bool,
  include_leading_newline : Bool,
  include_trailing_newline : Bool,
) -> InnerDiffSequence {
  if range.is_empty() {
    let anchor = empty_line_range_anchor(lines, range.start_line_number)
    return { values: [], start_boundaries: [anchor], end_boundaries: [anchor], }
  }
  let line_sequences : Array[InnerDiffLine] = [
    for line_number in range.start_line_number..<range.end_line_number_exclusive => {
      flatten_inner_diff_line(
        lines[line_number - 1],
        line_number,
        ignore_trim_whitespace,
      )
    }
  ]
  let values : Array[Int] = []
  let start_boundaries : Array[@base_common.Position] = []
  let end_boundaries : Array[@base_common.Position] = []
  let first = line_sequences[0]
  if include_leading_newline {
    let previous_line_number = range.start_line_number - 1
    let previous_end = @base_common.Position(
      previous_line_number,
      lines[previous_line_number - 1].length() + 1,
    )
    start_boundaries.push(previous_end)
    end_boundaries.push(previous_end)
    values.push('\n'.to_int())
  }
  start_boundaries.push(first.start_right)
  end_boundaries.push(first.start_left)
  for line_index in 0..<line_sequences.length() {
    let line = line_sequences[line_index]
    for value_index in 0..<line.values.length() {
      values.push(line.values[value_index])
      start_boundaries.push(line.ends[value_index])
      end_boundaries.push(line.ends[value_index])
    }
    if line_index + 1 < line_sequences.length() {
      let next = line_sequences[line_index + 1]
      values.push('\n'.to_int())
      start_boundaries.push(next.start_right)
      end_boundaries.push(next.start_left)
    }
  }
  if include_trailing_newline {
    let next_line_number = range.end_line_number_exclusive
    let next = flatten_inner_diff_line(
      lines[next_line_number - 1],
      next_line_number,
      ignore_trim_whitespace,
    )
    values.push('\n'.to_int())
    start_boundaries.push(next.start_right)
    end_boundaries.push(next.start_left)
  }
  { values, start_boundaries, end_boundaries, }
}

///|
fn InnerDiffSequence::range(
  self : InnerDiffSequence,
  start : Int,
  end_exclusive : Int,
) -> @base_common.Range {
  let start_position = self.start_boundaries[start]
  let end_position = self.end_boundaries[end_exclusive]
  if end_position.is_before(start_position) {
    @base_common.Range::from_positions(end_position, end_position)
  } else {
    @base_common.Range::from_positions(start_position, end_position)
  }
}

///|
fn is_valid_inner_diff_line_number(
  line_number : Int,
  lines : Array[String],
) -> Bool {
  line_number >= 1 && line_number <= lines.length()
}

///|
/// Refine one line mapping into maximal runs of changed Unicode scalars. Each
/// returned Range still uses UTF-16 columns, matching TextModel and Monaco.
fn compute_inner_changes(
  original_lines : Array[String],
  modified_lines : Array[String],
  original_range : @base_common.LineRange,
  modified_range : @base_common.LineRange,
  ignore_trim_whitespace : Bool,
) -> Array[RangeMapping]? {
  let mut original_leading_newline = false
  let mut modified_leading_newline = false
  let mut original_trailing_newline = false
  let mut modified_trailing_newline = false
  if is_valid_inner_diff_line_number(
      original_range.end_line_number_exclusive,
      original_lines,
    ) &&
    is_valid_inner_diff_line_number(
      modified_range.end_line_number_exclusive,
      modified_lines,
    ) {
    original_trailing_newline = !original_range.is_empty()
    modified_trailing_newline = !modified_range.is_empty()
  } else if !original_range.is_empty() && !modified_range.is_empty() {
    ()
  } else if original_range.start_line_number > 1 &&
    modified_range.start_line_number > 1 {
    original_leading_newline = !original_range.is_empty()
    modified_leading_newline = !modified_range.is_empty()
  } else {
    // Mirrors `LineRangeMapping.toRangeMapping2`: a valid line diff cannot
    // reach this shape. Keep the line mapping but omit unsafe refinement.
    return None
  }
  let original_length = line_range_code_units(original_lines, original_range) +
    (if original_leading_newline || original_trailing_newline { 1 } else { 0 })
  let modified_length = line_range_code_units(modified_lines, modified_range) +
    (if modified_leading_newline || modified_trailing_newline { 1 } else { 0 })
  if original_length > MaxInnerDiffCodeUnits ||
    modified_length > MaxInnerDiffCodeUnits ||
    original_length > MaxInnerDiffCodeUnits - modified_length {
    return None
  }
  let original = flatten_inner_diff_sequence(
    original_lines, original_range, ignore_trim_whitespace, original_leading_newline,
    original_trailing_newline,
  )
  let modified = flatten_inner_diff_sequence(
    modified_lines, modified_range, ignore_trim_whitespace, modified_leading_newline,
    modified_trailing_newline,
  )
  let diffs = compute_advanced_scalar_diffs(original.values, modified.values)
  Some(
    diffs.map(diff => {
      RangeMapping(
        original.range(diff.original.start, diff.original.end_exclusive),
        modified.range(diff.modified.start, diff.modified.end_exclusive),
      )
    }),
  )
}
