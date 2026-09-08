///|
test "live reasoning appends by owner and semantic finish deletes it" {
  let epoch = 7
  let key : LiveReasoningKey = {
    channel: @interop.ChannelId::Local,
    session: "desktop-test",
    run_id: "r7",
  }
  let input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Local,
    active_session="desktop-test",
    active_run_id="r7",
    current_project=None,
    projects=[],
    can_choose_project=false,
    project_menu_open=false,
    project_query="",
    root=None,
    items=[],
    streaming_response=None,
    streaming_identity="r7",
  )
  // An open run can precede its first durable User commit. Its independent
  // preview must not appear beneath the empty-chat welcome screen.
  assert_true(stream_blocks(input).is_empty())
  let empty = LiveReasoningState::{
    connections: @vector.new(),
    previews: @vector.new(),
    active: None,
  }
  let connected = empty.transition(
    ConnectionOpened(@interop.ChannelId::Local, websocket_epoch=epoch),
  )
  let target = input.live_reasoning_target()
  let (focused, focus_effect) = connected.update(Focused(target))
  assert_eq(focus_effect, Sync(target=key.wire(), step_label="#1", content=""))
  let (first, first_effect) = focused.update(
    Delta(key, websocket_epoch=epoch, "think"),
  )
  assert_eq(first_effect, Append(target=key.wire(), content="think"))
  let (live, second_effect) = first.update(
    Delta(key, websocket_epoch=epoch, "ing"),
  )
  assert_eq(second_effect, Append(target=key.wire(), content="ing"))
  assert_eq(live.content_for(input), Some("thinking"))
  let (_, hydrate_effect) = live.update(Focused(target))
  assert_eq(
    hydrate_effect,
    Sync(target=key.wire(), step_label="#1", content="thinking"),
  )

  // The full reasoning event is a semantic boundary, not a durable commit.
  // Removing the preview here makes both commit-first and finish-first delivery
  // converge without comparing the reasoning text with transcript history.
  let (finished, finish_effect) = live.update(
    Finished(key, websocket_epoch=epoch),
  )
  assert_eq(finished.content_for(input), None)
  assert_eq(finish_effect, Hide(target=key.wire()))

  let late = finished.transition(Delta(key, websocket_epoch=epoch, "late"))
  assert_eq(late.content_for(input), None)
  let next_step = late
    .transition(StepStarted(key, websocket_epoch=epoch))
    .transition(Delta(key, websocket_epoch=epoch, "next"))
  assert_eq(next_step.content_for(input), Some("next"))

  // Updating the same immutable snapshot twice must produce the same result;
  // an emitter may replay a state transition while scheduling a render.
  assert_true(
    focused.update(Delta(key, websocket_epoch=epoch, "think")) ==
    focused.update(Delta(key, websocket_epoch=epoch, "think")),
  )
}

