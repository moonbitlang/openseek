///|
pub(all) enum CloseSelection {
  All
  Others(DockTab)
  ToLeft(DockTab)
  ToRight(DockTab)
}

///|
/// Resolve against the current strip, not the active tab or a captured index.
/// A menu whose tab has gone away cannot close unrelated tabs.
pub fn tabs_to_close(
  state : State,
  selection : CloseSelection,
) -> Array[DockTab] {
  let anchor = match selection {
    All => return state.tabs.copy()
    Others(tab) | ToLeft(tab) | ToRight(tab) => tab
  }
  guard tab_index(state, anchor) is Some(index) else { return [] }
  match selection {
    All => state.tabs.copy()
    Others(_) => state.tabs.filter(tab => tab != anchor)
    ToLeft(_) => state.tabs[:index].to_owned()
    ToRight(_) => state.tabs[index + 1:].to_owned()
  }
}

///|
fn tab_menu_target(state : State, tab : DockTab) -> String {
  let owner = match state.owner {
    None => "unowned"
    Some(owner) => {
      let channel = match owner.channel {
        Local => "local"
        Remote(id) => "remote:\{id.length()}:\{id}"
      }
      "\{channel}:\{owner.session.length()}:\{owner.session}"
    }
  }
  let identity = match tab {
    File(path~) => "file:\{path.0}"
    GitDiff(diff~) => "history:\{diff.commit}:\{diff.path.0}"
    Browser(id~) => "browser:\{id}"
    FilePicker => "picker"
    Workflows => "workflows"
  }
  "dock:\{owner}:\{identity}"
}

///|
pub fn tab_menu(
  state : State,
  target : String,
  dispatch : @cmd.Emit[Msg],
  close : @cmd.Emit[CloseSelection],
) -> @action_menu.Definition? {
  guard state.tabs
    .iter()
    .find_first(tab => tab_menu_target(state, tab) == target)
    is Some(tab) else {
    return None
  }
  let entries : Array[@action_menu.Entry] = [
    Action({
      label: "Close",
      title: "Close this tab",
      icon: None,
      enabled: true,
      destructive: false,
      command: dispatch(TabClosed(tab)),
    }),
    Separator,
  ]
  for
    (label, selection) in [
      ("Close Others", Others(tab)),
      ("Close to the Left", ToLeft(tab)),
      ("Close to the Right", ToRight(tab)),
      ("Close All", All),
    ] {
    entries.push(
      Action({
        label,
        title: label,
        icon: None,
        enabled: !tabs_to_close(state, selection).is_empty(),
        destructive: false,
        command: close(selection),
      }),
    )
  }
  Some({ label: "Tab actions", entries, })
}
