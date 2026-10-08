// Renderer-neutral document diff contract. Unlike the old partial Monaco
// `ILinesDiffComputer` facade, this API describes only behavior implemented by
// this repository: synchronous calculation, trim-whitespace policy, changes
// classified by visibility.

///|
/// Options shared by all synchronous document diff providers.
pub(all) struct DocumentDiffOptions {
  ignore_trim_whitespace : Bool
} derive(Eq, Debug)

///|
/// Whether a change participates in visible diff features. Ignored changes
/// still participate in line alignment; providers recompute when filters change.
pub(all) enum DocumentDiffChangeKind {
  Visible
  Ignored
} derive(Eq, Debug)

///|
/// One source change and its visibility in this computation.
pub(all) struct DocumentDiffChange {
  kind : DocumentDiffChangeKind
  mapping : DetailedLineRangeMapping
} derive(Eq, Debug)

///|
pub fn DocumentDiffChange::DocumentDiffChange(
  mapping : DetailedLineRangeMapping,
  kind? : DocumentDiffChangeKind = Visible,
) -> DocumentDiffChange {
  { kind, mapping, }
}

///|
/// A complete document diff. All changes drive alignment; only Visible changes
/// drive decorations, overview markers, and navigation. Mappings are ordered
/// on both sides, with equal unchanged gaps. Touching changes of the same kind
/// are grouped; different kinds may touch but never overlap.
pub(all) struct DocumentDiff {
  changes : Array[DocumentDiffChange]
} derive(Eq, Debug)

///|
/// Synchronous, renderer-neutral document diff provider. Providers may raise
/// when calculation fails; the owning diff ViewModel is responsible for
/// converting that failure into its `Failed` state.
pub(open) trait DocumentDiffProvider {
  fn compute_diff(
    Self,
    @model.TextSnapshot,
    @model.TextSnapshot,
    DocumentDiffOptions,
  ) -> DocumentDiff raise

  /// Notifies the owner that provider configuration changed and the current
  /// model pair must be recomputed. Immutable providers return a no-op
  /// disposable and never invoke the listener.
  fn on_did_change(Self, () -> Unit) -> @base_common.Disposable

  /// Opt in only when the provider is exactly the built-in serializable algorithm.
  fn worker_kind(Self) -> DocumentDiffWorkerKind? = _
}

///|
pub extend DocumentDiff with Debug::{to_repr}

///|
pub extend DocumentDiff with Eq::{equal, not_equal}

///|
pub extend DocumentDiffOptions with Debug::{to_repr}

///|
pub extend DocumentDiffOptions with Eq::{equal, not_equal}

///|
pub extend DocumentDiffChangeKind with Debug::{to_repr}

///|
pub extend DocumentDiffChangeKind with Eq::{equal, not_equal}

///|
pub extend DocumentDiffChange with Debug::{to_repr}

///|
pub extend DocumentDiffChange with Eq::{equal, not_equal}

///|
pub(all) enum DocumentDiffWorkerKind {
  Line
}

///|
impl DocumentDiffProvider with fn worker_kind(_self) {
  None
}
