///|
fn command_draft() -> State {
  metadata_update(
    { ..State::empty(), user_id: Some("account"), epoch: 1, },
    Create,
  )
}

///|
fn draft_action(state : State, action : @composer.Action) -> State {
  metadata_update(state, ControlAction(state.draft_identity().unwrap(), action))
}

///|
test "all native commands share deferred session creation and observation readiness" {
  for
    command in [
      @wire.Compact,
      @wire.GoalSet(text="Ship", auto=false),
      @wire.JobsSnapshot(request_id="jobs"),
    ] {
    let blank = command_draft()
    let owner = blank.draft_identity().unwrap()
    let submission : PendingCommand = {
      request: blank.sequence + 1,
      input: Native(command),
    }
    let (pending, _) = blank.submit_command(
      owner.session(),
      submission,
      _ => @cmd.none,
      "fixture",
      0,
    )
    let (duplicate, _) = pending.submit_command(
      owner.session(),
      submission,
      _ => @cmd.none,
      "fixture",
      0,
    )
    assert_true(duplicate == pending)
    let created = metadata_update(
      pending,
      Created(1, submission.request, "session"),
    )
    assert_true(
      created.conversations["session"].outgoing.unwrap().input ==
      Native(command),
    )
    assert_false(created.conversations.contains(owner.session()))
    assert_true(
      created.conversations["session"] == pending.conversations[owner.session()],
    )
    assert_false(created.conversations["session"].generating)
    assert_false(created.can_send("session"))
    assert_true(created.conversations["session"].needs_observation())
    assert_true(
      metadata_update(created, Open("session")).conversations["session"].outgoing
      is Some(_),
    )
    let (observing, stream) = watch_fixture(created)
    let control : ControlState = {
      active_task_id: None,
      status: Idle,
      paused: false,
      queue: [],
      steers: [],
      compacting: false,
      compact_queued: false,
    }
    let ready = watch_snapshot(observing, stream, None, 0, control)
    assert_true(ready.conversations["session"].outgoing is None)
    assert_true(watch_snapshot(ready, stream, None, 0, control) == ready)
    let disconnected = metadata_update(
      ready,
      WatchEnded(1, "session", stream, None),
    )
    assert_true(disconnected.conversations["session"].outgoing is None)
    let changed = metadata_update(pending, AccountChanged(Some("other")))
    assert_true(
      metadata_update(changed, Created(1, submission.request, "late")) ==
      changed,
    )
  }
}

///|
test "first goal creation failures restore the shared editor and retry only on explicit submission" {
  let blank = command_draft()
  let identity : @composer.Identity = {
    owner: blank.draft_identity().unwrap(),
    archive_generation: 0,
  }
  let editing = draft_action(blank, @composer.GoalEditStarted(identity~))
  assert_false(editing.creating_session())
  assert_eq(
    editing.conversations[identity.owner.session()].controls.input().draft,
    Some(""),
  )
  let action = @composer.GoalSubmitted(
    identity~,
    draft="Keep this goal",
    prompt_present=true,
  )
  let pending = draft_action(editing, action)
  let request = pending.creation.unwrap().request
  assert_true(draft_action(pending, action) == pending)
  let failed = metadata_update(pending, CreateFailed(1, request, Http(503)))
  assert_false(failed.creating_session())
  assert_eq(
    failed.conversations[identity.owner.session()].controls.input().draft,
    Some("Keep this goal"),
  )
  let retried = draft_action(failed, action)
  assert_true(retried.creation.unwrap().request > request)
  assert_true(metadata_update(retried, Created(1, request, "late")) == retried)
  let created = metadata_update(
    retried,
    Created(1, retried.creation.unwrap().request, "session"),
  )
  let (observing, stream) = watch_fixture(created)
  let ready = watch_snapshot(observing, stream, None, 0, {
    active_task_id: None,
    status: Idle,
    paused: false,
    queue: [],
    steers: [],
    compacting: false,
    compact_queued: false,
  })
  assert_true(ready.conversations["session"].controls.pending is Some(_))
  let applied = native_event(
    ready,
    stream,
    None,
    1,
    @wire.GoalUpdated(goal=Some("Keep this goal")),
  )
  assert_true(applied.conversations["session"].controls.pending is None)
  assert_false(applied.conversations["session"].generating)
}

///|
test "first compact remains pending through its pre-command snapshot and definite refusal" {
  let blank = command_draft()
  let identity : @composer.Identity = {
    owner: blank.draft_identity().unwrap(),
    archive_generation: 0,
  }
  let pending = draft_action(
    blank,
    @composer.SlashCommand(identity~, command="compact"),
  )
  let creation = pending.creation.unwrap()
  let failed = metadata_update(
    pending,
    CreateFailed(1, creation.request, Http(503)),
  )
  assert_true(
    failed.conversations[identity.owner.session()].controls.compact_request
    is None,
  )
  assert_false(failed.creating_session())
  let created = metadata_update(
    pending,
    Created(1, creation.request, "session"),
  )
  let (observing, stream) = watch_fixture(created)
  let ready = watch_snapshot(observing, stream, None, 0, {
    active_task_id: None,
    status: Idle,
    paused: false,
    queue: [],
    steers: [],
    compacting: false,
    compact_queued: false,
  })
  assert_eq(
    ready.conversations["session"].controls.compact_request,
    Some(creation.request.to_string()),
  )
  let refused = metadata_update(
    ready,
    CommandFinished(
      1,
      "session",
      creation.request.to_string(),
      @wire.Compact,
      Rejected("Nothing to compact"),
    ),
  )
  assert_false(refused.conversations["session"].controls.is_compacting())
  assert_true(refused.can_send("session"))
  assert_true(refused.creation is None)
}

///|
test "a first command waits for a new observer after a definitive observation failure" {
  let blank = command_draft()
  let owner = blank.draft_identity().unwrap()
  let request = blank.sequence + 1
  let (pending, _) = blank.submit_command(
    owner.session(),
    { request, input: Native(@wire.Compact), },
    _ => @cmd.none,
    "fixture",
    0,
  )
  let created = metadata_update(pending, Created(1, request, "session"))
  let (observing, stream) = watch_fixture(created)
  let failed = metadata_update(
    observing,
    WatchEnded(1, "session", stream, Some(Http(403))),
  )
  assert_true(failed.conversations["session"].watch_status is Disconnected)
  assert_true(failed.conversations["session"].outgoing is Some(_))
  let reopened = metadata_update(failed, Open("session"))
  assert_true(reopened.conversations["session"].watch_status is Watching)
  let loaded = metadata_update(
    reopened,
    Loaded(1, "session", reopened.conversations["session"].request, {
      prediction: None,
      session: native_document([]),
      messages: [],
      generating: false,
    }),
  )
  let (observing, stream) = watch_fixture(loaded)
  let ready = watch_snapshot(observing, stream, None, 0, {
    active_task_id: None,
    status: Idle,
    paused: false,
    queue: [],
    steers: [],
    compacting: false,
    compact_queued: false,
  })
  assert_true(ready.conversations["session"].outgoing is None)
  assert_true(ready.conversations["session"].watch_status is Watching)
}
