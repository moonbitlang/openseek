///|
/// A connected local conversation at `placement`, in the light scheme: the
/// context most cases below start from.
fn local_ctx(session : String, placement : @interop.CheckoutPlacement) -> Ctx {
  {
    channel: @interop.ChannelId::Local,
    session,
    placement: Some(placement),
    dark_mode: false,
    connected: true,
  }
}

///|
test "Windows workspace paths use their final component as the tab label" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  guard @resource.of_path(@interop.ChannelId::Local, "/C:/Users/alice/project")
    is Some(workspace) else {
    fail("Windows resource fixture was invalid")
  }
  let ctx = local_ctx(
    "windows-workspace",
    @interop.WorkspaceRoot(root=workspace),
  )
  let (_, state) = update(emit, ToggleTerminal, State::empty(), ctx)
  guard state.tabs.get(0) is Some(tab) else {
    fail("terminal tab was not opened")
  }
  assert_eq(tab.workspace_label, "project")
}

///|
test "an exit before the open reply cannot revive a dead terminal" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  guard @resource.of_path(@interop.ChannelId::Local, "/work/project")
    is Some(workspace) else {
    fail("workspace resource fixture was invalid")
  }
  let ctx = local_ctx("exit-race", @interop.WorkspaceRoot(root=workspace))
  let (_, opening) = update(emit, ToggleTerminal, State::empty(), ctx)
  let key = opening.tabs[0].key
  let terminal_id = "terminal-exit-race"
  let (_, exited) = update(
    emit,
    SessionExited(channel=@interop.ChannelId::Local, id=terminal_id, code=0),
    opening,
    ctx,
  )
  assert_true(
    exited.exited_before_open.contains(
      (@interop.ChannelId::Local, terminal_id, 0),
    ),
  )
  let (_, replied) = update(
    emit,
    Opened(channel=@interop.ChannelId::Local, key~, id=terminal_id),
    exited,
    ctx,
  )
  assert_true(replied.tabs.is_empty())
  assert_true(
    !replied.exited_before_open.contains(
      (@interop.ChannelId::Local, terminal_id, 0),
    ),
  )
  assert_true(!replied.open)
}

///|
test "sync records color-scheme changes even when the shown tab is unchanged" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  guard @resource.of_path(@interop.ChannelId::Local, "/scratch/theme")
    is Some(scratch_root) else {
    fail("scratch resource fixture was invalid")
  }
  let light_ctx = local_ctx("theme", @interop.Scratch(root=Some(scratch_root)))
  let (light, _) = sync(emit, State::empty(), light_ctx)
  assert_true(light.shown is None)
  assert_true(light.synced_dark_mode is Some(false))
  let (dark, _) = sync(emit, light, { ..light_ctx, dark_mode: true, })
  assert_true(dark.shown is None)
  assert_true(dark.synced_dark_mode is Some(true))
}

///|
test "terminal UUIDs route independently of the focused device" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  guard @resource.of_path(@interop.ChannelId::Local, "/work/project")
    is Some(local_workspace) else {
    fail("local workspace resource fixture was invalid")
  }
  let local_ctx = local_ctx(
    "shared-session",
    @interop.WorkspaceRoot(root=local_workspace),
  )
  let remote : @interop.ChannelId = Remote("device-1")
  guard @resource.of_path(remote, "/work/project") is Some(remote_workspace) else {
    fail("remote workspace resource fixture was invalid")
  }
  let remote_ctx : Ctx = {
    ..local_ctx,
    channel: remote,
    placement: Some(@interop.WorkspaceRoot(root=remote_workspace)),
  }
  let (_, local_opening) = update(
    emit,
    ToggleTerminal,
    State::empty(),
    local_ctx,
  )
  let local_key = local_opening.tabs[0].key
  let local_id = "terminal-local"
  let (_, local_running) = update(
    emit,
    Opened(channel=@interop.ChannelId::Local, key=local_key, id=local_id),
    local_opening,
    local_ctx,
  )
  let (_, both_opening) = update(emit, NewTerminal, local_running, remote_ctx)
  let remote_key = both_opening.tabs[1].key
  let remote_id = "terminal-remote"
  let (_, both_running) = update(
    emit,
    Opened(channel=remote, key=remote_key, id=remote_id),
    both_opening,
    remote_ctx,
  )
  inspect(both_running.tabs.length(), content="2")
  let (_, remote_exited) = update(
    emit,
    SessionExited(channel=remote, id=remote_id, code=0),
    both_running,
    remote_ctx,
  )
  inspect(remote_exited.tabs.length(), content="1")
  guard remote_exited.tabs.get(0) is Some(tab) else {
    fail("local terminal was not preserved")
  }
  assert_true(
    tab.workspace is Project(@interop.ChannelId::Local, resource) &&
    resource.path == "/work/project",
  )
  assert_true(tab.id == Some(local_id))
}

