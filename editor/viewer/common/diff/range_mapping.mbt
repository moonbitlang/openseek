// Port of `vscode/src/vs/editor/common/diff/rangeMapping.ts` (vscode
// checked-in submodule): the mapping
// types a lines-diff result is expressed in.
//
// Parity ledger (source members):
// - `LineRangeMapping` — DEFERRED (the current computer emits detailed line
//   mappings directly, so the base-only mapping has no consumer).
// - `DetailedLineRangeMapping` — PORTED as a flat struct (MoonBit has no
//   class inheritance; it repeats `original`/`modified` beside
//   `inner_changes`). The default computer now fills character-level mappings
//   and exposes them as public range pairs; `toTextEdit`/`fromRangeMappings`/
//   `withInnerChangesFromLineRanges` remain DEFERRED (need TextEdit /
//   `LineRange.fromRangeInclusive` / `toRangeMapping`).
// - `RangeMapping` originalRange/modifiedRange/ctor/toString/flip/join —
//   PORTED. Statics `fromEdit`/`fromEditJoin`/`toTextEdit` — DEFERRED (no
//   TextEdit type); `join(list)`/`assertSorted` — DEFERRED (no consumer).
// - `lineRangeMappingFromRangeMappings`/`getLineRangeMapping` — DEFERRED
//   (only the char-level refinement pipeline builds line mappings from range
//   mappings; the viewer's computer emits line mappings directly).

///|
/// Maps a line range in the original text model to a line range in the
/// modified text model, together with the character-level inner range
/// mappings — `DetailedLineRangeMapping` (`rangeMapping.ts:196`). The source
/// class extends `LineRangeMapping`; MoonBit has no inheritance, so the
/// struct is flat and repeats the two line ranges.
pub struct DetailedLineRangeMapping {
  original : @base_common.LineRange
  modified : @base_common.LineRange
  /// If inner changes have not been computed, this is `None`. Otherwise it
  /// represents the character-level diff in this line range.
  priv inner_changes : Array[RangeMapping]?
} derive(Eq, Debug)

///|
fn DetailedLineRangeMapping::DetailedLineRangeMapping(
  original_range : @base_common.LineRange,
  modified_range : @base_common.LineRange,
  inner_changes : Array[RangeMapping]?,
) -> DetailedLineRangeMapping {
  { original: original_range, modified: modified_range, inner_changes }
}

///|
/// Character-level changes inside this line mapping, or `None` when the
/// refinement budget was exceeded. Returning public range pairs keeps the
/// package-private `RangeMapping` representation out of the public API while
/// allowing DiffViewer to render the computed refinement.
pub fn DetailedLineRangeMapping::get_inner_changes(
  self : DetailedLineRangeMapping,
) -> Array[(@base_common.Range, @base_common.Range)]? {
  self.inner_changes.map(changes => {
    changes.map(change => (change.original_range, change.modified_range))
  })
}

///|
/// Maps a range in the original text model to a range in the modified text
/// model — `RangeMapping` (`rangeMapping.ts:243`).
priv struct RangeMapping {
  /// The original range.
  original_range : @base_common.Range
  /// The modified range.
  modified_range : @base_common.Range
} derive(Eq, Debug)

///|
fn RangeMapping::RangeMapping(
  original_range : @base_common.Range,
  modified_range : @base_common.Range,
) -> RangeMapping {
  { original_range, modified_range }
}

///|
pub extend DetailedLineRangeMapping with Debug::{to_repr}

///|
pub extend DetailedLineRangeMapping with Eq::{equal, not_equal}
