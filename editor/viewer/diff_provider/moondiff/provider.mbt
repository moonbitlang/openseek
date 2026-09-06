///|
/// MoonDiff mode selected by the desktop review host. Line is intentionally
/// absent from the fragment provider below: Line continues to use the normal
/// full-file DiffEditor provider.
pub(all) enum MoonDiffMode {
  Line
  Token
  Tree
} derive(Eq, Debug)

///|
/// Immutable provider for one already-aligned MoonDiff fragment. A fragment
/// is linear by construction; top-level ordering stays outside this provider
/// and is represented by separate DiffEditor instances in the desktop host.
pub struct MoonFragmentDiffProvider {
  document : @diff.DocumentDiff
} derive(Eq, Debug)

///|
pub fn MoonFragmentDiffProvider::MoonFragmentDiffProvider(
  document : @diff.DocumentDiff,
) -> MoonFragmentDiffProvider {
  { document, }
}

///|
pub fn MoonFragmentDiffProvider::as_document_diff_provider(
  self : MoonFragmentDiffProvider,
) -> &@diff.DocumentDiffProvider {
  self
}

///|
pub impl @diff.DocumentDiffProvider for MoonFragmentDiffProvider with fn compute_diff(
  self,
  _original,
  _modified,
  _options,
) {
  self.document
}

///|
pub impl @diff.DocumentDiffProvider for MoonFragmentDiffProvider with fn on_did_change(
  _self,
  _listener,
) {
  @base_common.Disposable::from(() => ())
}

///|
fn source_lines(source : String) -> Array[String] {
  source.split("\n").map(line => line.to_owned()).collect()
}

///|
fn valid_hunk_range(start : Int, len : Int, total : Int) -> Bool {
  start >= 0 && len >= 0 && start <= total && len <= total - start
}

///|
fn valid_fragment_line(
  line : @mbtdiff.DiffLine,
  expected_index : Int,
  source : Array[String],
) -> Bool {
  line.index == expected_index &&
  expected_index >= 0 &&
  expected_index < source.length() &&
  line.text() == source[expected_index]
}

