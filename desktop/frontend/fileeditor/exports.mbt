// Public surface this package keeps exported on purpose: each block below is
// reachable only from another package, so it carries the reason it stays
// `pub`. Everything else the package exports has an ordinary consumer.

///|
/// Test seam. `desktop/frontend`'s tests build `EditorCommentAdded`,
/// `DiffCommentAdded` and `ApplyEditorFeedback` payloads by hand and assert on
/// `ModelUri::resource`, so they need to mint a model URI without a document
/// table (see `cloud_file_references_wbtest.mbt`, `composer_contract_wbtest.mbt`
/// and the editor-comment tests in `update.mbt`). Production code in that
/// package only ever receives one from this package's events.
pub fn ModelUri::of(resource : @common.Uri) -> ModelUri {
  ModelUri(resource.to_string())
}

///|
/// Settle a freshly projected placement against the retained one: a ready
/// value goes live and anything else parks. An unresolved projection keeps the
/// retained identity, because a gap must not erase what recovery compares
/// against. A new incarnation reconciles from `PlacementUnknown` instead, so
/// the checkout it replaced is not carried into it.
///
/// Test seam. `desktop/frontend`'s file-panel fixtures settle a placement
/// before dispatching (`placement: PlacementUnknown.reconcile(…)` in
/// `office_selection_wbtest.mbt`), so a panel state with a live or parked
/// checkout can be built without a host round trip.
pub fn ReconciledPlacement::reconcile(
  self : ReconciledPlacement,
  current : @interop.CheckoutPlacement?,
) -> ReconciledPlacement {
  match current {
    Some(value) if value.is_ready() => PlacementLive(value)
    Some(value) => PlacementParked(last_known=Some(value))
    None => PlacementParked(last_known=self.identity())
  }
}

///|
/// Whether reconciliation has parked this panel.
///
/// Test seam. `desktop/frontend`'s worktree tests assert that a missing
/// checkout parks the panel (`file_panel.placement.is_parked()` in
/// `worktrees.mbt`).
pub fn ReconciledPlacement::is_parked(self : ReconciledPlacement) -> Bool {
  self is PlacementParked(_)
}
