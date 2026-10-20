// The right panel's dock: one mixed tab strip whose entries may be of
// different kinds (files today; browser pages and other viewers later). The
// dock owns strip membership, order, and the active tab — the single source
// of truth the root update projects into the content subsystems (fileeditor
// receives the open-file list through its `Ctx`). Document state never lives
// here: a `File` tab is only an identity, and its content stays in the
// fileeditor package's document table.

///|
/// Immutable identity and tree coordinates for one historical comparison.
/// The surrounding strip is already scoped to a conversation owner, so the
/// commit/path pair distinguishes tabs without leaking filesystem paths into
/// the ordinary open-file projection.
pub(all) struct GitHistoryDiff {
  commit : String
  parent : String?
  path : @pathx.Relative
  original_path : @pathx.Relative?
  status : String
  kind : String
} derive(Eq, Debug)

///|
/// One strip entry. Adding a tab kind later (subagent viewer, review pane)
/// is a new variant plus its body view — the strip machine itself does not
/// change.
pub(all) enum DockTab {
  // Device-bound absolute identity; changing checkout never retargets a tab.
  File(path~ : @common.Uri)
  GitDiff(diff~ : GitHistoryDiff)
  // A browser page, rendered by a host-owned native web contents view; the
  // id keys the `preview` package's page state and the host's view. Page
  // ids are global, so each conversation's tabs keep naming their pages.
  Browser(id~ : Int32)
  // The transient open-a-file tab (at most one): the file view's tree with
  // a pick-a-file placeholder. Picking a file replaces it in place.
  FilePicker
  // The subagent viewer this enum's comment anticipated: every workflow the
  // conversation's snippets announced, one row per subagent, each a click
  // from that child's own transcript. At most one lives in the strip.
  Workflows
  Github
  Jobs
} derive(Eq)

///|
/// One conversation's dock. The root stores it under that conversation's key;
/// selecting another conversation does not move or copy either dock's tabs.
/// `active` is `None` exactly when `tabs` is empty, and a present active tab
/// belongs to `tabs`. An empty dock shows the launcher menu.
pub(all) struct DockState {
  // The strip, in opening order, and the tab whose body is on screen.
  tabs : Array[DockTab]
  active : DockTab?
} derive(Eq)

///|
pub fn DockState::empty() -> DockState {
  { tabs: [], active: None, }
}

///|
/// The strip's file paths, in strip order — the projection the root update
/// hands to fileeditor's `Ctx` for its stat/watch/reload sweeps.
pub fn file_paths(state : DockState) -> Array[@common.Uri] {
  [
    for tab in state.tabs if tab is File(path~) => path
  ]
}

///|
/// The active tab's file path, when the active tab is a file.
pub fn active_file(state : DockState) -> @common.Uri? {
  match state.active {
    Some(File(path~)) => Some(path)
    _ => None
  }
}

///|
pub fn history_diffs(state : DockState) -> Array[GitHistoryDiff] {
  [
    for tab in state.tabs if tab is GitDiff(diff~) => diff
  ]
}

///|
pub fn active_history_diff(state : DockState) -> GitHistoryDiff? {
  match state.active {
    Some(GitDiff(diff~)) => Some(diff)
    _ => None
  }
}

///|
/// The active tab's browser page id, when the active tab is a browser page.
pub fn active_browser(state : DockState) -> Int32? {
  match state.active {
    Some(Browser(id~)) => Some(id)
    _ => None
  }
}

///|
pub extend DockTab with Eq::{equal, not_equal}

///|
pub extend DockState with Eq::{equal, not_equal}

///|
pub extend GitHistoryDiff with Debug::{to_repr}

///|
pub extend GitHistoryDiff with Eq::{equal, not_equal}
