///|
fn cloud_ctx(session : String) -> Ctx {
  Ctx::cloud(account="account", session~, ready=true, epoch=1, dark_mode=false)
}

///|
test "Cloud terminal groups and exit events are scoped by connection, not PTY id" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let a = cloud_ctx("a")
  let b = cloud_ctx("b")
  let (_, state) = open_new_tab(emit, State::empty(), a)
  let key_a = state.tabs[0].key
  let (_, state) = update(
    emit,
    Opened(channel=a.channel, key=key_a, id="pty-1"),
    state,
    a,
  )
  let (_, state) = open_new_tab(emit, state, b)
  let key_b = state.tabs[1].key
  let (_, state) = update(
    emit,
    Opened(channel=b.channel, key=key_b, id="pty-1"),
    state,
    b,
  )
  assert_eq(state.visible_tabs(a).length(), 1)
  assert_eq(state.visible_tabs(b).length(), 1)
  let (_, state) = update(
    emit,
    SessionExited(channel=a.channel, id="pty-1", code=0),
    state,
    b,
  )
  assert_eq(state.visible_tabs(a).length(), 0)
  assert_eq(state.visible_tabs(b).length(), 1)
  assert_true(state.tabs[0].key == key_b)
}

///|
test "Cloud disconnect never respawns a terminal until an explicit new terminal" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let ctx = cloud_ctx("a")
  let (_, state) = update(emit, ToggleTerminal, State::empty(), ctx)
  let (_, state) = update(
    emit,
    CloudDisconnected(connection=ctx.channel, authenticated=true, reason=None),
    state,
    ctx,
  )
  let (state, _) = sync(emit, state, ctx)
  assert_true(state.tabs.is_empty())
  assert_true(state.interrupted_channels.contains(ctx.channel))
  let (_, hidden) = update(emit, ToggleTerminal, state, ctx)
  assert_false(hidden.open)
  let (_, state) = update(emit, ToggleTerminal, hidden, ctx)
  assert_true(state.open)
  assert_true(state.tabs.is_empty())
  assert_true(state.interrupted_channels.contains(ctx.channel))
  let (_, state) = update(emit, NewTerminal, state, ctx)
  assert_eq(state.tabs.length(), 1)
  assert_false(state.interrupted_channels.contains(ctx.channel))
}

///|
test "failed Cloud authentication restores an unstarted bang command" {
  let messages : Array[Msg] = []
  let emit : @cmd.Emit[Msg] = @cmd.Emit(msg => {
    messages.push(msg)
    @cmd.none
  })
  let ctx = cloud_ctx("a")
  let (_, state) = open_new_tab(emit, State::empty(), ctx, command={
    shell: "submission",
    text: "echo hi",
  })
  let (_, state) = update(
    emit,
    CloudDisconnected(
      connection=ctx.channel,
      authenticated=false,
      reason=Some("Shell access is not enabled for this account"),
    ),
    state,
    ctx,
  )
  assert_true(state.tabs.is_empty())
  assert_true(
    messages
    is [
      CommandNotStarted(
        shell="submission",
        message="Shell access is not enabled for this account"
      ),
    ],
  )
  assert_true(
    state.cloud_failures
    is [(_, Some("Shell access is not enabled for this account"))],
  )
  let (_, retried) = update(emit, NewTerminal, state, ctx)
  assert_true(retried.cloud_failures.is_empty())
  let (retired, _) = { ..state, live_channels: [ctx.channel], }.reconcile(
    emit,
    Input::Input(ctx~, live_channels=[], has_devices=true),
  )
  assert_true(retired.cloud_failures.is_empty())
}

///|
test "repeated emulator readiness opens only one PTY while authentication is pending" {
  let ctx = cloud_ctx("session")
  let emit = @cmd.Emit(_ => @cmd.none)
  let (_, state) = update(emit, NewTerminal, State::empty(), ctx)
  let tab = state.tabs[0]
  let (_, opening) = update(
    emit,
    EmulatorReady(key=tab.key, cols=80, rows=24),
    state,
    ctx,
  )
  assert_true(opening.tabs[0].status is TabOpening(requested=true))
  let (_, repeated) = update(
    emit,
    EmulatorReady(key=tab.key, cols=80, rows=24),
    opening,
    ctx,
  )
  assert_true(repeated.tabs == opening.tabs)
  assert_false(repeated.tabs[0].awaits_session(true))
}
