///|
fn valid_document_line_range(
  range : @base_common.LineRange,
  line_count : Int,
) -> Bool {
  range.start_line_number >= 1 &&
  range.end_line_number_exclusive >= range.start_line_number &&
  range.end_line_number_exclusive <= line_count + 1
}

///|
fn valid_document_range(
  range : @base_common.Range,
  snapshot : @model.TextSnapshot,
) -> Bool {
  if range.start_line_number < 1 ||
    range.end_line_number < range.start_line_number ||
    range.end_line_number > snapshot.line_count() {
    return false
  }
  let start_max = snapshot.get_line_max_column(range.start_line_number)
  let end_max = snapshot.get_line_max_column(range.end_line_number)
  range.start_column >= 1 &&
  range.start_column <= start_max &&
  range.end_column >= 1 &&
  range.end_column <= end_max &&
  (
    range.start_line_number < range.end_line_number ||
    range.start_column <= range.end_column
  )
}

///|
fn document_position_le(
  first : @base_common.Position,
  second : @base_common.Position,
) -> Bool {
  first.line_number < second.line_number ||
  (first.line_number == second.line_number && first.column <= second.column)
}

///|
// Port of VS Code's normalizeRangeMapping. A full-line character mapping is
// extended through the following newline so decoration and alignment features
// all observe the same canonical range.
fn normalize_document_range_mapping(
  range_mapping : RangeMapping,
  original : @model.TextSnapshot,
  modified : @model.TextSnapshot,
) -> RangeMapping {
  let original_range = range_mapping.original
  let modified_range = range_mapping.modified
  if original_range.end_line_number >= 1 &&
    original_range.end_line_number <= original.line_count() &&
    modified_range.end_line_number >= 1 &&
    modified_range.end_line_number <= modified.line_count() &&
    original_range.start_column == 1 &&
    modified_range.start_column == 1 &&
    (original_range.end_column != 1 || modified_range.end_column != 1) &&
    original_range.end_column ==
    original.get_line_max_column(original_range.end_line_number) &&
    modified_range.end_column ==
    modified.get_line_max_column(modified_range.end_line_number) &&
    original_range.end_line_number < original.line_count() &&
    modified_range.end_line_number < modified.line_count() {
    RangeMapping(
      original_range.set_end_position(original_range.end_line_number + 1, 1),
      modified_range.set_end_position(modified_range.end_line_number + 1, 1),
    )
  } else {
    range_mapping
  }
}

///|
fn normalize_document_diff(
  result : DocumentDiff,
  original : @model.TextSnapshot,
  modified : @model.TextSnapshot,
) -> DocumentDiff {
  {
    changes: result.changes.map(change => {
      ..change,
      mapping: DetailedLineRangeMapping(
        change.mapping.original,
        change.mapping.modified,
        change.mapping.inner_changes.map(inner_changes => {
          inner_changes.map(inner => {
            normalize_document_range_mapping(inner, original, modified)
          })
        }),
      ),
    }),
  }
}

///|
fn document_line_range_contains_range(
  parent : @base_common.LineRange,
  child : @base_common.Range,
  snapshot : @model.TextSnapshot,
) -> Bool {
  if !parent.is_empty() {
    // An EOF insertion/deletion includes the preceding newline because no
    // following newline exists. Its character range starts at the previous
    // line's end; it must not consume any unchanged character on that line.
    let starts_at_eof_newline = parent.start_line_number > 1 &&
      parent.end_line_number_exclusive == snapshot.line_count() + 1 &&
      child.start_line_number == parent.start_line_number - 1 &&
      child.start_column ==
      snapshot.get_line_max_column(child.start_line_number) &&
      child.end_line_number >= parent.start_line_number
    let start_is_inside = starts_at_eof_newline ||
      (
        child.start_line_number >= parent.start_line_number &&
        (
          child.start_line_number < parent.end_line_number_exclusive ||
          (
            child.is_empty() &&
            child.start_line_number == parent.end_line_number_exclusive &&
            child.start_column == 1
          )
        )
      )
    let end_is_inside = child.end_line_number < parent.end_line_number_exclusive ||
      (
        child.end_line_number == parent.end_line_number_exclusive &&
        child.end_column == 1
      )
    return start_is_inside && end_is_inside
  }
  if !child.is_empty() {
    let anchor_line = parent.start_line_number
    // Normalization extends both sides together. When one hunk side is empty,
    // that can turn its collapsed anchor on an empty logical line into the
    // canonical range covering exactly that line's newline.
    return anchor_line >= 1 &&
      anchor_line < snapshot.line_count() &&
      snapshot.get_line_max_column(anchor_line) == 1 &&
      child.start_line_number == anchor_line &&
      child.start_column == 1 &&
      child.end_line_number == anchor_line + 1 &&
      child.end_column == 1
  }
  let anchor = if parent.start_line_number <= snapshot.line_count() {
    @base_common.Position(parent.start_line_number.max(1), 1)
  } else {
    let last_line_number = snapshot.line_count().max(1)
    Position(last_line_number, snapshot.get_line_max_column(last_line_number))
  }
  child.get_start_position() == anchor && child.get_end_position() == anchor
}