///|
test "a disconnected channel retires only its terminal tabs" {
  let local_channel : @interop.ChannelId = @interop.ChannelId::Local
  let remote : @interop.ChannelId = Remote("device-1")
  guard @resource.of_path(local_channel, "/local") is Some(local_workspace) &&
    @resource.of_path(remote, "/remote") is Some(remote_workspace) else {
    fail("terminal workspace resource fixtures were invalid")
  }
  let state : State = {
    open: true,
    tabs: [
      {
        key: "tab-local",
        id: Some("terminal-local"),
        workspace: Project(local_channel, local_workspace),
        workspace_label: "local",
        session: "local",
        workspace_path: Some(local_workspace),
        status: TabRunning,
        command: None,
      },
      {
        key: "tab-remote",
        id: Some("terminal-remote"),
        workspace: Project(remote, remote_workspace),
        workspace_label: "remote",
        session: "remote",
        workspace_path: Some(remote_workspace),
        status: TabRunning,
        command: None,
      },
    ],
    active: [
      (Project(local_channel, local_workspace), "tab-local"),
      (Project(remote, remote_workspace), "tab-remote"),
    ],
    shown: Some("tab-remote"),
    exited_before_open: [
      (remote, "exited-remote", 0),
      (local_channel, "exited-local", 0),
    ],
    synced_dark_mode: Some(false),
    live_channels: [local_channel, remote],
  }
  let (_, disconnected) = disconnect(@cmd.Emit(_ => @cmd.none), state, remote)
  inspect(disconnected.tabs.length(), content="1")
  assert_true(
    disconnected.tabs[0].workspace
    is Project(@interop.ChannelId::Local, resource) &&
    resource.path == "/local",
  )
  assert_true(disconnected.shown is None)
  assert_true(
    disconnected.exited_before_open == [(local_channel, "exited-local", 0)],
  )
}

///|
test "an open panel waits for a reconnected channel before replacing its PTY" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let remote : @interop.ChannelId = @interop.ChannelId::Remote("device-1")
  guard @resource.of_path(remote, "/scratch/reconnect") is Some(scratch_root) else {
    fail("scratch resource fixture was invalid")
  }
  let disconnected_ctx : Ctx = {
    channel: remote,
    session: "reconnect",
    placement: Some(@interop.Scratch(root=Some(scratch_root))),
    dark_mode: false,
    connected: false,
  }
  let (_, opened) = update(
    emit,
    ToggleTerminal,
    State::empty(),
    disconnected_ctx,
  )
  assert_true(opened.open)
  assert_true(opened.tabs.is_empty())
  let (still_waiting, _) = sync(emit, opened, disconnected_ctx)
  assert_true(still_waiting.tabs.is_empty())
  let (reconnected, _) = sync(emit, still_waiting, {
    ..disconnected_ctx,
    connected: true,
  })
  inspect(reconnected.tabs.length(), content="1")
  assert_true(
    reconnected.tabs[0].workspace
    is Scratch(@interop.ChannelId::Remote("device-1"), "reconnect"),
  )
}