///|
fn changed_ranges(line : @mbtdiff.DiffLine) -> Array[@base_common.Range] {
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
fn line_end_anchor(line : @mbtdiff.DiffLine) -> @base_common.Range {
  let column = line.text().length() + 1
  Range(line.index + 1, column, line.index + 1, column)
}

///|
fn cursor_anchor(lines : Array[String], cursor : Int) -> @base_common.Range {
  if lines.is_empty() {
    return Range(1, 1, 1, 1)
  }
  if cursor < lines.length() {
    let line_number = cursor.max(0) + 1
    return Range(line_number, 1, line_number, 1)
  }
  let line_number = lines.length()
  let column = lines[line_number - 1].length() + 1
  Range(line_number, column, line_number, column)
}

///|
/// Preserve every changed segment. When one side has more changed spans than
/// the other, the surplus spans map to the opposite line end instead of being
/// dropped. This is local intraline geometry, not a synthesized top-level
/// ordering.
fn paired_inner_changes(
  original : @mbtdiff.DiffLine,
  modified : @mbtdiff.DiffLine,
) -> Array[@diff.RangeMapping]? {
  let original_ranges = changed_ranges(original)
  let modified_ranges = changed_ranges(modified)
  if original_ranges.is_empty() && modified_ranges.is_empty() {
    return Some([])
  }
  let count = original_ranges.length().max(modified_ranges.length())
  let original_anchor = line_end_anchor(original)
  let modified_anchor = line_end_anchor(modified)
  Some(
    [
      for index in 0..<count => {
        RangeMapping(
          original_ranges.get(index).unwrap_or(original_anchor),
          modified_ranges.get(index).unwrap_or(modified_anchor),
        )
      }
    ],
  )
}

///|
fn paired_change(
  original : @mbtdiff.DiffLine,
  modified : @mbtdiff.DiffLine,
) -> @diff.DetailedLineRangeMapping {
  DetailedLineRangeMapping(
    LineRange(original.index + 1, original.index + 2),
    LineRange(modified.index + 1, modified.index + 2),
    paired_inner_changes(original, modified),
  )
}

///|
fn old_only_change(
  original : @mbtdiff.DiffLine,
  modified_cursor : Int,
  modified_lines : Array[String],
) -> @diff.DetailedLineRangeMapping {
  let anchor = cursor_anchor(modified_lines, modified_cursor)
  DetailedLineRangeMapping(
    LineRange(original.index + 1, original.index + 2),
    LineRange(modified_cursor + 1, modified_cursor + 1),
    Some(
      changed_ranges(original).map(original_range => {
        RangeMapping(original_range, anchor)
      }),
    ),
  )
}

///|
fn new_only_change(
  modified : @mbtdiff.DiffLine,
  original_cursor : Int,
  original_lines : Array[String],
) -> @diff.DetailedLineRangeMapping {
  let anchor = cursor_anchor(original_lines, original_cursor)
  DetailedLineRangeMapping(
    LineRange(original_cursor + 1, original_cursor + 1),
    LineRange(modified.index + 1, modified.index + 2),
    Some(
      changed_ranges(modified).map(modified_range => {
        RangeMapping(anchor, modified_range)
      }),
    ),
  )
}

///|
fn ranges_touch(
  left : @base_common.LineRange,
  right : @base_common.LineRange,
) -> Bool {
  left.end_line_number_exclusive >= right.start_line_number &&
  right.end_line_number_exclusive >= left.start_line_number
}

///|
fn append_change(
  changes : Array[@diff.DetailedLineRangeMapping],
  change : @diff.DetailedLineRangeMapping,
) -> Unit {
  guard !changes.is_empty() else {
    changes.push(change)
    return
  }
  let index = changes.length() - 1
  let previous = changes[index]
  if !ranges_touch(previous.original, change.original) &&
    !ranges_touch(previous.modified, change.modified) {
    changes.push(change)
    return
  }
  let inner_changes = match (previous.inner_changes, change.inner_changes) {
    (Some(first), Some(second)) => {
      let joined = first.copy()
      joined.append(second)
      Some(joined)
    }
    _ => None
  }
  changes[index] = DetailedLineRangeMapping(
    previous.original.join(change.original),
    previous.modified.join(change.modified),
    inner_changes,
  )
}

///|
fn append_alignment(
  alignments : Array[@diff.LineRangeMapping],
  alignment : @diff.LineRangeMapping,
) -> Unit {
  guard !alignments.is_empty() else {
    alignments.push(alignment)
    return
  }
  let index = alignments.length() - 1
  let previous = alignments[index]
  if !ranges_touch(previous.original, alignment.original) &&
    !ranges_touch(previous.modified, alignment.modified) {
    alignments.push(alignment)
    return
  }
  alignments[index] = LineRangeMapping(
    previous.original.join(alignment.original),
    previous.modified.join(alignment.modified),
  )
}

///|
fn append_fragment_rows(
  rows : ArrayView[@mbtdiff.DiffRow],
  visible : Bool,
  original_lines : Array[String],
  modified_lines : Array[String],
  original_cursor : Int,
  modified_cursor : Int,
  changes : Array[@diff.DetailedLineRangeMapping],
  alignments : Array[@diff.LineRangeMapping],
) -> (Int, Int)? {
  let mut old_cursor = original_cursor
  let mut new_cursor = modified_cursor
  let block_changes : Array[@diff.DetailedLineRangeMapping] = []
  let block_alignments : Array[@diff.LineRangeMapping] = []
  for row in rows {
    match row {
      Paired(original, modified) => {
        if !valid_fragment_line(original, old_cursor, original_lines) ||
          !valid_fragment_line(modified, new_cursor, modified_lines) {
          return None
        }
        if visible {
          append_change(block_changes, paired_change(original, modified))
        }
        old_cursor += 1
        new_cursor += 1
      }
      OldOnly(original) => {
        if !valid_fragment_line(original, old_cursor, original_lines) {
          return None
        }
        let change = old_only_change(original, new_cursor, modified_lines)
        if visible {
          append_change(block_changes, change)
        } else {
          append_alignment(block_alignments, change.line_mapping())
        }
        old_cursor += 1
      }
      NewOnly(modified) => {
        if !valid_fragment_line(modified, new_cursor, modified_lines) {
          return None
        }
        let change = new_only_change(modified, old_cursor, original_lines)
        if visible {
          append_change(block_changes, change)
        } else {
          append_alignment(block_alignments, change.line_mapping())
        }
        new_cursor += 1
      }
    }
  }
  changes.append(block_changes)
  alignments.append(block_alignments)
  Some((old_cursor, new_cursor))
}

///|
fn adapt_fragment_document(
  document : @mbtdiff.HunkDocument,
  original_lines : Array[String],
  modified_lines : Array[String],
) -> @diff.DocumentDiff? {
  let changes : Array[@diff.DetailedLineRangeMapping] = []
  let alignments : Array[@diff.LineRangeMapping] = []
  for hunk in document.hunks {
    if !valid_hunk_range(hunk.old_start, hunk.old_len, original_lines.length()) ||
      !valid_hunk_range(hunk.new_start, hunk.new_len, modified_lines.length()) {
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
        ChangeBlock(rows) | IgnoredBlock(rows) => {
          guard append_fragment_rows(
              rows,
              block is ChangeBlock(_),
              original_lines,
              modified_lines,
              old_cursor,
              new_cursor,
              changes,
              alignments,
            )
            is Some((next_old, next_new)) else {
            return None
          }
          old_cursor = next_old
          new_cursor = next_new
        }
      }
    }
    if old_cursor != hunk.old_start + hunk.old_len ||
      new_cursor != hunk.new_start + hunk.new_len {
      return None
    }
  }
  Some({ changes, additional_alignments: alignments, })
}

///|
/// Convert exactly one MoonDiff fragment into the common DiffEditor contract.
/// No top-level ranges are rebased, sorted, padded, or flattened here.
fn fragment_document_diff(
  document : @mbtdiff.HunkDocument,
  original_source : String,
  modified_source : String,
) -> @diff.DocumentDiff? {
  let original : @model.TextSnapshot = TextSnapshot(original_source)
  let modified : @model.TextSnapshot = TextSnapshot(modified_source)
  guard adapt_fragment_document(
      document,
      source_lines(original_source),
      source_lines(modified_source),
    )
    is Some(candidate) else {
    return None
  }
  @diff.normalize_and_validate_document_diff(candidate, original, modified)
}

///|
pub extend MoonDiffMode with Eq::{equal, not_equal}

///|
pub extend MoonDiffMode with Debug::{to_repr}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend MoonFragmentDiffProvider with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` via the trait or `Repr(value)` instead", skip_current_package=true)
#doc(hidden)
pub extend MoonFragmentDiffProvider with Debug::{to_repr}

///|
#deprecated("Use the `@diff.DocumentDiffProvider` trait instead", skip_current_package=true)
#doc(hidden)
pub extend MoonFragmentDiffProvider with @diff.DocumentDiffProvider::{
  compute_diff,
  on_did_change,
}
