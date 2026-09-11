// macOS owns Command+W as a menu key equivalent. Replacing its native Close
// action with a menu command gives the shell and native Browser views one
// entry point without competing keydown handlers.

///|
fn focused_close_message() -> Msg? {
  guard @dom.document().get_active_element() is Some(element) else {
    return None
  }
  // Transient controls keep Close from reaching the content beneath them.
  if element.closest("[role=menu], [role=dialog], [role=listbox], .dock-menu")
    is Some(_) {
    None
  } else if element.closest(".terminal-panel") is Some(_) {
    Some(Terminal(@terminal.CloseActiveTerminal))
  } else if element.closest(".editor.tree-open .file-tree-pane") is Some(_) {
    // The navigator can own focus while a resource remains selected. Its
    // collapsed reopen control belongs to the dock, not an open navigator.
    Some(CloseWorkspaceNavigator)
  } else if element.closest(".editor") is Some(_) {
    Some(CloseActiveDockTab)
  } else {
    Some(AppCloseWindowRequested)
  }
}

///|
fn close_focused(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  if @interop.page_has_focus() {
    return match focused_close_message() {
      Some(message) => dispatch(message)
      None => @cmd.none
    }
  }
  // A native page has its own document: the shell's activeElement still
  // names its previous focus owner. Ask Proton instead of using that stale
  // element, and close the returned tab identity rather than a later active tab.
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let focused = @interop.bridge_request(
        @interop.ChannelId::Local,
        @commands.app_focused_browser,
        @protocol.NoPayload,
      ) catch {
        error => {
          scheduler.add(
            dispatch(HostActionFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      if focused.id is Some(id) {
        scheduler.add(
          @cmd.batch([
            dispatch(Dock(TabClosed(@dock.Browser(id~)))),
            focus_dock_after_render(),
          ]),
        )
      }
    })
  })
}

///|
/// Keep focus in the dock when its navigator, launcher, or a closed tab loses focus.
fn focus_dock_after_render() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document()
        .query_selector(".content.panel-open > .editor")
        .to_option()
        is Some(panel) &&
        panel.to_html_element() is Some(element) {
        element.focus()
      }
    },
    kind=@cmd.after_render,
  )
}