///|
test "a missing checkout refuses new PTYs and retires only its conversation" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  guard @resource.of_path(@interop.ChannelId::Local, "/work/project")
    is Some(workspace) &&
    @resource.of_path(@interop.ChannelId::Local, "/work/worktrees/wt")
    is Some(worktree_root) else {
    fail("workspace resource fixture was invalid")
  }
  let ctx = local_ctx(
    "missing",
    @interop.Worktree(project=workspace, name="wt", root=worktree_root),
  )
  let (_, opening) = update(emit, ToggleTerminal, State::empty(), ctx)
  let opening_key = opening.tabs[0].key
  let (_, running) = update(
    emit,
    Opened(
      channel=@interop.ChannelId::Local,
      key=opening_key,
      id="terminal-missing",
    ),
    opening,
    ctx,
  )
  let other_ctx = {
    ..ctx,
    session: "other",
    placement: Some(@interop.WorkspaceRoot(root=workspace)),
  }
  let (_, other_opening) = update(emit, NewTerminal, running, other_ctx)
  let other_key = other_opening.tabs[1].key
  let (_, both_running) = update(
    emit,
    Opened(
      channel=@interop.ChannelId::Local,
      key=other_key,
      id="terminal-other",
    ),
    other_opening,
    other_ctx,
  )
  let missing_ctx = {
    ..ctx,
    placement: Some(@interop.MissingWorktree(project=workspace, name="wt")),
  }
  let (retired, _) = sync(emit, both_running, missing_ctx)
  assert_eq(retired.tabs.length(), 1)
  assert_eq(retired.tabs[0].session, "other")
  assert_true(retired.shown is None)
  let (still_retired, _) = sync(emit, retired, missing_ctx)
  assert_true(still_retired == retired)
  let empty = State::empty()
  let (_, toggle_refused) = update(emit, ToggleTerminal, empty, missing_ctx)
  let (_, new_refused) = update(emit, NewTerminal, empty, missing_ctx)
  assert_true(toggle_refused == empty)
  assert_true(new_refused == empty)
}

///|
test "a worktree conversation never reuses the main checkout terminal group" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  guard @resource.of_path(@interop.ChannelId::Local, "/work/project")
    is Some(workspace) &&
    @resource.of_path(@interop.ChannelId::Local, "/work/worktrees/wt-1")
    is Some(worktree_root) else {
    fail("workspace resource fixture was invalid")
  }
  let main = local_ctx("main-chat", @interop.WorkspaceRoot(root=workspace))
  let (_, main_opening) = update(emit, ToggleTerminal, State::empty(), main)
  let worktree = {
    ..main,
    session: "worktree-chat",
    placement: Some(
      @interop.Worktree(project=workspace, name="wt-1", root=worktree_root),
    ),
  }
  // The panel is already open, but the worktree group is empty, so sync must
  // create a second tab rather than reveal the main checkout's tab.
  let (separated, _) = sync(emit, main_opening, worktree)
  assert_eq(separated.tabs.length(), 2)
  assert_true(
    separated.tabs[0].workspace == Project(@interop.ChannelId::Local, workspace),
  )
  assert_true(
    separated.tabs[1].workspace ==
    Worktree(@interop.ChannelId::Local, workspace, "wt-1"),
  )
}

///|
test "an unresolved placement cannot reveal or create a project terminal" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  guard @resource.of_path(@interop.ChannelId::Local, "/work/project")
    is Some(workspace) &&
    @resource.of_path(@interop.ChannelId::Local, "/work/worktrees/wt-1")
    is Some(worktree_root) else {
    fail("workspace resource fixture was invalid")
  }
  let main = local_ctx("main-chat", @interop.WorkspaceRoot(root=workspace))
  let (_, project_opening) = update(emit, ToggleTerminal, State::empty(), main)
  let unresolved : Ctx = { ..main, session: "restored-chat", placement: None, }
  // The existing project tab stays alive for its owner, but the restored
  // conversation cannot see it or create another tab under the same key.
  let (waiting, _) = sync(emit, project_opening, unresolved)
  assert_eq(waiting.tabs.length(), 1)
  assert_true(waiting.shown is None)
  let empty = State::empty()
  let (_, toggle_refused) = update(emit, ToggleTerminal, empty, unresolved)
  let (_, new_refused) = update(emit, NewTerminal, waiting, unresolved)
  assert_true(toggle_refused == empty)
  assert_true(new_refused == waiting)
  // Once the list identifies the worktree, the already-open panel creates a
  // correctly isolated worktree tab instead of migrating the project tab.
  let resolved = {
    ..unresolved,
    placement: Some(
      @interop.Worktree(project=workspace, name="wt-1", root=worktree_root),
    ),
  }
  let (separated, _) = sync(emit, waiting, resolved)
  assert_eq(separated.tabs.length(), 2)
  assert_true(
    separated.tabs[1].workspace ==
    Worktree(@interop.ChannelId::Local, workspace, "wt-1"),
  )
}

