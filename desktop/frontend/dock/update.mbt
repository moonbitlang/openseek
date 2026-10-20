// The strip machine. `update` is pure and command-free: the cross-package
// effects of a strip transition (showing a document, clearing the viewer,
// mounting hosts) are the root update's to command — it compares `active`
// before and after and drives the content subsystems accordingly.

///|
pub(all) enum Msg {
  // A tab in the strip was clicked: put its body on screen.
  TabActivated(DockTab)
  // A tab's close button was clicked. Closing the active tab activates its
  // right neighbor, else its left, else none.
  TabClosed(DockTab)
}

///|
fn tab_index(state : DockState, tab : DockTab) -> Int32? {
  state.tabs.search_by(entry => entry == tab)
}

///|
pub fn update(msg : Msg, state : DockState) -> DockState {
  match msg {
    TabActivated(tab) =>
      if tab_index(state, tab) is Some(_) {
        { ..state, active: Some(tab), }
      } else {
        state
      }
    TabClosed(tab) =>
      match tab_index(state, tab) {
        Some(index) => {
          let tabs = state.tabs.filter(entry => entry != tab)
          let active = if state.active is Some(active_tab) && active_tab == tab {
            // The right neighbor inherits the screen; at the strip's end,
            // the left one.
            match tabs.get(index) {
              Some(next) => Some(next)
              None => if index > 0 { tabs.get(index - 1) } else { None }
            }
          } else {
            state.active
          }
          { tabs, active, }
        }
        None => state
      }
  }
}

///|
/// Append `tab` unless the strip already holds it, then make it active — the
/// shared body of the `open_*` entry points below.
fn open_tab(state : DockState, tab : DockTab) -> DockState {
  let tabs = if tab_index(state, tab) is Some(_) {
    state.tabs
  } else {
    let tabs = state.tabs.copy()
    tabs.push(tab)
    tabs
  }
  { tabs, active: Some(tab), }
}

///|
/// Open `path`'s file tab (appending one if it is not in the strip yet) and
/// make it active — the strip half of a tree click or a chip jump.
pub fn open_file(state : DockState, path : @common.Uri) -> DockState {
  open_tab(state, DockTab::File(path~))
}

///|
/// Open one immutable historical comparison. Equality includes the commit, so
/// the same path at two revisions stays independently inspectable.
pub fn open_history_diff(state : DockState, diff : GitHistoryDiff) -> DockState {
  open_tab(state, DockTab::GitDiff(diff~))
}

///|
/// Open browser page `id`'s tab (appending one if it is not in the strip
/// yet) and make it active. The caller owns the id: allocating the page and
/// asking the host for its native view are the browser subsystem's business.
pub fn open_browser(state : DockState, id : Int32) -> DockState {
  open_tab(state, DockTab::Browser(id~))
}

///|
/// Open the transient file-picker tab, re-activating the existing one — at
/// most one lives in the strip.
pub fn open_picker(state : DockState) -> DockState {
  open_tab(state, FilePicker)
}

///|
/// Open the workflows tab, re-activating the existing one — at most one
/// lives in the strip.
pub fn open_workflows(state : DockState) -> DockState {
  open_tab(state, Workflows)
}

///|
/// A file was picked while the picker tab is in the strip: the picker is
/// replaced in place by the selected tab — unless the tab is already open,
/// in which case its existing tab activates and the picker closes. Without
/// a picker this is a plain tab open.
pub fn resolve_pick(state : DockState, tab : DockTab) -> DockState {
  guard tab_index(state, FilePicker) is Some(picker_index) else {
    return open_tab(state, tab)
  }
  if tab_index(state, tab) is Some(_) {
    let tabs = state.tabs.filter(entry => !(entry is FilePicker))
    { tabs, active: Some(tab), }
  } else {
    let tabs = state.tabs.copy()
    tabs[picker_index] = tab
    { tabs, active: Some(tab), }
  }
}

///|
pub fn open_jobs(state : DockState) -> DockState {
  open_tab(state, Jobs)
}

///|
pub fn open_github(state : DockState) -> DockState {
  open_tab(state, Github)
}