///|
test "live reasoning keeps concurrent conversations and runs isolated" {
  let epoch = 7
  let local_r7 : LiveReasoningKey = {
    channel: @interop.ChannelId::Local,
    session: "shared",
    run_id: "r7",
  }
  let local_r8 : LiveReasoningKey = {
    channel: @interop.ChannelId::Local,
    session: "shared",
    run_id: "r8",
  }
  let remote_r7 : LiveReasoningKey = {
    channel: @interop.ChannelId::Remote("device-b"),
    session: "shared",
    run_id: "r7",
  }
  let state = LiveReasoningState::{
      connections: @vector.new(),
      previews: @vector.new(),
      active: None,
    }
    .transition(
      ConnectionOpened(@interop.ChannelId::Local, websocket_epoch=epoch),
    )
    .transition(
      ConnectionOpened(
        @interop.ChannelId::Remote("device-b"),
        websocket_epoch=epoch,
      ),
    )
    .transition(Delta(local_r7, websocket_epoch=epoch, "local-old"))
    .transition(Delta(local_r8, websocket_epoch=epoch, "local-current"))
    .transition(Delta(remote_r7, websocket_epoch=epoch, "remote"))
  let local_input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Local,
    active_session="shared",
    active_run_id="r8",
    current_project=None,
    projects=[],
    can_choose_project=false,
    project_menu_open=false,
    project_query="",
    root=None,
    items=[],
    streaming_response=None,
    streaming_identity="r8",
  )
  let remote_input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Remote("device-b"),
    active_session="shared",
    active_run_id="r7",
    current_project=None,
    projects=[],
    can_choose_project=false,
    project_menu_open=false,
    project_query="",
    root=None,
    items=[],
    streaming_response=None,
    streaming_identity="r7",
  )
  assert_eq(state.content_for(local_input), Some("local-current"))
  assert_eq(state.content_for(remote_input), Some("remote"))

  let (focused, focus_effect) = state.update(
    Focused(local_input.live_reasoning_target()),
  )
  assert_eq(
    focus_effect,
    Sync(target=local_r8.wire(), step_label="#1", content="local-current"),
  )
  let (with_background, background_effect) = focused.update(
    Delta(remote_r7, websocket_epoch=epoch, "-more"),
  )
  assert_eq(background_effect, NoChange)
  assert_eq(with_background.content_for(remote_input), Some("remote-more"))

  let after_run = with_background.transition(
    RunFinished(@interop.ChannelId::Local, websocket_epoch=epoch, "r7"),
  )
  assert_eq(after_run.content_for(local_input), Some("local-current"))
  assert_eq(after_run.content_for(remote_input), Some("remote-more"))

  let after_channel = after_run.transition(
    ConnectionClosed(
      @interop.ChannelId::Remote("device-b"),
      websocket_epoch=epoch,
    ),
  )
  assert_eq(after_channel.content_for(local_input), Some("local-current"))
  assert_eq(after_channel.content_for(remote_input), None)
}

///|
test "live reasoning rejects stale connection callbacks" {
  let channel = @interop.ChannelId::Remote("device-b")
  let key : LiveReasoningKey = {
    channel,
    session: "desktop-test",
    run_id: "r7",
  }
  let input = Input(
    source=OpenSeek,
    focused=channel,
    active_session="desktop-test",
    active_run_id="r7",
    current_project=None,
    projects=[],
    can_choose_project=false,
    project_menu_open=false,
    project_query="",
    root=None,
    items=[],
    streaming_response=None,
    streaming_identity="r7",
  )
  let empty = LiveReasoningState::{
    connections: @vector.new(),
    previews: @vector.new(),
    active: None,
  }
  let current = empty
    .transition(ConnectionOpened(channel, websocket_epoch=1))
    .transition(Delta(key, websocket_epoch=1, "old"))
    .transition(ConnectionOpened(channel, websocket_epoch=2))
    .transition(Delta(key, websocket_epoch=2, "current"))

  // Both callbacks belong to the replaced socket. Neither may change the
  // current preview, even if JavaScript queued them before the replacement.
  let after_stale = current
    .transition(ConnectionOpened(channel, websocket_epoch=1))
    .transition(Delta(key, websocket_epoch=1, "-stale"))
    .transition(ConnectionClosed(channel, websocket_epoch=1))
  assert_eq(after_stale.content_for(input), Some("current"))

  // The current close clears once and keeps the epoch fenced, so a delta
  // already queued by the closed socket cannot recreate the preview.
  let closed = after_stale
    .transition(ConnectionClosed(channel, websocket_epoch=2))
    .transition(Delta(key, websocket_epoch=2, "late"))
  assert_eq(closed.content_for(input), None)
  assert_true(
    after_stale.transition(ConnectionClosed(channel, websocket_epoch=2)) ==
    after_stale.transition(ConnectionClosed(channel, websocket_epoch=2)),
  )

  // `agent.connected` can reopen the engine pump without replacing the
  // WebSocket. The same epoch becomes receiving again, starting from empty.
  let reopened = closed
    .transition(ConnectionOpened(channel, websocket_epoch=2))
    .transition(Delta(key, websocket_epoch=2, "fresh"))
  assert_eq(reopened.content_for(input), Some("fresh"))
}
