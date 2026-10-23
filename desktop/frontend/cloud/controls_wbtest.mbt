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
          compact_queued: false,
          compacting: false,
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
    conversation.steer_receipt("old", Some("s"), false) == conversation,
  )
  let received = conversation.steer_receipt(event.task_id, Some(id), false)
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
  let dropped = conversation.steer_receipt("task", Some("queued"), true)
  assert_eq(dropped.initial_submission, Some(draft))
  assert_eq(dropped.control_inputs.length(), 0)
}

///|
test "Cloud paused queue permits edit and withdrawal but not addition or steering" {
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
      compact_queued: false,
      compacting: false,
    }),
  }
  let state = state.replace("session", conversation)
  assert_true(
    conversation.control_context()
    is [
      @composer.QueuedInputPanel(
        enabled=true,
        items=[
          {
            state: @composer.Queued(interactive=true, steer_available=false, ..),
            ..
          },
        ]
      ),
    ],
  )
  for choice in [@composer.QueueNext, @composer.SteerNow] {
    assert_true(controls_submit(state, choice) == state)
  }
  let owner : @interop.ConversationIdentity = Cloud(
    account="account",
    session="session",
  )
  let identity : @composer.Identity = { owner, archive_generation: 0, }
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  let advance = (state : State, action : @composer.Action) => {
    state
    .update_control(ControlAction(owner, action), emit, Some("token"))
    .unwrap().0
  }
  assert_true(
    advance(state, @composer.QueuedInputSteerRequested(identity~, id="queue")) ==
    state,
  )
  let editing = advance(
    state,
    @composer.QueuedInputEditRequested(identity~, id="queue"),
  )
  assert_eq(editing.conversations["session"].queue_edit, Some("queue"))
  assert_true(
    editing.conversations["session"].control_primary_action(@composer.Steer)
    is @composer.SaveQueuedInput(available=true),
  )
  let draft : @composer.Draft = {
    task: "Edited while paused",
    images: [],
    mentions: [],
  }
  let saving = editing
    .update_control(Submit(owner, draft), emit, Some("token"))
    .unwrap().0
  let input = saving.conversations["session"].control_inputs[0]
  assert_eq(input.task_id, "task")
  assert_true(
    input.operation is QueueEdit(id="queue", content~) &&
    content.text() == draft.task,
  )
  assert_true(
    saving.conversations["session"].control_primary_action(@composer.Steer)
    is @composer.SaveQueuedInput(available=false),
  )
  let accepted = saving
    .update_control(
      ControlFinished(1, "session", "task", input.key, Accepted),
      emit,
      Some("token"),
    )
    .unwrap().0
  assert_eq(accepted.conversations["session"].queue_edit, None)
  assert_eq(accepted.conversations["session"].submission_sequence, 1)
  assert_false(accepted.conversations["session"].generating)
  let withdrawing = advance(
    state,
    @composer.QueuedInputDeleteRequested(identity~, id="queue"),
  )
  let withdrawal = withdrawing.conversations["session"].control_inputs[0]
  assert_eq(withdrawal.task_id, "task")
  assert_true(withdrawal.operation is QueueWithdraw(id="queue"))
  let removed = withdrawing.conversations["session"].control_snapshot(
    Some("task"),
    { ..conversation.control.unwrap(), queue: [], },
  )
  assert_true(removed.control_inputs.is_empty())
  assert_true(removed.control.unwrap().paused)
  let sending = metadata_update(
    state,
    Submit(owner, { task: "Explicit next prompt", images: [], mentions: [], }),
  )
  assert_true(sending.conversations["session"].sending)
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
      compact_queued: false,
      compacting: false,
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
  let received = conversation.steer_receipt("task", Some(input.key), false)
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
