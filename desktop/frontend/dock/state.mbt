// The right panel's dock: one mixed tab strip whose entries may be of
// different kinds (files today; browser pages and other viewers later). The
// dock owns strip membership, order, and the active tab — the single source
// of truth the root update projects into the content subsystems (fileeditor
// receives the open-file list through its `Ctx`). Document state never lives
// here: a `File` tab is only an identity, and its content stays in the
// fileeditor package's document table.

///|
/// One strip entry. Adding a tab kind later (browser preview, subagent
/// viewer) is a new variant plus its body view — the strip machine itself
/// does not change.
pub(all) enum DockTab {
  File(path~ : @pathx.Relative)
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
  // Whether the right panel is expanded. The panel is always rendered (the
  // viewer host element must stay put) and merely hidden by CSS when closed.
  open : Bool
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
  { open: false, owner: None, tabs: [], active: None, remembered: Map([]) }
}

///|
/// The strip's file paths, in strip order — the projection the root update
/// hands to fileeditor's `Ctx` for its stat/watch/reload sweeps.
pub fn file_paths(state : State) -> Array[@pathx.Relative] {
  state.tabs.map(tab => {
    match tab {
      File(path~) => path
    }
  })
}

///|
/// The active tab's file path, when the active tab is a file.
pub fn active_file(state : State) -> @pathx.Relative? {
  match state.active {
    Some(File(path~)) => Some(path)
    None => None
  }
}
