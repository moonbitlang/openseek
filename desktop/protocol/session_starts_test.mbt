///|
test "session start suggestions preserve task and explicit startup options" {
  let request : @protocol.SessionStartRequest = @json.from_json({
    "action": "start",
    "request_id": "focus-helper",
    "title": "Extract focus helper",
    "task": "Extract the helper.\nKeep its behavior.",
    "workspace": "/project",
    "model": "deepseek-chat",
    "thinking": "high",
    "max_steps": 20,
    "workspace_mode": "worktree",
  })
  assert_eq(request.workspace_mode, "worktree")
  assert_eq(request.task, "Extract the helper.\nKeep its behavior.")
  let pending = request.proposal("proposal-id")
  let snapshot : @protocol.SessionStartsSnapshot = {
    session: "source",
    workspace: Some("/source-project"),
    archived: Some(false),
    generation: 2,
    proposals: [
      { ..pending, status: "started", target_session: Some("target"), },
    ],
  }
  let roundtrip : @protocol.SessionStartsSnapshot = @json.from_json(
    snapshot.to_json(),
  )
  assert_true(roundtrip == snapshot)
  let event = @protocol.Notification::SessionStartsChanged(snapshot)
  assert_eq(event.wire_name(), "session.starts_changed")
  assert_true(
    @protocol.Notification::from_wire(event.wire_name(), event.params()) ==
    Some(event),
  )
  let default_request : @protocol.SessionStartRequest = @json.from_json({
    "request_id": "r",
    "title": "Title",
    "task": "Task",
    "workspace": "/project",
    "model": null,
    "thinking": null,
    "max_steps": null,
    "workspace_mode": null,
  })
  assert_eq(default_request.workspace_mode, "local")
  assert_true(default_request.model is None)
  assert_true(default_request.thinking is None)
  json_inspect(default_request.to_json(), content={
    "request_id": "r",
    "title": "Title",
    "task": "Task",
    "workspace": "/project",
    "workspace_mode": "local",
  })
}

///|
test "session suggestion snapshots carry source identity and decode legacy sidecars" {
  let legacy : @protocol.SessionStartsSnapshot = @json.from_json({
    "session": "source",
    "generation": 2,
    "proposals": [],
  })
  assert_true(legacy.workspace is None)
  assert_true(legacy.archived is None)
  json_inspect(legacy.to_json(), content={
    "session": "source",
    "generation": 2,
    "proposals": [],
  })
  let absent : @protocol.SessionStartsSnapshot = @json.from_json({
    "session": "source",
    "workspace": null,
    "archived": null,
    "generation": 2,
    "proposals": [],
  })
  assert_eq(absent, legacy)
  let archived : @protocol.SessionStartsSnapshot = {
    ..legacy,
    workspace: Some("/source-project"),
    archived: Some(true),
  }
  assert_eq(
    (@json.from_json(archived.to_json()) : @protocol.SessionStartsSnapshot),
    archived,
  )
  let event = @protocol.Notification::SessionStartsChanged(archived)
  assert_eq(
    @protocol.Notification::from_wire(event.wire_name(), event.params()),
    Some(event),
  )
  let selector : @protocol.SessionStartsListPayload = @json.from_json({
    "session": "source",
    "workspace": "/source-project",
    "archived": true,
  })
  assert_eq(selector.workspace, Some("/source-project"))
  assert_eq(selector.archived, Some(true))
  assert_eq(
    (@json.from_json(selector.to_json()) : @protocol.SessionStartsListPayload),
    selector,
  )
  let decision : @protocol.SessionStartDecision = @json.from_json({
    "session": "source",
    "workspace": "/source-project",
    "request_id": "r",
    "action": "start",
    "workspace_mode": "worktree",
    "model": "target-model",
  })
  assert_eq(decision.workspace, Some("/source-project"))
  assert_eq(decision.model, Some(Some("target-model")))
  assert_eq(
    (@json.from_json(decision.to_json()) : @protocol.SessionStartDecision),
    decision,
  )
  let malformed : Array[Json] = [
    {
      "session": "source",
      "workspace": false,
      "generation": 2,
      "proposals": [],
    },
    { "session": "source", "workspace": " ", "generation": 2, "proposals": [] },
    {
      "session": "source",
      "archived": "true",
      "generation": 2,
      "proposals": [],
    },
  ]
  for invalid in malformed {
    let parsed : @protocol.SessionStartsSnapshot? = Some(
      @json.from_json(invalid),
    ) catch {
      _ => None
    }
    assert_true(parsed is None)
  }
  let invalid_workspaces : Array[Json] = ["", " ", false]
  for workspace in invalid_workspaces {
    let selector : @protocol.SessionStartsListPayload? = Some(
      @json.from_json({ "session": "source", "workspace": workspace }),
    ) catch {
      _ => None
    }
    let decision : @protocol.SessionStartDecision? = Some(
      @json.from_json({
        "session": "source",
        "workspace": workspace,
        "request_id": "r",
        "action": "start",
      }),
    ) catch {
      _ => None
    }
    assert_true(selector is None)
    assert_true(decision is None)
  }
}

