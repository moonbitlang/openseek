///|
fn controls_fixture() -> State {
  {
    ..State::empty(),
    user_id: Some("account"),
    epoch: 1,
    sessions: [
      {
        id: "session",
        title: None,
        updated_at: None,
        generating: true,
        archived: false,
      },
    ],
    conversations: {
      "session": {
        ..Conversation::empty(),
        loading: false,
        history_required: false,
        generating: true,
        stream: Some(StreamLease::new()),
        task: Some("task"),
        last_seq: Some(2),
        control: Some({
          active_task_id: Some("task"),
          status: Running,
          paused: false,
          queue: [],
          steers: [],
        }),
      },
    },
  }
}

///|
fn controls_submit(state : State, choice : @composer.FollowupChoice) -> State {
  let owner : @interop.ConversationIdentity = Cloud(
    account="account",
    session="session",
  )
  let action = @composer.FollowupSubmitted(
    identity={ owner, archive_generation: 0, },
    draft={ task: "Follow up", mentions: [], images: [], },
    choice~,
    attachments=[],
  )
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  state
  .update_control(ControlAction(owner, action), emit, Some("token"))
  .unwrap().0
}

///|
test "Cloud stop acceptance keeps running until the authoritative terminal event" {
  let state = controls_fixture()
  let owner : @interop.ConversationIdentity = Cloud(
    account="account",
    session="session",
  )
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  let (requested, _) = state
    .update_control(
      ControlAction(
        owner,
        @composer.StopRequested(identity={ owner, archive_generation: 0, }),
      ),
      emit,
      Some("token"),
    )
    .unwrap()
  let input = requested.conversations["session"].control_inputs[0]
  let (accepted, _) = requested
    .update_control(
      ControlFinished(1, "session", "task", input.key, Accepted),
      emit,
      Some("token"),
    )
    .unwrap()
  let conversation = accepted.conversations["session"]
  assert_true(conversation.generating)
  assert_true(
    conversation.control_primary_action(@composer.Steer)
    is @composer.Running(can_stop=false, steer_available=false, ..),
  )
  let finished = conversation.control_receipt({
    session_id: "session",
    task_id: "task",
    seq: 3,
    kind: "task_finished",
    data: { "status": "completed" },
  })
  assert_eq(finished.control_inputs.length(), 0)
}

///|
test "Cloud steer receipt before HTTP acceptance acknowledges exactly once and fences old tasks" {
  let state = controls_submit(controls_fixture(), @composer.SteerNow)
  let conversation = state.conversations["session"]
  let id = conversation.control_inputs[0].key
  let event : Event = {
    session_id: "session",
    task_id: "task",
    seq: 3,
    kind: "steer_applied",
    data: { "submission_id": id, "content": "Follow up" },
  }
  assert_true(
    conversation.control_receipt({ ..event, task_id: "old", }) == conversation,
  )
  let received = conversation.control_receipt(event)
  assert_eq(received.submission_sequence, 1)
  assert_eq(received.control_inputs.length(), 0)
  let received_state = state.replace("session", received)
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  let (late, _) = received_state
    .update_control(
      ControlFinished(1, "session", "task", id, Accepted),
      emit,
      Some("token"),
    )
    .unwrap()
  assert_true(late == received_state)
}

///|
test "Cloud unknown control results retain input while explicit refusal settles it" {
  let state = controls_submit(controls_fixture(), @composer.SteerNow)
  let id = state.conversations["session"].control_inputs[0].key
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  let (unknown, _) = state
    .update_control(
      ControlFailed(1, "session", "task", id, Unreachable),
      emit,
      Some("token"),
    )
    .unwrap()
  let pending = unknown.conversations["session"]
  assert_eq(pending.control_inputs.length(), 1)
  assert_true(pending.control_inputs[0].unknown)
  assert_eq(pending.submission_sequence, 0)
  let unchanged = pending.control_snapshot(
    Some("task"),
    pending.control.unwrap(),
  )
  assert_eq(unchanged.control_inputs.length(), 1)
  let (refused, _) = unknown
    .update_control(
      ControlFinished(1, "session", "task", id, Rejected("task_not_running")),
      emit,
      Some("token"),
    )
    .unwrap()
  assert_eq(refused.conversations["session"].control_inputs.length(), 0)
  assert_eq(refused.conversations["session"].submission_sequence, 0)
}

