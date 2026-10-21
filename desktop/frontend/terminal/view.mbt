// The panel: a titlebar with the workspace group's tab strip over the
// emulators' stable container element. Rendered on every screen from the
// first paint — CSS hides the whole panel while closed — so the attached
// emulators are never torn down (see host.mbt).

///|
fn tab_view(
  locale~ : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  tab : Tab,
  active : Bool,
) -> @html.Html {
  // A command tab is named by what it runs.
  let label = match tab.command {
    Some(command) => "$ \{command.text}"
    None => tab.workspace_label
  }
  let title = match tab.status {
    TabOpening => "starting…"
    TabRunning => label
    TabFailed(message~) => message
    TabExited(code~) => "\{label} (exit \{code})"
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
      [@html.span(class="terminal-tab-label", label), ..status],
    ),
    @html.button(
      class="terminal-tab-close",
      title=ui(locale, CloseTerminal),
      on_click=dispatch(TabClosed(key=tab.key)),
      "✕",
    ),
  ])
}

///|
fn panel_view(
  locale~ : @i18n.Locale = English,
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
    @html.span(class="terminal-title", ui(locale, TerminalLabel)),
    ..match ctx.host_name {
      Some(name) => [@html.span(class="terminal-host-label", title=name, name)]
      None => []
    },
  ]
  let visible = state.visible_tabs(ctx)
  let active = state.active_tab(ctx)
  for tab in visible {
    items.push(
      tab_view(
        locale~,
        dispatch,
        tab,
        active is Some(current) && current.key == tab.key,
      ),
    )
  }
  if ctx.placement is Some(placement) && placement.is_ready() {
    items.push(
      @html.button(
        class="terminal-new",
        title=ui(locale, NewTerminal),
        on_click=dispatch(NewTerminal),
        "+",
      ),
    )
  }
  // The visible tab's failure detail at the right edge; a failed tab is
  // closed with its ✕ and a fresh one opened with "+".
  if !ctx.connected {
    items.push(
      @html.span(
        class="terminal-status",
        "Reconnecting… A new shell will open; previous input will not be replayed.",
      ),
    )
  } else if active is Some(tab) {
    match tab.status {
      TabOpening =>
        items.push(@html.span(class="terminal-status", "starting…"))
      TabFailed(message~) =>
        items.push(@html.span(class="terminal-status terminal-error", message))
      TabExited(code~) =>
        items.push(@html.span(class="terminal-status", "exit \{code}"))
      TabRunning =>
        match tab.input.failure {
          Some(Reconnecting) =>
            items.push(
              @html.span(
                class="terminal-status",
                "Reconnecting… Previous input will not be replayed.",
              ),
            )
          Some(Failed(message)) =>
            items.push(
              @html.span(class="terminal-status terminal-error", message),
            )
          None =>
            if state.interrupted_channels.contains(ctx.channel) {
              items.push(
                @html.span(
                  class="terminal-status",
                  "Reconnected with a new shell; previous input was not replayed.",
                ),
              )
            }
        }
    }
  } else if ctx.placement is None {
    items.push(
      @html.span(class="terminal-status", ui(locale, WaitingPlacement)),
    )
  } else if ctx.placement is Some(@interop.MissingWorktree(..)) {
    items.push(
      @html.span(
        class="terminal-status terminal-error",
        ui(locale, MissingWorktree),
      ),
    )
  }
  let maximize_label = ui(
    locale,
    if state.maximized {
      RestoreTerminal
    } else {
      MaximizeTerminal
    },
  )
  items.push(
    @html.button(
      class="terminal-maximize",
      title=maximize_label,
      attrs=@html.Attrs::build()
        .aria_label(maximize_label)
        .aria_pressed(state.maximized.to_string()),
      on_click=dispatch(ToggleMaximized),
      @svg.svg(
        width=16,
        height=16,
        view_box="0 0 16 16",
        attrs=@svg.Attrs::build()
          .fill("none")
          .stroke("currentColor")
          .stroke_linecap("round"),
        [
          @svg.path(
            d=if state.maximized {
              "M2.5 6H6V2.5M13.5 6H10V2.5M13.5 10H10v3.5M2.5 10H6v3.5"
            } else {
              "M6 2.5H2.5V6M10 2.5h3.5V6M13.5 10v3.5H10M6 13.5H2.5V10"
            },
          ),
        ],
      ),
    ),
  )
  items.push(
    @html.button(
      class="terminal-close",
      title=ui(locale, HideTerminal),
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
