// The panel's update loop. Two deliberate properties:
//
// Shells OUTLIVE conversation switches. Their running jobs, history, and
// working directories are the user's work, so nothing here retires a
// session because the active conversation changed — switching devices or
// workspaces only changes which tab group the panel shows, and each group's
// shells keep running (and rendering into their hidden emulators) meanwhile.
//
// A tab never migrates: it is bound at creation to the conversation and
// workspace it was opened for, and a restart after its shell exits reuses
// that binding. Sessions end when their child exits, when the user closes
// the tab or restarts it, or when its owning connection disconnects (the host
// tears that connection's task group down).

///|
/// The display label for the active conversation's workspace: the project
/// directory's name, or "scratch" for a conversation without one.
fn workspace_label(ctx : Ctx) -> String {
  guard ctx.placement is Some(placement) &&
    placement.project_root() is Some(project) else {
    return "scratch"
  }
  @resource.label(project)
}

///|
/// Create a tab bound to the active conversation's workspace and mount its
/// emulator (whose ready report spawns the session).
fn open_new_tab(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> (@cmd.Cmd, State) {
  guard workspace_key(ctx) is Some(group) else { return (@cmd.none, state) }
  let key = @uuid.mint()
  let tab : Tab = {
    key,
    id: None,
    workspace: group,
    workspace_label: workspace_label(ctx),
    session: ctx.session,
    workspace_path: ctx.placement.bind(placement => placement.project_root()),
    status: TabOpening,
  }
  let state = { ..state, tabs: state.tabs + [tab], shown: Some(key), }
  (
    @cmd.batch([terminal_resizer.mount(), mount_tab(dispatch, key)]),
    state.remember_active(group, key),
  )
}

///|
/// Remove a tab and dispose its emulator. Emptying the visible group takes
/// the panel with it: an open panel over an empty group would immediately
/// respawn a shell (see `sync`), which must not happen when the user
/// deliberately ended the last one.
fn drop_tab(state : State, ctx : Ctx, key : String) -> (Array[@cmd.Cmd], State) {
  let cmds = [dispose_tab(key)]
  let state = {
    ..state,
    tabs: state.tabs.filter(entry => entry.key != key),
    active: state.active.filter(entry => entry.1 != key),
  }
  let state = if state.open && state.visible_tabs(ctx).is_empty() {
    { ..state, open: false, }
  } else {
    state
  }
  (cmds, state)
}

///|
/// Retire PTYs opened for a conversation whose bound checkout disappeared.
/// A shell may keep an OS handle to the deleted directory, so merely hiding
/// its emulator would let it reappear after Repair with a stale cwd. Tabs
/// belonging to other conversations in the same project remain alive.
fn State::retire_missing_session(
  self : State,
  ctx : Ctx,
) -> (Array[@cmd.Cmd], State) {
  let retired : Array[String] = []
  let commands : Array[@cmd.Cmd] = []
  for tab in self.tabs {
    if tab.workspace.channel() == ctx.channel && tab.session == ctx.session {
      retired.push(tab.key)
      commands.push(dispose_tab(tab.key))
      if tab.id is Some(id) {
        commands.push(send_close(ctx.channel, id))
      }
    }
  }
  (
    commands,
    {
      ..self,
      tabs: self.tabs.filter(tab => !retired.contains(tab.key)),
      active: self.active.filter(entry => !retired.contains(entry.1)),
      shown: None,
    },
  )
}

///|
pub fn State::handle(
  self : State,
  dispatch : @cmd.Emit[Msg],
  msg : Msg,
  input : Input,
) -> (@cmd.Cmd, State) {
  // Tab keys and terminal ids are UUIDs, so a delayed reply from a retired
  // connection cannot attach itself to a later tab or PTY.
  update(dispatch, msg, self, input.ctx)
}

///|
/// Apply one accepted terminal message. Root integration calls `State::handle`
/// so retired channel replies are fenced before entering this state machine.
fn update(
  dispatch : @cmd.Emit[Msg],
  msg : Msg,
  state : State,
  ctx : Ctx,
) -> (@cmd.Cmd, State) {
  let checkout_ready = ctx.placement is Some(placement) && placement.is_ready()
  match msg {
    ToggleTerminal =>
      if state.open {
        // Hide only — every shell keeps running for the panel's return.
        (@cmd.none, { ..state, open: false, })
      } else if !checkout_ready {
        // An unresolved placement cannot safely choose a terminal group; a
        // missing checkout likewise has no directory in which to start one.
        (@cmd.none, state)
      } else {
        match state.active_tab(ctx) {
          // This workspace group already has shells; `sync` reveals its
          // tab once `open` flips.
          Some(_) => (@cmd.none, { ..state, open: true, })
          // First open in this workspace: start its first shell.
          None if ctx.connected => {
            let (cmd, state) = open_new_tab(dispatch, state, ctx)
            (cmd, { ..state, open: true, })
          }
          // A remote socket can be between attempts. Keep the panel visible
          // with its disconnected status; `sync` starts a fresh PTY only
          // after this channel reports ready again.
          None => (@cmd.none, { ..state, open: true, })
        }
      }
    NewTerminal =>
      if checkout_ready && ctx.connected {
        open_new_tab(dispatch, state, ctx)
      } else {
        (@cmd.none, state)
      }
    TabSelected(key~) => {
      guard state.tab_by_key(key) is Some(tab) else {
        return (@cmd.none, state)
      }
      (@cmd.none, state.remember_active(tab.workspace, key))
    }
    TabClosed(key~) => {
      guard state.tab_by_key(key) is Some(tab) else {
        return (@cmd.none, state)
      }
      let (cmds, state) = drop_tab(state, ctx, key)
      if tab.id is Some(id) {
        cmds.push(send_close(tab.workspace.channel(), id))
      }
      // `sync` reveals the group's fallback tab, if the closed one was on
      // screen.
      (@cmd.batch(cmds), state)
    }
    EmulatorReady(key~, cols~, rows~) => {
      // Ready reports are idempotent (mount_tab re-reports on reveal); only
      // a tab still waiting for its first session spawns one.
      guard state.tab_by_key(key) is Some(tab) else {
        return (@cmd.none, state)
      }
      if checkout_ready && tab.status is TabOpening && tab.id is None {
        (
          open_session(
            dispatch,
            tab.workspace.channel(),
            key,
            tab.session,
            tab.workspace_path,
            cols,
            rows,
          ),
          state,
        )
      } else {
        (@cmd.none, state)
      }
    }
    Opened(channel~, key~, id~) => {
      let owner = (channel, id)
      if state.exited_before_open.contains(owner) {
        // `terminal_exit` can beat this reply. Only the reply identifies
        // which opening tab owned the id, so retire it now and never publish
        // a `TabRunning` state for a dead PTY.
        let state = {
          ..state,
          exited_before_open: state.exited_before_open.filter(exited => {
            exited != owner
          }),
        }
        if state.tab_by_key(key) is Some(tab) &&
          tab.workspace.channel() == channel &&
          tab.status is TabOpening {
          let (cmds, state) = drop_tab(state, ctx, key)
          cmds.push(drop_pending(id))
          (@cmd.batch(cmds), state)
        } else {
          (drop_pending(id), state)
        }
      } else if state.tab_by_key(key) is Some(tab) &&
        tab.workspace.channel() == channel &&
        tab.status is TabOpening {
        (
          flush_pending(key, id),
          state.replace_tab({ ..tab, id: Some(id), status: TabRunning, }),
        )
      } else {
        // The tab was closed while the open was in flight; the session
        // belongs to nobody, so retire it on the host connection that opened
        // it, even if another device is focused now.
        (@cmd.batch([send_close(channel, id), drop_pending(id)]), state)
      }
    }
    OpenFailed(key~, message~) =>
      if state.tab_by_key(key) is Some(tab) {
        (@cmd.none, state.replace_tab({ ..tab, status: TabFailed(message~), }))
      } else {
        (@cmd.none, state)
      }
    UserInput(key~, data~) =>
      if checkout_ready &&
        state.tab_by_key(key) is Some(tab) &&
        tab.status is TabRunning &&
        tab.id is Some(id) {
        (send_input(dispatch, tab.workspace.channel(), id, data, false), state)
      } else {
        // Typing into an exited/unopened terminal has nowhere to go.
        (@cmd.none, state)
      }
    // The main frontend consumes this message before it reaches the panel
    // state machine. Keep direct package callers pure and exhaustive.
    LinkActivated(url=_) => (@cmd.none, state)
    BinaryInput(key~, data~) =>
      if checkout_ready &&
        state.tab_by_key(key) is Some(tab) &&
        tab.status is TabRunning &&
        tab.id is Some(id) {
        (send_input(dispatch, tab.workspace.channel(), id, data, true), state)
      } else {
        // Typing into an exited/unopened terminal has nowhere to go.
        (@cmd.none, state)
      }
    // The main package pops the toast; the panel's own state has nothing to
    // record for a lost keystroke.
    InputFailed(message=_) => (@cmd.none, state)
    ViewportResized(key~, cols~, rows~) =>
      if checkout_ready &&
        state.tab_by_key(key) is Some(tab) &&
        tab.status is TabRunning &&
        tab.id is Some(id) {
        (send_resize(tab.workspace.channel(), id, cols, rows), state)
      } else {
        (@cmd.none, state)
      }
    SessionExited(channel~, id~, code=_) =>
      match state.tab_by_id(id) {
        // The shell ended (Ctrl+D, `exit`, or a crash): its tab retires,
        // and the visible group's last tab takes the panel with it.
        Some(tab) => {
          let (cmds, state) = drop_tab(state, ctx, tab.key)
          (@cmd.batch(cmds), state)
        }
        None =>
          if state.tabs
            .iter()
            .any(tab => {
              tab.workspace.channel() == channel && tab.status is TabOpening
            }) {
            let owner = (channel, id)
            (
              drop_pending(id),
              if state.exited_before_open.contains(owner) {
                state
              } else {
                {
                  ..state,
                  exited_before_open: state.exited_before_open + [owner],
                }
              },
            )
          } else {
            (drop_pending(id), state)
          }
      }
  }
}

///|
/// Retire all tabs owned by one dead connection. The host tears down that
/// connection's PTYs before the browser dials again; UUID identities make
/// delayed lifecycle messages unable to match replacement tabs.
fn disconnect(state : State, channel : @interop.ChannelId) -> (@cmd.Cmd, State) {
  let commands : Array[@cmd.Cmd] = [term_host.clear_pending(channel)]
  let retired_keys : Array[String] = []
  for tab in state.tabs {
    if tab.workspace.channel() == channel {
      retired_keys.push(tab.key)
      commands.push(dispose_tab(tab.key))
    }
  }
  let shown = match state.shown {
    Some(key) if retired_keys.contains(key) => None
    shown => shown
  }
  (
    @cmd.batch(commands),
    {
      ..state,
      tabs: state.tabs.filter(tab => tab.workspace.channel() != channel),
      active: state.active.filter(entry => entry.0.channel() != channel),
      shown,
      exited_before_open: state.exited_before_open.filter(owner => {
        owner.0 != channel
      }),
    },
  )
}

///|
/// Reconcile the emulator display with the active conversation after every
/// message (the main package calls this like `@fileeditor.sync`). A
/// conversation switch produces no terminal message, yet it changes which
/// workspace group — and so which tab's emulator — belongs on screen; and
/// with the panel open, landing in a workspace that has no shell yet starts
/// its first one, so every workspace greets the user with its own terminal.
fn sync(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> (State, @cmd.Cmd) {
  if ctx.placement is None {
    // Preserve existing groups, but reveal none of them while this
    // conversation's group is unknown. A later placement reply can then
    // select or create the correct group without migrating any tab.
    let shown_changed = state.shown is Some(_)
    let theme_changed = state.synced_dark_mode != Some(ctx.dark_mode)
    let commands : Array[@cmd.Cmd] = []
    if shown_changed {
      commands.push(apply_shown(None))
    }
    if theme_changed {
      commands.push(apply_theme())
    }
    return (
      { ..state, shown: None, synced_dark_mode: Some(ctx.dark_mode), },
      @cmd.batch(commands),
    )
  }
  if ctx.placement is Some(@interop.MissingWorktree(..)) {
    let shown_changed = state.shown is Some(_)
    let theme_changed = state.synced_dark_mode != Some(ctx.dark_mode)
    let (commands, state) = state.retire_missing_session(ctx)
    if shown_changed {
      commands.push(apply_shown(None))
    }
    if theme_changed {
      commands.push(apply_theme())
    }
    return (
      { ..state, synced_dark_mode: Some(ctx.dark_mode), },
      @cmd.batch(commands),
    )
  }
  if state.open && ctx.connected && state.visible_tabs(ctx).is_empty() {
    let (cmd, state) = open_new_tab(dispatch, state, ctx)
    let theme_changed = state.synced_dark_mode != Some(ctx.dark_mode)
    let state = { ..state, synced_dark_mode: Some(ctx.dark_mode), }
    if theme_changed {
      return (state, @cmd.batch([cmd, apply_theme()]))
    }
    return (state, cmd)
  }
  let desired = if state.open {
    state.active_tab(ctx).map(tab => tab.key)
  } else {
    None
  }
  let shown_changed = desired != state.shown
  let theme_changed = state.synced_dark_mode != Some(ctx.dark_mode)
  let state = {
    ..state,
    shown: desired,
    synced_dark_mode: Some(ctx.dark_mode),
  }
  match (shown_changed, theme_changed) {
    (false, false) => (state, @cmd.none)
    (true, false) => (state, apply_shown(desired))
    (false, true) => (state, apply_theme())
    (true, true) => (state, @cmd.batch([apply_shown(desired), apply_theme()]))
  }
}
