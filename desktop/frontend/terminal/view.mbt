// The panel: a titlebar with the workspace group's tab strip over the
// emulators' stable container element. Rendered on every screen from the
// first paint — CSS hides the whole panel while closed — so the attached
// emulators are never torn down (see host.mbt).

///|
fn tab_view(dispatch : @cmd.Emit[Msg], tab : Tab, active : Bool) -> @html.Html {
  let title = match tab.status {
    TabOpening => "starting…"
    TabRunning => tab.workspace_label
    TabFailed(message~) => message
  }
  let status : Array[@html.Html] = if tab.status is TabFailed(..) {
    [@html.span(class="terminal-tab-failed", "!")]
  } else {
    []
  }
  @html.div(class=if active { "terminal-tab active" } else { "terminal-tab" }, [
    @html.button(
      class="terminal-tab-select",
      title~,
      on_click=dispatch(TabSelected(key=tab.key)),
      [@html.span(class="terminal-tab-label", tab.workspace_label), ..status],
    ),
    @html.button(
      class="terminal-tab-close",
      title="Close terminal",
      on_click=dispatch(TabClosed(key=tab.key)),
      "✕",
    ),
  ])
}

///|
fn panel_view(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  // Always render the grab strip so its position and the terminal host's
  // sibling index remain stable across open/close renders. Its listeners are
  // installed imperatively on the first terminal open (see resize.mbt).
  let resize_handle = @html.div(
    attrs=@html.Attrs::build()
      .id(TerminalResizeHandleId)
      .class("terminal-resize-handle"),
    ([] : Array[@html.Html]),
  )
  let items : Array[@html.Html] = [
    @html.span(class="terminal-title", "Terminal"),
  ]
  let visible = state.visible_tabs(ctx)
  let active = state.active_tab(ctx)
  for tab in visible {
    items.push(
      tab_view(dispatch, tab, active is Some(current) && current.key == tab.key),
    )
  }
  if ctx.placement is Some(placement) && placement.is_ready() {
    items.push(
      @html.button(
        class="terminal-new",
        title="New terminal in this workspace",
        on_click=dispatch(NewTerminal),
        "+",
      ),
    )
  }
  // The visible tab's failure detail at the right edge; a failed tab is
  // closed with its ✕ and a fresh one opened with "+".
  if active is Some(tab) {
    match tab.status {
      TabOpening =>
        items.push(@html.span(class="terminal-status", "starting…"))
      TabFailed(message~) =>
        items.push(@html.span(class="terminal-status terminal-error", message))
      TabRunning => ()
    }
  } else if ctx.placement is None {
    items.push(
      @html.span(class="terminal-status", "Waiting for workspace placement…"),
    )
  } else if ctx.placement is Some(@interop.MissingWorktree(..)) {
    items.push(
      @html.span(
        class="terminal-status terminal-error",
        "Worktree checkout is missing",
      ),
    )
  } else if !ctx.connected {
    items.push(@html.span(class="terminal-status", "reconnecting…"))
  }
  items.push(
    @html.button(
      class="terminal-close",
      title="Hide terminal (Ctrl+`)",
      on_click=dispatch(ToggleTerminal),
      "✕",
    ),
  )
  // The stable container the tab emulators attach into; it must stay empty
  // in the virtual DOM and never be re-keyed (see host.mbt).
  let host = @html.div(
    attrs=@html.Attrs::build().id(TerminalHostId).class("terminal-host"),
    ([] : Array[@html.Html]),
  )
  @html.div(
    attrs=@html.Attrs::build().class(
      if state.open {
        "terminal-panel open"
      } else {
        "terminal-panel"
      },
    ),
    [resize_handle, @html.div(class="terminal-titlebar", items), host],
  )
}
