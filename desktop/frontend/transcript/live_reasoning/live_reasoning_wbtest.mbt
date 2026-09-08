///|
/// State-only projection for transitions whose DOM effect is not under test.
fn LiveReasoningState::transition(
  self : LiveReasoningState,
  msg : LiveReasoningMsg,
) -> LiveReasoningState {
  self.update(msg).0
}

///|
/// The preview text this owner would show, if any.
fn LiveReasoningState::content_for(
  self : LiveReasoningState,
  key : Key,
) -> String? {
  self.preview_for(key).map(preview => preview.content())
}

///|
test "live reasoning appends by owner and semantic finish deletes it" {
  let key : Key = {
    channel: @interop.ChannelId::Local,
    session: "desktop-test",
    run_id: "r7",
  }
  let target : Target = { key, step_label: Some("#1"), }
  let empty = LiveReasoningState::{ previews: @vector.new(), active: None, }
  let (focused, focus_effect) = empty.update(Focused(Some(target)))
  assert_eq(
    focus_effect,
    Sync(target=key.wire(), step_label=Some("#1"), content=None),
  )
  let (first, first_effect) = focused.update(Delta(key, "think"))
  assert_eq(first_effect, Append(target=key.wire(), content="think"))
  let (live, second_effect) = first.update(Delta(key, "ing"))
  assert_eq(second_effect, Append(target=key.wire(), content="ing"))
  assert_eq(live.content_for(key), Some("thinking"))
  let (_, hydrate_effect) = live.update(Focused(Some(target)))
  assert_eq(
    hydrate_effect,
    Sync(target=key.wire(), step_label=Some("#1"), content=Some("thinking")),
  )

  // The full reasoning event is a semantic boundary, not a durable commit.
  // Removing the preview here makes both commit-first and finish-first delivery
  // converge without comparing the reasoning text with transcript history.
  let (finished, finish_effect) = live.update(Finished(key))
  assert_eq(finished.content_for(key), None)
  assert_eq(finish_effect, Hide(target=key.wire()))

  let late = finished.transition(Delta(key, "late"))
  assert_eq(late.content_for(key), None)
  let next_step = late
    .transition(StepStarted(key))
    .transition(Delta(key, "next"))
  assert_eq(next_step.content_for(key), Some("next"))

  // Updating the same immutable snapshot twice must produce the same result;
  // an emitter may replay a state transition while scheduling a render.
  assert_true(
    focused.update(Delta(key, "think")) == focused.update(Delta(key, "think")),
  )
}

///|
test "live reasoning keeps concurrent conversations and runs isolated" {
  let local_r7 : Key = {
    channel: @interop.ChannelId::Local,
    session: "shared",
    run_id: "r7",
  }
  let local_r8 : Key = {
    channel: @interop.ChannelId::Local,
    session: "shared",
    run_id: "r8",
  }
  let remote_r7 : Key = {
    channel: @interop.ChannelId::Remote("device-b"),
    session: "shared",
    run_id: "r7",
  }
  let state = LiveReasoningState::{ previews: @vector.new(), active: None, }
    .transition(Delta(local_r7, "local-old"))
    .transition(Delta(local_r8, "local-current"))
    .transition(Delta(remote_r7, "remote"))
  assert_eq(state.content_for(local_r8), Some("local-current"))
  assert_eq(state.content_for(remote_r7), Some("remote"))

  let (focused, focus_effect) = state.update(
    Focused(Some({ key: local_r8, step_label: Some("#1"), })),
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
  assert_eq(with_background.content_for(remote_r7), Some("remote-more"))

  // Finishing one run leaves the session's other run and the other device
  // untouched; retiring a device drops only that device's previews.
  let after_run = with_background.transition(
    RunFinished(@interop.ChannelId::Local, "r7"),
  )
  assert_eq(after_run.content_for(local_r7), None)
  assert_eq(after_run.content_for(local_r8), Some("local-current"))
  assert_eq(after_run.content_for(remote_r7), Some("remote-more"))

  let after_channel = after_run.transition(
    ClearChannel(@interop.ChannelId::Remote("device-b")),
  )
  assert_eq(after_channel.content_for(local_r8), Some("local-current"))
  assert_eq(after_channel.content_for(remote_r7), None)
}
