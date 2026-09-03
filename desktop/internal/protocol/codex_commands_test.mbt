///|
test "Codex thread start omits absent optional fields" {
  let payload : @protocol.CodexThreadStartPayload = {
    cwd: Some("/work/project"),
    model: None,
    draft_id: Some("desktop-draft-1"),
    permission_mode: AutoReview,
  }
  @debug.assert_eq(payload.to_json(), {
    "cwd": "/work/project",
    "openseekDraftId": "desktop-draft-1",
    "permissionMode": "autoReview",
  })
}

///|
test "Codex permission modes and turn payloads keep Desktop field names" {
  let modes : Array[@protocol.CodexPermissionMode] = [
    RequestApproval,
    AutoReview,
    FullAccess,
  ]
  @debug.assert_eq(modes.map(mode => mode.to_json()), [
    "requestApproval", "autoReview", "fullAccess",
  ])
  let resume_request : @protocol.CodexThreadResumePayload = {
    thread_id: "thread-1",
    permission_mode: RequestApproval,
  }
  @debug.assert_eq(resume_request.to_json(), {
    "threadId": "thread-1",
    "permissionMode": "requestApproval",
  })
  let start : @protocol.CodexTurnStartPayload = {
    thread_id: "thread-1",
    input: [{ "type": "text", "text": "hello" }],
    client_user_message_id: Some("page-1-submission-1"),
    model: Some("gpt-test"),
    effort: Some("high"),
    cwd: None,
    permission_mode: FullAccess,
  }
  @debug.assert_eq(start.to_json(), {
    "threadId": "thread-1",
    "input": [{ "type": "text", "text": "hello" }],
    "clientUserMessageId": "page-1-submission-1",
    "model": "gpt-test",
    "effort": "high",
    "permissionMode": "fullAccess",
  })
  let steer : @protocol.CodexTurnSteerPayload = {
    thread_id: "thread-1",
    input: [{ "type": "text", "text": "more" }],
    client_user_message_id: Some("page-1-submission-2"),
    expected_turn_id: "turn-1",
  }
  @debug.assert_eq(steer.to_json(), {
    "threadId": "thread-1",
    "input": [{ "type": "text", "text": "more" }],
    "clientUserMessageId": "page-1-submission-2",
    "expectedTurnId": "turn-1",
  })
  let legacy_steer : @protocol.CodexTurnSteerPayload = @json.from_json({
    "threadId": "thread-1",
    "input": [{ "type": "text", "text": "legacy" }],
    "expectedTurnId": "turn-1",
  })
  assert_eq(legacy_steer.client_user_message_id, None)
  @debug.assert_eq(legacy_steer.to_json(), {
    "threadId": "thread-1",
    "input": [{ "type": "text", "text": "legacy" }],
    "expectedTurnId": "turn-1",
  })
}

///|
test "Codex list and turn replies keep their typed envelopes" {
  let page : @protocol.CodexDataReply = @json.from_json({
    "data": [{ "id": "thread-1" }],
    "nextCursor": "cursor-2",
  })
  assert_eq(page.next_cursor, Some("cursor-2"))
  @debug.assert_eq(page.to_json(), {
    "data": [{ "id": "thread-1" }],
    "nextCursor": "cursor-2",
  })
  let started : @protocol.CodexTurnReply = @json.from_json({
    "turn": { "id": "turn-1", "status": "inProgress" },
  })
  assert_true(started.turn is Some(_))
  let steered : @protocol.CodexTurnReply = @json.from_json({
    "turnId": "turn-1",
  })
  assert_eq(steered.turn_id, Some("turn-1"))
}

///|
test "Codex commands preserve successes and return original host errors" {
  let success : @protocol.CodexCommandReply[@protocol.CodexThreadReply] = @json.from_json({
      "thread": { "id": "thread-1", "turns": [] },
    },
  )
  assert_true(success is CodexCommandSuccess(_))
  @debug.assert_eq(success.to_json(), {
    "thread": { "id": "thread-1", "turns": [] },
  })
  let failure : @protocol.CodexCommandReply[@protocol.CodexThreadReply] = @json.from_json({
      "error": "Codex app-server request thread/read failed",
    },
  )
  assert_true(
    failure is CodexCommandError("Codex app-server request thread/read failed"),
  )
  @debug.assert_eq(failure.to_json(), {
    "error": "Codex app-server request thread/read failed",
  })
}

///|
test "Codex server-request snapshots preserve actor generation" {
  let requests : @protocol.CodexServerRequestsReply = @json.from_json({
    "data": [
      {
        "request_id": 7,
        "method": "item/tool/requestUserInput",
        "params": { "threadId": "thread-1" },
      },
    ],
    "generation": 12,
  })
  assert_eq(requests.generation, 12)
  @debug.assert_eq(requests.to_json(), {
    "data": [
      {
        "request_id": 7,
        "method": "item/tool/requestUserInput",
        "params": { "threadId": "thread-1" },
      },
    ],
    "generation": 12,
  })
}

///|
test "Codex optional fields accept null and encode absence by omission" {
  let page : @protocol.CodexDataReply = @json.from_json({
    "data": [],
    "nextCursor": null,
    "futureMetadata": { "source": "stateDb" },
  })
  assert_true(page.next_cursor is None)
  @debug.assert_eq(page.to_json(), { "data": [] })
}

///|
test "Codex explicit codecs reject malformed known fields" {
  let decoded : @protocol.CodexDataReply? = Some(
    @json.from_json({ "data": [], "nextCursor": 42 }),
  ) catch {
    _ => None
  }
  assert_true(decoded is None)
}

///|
test "Codex multi-shape replies preserve their app-server object" {
  let archive : @protocol.CodexArchiveReply = @json.from_json({
    "kind": "needs_force",
    "dirty_paths": ["src/main.mbt"],
  })
  @debug.assert_eq(archive.to_json(), {
    "kind": "needs_force",
    "dirty_paths": ["src/main.mbt"],
  })
  let search : @protocol.CodexFileSearchReply = @json.from_json({
    "files": ["src/main.mbt"],
  })
  @debug.assert_eq(search.to_json(), { "files": ["src/main.mbt"] })
}
