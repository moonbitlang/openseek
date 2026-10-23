///|
fn goal_action(state : State, action : @composer.Action) -> State {
  metadata_update(
    state,
    ControlAction(@interop.Cloud(account="account", session="session"), action),
  )
}

///|
fn goal_identity() -> @composer.Identity {
  {
    owner: @interop.Cloud(account="account", session="session"),
    archive_generation: 0,
  }
}

///|
test "Cloud goals reuse shared input and wait for a saved goal rather than an assistant" {
  let state = controls_fixture()
  let editing = goal_action(
    state,
    @composer.SlashCommand(identity=goal_identity(), command="goal"),
  )
  assert_eq(editing.conversations["session"].controls.input().draft, Some(""))
  let sent = goal_action(
    editing,
    @composer.GoalSubmitted(
      identity=goal_identity(),
      draft="Ship it",
      prompt_present=true,
    ),
  )
  let conversation = sent.conversations["session"]
  assert_true(conversation.generating)
  assert_true(
    conversation.controls.input().pending
    is Some(@composer.GoalSetting("Ship it")),
  )
  assert_true(conversation.controls.input().draft is None)
  let accepted = metadata_update(
    sent,
    CommandFinished(
      1,
      "session",
      conversation.controls.pending.unwrap().id,
      @wire.GoalClear,
      Accepted,
    ),
  )
  assert_true(accepted == sent)
  let saved = accepted.replace(
    "session",
    conversation.command_event(@wire.GoalUpdated(goal=Some("Ship it"))),
  )
  assert_true(saved.conversations["session"].controls.input().pending is None)
  assert_true(
    saved.conversations["session"].controls.goal
    is Some({ text: "Ship it", blocked: None, }),
  )
  assert_true(saved.conversations["session"].generating)
  assert_true(
    metadata_update(
      saved,
      CommandFailed(
        1,
        "session",
        conversation.controls.pending.unwrap().id,
        @wire.GoalClear,
        Unreachable,
      ),
    ) ==
    saved,
  )
  let cleared = goal_action(
    saved,
    @composer.GoalCleared(identity=goal_identity()),
  )
  assert_true(
    cleared.conversations["session"].controls.input().pending
    is Some(@composer.GoalClearing),
  )
  let confirmed = cleared.conversations["session"].command_event(
    @wire.GoalUpdated(goal=None),
  )
  assert_true(
    confirmed.controls.goal is None &&
    confirmed.controls.input().pending is None,
  )
}

///|
test "Cloud goal failures retain recoverable input and fence earlier HTTP callbacks" {
  let identity = goal_identity()
  let editing = goal_action(
    controls_fixture(),
    @composer.GoalEditStarted(identity~),
  )
  let first = goal_action(
    editing,
    @composer.GoalSubmitted(identity~, draft="First", prompt_present=false),
  )
  let first_request = first.conversations["session"].controls.pending.unwrap().id
  let unknown = metadata_update(
    first,
    CommandFailed(1, "session", first_request, @wire.GoalClear, Unreachable),
  )
  assert_true(
    unknown.conversations["session"].controls.input().pending
    is Some(@composer.GoalSetting("First")),
  )
  let reopened = goal_action(unknown, @composer.GoalEditStarted(identity~))
  assert_eq(
    reopened.conversations["session"].controls.input().draft,
    Some("First"),
  )
  let second = goal_action(
    reopened,
    @composer.GoalSubmitted(identity~, draft="Second", prompt_present=false),
  )
  assert_true(
    metadata_update(
      second,
      CommandFailed(1, "session", first_request, @wire.GoalClear, Http(400)),
    ) ==
    second,
  )
  let rejected = metadata_update(
    second,
    CommandFinished(
      1,
      "session",
      second.conversations["session"].controls.pending.unwrap().id,
      @wire.GoalClear,
      Rejected("task_mismatch"),
    ),
  )
  assert_eq(
    rejected.conversations["session"].controls.input().draft,
    Some("Second"),
  )
  assert_true(
    rejected.conversations["session"].controls.input().pending is None,
  )
}