///|
/// A workspace ready to host a terminal, and an emitter that records what
/// the panel dispatches.
fn command_fixture(
  session : String,
) -> (Ctx, Input, Array[Msg], @cmd.Emit[Msg]) {
  guard @resource.of_path(@interop.ChannelId::Local, "/work/project")
    is Some(workspace) else {
    abort("workspace resource fixture was invalid")
  }
  let ctx = local_ctx(session, @interop.WorkspaceRoot(root=workspace))
  let input = Input(
    ctx~,
    live_channels=[@interop.ChannelId::Local],
    has_devices=true,
  )
  let sent : Array[Msg] = []
  let emit : @cmd.Emit[Msg] = @cmd.Emit(msg => {
    sent.push(msg)
    @cmd.none
  })
  (ctx, input, sent, emit)
}

///|
fn start_command(
  state : State,
  emit : @cmd.Emit[Msg],
  input : Input,
  shell : String,
  command : String,
) -> State {
  guard state.run_command(emit, input, shell~, command~, on_screen=true)
    is CommandStarted(_, started) else {
    abort("the command tab was not opened")
  }
  started
}

///|
test "a ! command gets its own tab without opening the panel" {
  let (ctx, input, _, emit) = command_fixture("run-command")
  let state = start_command(State::empty(), emit, input, "s-1", "moon test")
  assert_false(state.open)
  guard state.tabs is [tab] else { fail("expected exactly one tab") }
  assert_true(tab.status is TabOpening)
  assert_true(tab.command is Some({ shell: "s-1", text: "moon test", }))
  // It is the tab the panel shows once the user opens it.
  let (_, revealed) = update(emit, RevealCommand(shell="s-1"), state, ctx)
  assert_true(revealed.open)
  assert_true(revealed.active_tab(ctx) is Some({ key, .. }) && key == tab.key)
  // An open panel stays open.
  let opened = { ..State::empty(), open: true, }
  assert_true(start_command(opened, emit, input, "s-2", "ls").open)
}

///|
test "a ! command cannot run where no terminal can" {
  let (ctx, input, _, emit) = command_fixture("no-terminal")
  let away = { ..input, ctx: { ..ctx, connected: false, }, }
  assert_true(
    State::empty().run_command(
      emit,
      away,
      shell="s-1",
      command="ls",
      on_screen=true,
    )
    is CommandUnavailable,
  )
  // A placement still loading is worth asking again; nothing else is.
  let unplaced = { ..input, ctx: { ..ctx, placement: None, }, }
  assert_true(
    State::empty().run_command(
      emit,
      unplaced,
      shell="s-1",
      command="ls",
      on_screen=true,
    )
    is CommandUnresolved,
  )
}

///|
test "a command tab waits for its report after exit, then retires" {
  let (ctx, input, _, emit) = command_fixture("exit-command")
  let opening = start_command(State::empty(), emit, input, "s-1", "ls")
  let key = opening.tabs[0].key
  let (_, running) = update(
    emit,
    Opened(channel=@interop.ChannelId::Local, key~, id="pty-1"),
    opening,
    ctx,
  )
  assert_true(running.tabs[0].status is TabRunning)
  let (_, exited) = update(
    emit,
    SessionExited(channel=@interop.ChannelId::Local, id="pty-1", code=2),
    running,
    ctx,
  )
  // Still there: the report has to read its screen first.
  guard exited.tabs is [tab] else { fail("the exited tab was dropped") }
  assert_true(tab.status is TabExited(code=2))
  assert_true(tab.id is None)
  // Typing into it goes nowhere: the session is gone.
  let (_, typed) = update(emit, UserInput(key~, data="x"), exited, ctx)
  assert_true(typed == exited)
  let (_, reported) = update(
    emit,
    CommandFinished(shell="s-1", exit_code=Some(2), output="", truncated=false),
    exited,
    ctx,
  )
  assert_true(reported.tabs.is_empty())
}

