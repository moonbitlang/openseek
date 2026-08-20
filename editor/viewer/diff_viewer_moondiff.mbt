///|
/// The selected algorithm plus the line mappings consumed by the existing
/// decoration/alignment renderer. `effective_mode` records the algorithm that
/// produced those mappings when moondiff degrades Tree to Token or validation
/// rejects a specialized document and returns to Standard.
priv struct DiffChangeCalculation {
  changes : Array[DiffLineChange]
  effective_mode : DiffViewerMode
  fell_back : Bool
}

///|
fn DiffEditorModel::supports_moondiff(self : DiffEditorModel) -> Bool {
  self.modified.uri.path.to_lower().has_suffix(".mbt")
}

///|
fn standard_diff_changes(
  original_lines : Array[String],
  modified_lines : Array[String],
) -> Array[DiffLineChange] {
  let diff = @diff.get_default().compute_diff(original_lines, modified_lines, {
    ignore_trim_whitespace: false,
    max_computation_time_ms: 5000,
    compute_moves: false,
  })
  diff.changes.map(change => {
    let original_inner_changed : Array[@base_common.Range] = []
    let modified_inner_changed : Array[@base_common.Range] = []
    match change.get_inner_changes() {
      Some(inner_changes) =>
        for inner_change in inner_changes {
          let (original, modified) = inner_change
          original_inner_changed.push(original)
          modified_inner_changed.push(modified)
        }
      None => ()
    }
    {
      original: change.original,
      modified: change.modified,
      original_inner_changed,
      modified_inner_changed,
      render_change: true,
    }
  })
}

///|
fn calculate_diff_changes(
  requested_mode : DiffViewerMode,
  specialized_available : Bool,
  ignore_comments : Bool,
  original_lines : Array[String],
  modified_lines : Array[String],
  original_source : String,
  modified_source : String,
) -> DiffChangeCalculation {
  if !specialized_available || requested_mode is StandardDiff {
    return {
      changes: standard_diff_changes(original_lines, modified_lines),
      effective_mode: StandardDiff,
      fell_back: false,
    }
  }
  match
    moondiff_changes(
      requested_mode, ignore_comments, original_lines, modified_lines, original_source,
      modified_source,
    ) {
    Some(calculation) => calculation
    None =>
      {
        changes: standard_diff_changes(original_lines, modified_lines),
        effective_mode: StandardDiff,
        fell_back: true,
      }
  }
}

///|
fn moondiff_changes(
  mode : DiffViewerMode,
  ignore_comments : Bool,
  original_lines : Array[String],
  modified_lines : Array[String],
  original_source : String,
  modified_source : String,
) -> DiffChangeCalculation? {
  let (document, effective_mode, fell_back) = match mode {
    StandardDiff => return None
    TokenDiff =>
      (
        @tokdiff.diff(
          old=original_lines,
          new=modified_lines,
          context=0,
          line_cleanup=true,
          ignore_comments~,
        ),
        TokenDiff,
        false,
      )
    TreeDiff => {
      let result = @mbtdiff.diff(
        original_source,
        modified_source,
        options=@mbtdiff.DiffOptions::new(context_lines=0, ignore_comments~),
      )
      let fell_back = result.has_fallback()
      // A typed Tree fallback already contains moondiff's lexical document.
      // Keep that result instead of calculating an unrelated Standard diff.
      (
        result.document(),
        if fell_back {
          TokenDiff
        } else {
          TreeDiff
        },
        fell_back,
      )
    }
  }
  guard moondiff_document_changes(document, original_lines, modified_lines)
    is Some(changes) else {
    return None
  }
  // Token diff has no typed error channel, so validate its empty filtered
  // document against the unfiltered calculation. For either specialized mode,
  // keep validated one-sided rows as neutral alignment changes: comments and
  // blank lines remain undecorated, while later source lines still line up.
  if original_source != modified_source && changes.is_empty() {
    if ignore_comments {
      match ignored_only_alignment_changes(original_lines, modified_lines) {
        Some(alignment) =>
          return Some({ changes: alignment, effective_mode, fell_back })
        None if effective_mode is TokenDiff => return None
        None => ()
      }
    } else if effective_mode is TokenDiff {
      return None
    }
  }
  Some({ changes, effective_mode, fell_back })
}

///|
fn ignored_only_alignment_changes(
  original_lines : Array[String],
  modified_lines : Array[String],
) -> Array[DiffLineChange]? {
  let unfiltered = @tokdiff.diff(
    old=original_lines,
    new=modified_lines,
    context=0,
    line_cleanup=true,
    ignore_comments=false,
  )
  match moondiff_document_changes(unfiltered, original_lines, modified_lines) {
    Some(changes) if !changes.is_empty() => {
      let alignment = []
      for change in changes {
        if change.original.length() != change.modified.length() {
          alignment.push({
            original: change.original,
            modified: change.modified,
            original_inner_changed: [],
            modified_inner_changed: [],
            render_change: false,
          })
        }
      }
      Some(alignment)
    }
    _ => None
  }
}

///|
fn valid_moondiff_hunk_range(start : Int, len : Int, total : Int) -> Bool {
  start >= 0 && len >= 0 && start <= total && len <= total - start
}

