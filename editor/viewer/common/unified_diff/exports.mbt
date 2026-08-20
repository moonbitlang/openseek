// Deliberate external/staged contracts for the full-diff renderer planned as
// this package's first production consumer. Keeping the surface here makes the
// temporary analyzer exception explicit while the renderer lands separately.

///|
/// One line in a unified diff hunk.
pub(all) enum UnifiedDiffLineKind {
  Context
  Deletion
  Addition
} derive(Eq, Debug)

///|
/// A line carries the number for each side on which it exists. Context lines
/// have both, deletions only the original number, and additions only the
/// modified number.
pub(all) struct UnifiedDiffLine {
  kind : UnifiedDiffLineKind
  original_line_number : Int?
  modified_line_number : Int?
  text : String
} derive(Eq, Debug)

///|
/// One review comment submitted from a rendered unified-diff line. The line
/// retains both number domains so a host can attach additions/context to the
/// working document and deletions to the original revision without depending
/// on renderer DOM attributes.
pub(all) struct UnifiedDiffLineComment {
  line : UnifiedDiffLine
  comment : String
} derive(Eq, Debug)

///|
/// One context-bounded unified diff hunk. Start numbers follow unified-diff
/// notation: an empty side is anchored at the preceding line (zero at the
/// beginning of a file).
pub(all) struct UnifiedDiffHunk {
  original_start_line_number : Int
  original_line_count : Int
  modified_start_line_number : Int
  modified_line_count : Int
  lines : Array[UnifiedDiffLine]
} derive(Eq, Debug)

///|
/// One algorithm-neutral line change. Ranges are 1-based and half-open;
/// an empty original range is an insertion and an empty modified range is a
/// deletion. Algorithms must return changes in document order.
pub(all) struct UnifiedDiffChange {
  original_start_line_number : Int
  original_end_line_number_exclusive : Int
  modified_start_line_number : Int
  modified_end_line_number_exclusive : Int
} derive(Eq, Debug)

///|
/// Options that belong to line matching rather than hunk presentation.
pub(all) struct UnifiedDiffAlgorithmOptions {
  ignore_trim_whitespace : Bool
  max_computation_time_ms : Int
} derive(Eq, Debug)

///|
/// Replaceable line-matching boundary. The unified-hunk model depends only on
/// `UnifiedDiffChange`, so a future algorithm needs only this small adapter.
struct UnifiedDiffAlgorithm {
  compute_changes_callback : (
    Array[String],
    Array[String],
    UnifiedDiffAlgorithmOptions,
  ) -> Array[UnifiedDiffChange]
}

///|
/// Creates an algorithm adapter from a line-change callback.
pub fn UnifiedDiffAlgorithm::UnifiedDiffAlgorithm(
  compute_changes~ : (Array[String], Array[String], UnifiedDiffAlgorithmOptions) -> Array[
    UnifiedDiffChange,
  ],
) -> UnifiedDiffAlgorithm {
  { compute_changes_callback: compute_changes }
}

///|
/// The current adapter uses the editor's existing diff engine, keeping full
/// and quick diff aligned without coupling the hunk builder to that engine.
pub fn default_unified_diff_algorithm() -> UnifiedDiffAlgorithm {
  UnifiedDiffAlgorithm(compute_changes=(original_lines, modified_lines, options) => {
    @diff.get_default().compute_diff(original_lines, modified_lines, {
      ignore_trim_whitespace: options.ignore_trim_whitespace,
      max_computation_time_ms: options.max_computation_time_ms,
      compute_moves: false,
    }).changes.map(change => {
      original_start_line_number: change.original.start_line_number,
      original_end_line_number_exclusive: change.original.end_line_number_exclusive,
      modified_start_line_number: change.modified.start_line_number,
      modified_end_line_number_exclusive: change.modified.end_line_number_exclusive,
    })
  })
}

///|
/// Compute context-bounded unified diff hunks from two arrays of lines.
///
/// Both `[]` and the editor's `[""]` representation are treated as an empty
/// document before invoking the algorithm.
///
/// By default, line mapping comes from the editor's existing diff engine so a
/// future full-diff view and the current quick-diff gutter agree. Pass an
/// alternate `algorithm` to replace matching without changing hunk rendering.
pub fn compute_unified_diff(
  original_lines : Array[String],
  modified_lines : Array[String],
  context_lines? : Int = 3,
  ignore_trim_whitespace? : Bool = false,
  max_computation_time_ms? : Int = 1000,
  algorithm? : UnifiedDiffAlgorithm = default_unified_diff_algorithm(),
) -> Array[UnifiedDiffHunk] {
  let context_lines = context_lines.max(0)
  let original_lines = canonical_diff_lines(original_lines)
  let modified_lines = canonical_diff_lines(modified_lines)
  let changes = algorithm.compute_changes(original_lines, modified_lines, {
    ignore_trim_whitespace,
    max_computation_time_ms,
  })
  hunk_windows(
    changes,
    original_lines.length(),
    modified_lines.length(),
    context_lines,
  ).map(window => window.to_hunk(original_lines, modified_lines))
}

///|
pub extend UnifiedDiffAlgorithmOptions with Debug::{to_repr}

///|
pub extend UnifiedDiffAlgorithmOptions with Eq::{equal, not_equal}

///|
pub extend UnifiedDiffChange with Debug::{to_repr}

///|
pub extend UnifiedDiffChange with Eq::{equal, not_equal}

///|
pub extend UnifiedDiffHunk with Debug::{to_repr}

///|
pub extend UnifiedDiffHunk with Eq::{equal, not_equal}

///|
pub extend UnifiedDiffLine with Debug::{to_repr}

///|
pub extend UnifiedDiffLine with Eq::{equal, not_equal}

///|
pub extend UnifiedDiffLineComment with Debug::{to_repr}

///|
pub extend UnifiedDiffLineComment with Eq::{equal, not_equal}

///|
pub extend UnifiedDiffLineKind with Debug::{to_repr}

///|
pub extend UnifiedDiffLineKind with Eq::{equal, not_equal}
