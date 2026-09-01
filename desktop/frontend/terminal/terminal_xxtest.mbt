///|
test "Windows workspace paths use their final component as the tab label" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  guard @resource.of_path(@interop.ChannelId::Local, "/C:/Users/alice/project")
    is Some(workspace) else {
    fail("Windows resource fixture was invalid")
  }
  let ctx : Ctx = {
    channel: @interop.ChannelId::Local,
    session: "windows-workspace",
    placement: Some(@interop.WorkspaceRoot(root=workspace)),
    dark_mode: false,
    connected: true,
  }
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
  let ctx : Ctx = {
    channel: @interop.ChannelId::Local,
    session: "exit-race",
    placement: Some(@interop.WorkspaceRoot(root=workspace)),
    dark_mode: false,
    connected: true,
  }
  let (_, opening) = update(emit, ToggleTerminal, State::empty(), ctx)
  let (_, exited) = update(
    emit,
    SessionExited(
      channel=@interop.ChannelId::Local,
      id="terminal-exit-race",
      code=0,
    ),
    opening,
    ctx,
  )
  assert_true(
    exited.exited_before_open.contains(
      (@interop.ChannelId::Local, "terminal-exit-race"),
    ),
  )
  let (_, replied) = update(
    emit,
    Opened(channel=@interop.ChannelId::Local, key=1, id="terminal-exit-race"),
    exited,
    ctx,
  )
  assert_true(replied.tabs.is_empty())
  assert_true(
    !replied.exited_before_open.contains(
      (@interop.ChannelId::Local, "terminal-exit-race"),
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
  let light_ctx : Ctx = {
    channel: @interop.ChannelId::Local,
    session: "theme",
    placement: Some(@interop.Scratch(root=Some(scratch_root))),
    dark_mode: false,
    connected: true,
  }
  let (light, _) = sync(emit, State::empty(), light_ctx)
  assert_true(light.shown is None)
  assert_true(light.synced_dark_mode is Some(false))
  let (dark, _) = sync(emit, light, { ..light_ctx, dark_mode: true, })
  assert_true(dark.shown is None)
  assert_true(dark.synced_dark_mode is Some(true))
}

///|
test "terminal routes retain their owning device" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  guard @resource.of_path(@interop.ChannelId::Local, "/work/project")
    is Some(local_workspace) else {
    fail("local workspace resource fixture was invalid")
  }
  let local_ctx : Ctx = {
    channel: @interop.ChannelId::Local,
    session: "shared-session",
    placement: Some(@interop.WorkspaceRoot(root=local_workspace)),
    dark_mode: false,
    connected: true,
  }
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
  let (_, local_running) = update(
    emit,
    Opened(
      channel=@interop.ChannelId::Local,
      key=1,
      id="shared-terminal-fixture",
    ),
    local_opening,
    local_ctx,
  )
  let (_, both_opening) = update(emit, NewTerminal, local_running, remote_ctx)
  let (_, both_running) = update(
    emit,
    Opened(channel=remote, key=2, id="shared-terminal-fixture"),
    both_opening,
    remote_ctx,
  )
  inspect(both_running.tabs.length(), content="2")
  let (_, remote_exited) = update(
    emit,
    SessionExited(channel=remote, id="shared-terminal-fixture", code=0),
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
  assert_true(tab.id is Some("shared-terminal-fixture"))
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
    next_key: 3,
    tabs: [
      {
        key: 1,
        id: Some("local-terminal"),
        workspace: Project(local_channel, local_workspace),
        workspace_label: "local",
        session: "local",
        workspace_path: Some(local_workspace),
        status: TabRunning,
      },
      {
        key: 2,
        id: Some("remote-terminal"),
        workspace: Project(remote, remote_workspace),
        workspace_label: "remote",
        session: "remote",
        workspace_path: Some(remote_workspace),
        status: TabRunning,
      },
    ],
    active: [
      (Project(local_channel, local_workspace), 1),
      (Project(remote, remote_workspace), 2),
    ],
    shown: Some(2),
    exited_before_open: [
      (remote, "remote-opening-terminal"),
      (local_channel, "local-opening-terminal"),
    ],
    synced_dark_mode: Some(false),
    live_channels: [local_channel, remote],
  }
  let (_, disconnected) = disconnect(state, remote)
  inspect(disconnected.tabs.length(), content="1")
  assert_true(
    disconnected.tabs[0].workspace
    is Project(@interop.ChannelId::Local, resource) &&
    resource.path == "/local",
  )
  assert_true(disconnected.shown is None)
  assert_true(
    disconnected.exited_before_open ==
    [(local_channel, "local-opening-terminal")],
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
  let ctx : Ctx = {
    channel: @interop.ChannelId::Local,
    session: "missing",
    placement: Some(
      @interop.Worktree(project=workspace, name="wt", root=worktree_root),
    ),
    dark_mode: false,
    connected: true,
  }
  let (_, opening) = update(emit, ToggleTerminal, State::empty(), ctx)
  let (_, running) = update(
    emit,
    Opened(channel=@interop.ChannelId::Local, key=1, id="worktree-terminal"),
    opening,
    ctx,
  )
  let other_ctx = {
    ..ctx,
    session: "other",
    placement: Some(@interop.WorkspaceRoot(root=workspace)),
  }
  let (_, other_opening) = update(emit, NewTerminal, running, other_ctx)
  let (_, both_running) = update(
    emit,
    Opened(channel=@interop.ChannelId::Local, key=2, id="project-terminal"),
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
  let (_, toggle_refused) = update(
    emit,
    ToggleTerminal,
    State::empty(),
    missing_ctx,
  )
  let (_, new_refused) = update(emit, NewTerminal, State::empty(), missing_ctx)
  assert_true(toggle_refused == State::empty())
  assert_true(new_refused == State::empty())
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
  let main : Ctx = {
    channel: @interop.ChannelId::Local,
    session: "main-chat",
    placement: Some(@interop.WorkspaceRoot(root=workspace)),
    dark_mode: false,
    connected: true,
  }
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
  let main : Ctx = {
    channel: @interop.ChannelId::Local,
    session: "main-chat",
    placement: Some(@interop.WorkspaceRoot(root=workspace)),
    dark_mode: false,
    connected: true,
  }
  let (_, project_opening) = update(emit, ToggleTerminal, State::empty(), main)
  let unresolved : Ctx = { ..main, session: "restored-chat", placement: None, }
  // The existing project tab stays alive for its owner, but the restored
  // conversation cannot see it or create another tab under the same key.
  let (waiting, _) = sync(emit, project_opening, unresolved)
  assert_eq(waiting.tabs.length(), 1)
  assert_true(waiting.shown is None)
  let (_, toggle_refused) = update(
    emit,
    ToggleTerminal,
    State::empty(),
    unresolved,
  )
  let (_, new_refused) = update(emit, NewTerminal, waiting, unresolved)
  assert_true(toggle_refused == State::empty())
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