///|
fn valid_moondiff_line(
  line : @tokdiff.DiffLine,
  expected_index : Int,
  source : Array[String],
) -> Bool {
  line.index == expected_index &&
  expected_index >= 0 &&
  expected_index < source.length() &&
  line.text() == source[expected_index]
}

///|
fn moondiff_inner_ranges(line : @tokdiff.DiffLine) -> Array[@base_common.Range] {
  let ranges : Array[@base_common.Range] = []
  let mut column = 1
  for segment in line.segments {
    let end_column = column + segment.text.length()
    if segment.kind is Changed && end_column > column {
      ranges.push(Range(line.index + 1, column, line.index + 1, end_column))
    }
    column = end_column
  }
  ranges
}

///|
fn moondiff_paired_change(
  original : @tokdiff.DiffLine,
  modified : @tokdiff.DiffLine,
) -> DiffLineChange {
  {
    original: LineRange(original.index + 1, original.index + 2),
    modified: LineRange(modified.index + 1, modified.index + 2),
    original_inner_changed: moondiff_inner_ranges(original),
    modified_inner_changed: moondiff_inner_ranges(modified),
    render_change: true,
  }
}

///|
fn moondiff_old_only_change(
  original : @tokdiff.DiffLine,
  modified_cursor : Int,
  render_change : Bool,
) -> DiffLineChange {
  {
    original: LineRange(original.index + 1, original.index + 2),
    modified: LineRange(modified_cursor + 1, modified_cursor + 1),
    original_inner_changed: moondiff_inner_ranges(original),
    modified_inner_changed: [],
    render_change,
  }
}

///|
fn moondiff_new_only_change(
  modified : @tokdiff.DiffLine,
  original_cursor : Int,
  render_change : Bool,
) -> DiffLineChange {
  {
    original: LineRange(original_cursor + 1, original_cursor + 1),
    modified: LineRange(modified.index + 1, modified.index + 2),
    original_inner_changed: [],
    modified_inner_changed: moondiff_inner_ranges(modified),
    render_change,
  }
}

///|
fn append_moondiff_rows(
  rows : Array[@tokdiff.DiffRow],
  render_changes : Bool,
  original_lines : Array[String],
  modified_lines : Array[String],
  original_cursor : Int,
  modified_cursor : Int,
  changes : Array[DiffLineChange],
) -> (Int, Int)? {
  let mut old_cursor = original_cursor
  let mut new_cursor = modified_cursor
  for row in rows {
    match row {
      Paired(original, modified) => {
        if !valid_moondiff_line(original, old_cursor, original_lines) ||
          !valid_moondiff_line(modified, new_cursor, modified_lines) {
          return None
        }
        if render_changes {
          changes.push(moondiff_paired_change(original, modified))
        }
        old_cursor += 1
        new_cursor += 1
      }
      OldOnly(original) => {
        if !valid_moondiff_line(original, old_cursor, original_lines) {
          return None
        }
        changes.push(
          moondiff_old_only_change(original, new_cursor, render_changes),
        )
        old_cursor += 1
      }
      NewOnly(modified) => {
        if !valid_moondiff_line(modified, new_cursor, modified_lines) {
          return None
        }
        changes.push(
          moondiff_new_only_change(modified, old_cursor, render_changes),
        )
        new_cursor += 1
      }
    }
  }
  Some((old_cursor, new_cursor))
}

///|
/// Validate moondiff's renderer-neutral document against the exact models and
/// adapt its zero-based aligned rows to the Viewer's one-based line/range
/// contract. Validation is also Token mode's failure boundary because its
/// public calculation API is deliberately total and has no typed error value.
fn moondiff_document_changes(
  document : @tokdiff.DiffDocument,
  original_lines : Array[String],
  modified_lines : Array[String],
) -> Array[DiffLineChange]? {
  let changes : Array[DiffLineChange] = []
  for hunk in document.hunks {
    if !valid_moondiff_hunk_range(
        hunk.old_start,
        hunk.old_len,
        original_lines.length(),
      ) ||
      !valid_moondiff_hunk_range(
        hunk.new_start,
        hunk.new_len,
        modified_lines.length(),
      ) {
      return None
    }
    let mut old_cursor = hunk.old_start
    let mut new_cursor = hunk.new_start
    for block in hunk.blocks {
      match block {
        ContextBlock(lines) =>
          for line in lines {
            if line.old_index != old_cursor ||
              line.new_index != new_cursor ||
              old_cursor >= original_lines.length() ||
              new_cursor >= modified_lines.length() ||
              line.text != original_lines[old_cursor] ||
              line.text != modified_lines[new_cursor] {
              return None
            }
            old_cursor += 1
            new_cursor += 1
          }
        ChangeBlock(rows) =>
          match
            append_moondiff_rows(
              rows, true, original_lines, modified_lines, old_cursor, new_cursor,
              changes,
            ) {
            Some((next_old, next_new)) => {
              old_cursor = next_old
              new_cursor = next_new
            }
            None => return None
          }
        IgnoredBlock(rows) =>
          match
            append_moondiff_rows(
              rows, false, original_lines, modified_lines, old_cursor, new_cursor,
              changes,
            ) {
            Some((next_old, next_new)) => {
              old_cursor = next_old
              new_cursor = next_new
            }
            None => return None
          }
      }
    }
    if old_cursor != hunk.old_start + hunk.old_len ||
      new_cursor != hunk.new_start + hunk.new_len {
      return None
    }
  }
  Some(changes)
}