///|
fn valid_document_inner_changes(
  inner_changes : Array[RangeMapping],
  parent_original : @base_common.LineRange,
  parent_modified : @base_common.LineRange,
  original : @model.TextSnapshot,
  modified : @model.TextSnapshot,
) -> Bool {
  let mut previous_original_end : @base_common.Position? = None
  let mut previous_modified_end : @base_common.Position? = None
  for inner in inner_changes {
    if !valid_document_range(inner.original, original) ||
      !valid_document_range(inner.modified, modified) ||
      !document_line_range_contains_range(
        parent_original,
        inner.original,
        original,
      ) ||
      !document_line_range_contains_range(
        parent_modified,
        inner.modified,
        modified,
      ) {
      return false
    }
    match (previous_original_end, previous_modified_end) {
      (Some(original_end), Some(modified_end)) =>
        if !document_position_le(
            original_end,
            inner.original.get_start_position(),
          ) ||
          !document_position_le(
            modified_end,
            inner.modified.get_start_position(),
          ) {
          return false
        }
      _ => ()
    }
    previous_original_end = Some(inner.original.get_end_position())
    previous_modified_end = Some(inner.modified.get_end_position())
  }
  true
}

///|
fn valid_document_alignment_sequence(
  result : DocumentDiff,
  original_line_count : Int,
  modified_line_count : Int,
) -> Bool {
  if result.changes.is_empty() {
    return original_line_count == modified_line_count
  }
  let first = result.changes[0].mapping
  if first.original.start_line_number != first.modified.start_line_number {
    return false
  }
  for index in 1..<result.changes.length() {
    let previous = result.changes[index - 1]
    let current = result.changes[index]
    let original_gap = current.mapping.original.start_line_number -
      previous.mapping.original.end_line_number_exclusive
    let modified_gap = current.mapping.modified.start_line_number -
      previous.mapping.modified.end_line_number_exclusive
    if original_gap < 0 ||
      modified_gap < 0 ||
      original_gap != modified_gap ||
      (previous.kind == current.kind && original_gap == 0) {
      return false
    }
  }
  let last = result.changes[result.changes.length() - 1].mapping
  original_line_count - last.original.end_line_number_exclusive ==
  modified_line_count - last.modified.end_line_number_exclusive
}

///|
fn valid_document_diff(
  result : DocumentDiff,
  original : @model.TextSnapshot,
  modified : @model.TextSnapshot,
) -> Bool {
  let mut original_end = 1
  let mut modified_end = 1
  for entry in result.changes {
    let change = entry.mapping
    if !valid_document_line_range(change.original, original.line_count()) ||
      !valid_document_line_range(change.modified, modified.line_count()) ||
      change.original.start_line_number < original_end ||
      change.modified.start_line_number < modified_end {
      return false
    }
    original_end = change.original.end_line_number_exclusive
    modified_end = change.modified.end_line_number_exclusive
    match change.inner_changes {
      Some(inner_changes) =>
        if !valid_document_inner_changes(
            inner_changes,
            change.original,
            change.modified,
            original,
            modified,
          ) {
          return false
        }
      None => ()
    }
  }
  valid_document_alignment_sequence(
    result,
    original.line_count(),
    modified.line_count(),
  )
}

///|
/// Canonicalize a provider result and accept it only when every mapping follows
/// the shared document-diff invariants. Optional providers should use this
/// helper before settling a specialized mode so rejected output can fall back
/// to Line; the DiffEditor calls it again as the final consumer boundary.
pub fn normalize_and_validate_document_diff(
  result : DocumentDiff,
  original : @model.TextSnapshot,
  modified : @model.TextSnapshot,
) -> DocumentDiff? {
  let normalized = normalize_document_diff(result, original, modified)
  if valid_document_diff(normalized, original, modified) {
    Some(normalized)
  } else {
    None
  }
}
