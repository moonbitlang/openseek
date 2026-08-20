// Port of `vscode/src/vs/editor/common/diff/linesDiffComputer.ts` (vscode
// checked-in submodule): the computer
// options and result shape. The sole local engine is exposed concretely from
// `default_lines_diff_computer.mbt` instead of retaining the source interface
// as an unused runtime abstraction.
//
// Parity ledger (source members):
// - `ILinesDiffComputer.computeDiff` — PORTED as
//   `DefaultLinesDiffComputer::compute_diff`.
// - `ILinesDiffComputerOptions` — PORTED; `extendToSubwords?` — DEFERRED
//   (consumed only by the char-level refinement, which is not ported).
// - `LinesDiff` changes/hitTimeout — PORTED. Move detection and its result
//   shape are deferred because the viewer's computer does not implement it.

///|
/// `ILinesDiffComputerOptions` (`linesDiffComputer.ts:12`).
pub(all) struct LinesDiffComputerOptions {
  ignore_trim_whitespace : Bool
  /// `0` disables the computation budget entirely (Monaco's
  /// `InfiniteTimeout`).
  max_computation_time_ms : Int
  compute_moves : Bool
} derive(Eq, Debug)

///|
/// `LinesDiff` (`linesDiffComputer.ts:19`).
pub struct LinesDiff {
  changes : Array[DetailedLineRangeMapping]
  /// Indicates if the time out was reached. In that case, the diffs might be
  /// an approximation and the user should be asked to rerun the diff with
  /// more time.
  priv hit_timeout : Bool
} derive(Eq, Debug)

///|
pub extend LinesDiff with Debug::{to_repr}

///|
pub extend LinesDiff with Eq::{equal, not_equal}

///|
pub extend LinesDiffComputerOptions with Debug::{to_repr}

///|
pub extend LinesDiffComputerOptions with Eq::{equal, not_equal}
