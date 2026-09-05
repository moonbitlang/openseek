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
  File(path~ : @pathx.Relative)
  GitDiff(diff~ : GitHistoryDiff)
  // A browser page, rendered by a host-owned native web contents view; the
  // id keys the `preview` package's page state and the host's view. Page
  // ids are global, so a parked strip's tabs keep naming their pages.
  Browser(id~ : Int)
  // The transient open-a-file tab (at most one): the file view's tree with
  // a pick-a-file placeholder. Picking a file replaces it in place.
  FilePicker
  // The subagent viewer this enum's comment anticipated: every workflow the
  // conversation's snippets announced, one row per subagent, each a click
  // from that child's own transcript. At most one lives in the strip.
  Workflows
} derive(Eq)

///|
/// A conversation's parked strip: identities and the active tab only,
/// mirroring how fileeditor used to park its tab set. Restoring never brings
/// content back by itself — the content subsystems reload on demand.
pub(all) struct RememberedStrip {
  tabs : Array[DockTab]
  active : DockTab?
} derive(Eq)

///|
/// The dock's state. Invariant: `active` is `None` exactly when `tabs` is
/// empty (an empty strip shows the panel's placeholder body; from M2 on, the
/// launcher menu).
pub(all) struct State {
  // Which conversation the live strip belongs to; `None` before the first
  // sync. Switching conversations parks the strip under this key.
  owner : @interop.ConversationKey?
  // The strip, in opening order, and the tab whose body is on screen.
  tabs : Array[DockTab]
  active : DockTab?
  // Strips parked by conversation switches, restored when their conversation
  // returns to the screen.
  remembered : Map[@interop.ConversationKey, RememberedStrip]
} derive(Eq)

///|
pub fn State::empty() -> State {
  { owner: None, tabs: [], active: None, remembered: Map([]), }
}

///|
/// The strip's file paths, in strip order — the projection the root update
/// hands to fileeditor's `Ctx` for its stat/watch/reload sweeps.
pub fn file_paths(state : State) -> Array[@pathx.Relative] {
  let paths : Array[@pathx.Relative] = []
  for tab in state.tabs {
    if tab is File(path~) {
      paths.push(path)
    }
  }
  paths
}

///|
/// The active tab's file path, when the active tab is a file.
pub fn active_file(state : State) -> @pathx.Relative? {
  match state.active {
    Some(File(path~)) => Some(path)
    _ => None
  }
}

///|
pub fn history_diffs(state : State) -> Array[GitHistoryDiff] {
  let diffs : Array[GitHistoryDiff] = []
  for tab in state.tabs {
    if tab is GitDiff(diff~) {
      diffs.push(diff)
    }
  }
  diffs
}

///|
pub fn active_history_diff(state : State) -> GitHistoryDiff? {
  match state.active {
    Some(GitDiff(diff~)) => Some(diff)
    _ => None
  }
}

///|
/// The active tab's browser page id, when the active tab is a browser page.
pub fn active_browser(state : State) -> Int? {
  match state.active {
    Some(Browser(id~)) => Some(id)
    _ => None
  }
}

///|
pub extend DockTab with Eq::{equal, not_equal}

///|
pub extend RememberedStrip with Eq::{equal, not_equal}

///|
pub extend State with Eq::{equal, not_equal}

///|
pub extend GitHistoryDiff with Debug::{to_repr}

///|
pub extend GitHistoryDiff with Eq::{equal, not_equal}
