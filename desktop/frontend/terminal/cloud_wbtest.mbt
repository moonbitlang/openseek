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
    CloudDisconnected(connection=ctx.channel, authenticated=true),
    state,
    ctx,
  )
  let (state, _) = sync(emit, state, ctx)
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
    CloudDisconnected(connection=ctx.channel, authenticated=false),
    state,
    ctx,
  )
  assert_true(state.tabs.is_empty())
  assert_true(messages is [CommandNotStarted(shell="submission", ..)])
}