///|
test "Cloud goal editing does not require an observer and cannot create or mutate archived sessions" {
  let identity = goal_identity()
  let state = controls_fixture()
  let offline = state.replace("session", {
    ..state.conversations["session"],
    watch_status: Reconnecting,
  })
  let edited = goal_action(offline, @composer.GoalEditStarted(identity~))
  assert_eq(edited.conversations["session"].controls.input().draft, Some(""))
  let closed = goal_action(edited, @composer.GoalCancelled(identity~))
  assert_true(closed.conversations["session"].controls.input().draft is None)
  let archived = {
    ..state,
    sessions: state.sessions.map(session => { ..session, archived: true, }),
  }
  assert_true(
    goal_action(archived, @composer.GoalEditStarted(identity~)) == archived,
  )
  let empty = { ..State::empty(), user_id: Some("account"), }
  assert_true(
    goal_action(empty, @composer.SlashCommand(identity~, command="goal")) ==
    empty,
  )
}

///|
test "Cloud restores goals from native records without settling against old identical markers" {
  let old = native_document([
    { "kind": "runtime_notice", "payload": { "content": "[goal]\nShip it" } },
  ])
  let base = controls_fixture()
  let state = base.replace("session", {
    ..base.conversations["session"].restore_goal(old),
    document: old,
  })
  let editing = goal_action(
    state,
    @composer.GoalEditStarted(identity=goal_identity()),
  )
  let sent = goal_action(
    editing,
    @composer.GoalSubmitted(
      identity=goal_identity(),
      draft="Ship it",
      prompt_present=false,
    ),
  )
  assert_true(
    sent.conversations["session"].restore_goal(old).controls.input().pending
    is Some(_),
  )
  let recorded = native_document([
    { "kind": "runtime_notice", "payload": { "content": "[goal]\nShip it" } },
    { "kind": "runtime_notice", "payload": { "content": "[goal]\nShip it" } },
  ])
  let settled = sent.conversations["session"].restore_goal(recorded)
  assert_true(settled.controls.input().pending is None)
  assert_true(settled.controls.goal is Some({ text: "Ship it", .. }))
  let cleared = native_document([
    { "kind": "runtime_notice", "payload": { "content": "[goal cleared]" } },
  ])
  assert_true(settled.restore_goal(cleared).controls.goal is None)
}

///|
test "Cloud goal rejection preserves a reopened editor" {
  let identity = goal_identity()
  let editing = goal_action(
    controls_fixture(),
    @composer.GoalEditStarted(identity~),
  )
  let sent = goal_action(
    editing,
    @composer.GoalSubmitted(identity~, draft="First", prompt_present=false),
  )
  let conversation = sent.conversations["session"]
  let reopened = sent.replace("session", {
    ..conversation,
    controls: { ..conversation.controls, edit: Some({ draft: "New edit", }), },
  })
  let rejected = metadata_update(
    reopened,
    CommandFinished(
      1,
      "session",
      conversation.controls.pending.unwrap().id,
      @wire.GoalClear,
      Rejected("task_mismatch"),
    ),
  )
  assert_eq(
    rejected.conversations["session"].controls.input().draft,
    Some("New edit"),
  )
}

///|
test "Cloud missing model credentials reject goal and restore the submitted editor" {
  let editing = goal_action(
    controls_fixture(),
    @composer.GoalEditStarted(identity=goal_identity()),
  )
  let requested = goal_action(
    editing,
    @composer.GoalSubmitted(
      identity=goal_identity(),
      draft="Ship it",
      prompt_present=true,
    ),
  )
  let request = requested.conversations["session"].controls.pending.unwrap().id
  let refused = metadata_update(
    requested,
    CommandFailed(1, "session", request, @wire.GoalClear, ServiceNotConfigured),
  )
  assert_true(refused.conversations["session"].controls.input().pending is None)
  assert_eq(
    refused.conversations["session"].controls.input().draft,
    Some("Ship it"),
  )
  assert_eq(
    refused.conversations["session"].notice,
    Some(Failure::ServiceNotConfigured.label()),
  )
  for failure in ([Unreachable, Http(503), Malformed] : Array[Failure]) {
    let unknown = metadata_update(
      requested,
      CommandFailed(1, "session", request, @wire.GoalClear, failure),
    )
    assert_true(
      unknown.conversations["session"].controls.input().pending
      is Some(@composer.GoalSetting("Ship it")),
    )
  }
}
