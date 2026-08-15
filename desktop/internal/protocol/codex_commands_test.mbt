///|
test "Codex thread start omits absent optional fields" {
  let payload : @protocol.CodexThreadStartPayload = {
    cwd: Some("/work/project"),
    model: None,
    draft_id: Some("desktop-draft-1"),
  }
  @debug.assert_eq(payload.to_json(), {
    "cwd": "/work/project",
    "openseekDraftId": "desktop-draft-1",
  })
}

///|
test "Codex turn payloads keep app-server field names" {
  let start : @protocol.CodexTurnStartPayload = {
    thread_id: "thread-1",
    input: [{ "type": "text", "text": "hello" }],
    model: Some("gpt-test"),
    cwd: None,
  }
  @debug.assert_eq(start.to_json(), {
    "threadId": "thread-1",
    "input": [{ "type": "text", "text": "hello" }],
    "model": "gpt-test",
  })
  let steer : @protocol.CodexTurnSteerPayload = {
    thread_id: "thread-1",
    input: [{ "type": "text", "text": "more" }],
    expected_turn_id: "turn-1",
  }
  @debug.assert_eq(steer.to_json(), {
    "threadId": "thread-1",
    "input": [{ "type": "text", "text": "more" }],
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
test "Codex optional fields accept null and encode absence by omission" {
  let page : @protocol.CodexDataReply = @json.from_json({
    "data": [],
    "nextCursor": null,
    "futureMetadata": { "source": "stateDb" },
  })
  assert_true(page.next_cursor is None)
  @debug.assert_eq(page.to_json(), { "data": [] })
  let resumed : @protocol.CodexThreadResumeReply = @json.from_json({
    "thread": null,
    "status": "activeWriter",
    "futureMetadata": true,
  })
  assert_true(resumed.thread is None)
  assert_eq(resumed.status, Some("activeWriter"))
  @debug.assert_eq(resumed.to_json(), { "status": "activeWriter" })
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
