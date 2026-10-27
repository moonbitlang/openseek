// Exports kept on purpose even though no package in this workspace calls them
// outside tests. `moon ide analyze` counts cross-package uses only, so each
// block below records the consumer that needs it.

///|
/// The chip tint for a check rollup. Kept exported as a test seam:
/// `desktop/frontend/branch.mbt` asserts the tint for every rollup state.
pub fn GitChecks::tone(self : GitChecks) -> String {
  if self.failed > 0 {
    "failed"
  } else if self.pending > 0 {
    "pending"
  } else {
    "passed"
  }
}

///|
/// The localized one-line CI summary. Kept exported as a test seam:
/// `desktop/frontend/branch.mbt` asserts its counts and plural agreement.
pub fn GitChecks::summary(
  locale~ : @i18n.Locale = English,
  self : GitChecks,
) -> String {
  let parts : Array[String] = []
  if self.failed > 0 {
    parts.push(dynamic_text(locale, DFailedChecks(self.failed.to_string())))
  }
  if self.pending > 0 {
    parts.push(dynamic_text(locale, DPendingChecks(self.pending.to_string())))
  }
  if self.passed > 0 {
    parts.push(dynamic_text(locale, DPassedChecks(self.passed.to_string())))
  }
  if parts.is_empty() {
    ui(locale, NoChecks)
  } else {
    parts.join(" · ")
  }
}

///|
/// The chip label for a pull request in each state. Kept exported as a test
/// seam: `desktop/frontend/branch.mbt` asserts every state's label.
pub fn GitPullRequest::label(self : GitPullRequest) -> String {
  let suffix = match self.state {
    "open" => if self.draft { " Draft" } else { "" }
    "merged" => " Merged"
    "closed" => " Closed"
    _ => ""
  }
  "#\{self.number}\{suffix}"
}

///|
/// The chip tint of a presentation without a pull request. Kept exported as a
/// test seam: `desktop/frontend/branch.mbt` asserts the "none" tint.
pub fn GitPresentation::tone(self : GitPresentation) -> String {
  self.pull_request
  .bind(pull_request => pull_request.checks)
  .map(checks => checks.tone())
  .unwrap_or("none")
}

///|
/// The archive-discard warning sentence. Kept exported as a test seam:
/// `desktop/frontend/worktrees.mbt` asserts it names the host's changed paths.
pub fn WorktreeArchiveDialog::message(
  locale~ : @i18n.Locale = English,
  self : WorktreeArchiveDialog,
) -> String {
  let refusal = self.refusal
  let preview = dirty_paths_preview(
    refusal.dirty_paths,
    refusal.dirty_path_count,
  )
  dynamic_text(
    locale,
    DArchiveWarning(refusal.worktree.to_string(), preview.to_string()),
  )
}
