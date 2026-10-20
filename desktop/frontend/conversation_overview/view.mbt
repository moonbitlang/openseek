///|
/// Where the conversation runs, as the root knows it.
pub(all) struct Environment {
  /// The device's name, or `None` for the computer this window runs on.
  device : String?
  /// The project's display name and its directory.
  project : String
  path : String
  /// The checked-out branch; `None` when the checkout is not a repository or
  /// the host has not reported it yet.
  branch : String?
  /// The worktree the conversation runs in, when it has one of its own.
  worktree : String?
  /// The device's Remote Control setting; `None` where the window cannot
  /// change it (a browser console).
  remote : RemoteControl?
}

///|
/// Remote Control is a device setting shared with Settings, shown here so
/// the user can see whether this conversation is reachable from elsewhere.
pub(all) enum RemoteControl {
  /// Turned on by the environment the host was started in.
  Managed
  /// Needs a signed-in account first; Settings has the sign-in.
  SignedOut
  /// The user can turn it on or off; `busy` while a sign-in is in flight.
  Switch(enabled~ : Bool, busy~ : Bool)
}

///|
/// What the conversation's engine is connected to: a one-line summary for
/// the folded card and the rows for the unfolded one, drawn by the package
/// that owns the MCP status.
pub(all) struct Connectors {
  summary : String
  rows : Array[@html.Html]
  /// Ask again; `None` while a question is already out.
  refresh : @cmd.Cmd?
}

///|
/// The titlebar control that shows and hides the overview. One control owns
/// both states, whether the overview is a rail or a panel over the
/// conversation.
pub fn toggle(
  locale~ : @i18n.Locale = English,
  open : Bool,
  on_click : @cmd.Cmd,
) -> @html.Html {
  let label = if open {
    text(locale, HideOverview)
  } else {
    text(locale, ShowOverview)
  }
  @html.button(
    class=if open {
      "panel-toggle conv-overview-toggle active"
    } else {
      "panel-toggle conv-overview-toggle"
    },
    type_="button",
    title=label,
    attrs=@html.Attrs::build().aria_label(label).aria_pressed(open.to_string()),
    on_click~,
    @icons.icon(@icons.icon_preview),
  )
}

///|
/// The overview's cards. The stylesheet places it: a rail beside the
/// conversation when the main pane has room for both, otherwise a panel over
/// the transcript's right edge.
pub fn view(
  locale~ : @i18n.Locale = English,
  state : State,
  environment~ : Environment,
  connectors~ : Connectors,
  emit : @cmd.Emit[Msg],
  set_remote~ : (Bool) -> @cmd.Cmd,
) -> @html.Html {
  @html.aside(
    class="conv-overview",
    attrs=@html.Attrs::build().aria_label(text(locale, Overview)),
    [
      card(
        locale,
        Environment,
        state,
        emit,
        aside=[],
        environment_rows(locale, environment, set_remote),
      ),
      card(
        locale,
        Connectors,
        state,
        emit,
        // Folded, the card is its summary; unfolded, the rows say it all and
        // the summary gives way to asking again.
        aside=[
          if state.is_open(Connectors) {
            refresh_button(locale, connectors.refresh)
          } else {
            @html.span(class="conv-overview-summary", connectors.summary)
          },
        ],
        connectors.rows,
      ),
    ],
  )
}

///|
/// One card: its title folds and unfolds it, the aside stays visible either
/// way, and the rows come last so folding never moves the title's button.
fn card(
  locale : @i18n.Locale,
  section : Section,
  state : State,
  emit : @cmd.Emit[Msg],
  aside~ : Array[@html.Html],
  rows : Array[@html.Html],
) -> @html.Html {
  let open = state.is_open(section)
  let title = match section {
    Environment => text(locale, EnvironmentTitle)
    Connectors => text(locale, ConnectorsTitle)
  }
  @html.div(class="conv-overview-card", [
    @html.div(class="conv-overview-card-head", [
      @html.button(
        class=if open {
          "conv-overview-card-title open"
        } else {
          "conv-overview-card-title"
        },
        type_="button",
        attrs=@html.Attrs::build().aria_expanded(open.to_string()),
        on_click=emit(Toggled(section)),
        [@html.span(title), @icons.icon(@icons.icon_chevron_down)],
      ),
      @html.div(class="conv-overview-card-aside", aside),
    ]),
    if open {
      @html.div(class="conv-overview-card-rows", rows)
    } else {
      @html.nothing
    },
  ])
}

///|
fn refresh_button(locale : @i18n.Locale, refresh : @cmd.Cmd?) -> @html.Html {
  let label = text(locale, Refresh)
  @html.button(
    class="conv-overview-mini",
    type_="button",
    title=label,
    disabled=refresh is None,
    attrs=@html.Attrs::build().aria_label(label),
    on_click=refresh.unwrap_or(@cmd.none),
    @icons.icon(@icons.icon_sync),
  )
}

///|
/// The environment's rows. Every row keeps its position, absent or not, so a
/// branch arriving never rebuilds the Remote Control switch below it.
fn environment_rows(
  locale : @i18n.Locale,
  environment : Environment,
  set_remote : (Bool) -> @cmd.Cmd,
) -> Array[@html.Html] {
  [
    row(@icons.icon_vm, [
      @html.span(
        class="conv-overview-row-text",
        environment.device.unwrap_or(text(locale, ThisComputer)),
      ),
    ]),
    row(@icons.icon_folder, title=environment.path, [
      @html.span(class="conv-overview-row-text", [
        @html.span(environment.project),
        @html.span(class="conv-overview-row-sub", " · " + environment.path),
      ]),
    ]),
    if environment.branch is Some(branch) {
      row(@icons.icon_git_branch, title=branch, [
        @html.span(class="conv-overview-row-text", branch),
        if environment.worktree is Some(name) {
          @html.span(
            class="conv-overview-tag",
            title=name,
            text(locale, WorktreeTag),
          )
        } else {
          @html.nothing
        },
      ])
    } else {
      @html.nothing
    },
    if environment.remote is Some(remote) {
      remote_row(locale, remote, set_remote)
    } else {
      @html.nothing
    },
  ]
}

///|
fn remote_row(
  locale : @i18n.Locale,
  remote : RemoteControl,
  set_remote : (Bool) -> @cmd.Cmd,
) -> @html.Html {
  let (enabled, disabled, note) = match remote {
    Managed => (true, true, Some(text(locale, RemoteManaged)))
    SignedOut => (false, true, Some(text(locale, RemoteSignedOut)))
    Switch(enabled~, busy~) => (enabled, busy, None)
  }
  let label = text(locale, RemoteControlLabel)
  row(@icons.icon_remote, title=note.unwrap_or(label), [
    @html.span(class="conv-overview-row-text", label),
    @html.button(
      class=if enabled {
        "conv-overview-switch on"
      } else {
        "conv-overview-switch"
      },
      type_="button",
      disabled~,
      attrs=@html.Attrs::build()
        .role("switch")
        .aria_checked(enabled.to_string())
        .aria_label(label),
      on_click=set_remote(!enabled),
      @html.nothing,
    ),
  ])
}

///|
fn row(
  image : () -> @html.Html,
  title? : String,
  children : Array[@html.Html],
) -> @html.Html {
  @html.div(class="conv-overview-row", title?, [@icons.icon(image), ..children])
}
