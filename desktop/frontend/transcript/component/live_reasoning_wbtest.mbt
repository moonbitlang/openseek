///|
/// State-only projection for transitions whose DOM effect is not under test.
fn LiveReasoningState::transition(
  self : LiveReasoningState,
  msg : LiveReasoningMsg,
) -> LiveReasoningState {
  self.update(msg).0
}

///|
/// The preview text this input would show, if any.
fn LiveReasoningState::content_for(
  self : LiveReasoningState,
  input : Input,
) -> String? {
  guard input.live_reasoning_target() is Some(target) else { return None }
  self.preview_for(target.key).map(preview => preview.content())
}

///|
test "live reasoning appends by owner and semantic finish deletes it" {
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
  let empty = LiveReasoningState::{ previews: @vector.new(), active: None, }
  let target = input.live_reasoning_target()
  let (focused, focus_effect) = empty.update(Focused(target))
  assert_eq(
    focus_effect,
    Sync(target=key.wire(), step_label=Some("#1"), content=None),
  )
  let (first, first_effect) = focused.update(Delta(key, "think"))
  assert_eq(first_effect, Append(target=key.wire(), content="think"))
  let (live, second_effect) = first.update(Delta(key, "ing"))
  assert_eq(second_effect, Append(target=key.wire(), content="ing"))
  assert_eq(live.content_for(input), Some("thinking"))
  let (_, hydrate_effect) = live.update(Focused(target))
  assert_eq(
    hydrate_effect,
    Sync(target=key.wire(), step_label=Some("#1"), content=Some("thinking")),
  )

  // The full reasoning event is a semantic boundary, not a durable commit.
  // Removing the preview here makes both commit-first and finish-first delivery
  // converge without comparing the reasoning text with transcript history.
  let (finished, finish_effect) = live.update(Finished(key))
  assert_eq(finished.content_for(input), None)
  assert_eq(finish_effect, Hide(target=key.wire()))

  let late = finished.transition(Delta(key, "late"))
  assert_eq(late.content_for(input), None)
  let next_step = late
    .transition(StepStarted(key))
    .transition(Delta(key, "next"))
  assert_eq(next_step.content_for(input), Some("next"))

  // Updating the same immutable snapshot twice must produce the same result;
  // an emitter may replay a state transition while scheduling a render.
  assert_true(
    focused.update(Delta(key, "think")) == focused.update(Delta(key, "think")),
  )
}

///|
test "live reasoning keeps concurrent conversations and runs isolated" {
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
  let state = LiveReasoningState::{ previews: @vector.new(), active: None, }
    .transition(Delta(local_r7, "local-old"))
    .transition(Delta(local_r8, "local-current"))
    .transition(Delta(remote_r7, "remote"))
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
    Sync(
      target=local_r8.wire(),
      step_label=Some("#1"),
      content=Some("local-current"),
    ),
  )
  let (with_background, background_effect) = focused.update(
    Delta(remote_r7, "-more"),
  )
  assert_eq(background_effect, NoChange)
  assert_eq(with_background.content_for(remote_input), Some("remote-more"))

  let after_run = with_background.transition(
    RunFinished(@interop.ChannelId::Local, "r7"),
  )
  assert_eq(after_run.content_for(local_input), Some("local-current"))
  assert_eq(after_run.content_for(remote_input), Some("remote-more"))

  let after_channel = after_run.transition(
    ClearChannel(@interop.ChannelId::Remote("device-b")),
  )
  assert_eq(after_channel.content_for(local_input), Some("local-current"))
  assert_eq(after_channel.content_for(remote_input), None)
}