///|
test "session start codecs reject ambiguous or malformed actions and outcomes" {
  for
    invalid in [
      null,
      {},
      {
        "request_id": "r",
        "title": " ",
        "task": "Task",
        "workspace": "/project",
      },
      {
        "request_id": "r",
        "title": "Title",
        "task": "",
        "workspace": "/project",
      },
      {
        "request_id": "r",
        "title": "Title",
        "task": "Task",
        "workspace": "/project",
        "workspace_mode": "unknown",
      },
      {
        "request_id": "r",
        "title": "Title",
        "task": "Task",
        "workspace": "/project",
        "max_steps": 0,
      },
      {
        "request_id": "r",
        "title": "Title",
        "task": "Task",
        "workspace": "/project",
        "thinking": "low",
      },
      {
        "request_id": "r",
        "title": "Title",
        "task": "Task",
        "workspace": "/project",
        "model": " ",
      },
    ] {
    let parsed : @protocol.SessionStartRequest? = Some(@json.from_json(invalid)) catch {
      _ => None
    }
    assert_true(parsed is None)
  }
  let request : @protocol.SessionStartRequest = @json.from_json({
    "request_id": "r",
    "title": "Title",
    "task": "Task",
    "workspace": "/project",
  })
  let pending = request.proposal("id")
  for
    invalid in [
      { ..pending, status: "started", },
      { ..pending, status: "starting", },
      { ..pending, status: "here", },
      { ..pending, status: "failed", },
      { ..pending, status: "accepted", },
      { ..pending, target_session: Some("target"), },
      { ..pending, error: Some("unexpected"), },
    ] {
    let parsed : @protocol.SessionStartProposal? = Some(
      @json.from_json(invalid.to_json()),
    ) catch {
      _ => None
    }
    assert_true(parsed is None)
  }
  for
    invalid in [
      null,
      {},
      { "session": "s", "request_id": "r", "action": "approve" },
      { "session": "s", "request_id": "r", "action": "start", "model": " " },
      {
        "session": "s",
        "request_id": "r",
        "action": "start",
        "workspace_mode": false,
      },
    ] {
    let parsed : @protocol.SessionStartDecision? = Some(
      @json.from_json(invalid),
    ) catch {
      _ => None
    }
    assert_true(parsed is None)
  }
  let decision : @protocol.SessionStartDecision = @json.from_json({
    "session": "s",
    "request_id": "r",
    "action": "here",
  })
  assert_true(
    (@json.from_json(decision.to_json()) : @protocol.SessionStartDecision) ==
    decision,
  )
}

///|
test "session start model decisions distinguish keep clear and explicit choice" {
  let keep : @protocol.SessionStartDecision = @json.from_json({
    "session": "s",
    "request_id": "r",
    "action": "start",
  })
  let clear : @protocol.SessionStartDecision = @json.from_json({
    "session": "s",
    "request_id": "r",
    "action": "start",
    "model": null,
  })
  let explicit : @protocol.SessionStartDecision = @json.from_json({
    "session": "s",
    "request_id": "r",
    "action": "start",
    "model": "deepseek-chat",
  })
  assert_true(keep.model is None)
  assert_true(clear.model is Some(None))
  assert_eq(explicit.model, Some(Some("deepseek-chat")))
  for decision in [keep, clear, explicit] {
    let roundtrip : @protocol.SessionStartDecision = @json.from_json(
      decision.to_json(),
    )
    assert_true(roundtrip == decision)
  }
  json_inspect(clear.to_json(), content={
    "session": "s",
    "request_id": "r",
    "action": "start",
    "model": null,
  })
}

///|
test "Work here carries source settings separately from new-session options" {
  let decision : @protocol.SessionStartDecision = @json.from_json({
    "session": "source",
    "request_id": "r",
    "action": "here",
    "here": {
      "model": "source-model",
      "thinking": "no",
      "approval": "review",
      "max_steps": 8,
      "followup_behavior": "queue",
    },
  })
  assert_true(decision.model is None)
  assert_true(decision.workspace_mode is None)
  guard decision.here is Some(options) else {
    fail("missing source input options")
  }
  assert_eq(options.model, Some("source-model"))
  assert_eq(options.thinking, Some(ThinkingOff))
  assert_eq(options.approval, Some(ApprovalReview))
  assert_eq(options.followup_behavior, "queue")
  let decoded : @protocol.SessionStartDecision = @json.from_json(
    decision.to_json(),
  )
  assert_true(decoded == decision)
  for
    invalid in [
      Json::empty_object(),
      { "followup_behavior": "unknown" },
      { "followup_behavior": "queue", "max_steps": 0 },
      { "followup_behavior": "steer", "model": " " },
      { "followup_behavior": "steer", "approval": "never" },
      { "followup_behavior": "steer", "approval": false },
    ] {
    let parsed : @protocol.SessionStartHereOptions? = Some(
      @json.from_json(invalid),
    ) catch {
      _ => None
    }
    assert_true(parsed is None)
  }
}

///|
test "Work here absent or null approval retains the ordinary ask default" {
  let inputs : Array[Json] = [
    { "followup_behavior": "steer" },
    { "followup_behavior": "queue", "approval": null },
  ]
  for input in inputs {
    let options : @protocol.SessionStartHereOptions = @json.from_json(input)
    assert_true(options.approval is None)
    let roundtrip : @protocol.SessionStartHereOptions = @json.from_json(
      options.to_json(),
    )
    assert_true(roundtrip == options)
  }
}
