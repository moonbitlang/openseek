///|
fn input_fixture() -> (Ctx, State) raise {
  guard @resource.of_path(@interop.ChannelId::Local, "/work/input")
    is Some(root) else {
    fail("invalid fixture")
  }
  let ctx = local_ctx("input", @interop.WorkspaceRoot(root~))
  let (_, state) = update(
    @cmd.Emit(_ => @cmd.none),
    ToggleTerminal,
    State::empty(),
    ctx,
  )
  (ctx, state)
}

///|
fn input_ack(state : State) -> State raise {
  guard state.tabs[0].input.active is Some(batch) &&
    state.tabs[0].id is Some(id) else {
    fail("no active write")
  }
  finish_input(
    @cmd.Emit(_ => @cmd.none),
    state,
    state.tabs[0].key,
    id,
    batch.token,
    Ok(()),
  ).1
}

///|
test "input waits for open and coalesces a burst without losing byte order" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (ctx, opening) = input_fixture()
  let key = opening.tabs[0].key
  let (_, queued) = update(
    emit,
    UserInput(key~, data="before-open"),
    opening,
    ctx,
  )
  assert_true(queued.tabs[0].input.active is None)
  let (_, running) = update(
    emit,
    Opened(channel=@interop.ChannelId::Local, key~, id="pty"),
    queued,
    ctx,
  )
  guard running.tabs[0].input.active is Some(first) else {
    fail("input did not start")
  }
  assert_eq(first.chunk.data, "before-open")
  let mut state = running
  for i = 0; i < 200; i = i + 1 {
    state = update(emit, UserInput(key~, data="\{i},"), state, ctx).1
    assert_true(state.tabs[0].input.active == Some(first))
  }
  state = input_ack(state)
  guard state.tabs[0].input.active is Some(next) else {
    fail("queued burst was lost")
  }
  assert_eq(next.chunk.data, Array::makei(200, i => "\{i},").join(""))
  state = input_ack(state)
  assert_true(state.tabs[0].input.active is None)
  assert_true(state.tabs[0].input.pending.is_empty())
}

///|
test "binary input keeps separate base64 records between text events" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (ctx, opening) = input_fixture()
  let key = opening.tabs[0].key
  let mut state = opening
  for
    msg in [
      UserInput(key~, data="a"),
      BinaryInput(key~, data="/w=="),
      BinaryInput(key~, data="AA=="),
      UserInput(key~, data="b"),
    ] {
    state = update(emit, msg, state, ctx).1
  }
  state = update(
      emit,
      Opened(channel=@interop.ChannelId::Local, key~, id="pty"),
      state,
      ctx,
    ).1
  for expected in [("a", false), ("/w==", true), ("AA==", true), ("b", false)] {
    guard state.tabs[0].input.active is Some(batch) else {
      fail("record missing")
    }
    assert_eq((batch.chunk.data, batch.chunk.binary), expected)
    state = input_ack(state)
  }
  assert_true(state.tabs[0].input.active is None)
}

///|
test "failed or stale input acknowledgements never replay uncertain writes" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (ctx, opening) = input_fixture()
  let key = opening.tabs[0].key
  let mut state = update(
      emit,
      Opened(channel=@interop.ChannelId::Local, key~, id="pty"),
      opening,
      ctx,
    ).1
  state = update(emit, UserInput(key~, data="sent"), state, ctx).1
  state = update(emit, UserInput(key~, data="unsent"), state, ctx).1
  guard state.tabs[0].input.active is Some(batch) else { fail("write missing") }
  let stale = finish_input(emit, state, key, "other-pty", batch.token, Ok(())).1
  assert_true(stale == state)
  let stale = finish_input(emit, state, key, "pty", "old-token", Ok(())).1
  assert_true(stale == state)
  state = finish_input(
      emit,
      state,
      key,
      "pty",
      batch.token,
      Err("disconnected"),
    ).1
  assert_true(state.tabs[0].input.failure is Some(_))
  assert_true(state.tabs[0].input.pending.is_empty())
  assert_true(state.tabs[0].input.active is None)
  assert_true(state.tabs[0].status is TabRunning)
  assert_true(
    update(emit, UserInput(key~, data="ignored"), state, ctx).1 == state,
  )
  assert_true(
    finish_input(emit, state, key, "pty", batch.token, Ok(())).1 == state,
  )
  let closed = update(emit, TabClosed(key~), state, ctx).1
  let replacement = update(emit, NewTerminal, closed, ctx).1
  assert_true(
    finish_input(emit, replacement, key, "pty", batch.token, Ok(())).1 ==
    replacement,
  )
}

///|
test "input budgets count UTF8 bytes and bound queued events without truncation" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (ctx, opening) = input_fixture()
  let key = opening.tabs[0].key
  let running = update(
      emit,
      Opened(channel=@interop.ChannelId::Local, key~, id="pty"),
      opening,
      ctx,
    ).1
  let text = Array::make(InputByteLimit / 2, "é").join("")
  let full = update(emit, UserInput(key~, data=text), running, ctx).1
  guard full.tabs[0].input.active is Some(batch) else {
    fail("bounded paste refused")
  }
  assert_eq(batch.chunk.data, text)
  let overflow = update(emit, UserInput(key~, data="x"), full, ctx).1
  assert_true(overflow.tabs[0].input.failure is Some(_))
  assert_true(overflow.tabs[0].input.active == Some(batch))
  assert_true(overflow.tabs[0].input.pending.is_empty())
  assert_true(input_ack(overflow).tabs[0].input.active is None)
  let mut queued = opening
  for i = 0; i < InputChunkLimit; i = i + 1 {
    queued = update(emit, UserInput(key~, data="x"), queued, ctx).1
  }
  assert_true(queued.tabs[0].input.failure is None)
  queued = update(emit, UserInput(key~, data="x"), queued, ctx).1
  assert_true(queued.tabs[0].input.failure is Some(_))
  assert_true(queued.tabs[0].input.pending.is_empty())
}