///|
test "Cloud dropped queued steer restores its complete editable content" {
  let image = @wire.Image::from_base64(
    media_type="image/gif",
    "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==",
  )
  let content : @wire.Content = Content([Text("Recover this"), Image(image)])
  let draft = control_draft(content)
  assert_eq(draft.task, "Recover this")
  assert_eq(draft.images.length(), 1)
  assert_eq(prompt_content(draft), content)
  let conversation = {
    ..controls_fixture().conversations["session"],
    control_inputs: [
      {
        task_id: "task",
        key: "queued",
        operation: QueueSteer(id="queued"),
        draft: Some(draft),
        source: None,
        attachments: [],
        acknowledged: true,
        unknown: false,
      },
    ],
  }
  let dropped = conversation.control_receipt({
    session_id: "session",
    task_id: "task",
    seq: 4,
    kind: "steer_dropped",
    data: { "submission_id": "queued" },
  })
  assert_eq(dropped.initial_submission, Some(draft))
  assert_eq(dropped.control_inputs.length(), 0)
}

///|
test "Cloud paused queue stays visible and cannot be mutated while idle" {
  let state = controls_fixture()
  let conversation = {
    ..state.conversations["session"],
    generating: false,
    control: Some({
      active_task_id: None,
      status: Idle,
      paused: true,
      queue: [{ id: "queue", content: Content([Text("Retained")]), }],
      steers: [],
    }),
  }
  let state = state.replace("session", conversation)
  assert_true(
    conversation.control_context()
    is [@composer.QueuedInputPanel(enabled=false, items=[{ id: "queue", .. }])],
  )
  let owner : @interop.ConversationIdentity = Cloud(
    account="account",
    session="session",
  )
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  let (changed, _) = state
    .update_control(
      ControlAction(
        owner,
        @composer.QueuedInputDeleteRequested(
          identity={ owner, archive_generation: 0, },
          id="queue",
        ),
      ),
      emit,
      Some("token"),
    )
    .unwrap()
  assert_true(changed == state)
}

///|
test "Cloud HTTP reconciliation settles inputs without replacing SSE state" {
  let state = controls_submit(controls_fixture(), @composer.QueueNext)
  let conversation = state.conversations["session"]
  let input = conversation.control_inputs[0]
  let snapshot : ControlSnapshot = {
    session_id: "session",
    task_id: Some("task"),
    seq: 3,
    data: {
      active_task_id: Some("task"),
      status: Running,
      paused: false,
      queue: [{ id: input.key, content: Content([Text("Follow up")]), }],
      steers: [],
    },
  }
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  let (checked, _) = state
    .update_control(
      ControlChecked(1, "session", "task", snapshot),
      emit,
      Some("token"),
    )
    .unwrap()
  assert_true(checked.conversations["session"].control == conversation.control)
  assert_eq(checked.conversations["session"].submission_sequence, 1)
  assert_eq(checked.conversations["session"].control_inputs.length(), 1)
  assert_true(checked.conversations["session"].control_inputs[0].acknowledged)
  let streamed = checked.conversations["session"].control_snapshot(
    snapshot.task_id,
    snapshot.data,
  )
  assert_eq(streamed.control_inputs.length(), 0)
}

