///|
test "unknown session items preserve their complete wire object" {
  let raw : Json = {
    "kind": "future_item",
    "payload": { "value": 42 },
    "future_field": true,
  }
  let item : @protocol.SessionItem = @json.from_json(raw)
  guard item is Unknown(preserved) else {
    fail("expected an unknown session item")
  }
  assert_false(item.is_terminal())
  @debug.assert_eq(preserved, raw)
  @debug.assert_eq(item.to_json(), raw)
}

///|
test "agent connected requires a concrete scratch root" {
  assert_true(
    @protocol.Notification::from_wire("agent.connected", { "ready": true })
    is None,
  )
  guard @protocol.Notification::from_wire("agent.connected", {
      "ready": true,
      "scratch_root": "/scratch",
    })
    is Some(AgentConnected(payload)) else {
    fail("connected notification with a scratch root did not decode")
  }
  assert_eq(payload.scratch_root, "/scratch")
}

///|
test "new payload shapes fall back to a raw session item" {
  let raw : Json = {
    "kind": "terminal",
    "payload": { "kind": "future_terminal", "message": "later" },
  }
  let item : @protocol.SessionItem = @json.from_json(raw)
  guard item is UnknownTerminal(preserved) else {
    fail("expected a future terminal boundary to remain raw")
  }
  assert_true(item.is_terminal())
  @debug.assert_eq(preserved, raw)
  @debug.assert_eq(item.to_json(), raw)
  let missing_payload : Json = { "kind": "terminal", "future_field": true }
  let missing_item : @protocol.SessionItem = @json.from_json(missing_payload)
  guard missing_item is UnknownTerminal(preserved) else {
    fail("expected a malformed terminal boundary to remain raw")
  }
  assert_true(missing_item.is_terminal())
  @debug.assert_eq(preserved, missing_payload)
}

///|
test "Git original-file replies round-trip through their manual codec" {
  let replies : Array[@protocol.GitOriginalFileReply] = [
    Missing,
    BinaryOriginal,
    OversizedOriginal,
    OriginalContent("fn main { println(\"hi\") }"),
  ]
  for reply in replies {
    let decoded : @protocol.GitOriginalFileReply = @json.from_json(
      reply.to_json(),
    )
    @debug.assert_eq(decoded, reply)
  }
}

///|
test "archive replies keep success compatible and encode dirty confirmation" {
  let sessions : @protocol.SessionsReply = { groups: [] }
  let success = @protocol.ArchiveReply::Archived(sessions)
  @debug.assert_eq(success.to_json(), sessions.to_json())
  let decoded_success : @protocol.ArchiveReply = @json.from_json(
    sessions.to_json(),
  )
  @debug.assert_eq(decoded_success, success)
  let refusal : @protocol.ArchiveReply = NeedsForce({
    worktree: "wt-1",
    dirty_paths: ["desktop/lepus", "editor/tokenizer.mbt"],
    dirty_path_count: 5,
  })
  let decoded_refusal : @protocol.ArchiveReply = @json.from_json(
    refusal.to_json(),
  )
  @debug.assert_eq(decoded_refusal, refusal)
}

///|
test "Git changes replies preserve review identities and accept legacy omission" {
  let reply : @protocol.GitChangesReply = {
    repository: true,
    head: Some("0123456789abcdef"),
    baseline: Some("fedcba9876543210"),
    changes: [],
  }
  let decoded : @protocol.GitChangesReply = @json.from_json(reply.to_json())
  @debug.assert_eq(decoded, reply)
  let legacy : @protocol.GitChangesReply = @json.from_json({
    "repository": true,
    "changes": [],
  })
  @debug.assert_eq(legacy.head, None)
  @debug.assert_eq(legacy.baseline, None)
}

///|
test "Git original-file payloads pin a revision and accept legacy omission" {
  let payload : @protocol.GitOriginalFilePayload = {
    session: "session",
    workspace: Some("/worktree"),
    path: "src/main.mbt",
    revision: Some("0123456789abcdef"),
  }
  let decoded : @protocol.GitOriginalFilePayload = @json.from_json(
    payload.to_json(),
  )
  @debug.assert_eq(decoded, payload)
  let legacy : @protocol.GitOriginalFilePayload = @json.from_json({
    "session": "session",
    "workspace": "/worktree",
    "path": "src/main.mbt",
  })
  @debug.assert_eq(legacy.revision, None)
}

///|
test "file search payload and reply round-trip at the JSON boundary" {
  let raw_payload : Json = {
    "path": "/work/project",
    "cache_key": "quick-open:session-1:7",
    "query": "src main",
    "max_results": 512,
    "generation": 7,
  }
  let payload : @protocol.SearchFilesPayload = @json.from_json(raw_payload)
  assert_eq(payload.path, "/work/project")
  assert_eq(payload.cache_key, "quick-open:session-1:7")
  assert_eq(payload.query, "src main")
  assert_eq(payload.max_results, 512)
  assert_eq(payload.generation, 7)
  @debug.assert_eq(payload.to_json(), raw_payload)
  let raw_reply : Json = {
    "files": ["src/main.mbt", "src/main_test.mbt"],
    "from_cache": true,
    "limit_hit": false,
    "cancelled": false,
  }
  let reply : @protocol.SearchFilesReply = @json.from_json(raw_reply)
  assert_eq(reply.files, ["src/main.mbt", "src/main_test.mbt"])
  assert_true(reply.from_cache)
  assert_false(reply.limit_hit)
  assert_false(reply.cancelled)
  @debug.assert_eq(reply.to_json(), raw_reply)
  let raw_cancel : Json = {
    "cache_key": "quick-open:session-1:7",
    "generation": 7,
  }
  let cancel : @protocol.CancelSearchFilesPayload = @json.from_json(raw_cancel)
  assert_eq(cancel.cache_key, "quick-open:session-1:7")
  assert_eq(cancel.generation, 7)
  @debug.assert_eq(cancel.to_json(), raw_cancel)
  let raw_clear : Json = { "cache_key": "quick-open:session-1:7" }
  let clear : @protocol.ClearFileSearchCachePayload = @json.from_json(raw_clear)
  assert_eq(clear.cache_key, "quick-open:session-1:7")
  @debug.assert_eq(clear.to_json(), raw_clear)
}
