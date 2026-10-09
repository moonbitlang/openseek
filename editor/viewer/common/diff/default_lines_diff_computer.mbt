// Built-in synchronous document diff provider. Its renderer-neutral contract
// stays local, while its readability pipeline follows the pinned VS Code
// Advanced diff's weighted short-sequence alignment and heuristic refinement.
// moonbitlang/core/diff's Myers implementation remains the large-sequence
// fallback; timeout and move protocols remain outside this contract.

///|
/// Stateless built-in document diff provider.
pub struct LineDocumentDiffProvider {
  _unit : Unit
} derive(Eq, Debug)

///|
pub fn LineDocumentDiffProvider::LineDocumentDiffProvider() -> LineDocumentDiffProvider {
  { _unit: (), }
}

///|
fn snapshot_lines(snapshot : @model.TextSnapshot) -> Array[String] {
  let lines : Array[String] = []
  for line_number in 1..<=snapshot.line_count() {
    lines.push(snapshot.get_line_content(line_number))
  }
  lines
}

///|
pub fn LineDocumentDiffProvider::compute_diff(
  self : LineDocumentDiffProvider,
  original : @model.TextSnapshot,
  modified : @model.TextSnapshot,
  options : DocumentDiffOptions,
) -> DocumentDiff {
  self.compute_lines_diff(
    snapshot_lines(original),
    snapshot_lines(modified),
    options,
  )
}

///|
fn LineDocumentDiffProvider::compute_lines_diff(
  self : LineDocumentDiffProvider,
  original_lines : Array[String],
  modified_lines : Array[String],
  options : DocumentDiffOptions,
) -> DocumentDiff {
  ignore(self)
  // Normalize before both equality and empty-document handling. Otherwise a
  // whitespace-only logical line and an empty line incorrectly remain a
  // visible change when trim whitespace is ignored.
  let old_input = if options.ignore_trim_whitespace {
    original_lines.map(line => line.trim().to_owned())
  } else {
    original_lines
  }
  let new_input = if options.ignore_trim_whitespace {
    modified_lines.map(line => line.trim().to_owned())
  } else {
    modified_lines
  }
  if old_input == new_input {
    return { changes: [], }
  }

  // Preserve Monaco's useful empty-document shape: its one logical empty line
  // participates in a single whole-document change.
  if (old_input.length() == 1 && old_input[0].length() == 0) ||
    (new_input.length() == 1 && new_input[0].length() == 0) {
    return {
      changes: [
        DocumentDiffChange(
          DetailedLineRangeMapping(
            LineRange(1, original_lines.length() + 1),
            LineRange(1, modified_lines.length() + 1),
            compute_inner_changes(
              original_lines,
              modified_lines,
              LineRange(1, original_lines.length() + 1),
              LineRange(1, modified_lines.length() + 1),
              options.ignore_trim_whitespace,
            ),
          ),
        ),
      ],
    }
  }

  let line_diffs = include_strict_whitespace_line_diffs(
    original_lines,
    modified_lines,
    compute_advanced_line_diffs(original_lines, modified_lines),
    options.ignore_trim_whitespace,
  )
  let changes : Array[DetailedLineRangeMapping] = []
  for diff in line_diffs {
    let original_line_range = @base_common.LineRange(
      diff.original.start + 1,
      diff.original.end_exclusive + 1,
    )
    let modified_line_range = @base_common.LineRange(
      diff.modified.start + 1,
      diff.modified.end_exclusive + 1,
    )
    let inner_changes = compute_inner_changes(
      original_lines,
      modified_lines,
      original_line_range,
      modified_line_range,
      options.ignore_trim_whitespace,
    )
    let line_mapping = match inner_changes {
      Some(inner_changes) =>
        line_range_mapping_from_inner_changes(
          inner_changes, original_lines, modified_lines,
        ).unwrap_or(LineRangeMapping(original_line_range, modified_line_range))
      None => LineRangeMapping(original_line_range, modified_line_range)
    }
    changes.push(
      DetailedLineRangeMapping(
        line_mapping.original,
        line_mapping.modified,
        inner_changes,
      ),
    )
  }
  { changes: changes.map(mapping => DocumentDiffChange(mapping)), }
}

///|
pub impl DocumentDiffProvider for LineDocumentDiffProvider with fn compute_diff(
  self,
  original,
  modified,
  options,
) {
  self.compute_diff(original, modified, options)
}

///|
pub impl DocumentDiffProvider for LineDocumentDiffProvider with fn on_did_change(
  _self,
  _listener,
) {
  @base_common.Disposable::from(() => ())
}

///|
pub extend LineDocumentDiffProvider with Debug::{to_repr}

///|
pub extend LineDocumentDiffProvider with Eq::{equal, not_equal}

///|
pub extend LineDocumentDiffProvider with DocumentDiffProvider::{on_did_change}

///|
pub impl DocumentDiffProvider for LineDocumentDiffProvider with fn worker_kind(
  _self,
) {
  Some(Line)
}

///|
pub extend LineDocumentDiffProvider with DocumentDiffProvider::{worker_kind}
