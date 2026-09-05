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
fn tab_index(state : State, tab : DockTab) -> Int? {
  state.tabs.search_by(entry => entry == tab)
}

///|
pub fn update(msg : Msg, state : State) -> State {
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
          let active = if state.active == Some(tab) {
            // The right neighbor inherits the screen; at the strip's end,
            // the left one.
            match tabs.get(index) {
              Some(next) => Some(next)
              None => if index > 0 { tabs.get(index - 1) } else { None }
            }
          } else {
            state.active
          }
          { ..state, tabs, active, }
        }
        None => state
      }
  }
}

///|
/// Open `path`'s file tab (appending one if it is not in the strip yet) and
/// make it active — the strip half of a tree click or a chip jump.
pub fn open_file(state : State, path : @pathx.Relative) -> State {
  let tab = DockTab::File(path~)
  let tabs = if tab_index(state, tab) is Some(_) {
    state.tabs
  } else {
    let tabs = state.tabs.copy()
    tabs.push(tab)
    tabs
  }
  { ..state, tabs, active: Some(tab), }
}

///|
/// Open one immutable historical comparison. Equality includes the commit, so
/// the same path at two revisions stays independently inspectable.
pub fn open_history_diff(state : State, diff : GitHistoryDiff) -> State {
  let tab = DockTab::GitDiff(diff~)
  let tabs = if tab_index(state, tab) is Some(_) {
    state.tabs
  } else {
    let tabs = state.tabs.copy()
    tabs.push(tab)
    tabs
  }
  { ..state, tabs, active: Some(tab), }
}

///|
/// Open browser page `id`'s tab (appending one if it is not in the strip
/// yet) and make it active. The caller owns the id: allocating the page and
/// asking the host for its native view are the browser subsystem's business.
pub fn open_browser(state : State, id : Int) -> State {
  let tab = DockTab::Browser(id~)
  let tabs = if tab_index(state, tab) is Some(_) {
    state.tabs
  } else {
    let tabs = state.tabs.copy()
    tabs.push(tab)
    tabs
  }
  { ..state, tabs, active: Some(tab), }
}

///|
/// Open the transient file-picker tab, re-activating the existing one — at
/// most one lives in the strip.
pub fn open_picker(state : State) -> State {
  let tabs = if tab_index(state, FilePicker) is Some(_) {
    state.tabs
  } else {
    let tabs = state.tabs.copy()
    tabs.push(FilePicker)
    tabs
  }
  { ..state, tabs, active: Some(FilePicker), }
}

///|
/// Open the workflows tab, re-activating the existing one — at most one
/// lives in the strip.
pub fn open_workflows(state : State) -> State {
  let tabs = if tab_index(state, Workflows) is Some(_) {
    state.tabs
  } else {
    let tabs = state.tabs.copy()
    tabs.push(Workflows)
    tabs
  }
  { ..state, tabs, active: Some(Workflows), }
}

///|
/// A file was picked while the picker tab is in the strip: the picker is
/// replaced in place by that file's tab — unless the file is already open,
/// in which case its existing tab activates and the picker closes. Without
/// a picker this is a plain `open_file`.
pub fn resolve_pick(state : State, path : @pathx.Relative) -> State {
  guard tab_index(state, FilePicker) is Some(picker_index) else {
    return open_file(state, path)
  }
  let file = DockTab::File(path~)
  if tab_index(state, file) is Some(_) {
    let tabs = state.tabs.filter(entry => !(entry is FilePicker))
    { ..state, tabs, active: Some(file), }
  } else {
    let tabs = state.tabs.copy()
    tabs[picker_index] = file
    { ..state, tabs, active: Some(file), }
  }
}

///|
/// Reconcile the strip with the active conversation: when the conversation
/// changed, park the current strip under its owner and restore the new
/// conversation's parked strip (or an empty one). Pure — reloading the
/// restored documents is the content subsystems' business, driven by their
/// own sync against the fresh projection.
pub fn sync(state : State, owner : @interop.ConversationKey) -> State {
  if state.owner == Some(owner) {
    return state
  }
  let remembered = state.remembered.copy()
  if state.owner is Some(previous) && !previous.session.is_empty() {
    remembered[previous] = { tabs: state.tabs, active: state.active, }
  }
  let (tabs, active) = match remembered.get(owner) {
    Some(parked) => (parked.tabs.copy(), parked.active)
    None => ([], (None : DockTab?))
  }
  { owner: Some(owner), tabs, active, remembered, }
}
