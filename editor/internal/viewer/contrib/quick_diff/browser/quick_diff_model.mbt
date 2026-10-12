// The diff-computation half of `vscode/src/vs/workbench/contrib/scm/browser/
// quickDiffModel.ts` (checked-in vscode submodule), reduced to a pure function: the
// viewer's text models are immutable and the service stores one original per
// resource, so the source's reference-counted per-resource model (throttled
// recompute, provider merge, `compareChanges` sort) collapses to
// `compute_changes` — the `_diff` method's pipeline (`quickDiffModel.ts:348`:
// `editorWorkerService.computeDiff`) over the Line-diff-backed default computer.
// The decoration layer consumes its detailed line mappings directly, so the
// source's intermediate line-change re-encoding is unnecessary.
//
// Parity ledger: `QuickDiffModel._diff`'s computation — PORTED (`charChanges`
// — DEFERRED, the computer produces no inner changes). Everything else in
// `quickDiffModel.ts` (service/reference plumbing, editor-model sync,
// multi-provider merge) — N-A under the single-provider reduction (see
// `../common/quick_diff.mbt`).

///|
/// `QuickDiffModel._diff` (`quickDiffModel.ts:348`) reduced: computes the
/// line-level changes between the original document and the modified one.
/// The trim-whitespace default mirrors
/// `scm.diffDecorationsIgnoreTrimWhitespace`'s `'false'` default
/// (`scm.contribution.ts:239`). The local Line provider is synchronous and
/// has no wall-clock budget option.
pub fn compute_changes(
  original_lines : Array[String],
  modified_lines : Array[String],
  ignore_trim_whitespace~ : Bool = false,
) -> Array[@diff.DetailedLineRangeMapping] {
  @diff.LineDocumentDiffProvider().compute_diff(
    TextSnapshot(original_lines.join("\n")),
    TextSnapshot(modified_lines.join("\n")),
    { ignore_trim_whitespace, },
  ).changes.map(change => change.mapping)
}
