///|
/// A conversation with `!` command `s1` (`ls`) still running and the user's
/// own unsent writing in the composer.
fn with_running_shell(model : Model, conv : Conversation) -> Model {
  model.replace_conversation({
    ..conv,
    task: "my own draft",
    composer_draft_present: true,
    shell_commands: [{ id: "s1", command: "ls", }],
  })
}

///|
test "a finished ! command starts a turn with its result when the conversation is idle" {
  let dispatch = test_dispatch()
  let model = with_running_shell(test_model(), test_model().active())
  let (_, sent) = shell_command_finished(
    dispatch,
    model,
    "s1",
    Some(0),
    "README.md\nsrc",
    false,
  )
  let conv = sent.active()
  assert_true(conv.shell_commands.is_empty())
  assert_true(conv.run is Starting(..))
  guard conv.pending_prompt is Some({ draft, .. }) &&
    @command_context.parse(draft) is Some(result) else {
    fail("the result was not sent as the turn's prompt")
  }
  assert_eq(result.command, "ls")
  assert_eq(result.exit, "0")
  assert_eq(result.output, ["README.md", "src"])
  // The user's own writing was set aside for the send, not consumed by it.
  assert_eq(conv.task, "my own draft")
  assert_true(conv.composer_draft_present)
}

///|
test "a finished ! command steers the turn that is running" {
  let dispatch = test_dispatch()
  let model = with_running_shell(test_model(), running_conversation())
  let (_, sent) = shell_command_finished(
    dispatch,
    model,
    "s1",
    None,
    "partial",
    false,
  )
  let conv = sent.active()
  assert_true(conv.shell_commands.is_empty())
  guard conv.pending_steers is [steer] &&
    @command_context.parse(steer.content) is Some(result) else {
    fail("the result was not sent into the open turn")
  }
  assert_eq(steer.run_id, Some("r7"))
  // It did not exit on its own account: interrupted, or its tab was closed.
  assert_eq(result.exit, "cancelled")
  assert_eq(conv.task, "my own draft")
}

///|
test "a result that cannot be sent yet waits in the composer" {
  let dispatch = test_dispatch()
  let model = with_running_shell(test_model(), {
    ..test_model().active(),
    compaction: Compacting,
  })
  let (_, held) = shell_command_finished(
    dispatch,
    model,
    "s1",
    Some(0),
    "out",
    false,
  )
  let conv = held.active()
  assert_true(conv.shell_commands.is_empty())
  assert_true(conv.run is NoRun(..))
  // Ahead of the user's own text, so nothing a command printed is dropped.
  assert_true(conv.task.has_prefix("<user_shell_command>\n"))
  assert_true(conv.task.has_suffix("</user_shell_command>\n\nmy own draft"))
  assert_true(conv.composer_draft_present)
}

///|
test "a ! command that never ran goes back to an empty composer only" {
  let dispatch = test_dispatch()
  let conv = test_model().active()
  let empty = test_model().replace_conversation({
    ..conv,
    shell_commands: [{ id: "s1", command: "moon test", }],
  })
  let (_, restored) = shell_not_started(
    dispatch,
    empty,
    conv.device,
    conv.session_id,
    "s1",
    "no terminal",
  )
  assert_true(restored.active().shell_commands.is_empty())
  assert_eq(restored.active().task, "!moon test")
  // Newer writing there is never overwritten.
  let (_, kept) = shell_not_started(
    dispatch,
    with_running_shell(test_model(), conv),
    conv.device,
    conv.session_id,
    "s1",
    "no terminal",
  )
  assert_true(kept.active().shell_commands.is_empty())
  assert_eq(kept.active().task, "my own draft")
}

///|
test "a report for a command nobody is waiting on changes nothing" {
  let dispatch = test_dispatch()
  let model = test_model()
  let (_, same) = shell_command_finished(
    dispatch,
    model,
    "unknown",
    Some(0),
    "out",
    false,
  )
  assert_true(same.active() == model.active())
}

///|
test "a result from a device that is not focused waits in its composer" {
  let dispatch = test_dispatch()
  let model = with_running_shell(test_model(), test_model().active())
  // The page mirrors host settings for the focused device only.
  let elsewhere = { ..model, focused: @interop.ChannelId::Remote("device-b"), }
  let (_, held) = shell_command_finished(
    dispatch,
    elsewhere,
    "s1",
    Some(0),
    "out",
    false,
  )
  guard held.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(conv) else {
    fail("the conversation is gone")
  }
  assert_true(conv.shell_commands.is_empty())
  assert_true(conv.run is NoRun(..))
  assert_true(conv.task.has_prefix("<user_shell_command>\n"))
  assert_true(conv.task.has_suffix("\n\nmy own draft"))
}

///|
test "a held result takes the draft out of a queue edit" {
  let dispatch = test_dispatch()
  let conv = {
    ..running_conversation(),
    queue_edit: Some(Saving(id="queued-1", run_id="r7", mentions=[])),
    queued_inputs: [{ id: "queued-1", content: "original", images: [], }],
  }
  let model = with_running_shell(test_model(), conv)
  // A device that is not focused: the result is held, not sent.
  let elsewhere = { ..model, focused: @interop.ChannelId::Remote("device-b"), }
  let (_, held) = shell_command_finished(
    dispatch,
    elsewhere,
    "s1",
    Some(0),
    "out",
    false,
  )
  guard held.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(after) else {
    fail("the conversation is gone")
  }
  // The held result takes ownership of the draft, but cannot release the
  // outstanding request's lock and permit a second save of the same item.
  assert_true(after.queue_edit is Some(SavingDetached(..)))
  assert_true(after.task.has_prefix("<user_shell_command>\n"))
  let focused = { ..held, focused: after.device, }
  let (_, edited) = update(
    dispatch,
    ComposerAction(
      @composer.QueuedInputEditRequested(
        identity=focused.composer_input().identity,
        id="queued-1",
      ),
    ),
    focused,
  )
  assert_true(edited.active().queue_edit == after.queue_edit)
  let (_, duplicate) = update(dispatch, Send, edited)
  assert_eq(duplicate.active().task, after.task)
  assert_true(duplicate.active().queue_edit == after.queue_edit)
  let (_, rejected) = update_device_msg(
    dispatch,
    after.device,
    QueueEditRejected(
      session=after.session_id,
      id="queued-1",
      run_id="r7",
      message="save rejected",
    ),
    focused,
  )
  assert_true(rejected.active().queue_edit is None)
  assert_eq(rejected.active().task, after.task)
  let accepted = QueueAccepted(
    session=after.session_id,
    action=QueueEdit(id="queued-1", text="accepted revision", images=[]),
    run_id="r7",
  )
  for _ in 0..<2 {
    let (_, updated) = update_device_msg(dispatch, after.device, accepted, held)
    guard updated.find_conversation(after.device, after.session_id)
      is Some(saved) else {
      fail("the conversation is gone")
    }
    assert_eq(saved.queued_inputs[0].content, "accepted revision")
    assert_true(saved.queue_edit is None)
    assert_eq(saved.task, after.task)
    assert_eq(updated.submission_sequence, held.submission_sequence)
  }
  assert_eq(after.queued_inputs[0].content, "original")
}
