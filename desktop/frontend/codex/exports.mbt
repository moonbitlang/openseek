// Deliberate exports with no production consumer in the workspace; see
// shrink_package.md. Each block names the consumer `moon ide analyze` counts as
// a test-only use: the `desktop/frontend` package's tests, which reach Codex
// state through the same boundary production uses.

///|
/// Build state from the authoritative `thread/read(includeTurns=true)` reply.
/// The shell's black-box workspace tests use the same boundary as production
/// instead of constructing Codex's private thread representation.
///
/// Test seam for `desktop/frontend` tests: `approval_mode_wbtest.mbt` ("a
/// started Codex turn closes the shell-owned approval menu"),
/// `browser_annotation.mbt` ("browser picks attach to the Codex composer
/// without changing the OpenSeek draft"), `chats_wbtest.mbt` ("managed Codex
/// chats are excluded from Chat and Work lists", "navigation does not restore
/// retired standalone Codex conversations"), `cloud_chat_wbtest.mbt` ("Codex
/// projection cannot use the remembered Cloud transcript or its capability
/// restrictions", "managed local and Codex Chats start Cloud even when
/// browsing Work", "new-chat shortcuts create conversations in the selected
/// Codex project"), `office_selection_wbtest.mbt` (its
/// `office_selection_model` helper), `task_status_wbtest.mbt` (the three
/// "Codex outcomes ..." tests), `update.mbt` (twelve Codex tests there) and
/// `worktrees.mbt` ("worktree broadcasts and reconnect snapshots update an
/// open Codex task").
pub fn State::from_thread_snapshot(value : Json) -> State {
  State().with_thread_reply(value, CodexImportedSnapshot)
}

///|
/// Expose the draft as read-only text for shell-level integration tests.
///
/// Test seam for `desktop/frontend` tests: `console.mbt` ("account changes
/// retire focused host mirrors before the new roster answers") and
/// `update.mbt` ("Codex editor comments use annotation context, not textarea
/// text or OpenSeek chat").
pub fn State::draft_text(self : State) -> String {
  self.draft
}