///|
test "a quick command that exits before its open reply still reports" {
  let (ctx, input, _, emit) = command_fixture("quick-command")
  let opening = start_command(State::empty(), emit, input, "s-1", "true")
  let key = opening.tabs[0].key
  let (_, early) = update(
    emit,
    SessionExited(channel=@interop.ChannelId::Local, id="pty-quick", code=0),
    opening,
    ctx,
  )
  assert_true(
    early.exited_before_open == [(@interop.ChannelId::Local, "pty-quick", 0)],
  )
  let (_, replied) = update(
    emit,
    Opened(channel=@interop.ChannelId::Local, key~, id="pty-quick"),
    early,
    ctx,
  )
  guard replied.tabs is [tab] else { fail("the command tab was dropped") }
  assert_true(tab.status is TabExited(code=0))
  assert_true(replied.exited_before_open.is_empty())
}

///|
test "a command whose session cannot open is handed back" {
  let (ctx, input, sent, emit) = command_fixture("failed-command")
  let opening = start_command(State::empty(), emit, input, "s-1", "ls")
  let key = opening.tabs[0].key
  let (_, failed) = update(
    emit,
    OpenFailed(key~, message="no workspace"),
    opening,
    ctx,
  )
  assert_true(failed.tabs.is_empty())
  assert_true(
    sent is [.., CommandNotStarted(shell="s-1", message="no workspace")],
  )
}

///|
test "only a command tab still running owes a report when torn down" {
  let (ctx, input, _, emit) = command_fixture("abandoned-command")
  let opening = start_command(State::empty(), emit, input, "s-1", "sleep 9")
  let tab = opening.tabs[0]
  assert_true(tab.abandoned(emit) is Some(_))
  assert_true({ ..tab, status: TabRunning, }.abandoned(emit) is Some(_))
  assert_true({ ..tab, status: TabExited(code=0), }.abandoned(emit) is None)
  assert_true({ ..tab, command: None, }.abandoned(emit) is None)
  // Closing it retires the tab like any other.
  let (_, closed) = update(emit, TabClosed(key=tab.key), opening, ctx)
  assert_true(closed.tabs.is_empty())
}

///|
test "a signal-killed session has no exit code of its own" {
  assert_eq(exit_code_of(0), Some(0))
  assert_eq(exit_code_of(130), Some(130))
  assert_eq(exit_code_of(-1), None)
}

///|
test "a command tab opens its session whatever conversation is on screen" {
  let (_, input, _, emit) = command_fixture("background-command")
  let opening = start_command(State::empty(), emit, input, "s-1", "moon test")
  // The conversation on screen may have no resolved checkout; a shell tab
  // waits for it, the command tab does not.
  let tab = opening.tabs[0]
  assert_true(tab.awaits_session(false))
  assert_false({ ..tab, command: None, }.awaits_session(false))
  assert_true({ ..tab, command: None, }.awaits_session(true))
  assert_false({ ..tab, status: TabRunning, }.awaits_session(true))
}

///|
test "a command for a workspace that is not on screen leaves the display alone" {
  let (ctx, input, _, emit) = command_fixture("off-screen-command")
  // The user's own shell is on screen in the open panel.
  let (_, shell) = update(emit, ToggleTerminal, State::empty(), ctx)
  let shown = shell.shown
  guard shell.run_command(
      emit,
      input,
      shell="s-1",
      command="moon test",
      on_screen=false,
    )
    is CommandStarted(_, started) else {
    fail("the command tab was not opened")
  }
  assert_eq(started.tabs.length(), 2)
  assert_true(started.shown == shown)
  // The group's remembered tab is still the shell.
  assert_true(started.active_tab(ctx) is Some({ command: None, .. }))
}