///|
test "Cloud a late queue edit reply cannot acknowledge the next edit of that item" {
  let state = controls_fixture()
  let item : QueueEntry = { id: "queue", content: Content([Text("First")]), }
  let control = {
    ..state.conversations["session"].control.unwrap(),
    queue: [item],
  }
  let state = state.replace("session", {
    ..state.conversations["session"],
    control: Some(control),
    queue_edit: Some("queue"),
  })
  let owner : @interop.ConversationIdentity = Cloud(
    account="account",
    session="session",
  )
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  let draft : @composer.Draft = { task: "Second", mentions: [], images: [], }
  let (first, _) = state
    .update_control(Submit(owner, draft), emit, Some("token"))
    .unwrap()
  let first_key = first.conversations["session"].control_inputs[0].key
  let confirmed = first.conversations["session"].control_snapshot(
    Some("task"),
    { ..control, queue: [{ ..item, content: Content([Text("Second")]), }], },
  )
  assert_eq(confirmed.control_inputs.length(), 0)
  let first = first.replace("session", {
    ..confirmed,
    queue_edit: Some("queue"),
  })
  let (second, _) = first
    .update_control(
      Submit(owner, { ..draft, task: "Third", }),
      emit,
      Some("token"),
    )
    .unwrap()
  let second_key = second.conversations["session"].control_inputs[0].key
  assert_true(first_key != second_key)
  let (late, _) = second
    .update_control(
      ControlFinished(1, "session", "task", first_key, Accepted),
      emit,
      Some("token"),
    )
    .unwrap()
  assert_true(late == second)
  assert_eq(late.conversations["session"].control_inputs[0].key, second_key)
  assert_eq(late.conversations["session"].submission_sequence, 1)
}

///|
test "Cloud old-task receipts settle their input without acknowledging a new draft" {
  let state = controls_submit(controls_fixture(), @composer.SteerNow)
  let conversation = state.conversations["session"]
  let input = conversation.control_inputs[0]
  let draft : @composer.Draft = { task: "New draft", mentions: [], images: [], }
  let conversation = {
    ..conversation,
    task: Some("next"),
    initial_submission: Some(draft),
  }
  let received = conversation.control_receipt({
    session_id: "session",
    task_id: "task",
    seq: 4,
    kind: "steer_applied",
    data: { "submission_id": input.key },
  })
  assert_eq(received.control_inputs.length(), 0)
  assert_eq(received.submission_sequence, conversation.submission_sequence)
  assert_eq(received.initial_submission, Some(draft))
}

///|
test "Cloud failed input preparation is definite and preserves the editable source" {
  let state = controls_submit(controls_fixture(), @composer.SteerNow)
  let id = state.conversations["session"].control_inputs[0].key
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  let (failed, _) = state
    .update_control(
      ControlPreparationFailed(1, "session", "task", id, InvalidImage),
      emit,
      Some("token"),
    )
    .unwrap()
  assert_eq(failed.conversations["session"].control_inputs.length(), 0)
  assert_eq(failed.conversations["session"].submission_sequence, 0)
  assert_eq(
    failed.conversations["session"].notice,
    Some(Failure::InvalidImage.label()),
  )
  let (expired, _) = state
    .update_control(
      ControlPreparationFailed(1, "session", "task", id, Unauthorized),
      emit,
      Some("token"),
    )
    .unwrap()
  assert_true(expired.needs_sign_in)
}

///|
test "Cloud a late acceptance preserves a draft restored after that request began" {
  let state = controls_submit(controls_fixture(), @composer.SteerNow)
  let conversation = state.conversations["session"]
  let input = conversation.control_inputs[0]
  let recovered : @composer.Draft = {
    task: "Recovered input",
    mentions: [],
    images: [],
  }
  let state = state.replace("session", {
    ..conversation,
    initial_submission: Some(recovered),
  })
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  let (accepted, _) = state
    .update_control(
      ControlFinished(1, "session", "task", input.key, Accepted),
      emit,
      Some("token"),
    )
    .unwrap()
  assert_eq(
    accepted.conversations["session"].initial_submission,
    Some(recovered),
  )
}

///|
test "Cloud disconnected control snapshots retain a read-only queue" {
  let state = controls_fixture()
  let conversation = state.conversations["session"]
  let control = {
    ..conversation.control.unwrap(),
    queue: [{ id: "retained", content: Content([Text("Retained")]), }],
  }
  let conversation = { ..conversation, stream: None, control: Some(control), }
  assert_true(
    conversation.control_primary_action(@composer.Steer)
    is @composer.Send(available=false),
  )
  assert_true(
    conversation.control_context()
    is [
      @composer.QueuedInputPanel(enabled=false, items=[{ id: "retained", .. }]),
    ],
  )
  let state = state.replace("session", conversation)
  let unchanged = controls_submit(state, @composer.SteerNow)
  assert_true(unchanged == state)
}
