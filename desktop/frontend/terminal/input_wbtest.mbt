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
      Err(WriteFailed("PTY write failed")),
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

///|
test "connection loss recovers with fresh input only in either callback order" {
  let remote : @interop.ChannelId = Remote("device")
  guard @resource.of_path(remote, "/work/input") is Some(root) else {
    fail("invalid fixture")
  }
  let ctx : Ctx = {
    channel: remote,
    session: "input",
    placement: Some(@interop.WorkspaceRoot(root~)),
    dark_mode: false,
    connected: true,
  }
  for reply_first in [true, false] {
    let messages : Array[Msg] = []
    let emit : @cmd.Emit[Msg] = @cmd.Emit(msg => {
      messages.push(msg)
      @cmd.none
    })
    let (_, opening) = update(emit, ToggleTerminal, State::empty(), ctx)
    let key = opening.tabs[0].key
    let mut state = update(
        emit,
        Opened(channel=remote, key~, id="old"),
        opening,
        ctx,
      ).1
    state = { ..state, live_channels: [remote], }
    state = update(emit, UserInput(key~, data="maybe-delivered\n"), state, ctx).1
    state = update(emit, UserInput(key~, data="unsent-tail\n"), state, ctx).1
    guard state.tabs[0].input.active is Some(batch) else { fail("no write") }
    let failure = InputSettled(
      key~,
      id="old",
      token=batch.token,
      result=Err(ConnectionLost),
    )
    if reply_first {
      state = update(emit, failure, state, ctx).1
      assert_true(state.tabs[0].input.failure is Some(Reconnecting))
      assert_true(state.tabs[0].input.pending.is_empty())
      assert_true(state.tabs[0].input.active is None)
      assert_true(
        update(emit, UserInput(key~, data="ignored"), state, ctx).1 == state,
      )
    }
    let down = { ..ctx, connected: false, }
    state = state.reconcile(
        emit,
        Input(ctx=down, live_channels=[], has_devices=true),
      ).0
    assert_true(state.open)
    assert_true(state.tabs.is_empty())
    assert_true(state.interrupted_channels.contains(remote))
    if !reply_first {
      assert_true(update(emit, failure, state, down).1 == state)
    }
    state = state.reconcile(
        emit,
        Input(ctx~, live_channels=[remote], has_devices=true),
      ).0
    assert_eq(state.tabs.length(), 1)
    let replacement_key = state.tabs[0].key
    assert_true(replacement_key != key)
    state = update(
        emit,
        Opened(channel=remote, key=replacement_key, id="new"),
        state,
        ctx,
      ).1
    assert_true(state.tabs[0].input.active is None)
    assert_true(state.tabs[0].input.pending.is_empty())
    assert_true(update(emit, failure, state, ctx).1 == state)
    assert_true(
      finish_input(emit, state, key, "old", batch.token, Ok(())).1 == state,
    )
    state = update(
        emit,
        UserInput(key=replacement_key, data="fresh\n"),
        state,
        ctx,
      ).1
    guard state.tabs[0].input.active is Some(fresh) else {
      fail("new input remained paused")
    }
    assert_eq(fresh.chunk.data, "fresh\n")
    assert_false(state.interrupted_channels.contains(remote))
    assert_false(messages.any(msg => msg is InputFailed(..)))
  }
}
