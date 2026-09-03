///|
test "session list rows decode activity stamps and tolerate the engine's null" {
  let rows = @protocol.SessionListEntry::array_from_wire([
    { "id": "desktop-a", "title": "stamped", "updated_at_ms": 1500.0 },
    { "id": "desktop-b", "title": "husk", "updated_at_ms": null },
    { "id": "desktop-c", "title": "old engine without the field" },
  ])
  assert_eq(rows.length(), 3)
  assert_eq(rows[0].updated_at_ms, Some(1500.0))
  assert_eq(rows[1].updated_at_ms, None)
  assert_eq(rows[2].updated_at_ms, None)
}

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
test "a durable prompt keeps its text whatever the submission tag looks like" {
  // Untagged encodes exactly as every record written before the field
  // existed: the key is absent, not null.
  let untagged : @protocol.SessionUserMessage = {
    content: "hello",
    submission_id: None,
  }
  @debug.assert_eq(untagged.to_json(), { "content": "hello" })
  let tagged : @protocol.SessionUserMessage = {
    content: "hello",
    submission_id: Some("sub-1"),
  }
  @debug.assert_eq(tagged.to_json(), {
    "content": "hello",
    "submission_id": "sub-1",
  })

  // The tag is a correlation hint. Every way of not having one decodes to the
  // same untagged prompt, and the text survives all of them — a refusal here
  // would reach `SessionItem` as `Unknown` and drop the prompt off screen.
  for
    absent in (
      [
        { "content": "hello" },
        { "content": "hello", "submission_id": Json::null() },
        { "content": "hello", "submission_id": 7 },
        { "content": "hello", "annotated_by_a_newer_store": true },
      ] : Array[Json]) {
    let decoded : @protocol.SessionUserMessage = @json.from_json(absent)
    assert_eq(decoded.content, "hello")
    assert_eq(decoded.submission_id, None)
  }
  let carried : @protocol.SessionUserMessage = @json.from_json({
    "content": "hello",
    "submission_id": "sub-1",
  })
  assert_eq(carried.submission_id, Some("sub-1"))

  // The message itself is required, and refusing is what makes the enclosing
  // item keep the raw line instead of inventing an empty prompt.
  let contentless : Json = {
    "kind": "user",
    "payload": { "submission_id": "s" },
  }
  let item : @protocol.SessionItem = @json.from_json(contentless)
  assert_true(item is Unknown(_))
}

///|
test "durable assistant replay provenance has an explicit codec" {
  let plain : @protocol.SessionAssistantMessage = {
    content: "answer",
    tool_calls: None,
    reasoning_content: None,
    is_replay: None,
  }
  @debug.assert_eq(plain.to_json(), { "content": "answer" })
  let replay : @protocol.SessionAssistantMessage = {
    content: "answer",
    tool_calls: Some([]),
    reasoning_content: Some("thought"),
    is_replay: Some(true),
  }
  @debug.assert_eq(replay.to_json(), {
    "content": "answer",
    "tool_calls": [],
    "reasoning_content": "thought",
    "is_replay": true,
  })
  let decoded : @protocol.SessionAssistantMessage = @json.from_json(
    replay.to_json(),
  )
  assert_eq(decoded, replay)

  // Optional annotations cannot hide otherwise readable prose.
  let tolerant : @protocol.SessionAssistantMessage = @json.from_json({
    "content": "answer",
    "reasoning_content": 7,
    "is_replay": "yes",
    "newer_annotation": true,
  })
  assert_eq(tolerant.reasoning_content, None)
  assert_eq(tolerant.is_replay, None)

  // Content and a present tool-call list are functional data. Invalid values
  // make the enclosing item preserve the complete raw event as Unknown.
  for
    payload in (
      [
        { "tool_calls": [] },
        { "content": null, "tool_calls": [] },
        { "content": "answer", "tool_calls": "lost" },
      ] : Array[Json]) {
    let item : @protocol.SessionItem = @json.from_json({
      "kind": "assistant",
      "payload": payload,
    })
    assert_true(item is Unknown(_))
  }
}

///|
test "durable tool results explicitly encode their optional brief" {
  let plain : @protocol.SessionToolResult = {
    tool_call_id: "call-1",
    tool_name: "read",
    content: "contents",
    is_error: false,
    brief: None,
  }
  @debug.assert_eq(plain.to_json(), {
    "tool_call_id": "call-1",
    "tool_name": "read",
    "content": "contents",
    "is_error": false,
  })
  let annotated : @protocol.SessionToolResult = {
    ..plain,
    brief: Some("read moon.mod"),
  }
  @debug.assert_eq(annotated.to_json(), {
    "tool_call_id": "call-1",
    "tool_name": "read",
    "content": "contents",
    "is_error": false,
    "brief": "read moon.mod",
  })
}

///|
test "durable tool result brief cannot hide a valid result" {
  for
    payload in (
      [
        {
          "tool_call_id": "call-1",
          "tool_name": "read",
          "content": "contents",
          "is_error": false,
        },
        {
          "tool_call_id": "call-1",
          "tool_name": "read",
          "content": "contents",
          "is_error": false,
          "brief": null,
        },
        {
          "tool_call_id": "call-1",
          "tool_name": "read",
          "content": "contents",
          "is_error": false,
          "brief": 7,
        },
        {
          "tool_call_id": "call-1",
          "tool_name": "read",
          "content": "contents",
          "is_error": false,
          "future_annotation": true,
        },
      ] : Array[Json]) {
    let decoded : @protocol.SessionToolResult = @json.from_json(payload)
    assert_eq(decoded.brief, None)
  }
  let annotated : @protocol.SessionToolResult = @json.from_json({
    "tool_call_id": "call-1",
    "tool_name": "read",
    "content": "contents",
    "is_error": false,
    "brief": "read moon.mod",
  })
  assert_eq(annotated.brief, Some("read moon.mod"))

  // Every core field is required and typed; `SessionItem` preserves any
  // invalid record verbatim instead of inventing a partial tool result.
  for
    payload in (
      [
        { "tool_name": "read", "content": "contents", "is_error": false },
        {
          "tool_call_id": null,
          "tool_name": "read",
          "content": "contents",
          "is_error": false,
        },
        {
          "tool_call_id": "call-1",
          "tool_name": 7,
          "content": "contents",
          "is_error": false,
        },
        {
          "tool_call_id": "call-1",
          "tool_name": "read",
          "content": false,
          "is_error": false,
        },
        {
          "tool_call_id": "call-1",
          "tool_name": "read",
          "content": "contents",
          "is_error": "no",
        },
      ] : Array[Json]) {
    let item : @protocol.SessionItem = @json.from_json({
      "kind": "tool_result",
      "payload": payload,
    })
    assert_true(item is Unknown(_))
  }
}

///|
test "agent connected names how much of the host is up" {
  guard @protocol.Notification::from_wire("agent.connected", {
      "stage": "serving",
    })
    is Some(AgentConnected(serving)) else {
    fail("serving connect did not decode")
  }
  assert_eq(serving.stage, Serving)
  guard @protocol.Notification::from_wire("agent.connected", {
      "stage": "accepted",
    })
    is Some(AgentConnected(accepted)) else {
    fail("accepted connect did not decode")
  }
  assert_eq(accepted.stage, Accepted)
  // A field this build does not know is not a reason to drop a connect.
  guard @protocol.Notification::from_wire("agent.connected", {
      "stage": "serving",
      "roots": ["/work"],
    })
    is Some(AgentConnected(extra)) else {
    fail("an unknown field dropped the connect")
  }
  assert_eq(extra.stage, Serving)
  // The stage is the payload: a host that names none says nothing this
  // client can act on, so the notification is refused rather than guessed at.
  assert_true(
    @protocol.Notification::from_wire("agent.connected", { "ready": true })
    is None,
  )
  // Neither does a stage that is not a string, is null, or spells a stage
  // this build cannot reason about. Reading an unknown one as `accepted`
  // would be a guess about whether a run can start.
  assert_true(
    @protocol.Notification::from_wire("agent.connected", { "stage": 1 }) is None,
  )
  assert_true(
    @protocol.Notification::from_wire("agent.connected", { "stage": null })
    is None,
  )
  assert_true(
    @protocol.Notification::from_wire("agent.connected", { "stage": "draining" })
    is None,
  )
  @debug.assert_eq(
    ({ stage: Serving, windows: false, } : @protocol.ConnectedPayload).to_json(),
    { "stage": "serving" },
  )
  @debug.assert_eq(
    ({ stage: Accepted, windows: false, } : @protocol.ConnectedPayload).to_json(),
    { "stage": "accepted" },
  )
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
test "file reads use one absolute path and may return image bytes" {
  let request : @protocol.ReadFilePayload = @json.from_json({
    "path": "/work/readme.md",
  })
  assert_eq(request.path, "/work/readme.md")
  assert_eq(request.root, None)
  @debug.assert_eq(request.to_json(), { "path": "/work/readme.md" })
  let relative : @protocol.ReadFilePayload = {
    path: "../image.png",
    root: Some("/work/project"),
  }
  @debug.assert_eq(relative.to_json(), {
    "path": "../image.png",
    "root": "/work/project",
  })
  let reply = @protocol.BinaryContent(
    data_base64="iVBORw0KGgo=",
    media_type="image/png",
  )
  let decoded : @protocol.ReadFileReply = @json.from_json(reply.to_json())
  @debug.assert_eq(decoded, reply)
}

///|
test "open-path replies distinguish system, editor, and directory targets" {
  let legacy : @protocol.OpenPathReply = @json.from_json({ "opened": true })
  @debug.assert_eq(legacy, Opened)
  let system : @protocol.OpenPathReply = Opened
  let ordinary : @protocol.OpenPathReply = Editor({
    path: "README.md",
    line: None,
    column: None,
  })
  let positioned : @protocol.OpenPathReply = Editor({
    path: "src/main.mbt",
    line: Some(2738),
    column: Some(17),
  })
  let directory : @protocol.OpenPathReply = Directory({ path: "src", })
  let refused : @protocol.OpenPathReply = Refused(
    "File does not exist: nope.mbt",
  )
  for reply in [system, ordinary, positioned, directory, refused] {
    let decoded : @protocol.OpenPathReply = @json.from_json(reply.to_json())
    @debug.assert_eq(decoded, reply)
  }
}

///|
test "archive replies keep success compatible and encode dirty confirmation" {
  let sessions : @protocol.SessionsReply = { groups: [], }
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
test "worktree creation accepts exactly representable owner namespaces" {
  let legacy : @protocol.WorktreeCreatePayload = @json.from_json({
    "workspace": "/work/project",
    "session": "session-1",
  })
  assert_eq(legacy.session, Some("session-1"))
  assert_eq(legacy.codex_thread, None)
  let codex : @protocol.WorktreeCreatePayload = @json.from_json({
    "workspace": "/work/project",
    "codex_thread": "thread-1",
  })
  assert_eq(codex.session, None)
  assert_eq(codex.codex_thread, Some("thread-1"))
  @debug.assert_eq(codex.to_json(), {
    "workspace": "/work/project",
    "codex_thread": "thread-1",
  })
  let nullable : @protocol.WorktreeCreatePayload = @json.from_json({
    "workspace": "/work/project",
    "session": null,
    "codex_thread": "thread-1",
    "futureMetadata": true,
  })
  assert_eq(nullable, codex)
  let both_rejected = try {
    let _ : @protocol.WorktreeCreatePayload = @json.from_json({
      "workspace": "/work/project",
      "session": "session-1",
      "codex_thread": "thread-1",
    })
  } catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(both_rejected)
  let missing_rejected = try {
    let _ : @protocol.WorktreeCreatePayload = @json.from_json({
      "workspace": "/work/project",
    })
  } catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(missing_rejected)
  let wrong_type_rejected = try {
    let _ : @protocol.WorktreeCreatePayload = @json.from_json({
      "workspace": "/work/project",
      "session": 7,
    })
  } catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(wrong_type_rejected)
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

///|
test "text search payload and UTF-16 reply round-trip at the JSON boundary" {
  let raw_payload : Json = {
    "root": "/work/project",
    "query": "moon",
    "regex": false,
    "case_sensitive": true,
    "whole_word": true,
    "include_glob": "src/**,tests/**",
    "exclude_glob": "**/*.snap",
    "session_key": "search:session-1:/work/project",
    "generation": 9,
    "max_results": 20000,
  }
  let payload : @protocol.SearchTextPayload = @json.from_json(raw_payload)
  assert_eq(payload.root, "/work/project")
  assert_eq(payload.query, "moon")
  assert_false(payload.regex)
  assert_true(payload.case_sensitive)
  assert_true(payload.whole_word)
  assert_eq(payload.include_glob, "src/**,tests/**")
  assert_eq(payload.exclude_glob, "**/*.snap")
  assert_eq(payload.session_key, "search:session-1:/work/project")
  assert_eq(payload.generation, 9)
  assert_eq(payload.max_results, 20000)
  @debug.assert_eq(payload.to_json(), raw_payload)
  let raw_reply : Json = {
    "root": "/work/project",
    "generation": 9,
    "matches": [
      {
        "path": "src/main.mbt",
        "line_number": 4,
        "preview": "let moon = \"🌙\"",
        "preview_start_column": 1,
        "ranges": [{ "start_column": 5, "end_column": 9 }],
      },
    ],
    "match_count": 1,
    "file_count": 1,
    "limit_hit": false,
    "cancelled": false,
  }
  let reply : @protocol.SearchTextReply = @json.from_json(raw_reply)
  assert_eq(reply.matches[0].ranges[0].start_column, 5)
  assert_eq(reply.matches[0].ranges[0].end_column, 9)
  assert_true(reply.error is None)
  @debug.assert_eq(reply.to_json(), raw_reply)
  let cancel : @protocol.CancelSearchTextPayload = {
    session_key: "search:session-1:/work/project",
    generation: 9,
  }
  let decoded : @protocol.CancelSearchTextPayload = @json.from_json(
    cancel.to_json(),
  )
  @debug.assert_eq(decoded, cancel)
  let raw_error_reply : Json = {
    "root": "/work/project",
    "generation": 10,
    "matches": [],
    "match_count": 0,
    "file_count": 0,
    "limit_hit": false,
    "cancelled": false,
    "error_code": "invalid_regex",
    "error_message": "regex parse error",
  }
  let error_reply : @protocol.SearchTextReply = @json.from_json(raw_error_reply)
  assert_eq(
    error_reply.error,
    Some({ code: "invalid_regex", message: "regex parse error", }),
  )
  @debug.assert_eq(error_reply.to_json(), raw_error_reply)
}

///|
test "text search payload rejects missing and invalid required fields" {
  let missing_rejected = try {
    let _ : @protocol.SearchTextPayload = @json.from_json({
      "root": "/work/project",
      "query": "moon",
      "regex": false,
      "case_sensitive": false,
      "whole_word": false,
      "include_glob": "",
      "exclude_glob": "",
      "generation": 1,
      "max_results": 20000,
    })
  } catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(missing_rejected)
  let invalid_rejected = try {
    let _ : @protocol.CancelSearchTextPayload = @json.from_json({
      "session_key": 7,
      "generation": 1,
    })
  } catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(invalid_rejected)
  let null_rejected = try {
    let _ : @protocol.SearchTextPayload = @json.from_json({
      "root": Json::null(),
      "query": "moon",
      "regex": false,
      "case_sensitive": false,
      "whole_word": false,
      "include_glob": "",
      "exclude_glob": "",
      "session_key": "search:null",
      "generation": 1,
      "max_results": 20000,
    })
  } catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(null_rejected)
  let half_error_rejected = try {
    let _ : @protocol.SearchTextReply = @json.from_json({
      "root": "/work/project",
      "generation": 1,
      "matches": [],
      "match_count": 0,
      "file_count": 0,
      "limit_hit": false,
      "cancelled": false,
      "error_code": "search_failed",
    })
  } catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(half_error_rejected)
  let empty_error_sentinel_rejected = try {
    let _ : @protocol.SearchTextReply = @json.from_json({
      "root": "/work/project",
      "generation": 1,
      "matches": [],
      "match_count": 0,
      "file_count": 0,
      "limit_hit": false,
      "cancelled": false,
      "error_code": "",
      "error_message": "",
    })
  } catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(empty_error_sentinel_rejected)
}

///|
test "workspace replies keep success compatible and carry refusals" {
  let success : @protocol.WorkspacesReply = Workspaces(["/home/u/proj"])
  @debug.assert_eq(success.to_json(), { "workspaces": ["/home/u/proj"] })
  let decoded : @protocol.WorkspacesReply = @json.from_json(success.to_json())
  @debug.assert_eq(decoded, success)
  let refusal : @protocol.WorkspacesReply = WorkspaceError(
    "/w is a linked git worktree; attach the main checkout instead",
  )
  let decoded_refusal : @protocol.WorkspacesReply = @json.from_json(
    refusal.to_json(),
  )
  @debug.assert_eq(decoded_refusal, refusal)
}

///|
test "worktree creation results keep success compatible and carry refusals" {
  let created : @protocol.WorktreeCreateResult = WorktreeCreatedReply({
    name: "wt-1",
    worktrees: [],
  })
  @debug.assert_eq(created.to_json(), { "name": "wt-1", "worktrees": [] })
  let decoded : @protocol.WorktreeCreateResult = @json.from_json(
    created.to_json(),
  )
  @debug.assert_eq(decoded, created)
  let refused : @protocol.WorktreeCreateResult = WorktreeCreateError(
    "Submodules did not finish initializing within 10 seconds.",
  )
  @debug.assert_eq(refused.to_json(), {
    "error": "Submodules did not finish initializing within 10 seconds.",
  })
  let decoded_refusal : @protocol.WorktreeCreateResult = @json.from_json(
    refused.to_json(),
  )
  @debug.assert_eq(decoded_refusal, refused)
}

///|
test "browse replies keep success compatible and carry refusals" {
  let rooted : @protocol.BrowseDirectoryReply = Listing(path="/", parent=None, entries=[
    "home",
  ])
  // A root listing omits `parent`, matching the retired struct encoding.
  @debug.assert_eq(rooted.to_json(), { "path": "/", "entries": ["home"] })
  let nested : @protocol.BrowseDirectoryReply = Listing(
    path="/home/u",
    parent=Some("/home"),
    entries=[],
  )
  for reply in [rooted, nested] {
    let decoded : @protocol.BrowseDirectoryReply = @json.from_json(
      reply.to_json(),
    )
    @debug.assert_eq(decoded, reply)
  }
  let refusal : @protocol.BrowseDirectoryReply = BrowseError(
    "no such directory: /gone",
  )
  @debug.assert_eq(refusal.to_json(), { "error": "no such directory: /gone" })
  let decoded_refusal : @protocol.BrowseDirectoryReply = @json.from_json(
    refusal.to_json(),
  )
  @debug.assert_eq(decoded_refusal, refusal)
  let drives : @protocol.BrowseDirectoryReply = Drives(entries=["C:", "D:"])
  @debug.assert_eq(drives.to_json(), { "drives": ["C:", "D:"] })
  let decoded_drives : @protocol.BrowseDirectoryReply = @json.from_json(
    drives.to_json(),
  )
  @debug.assert_eq(decoded_drives, drives)
}

///|
test "agent connected states the host platform and tolerates its absence" {
  // A Windows host says so in the readiness signal itself, and the flag
  // survives the round trip.
  let windows : @protocol.ConnectedPayload = { stage: Serving, windows: true, }
  @debug.assert_eq(windows.to_json(), { "stage": "serving", "windows": true })
  let decoded : @protocol.ConnectedPayload = @json.from_json(windows.to_json())
  @debug.assert_eq(decoded, windows)
  // Hosts predating the field — and POSIX hosts, whose encoding omits it —
  // read as POSIX rather than dropping the connect.
  guard @protocol.Notification::from_wire("agent.connected", {
      "stage": "serving",
    })
    is Some(AgentConnected(legacy)) else {
    fail("a connect without the platform field was dropped")
  }
  assert_false(legacy.windows)
  // A malformed value is refused like any other unreadable payload.
  assert_true(
    @protocol.Notification::from_wire("agent.connected", {
      "stage": "serving",
      "windows": "yes",
    })
    is None,
  )
}

///|
test "directory creation payload has explicit required-field semantics" {
  let payload : @protocol.CreateDirectoryPayload = @json.from_json({
    "parent": "/home/u",
    "name": "new project",
    "future_field": true,
  })
  assert_eq(payload.parent, "/home/u")
  assert_eq(payload.name, "new project")
  @debug.assert_eq(payload.to_json(), {
    "parent": "/home/u",
    "name": "new project",
  })
  for
    malformed in (
      [
        {},
        { "parent": "/home/u" },
        { "parent": null, "name": "new project" },
        { "parent": "/home/u", "name": 7 },
      ] : Array[Json]) {
    try {
      let _ : @protocol.CreateDirectoryPayload = @json.from_json(malformed)
    } catch {
      _ => ()
    } noraise {
      _ => fail("expected malformed directory creation payload to fail")
    }
  }
}

///|
test "Git pull-request payload controls optional branch hints explicitly" {
  let payload : @protocol.GitPullRequestPayload = @json.from_json({
    "session": "thread-1",
    "cwd": null,
    "branch_hint": "openseek/wt-1",
    "future_metadata": true,
  })
  assert_eq(payload.session, "thread-1")
  assert_eq(payload.cwd, None)
  assert_eq(payload.branch_hint, Some("openseek/wt-1"))
  @debug.assert_eq(payload.to_json(), {
    "session": "thread-1",
    "branch_hint": "openseek/wt-1",
  })
  let absent : @protocol.GitPullRequestPayload = @json.from_json({
    "session": "thread-2",
  })
  @debug.assert_eq(absent.to_json(), { "session": "thread-2" })
  let missing_session = try {
    let _ : @protocol.GitPullRequestPayload = @json.from_json({
      "branch_hint": "openseek/wt-1",
    })
    false
  } catch {
    _ => true
  }
  assert_true(missing_session)
  let malformed_hint = try {
    let _ : @protocol.GitPullRequestPayload = @json.from_json({
      "session": "thread-1",
      "branch_hint": 7,
    })
    false
  } catch {
    _ => true
  }
  assert_true(malformed_hint)
}

///|
test "language payload codecs require every routing coordinate" {
  let opened : @protocol.LspOpenPayload = @json.from_json({
    "session": "thread-1",
    "root": "/work/project",
    "path": "src/main.mbt",
    "future_metadata": true,
  })
  @debug.assert_eq(opened.to_json(), {
    "session": "thread-1",
    "root": "/work/project",
    "path": "src/main.mbt",
  })
  let hovered : @protocol.LspHoverPayload = @json.from_json({
    "session": "thread-1",
    "root": "/work/project",
    "path": "src/main.mbt",
    "line": 8,
    "character": 13,
  })
  @debug.assert_eq(hovered.to_json(), {
    "session": "thread-1",
    "root": "/work/project",
    "path": "src/main.mbt",
    "line": 8,
    "character": 13,
  })
  let symbols : @protocol.WorkspaceSymbolsPayload = @json.from_json({
    "session": "thread-1",
    "root": "/work/project",
    "query": "WorktreeInfo",
  })
  @debug.assert_eq(symbols.to_json(), {
    "session": "thread-1",
    "root": "/work/project",
    "query": "WorktreeInfo",
  })
  let navigation : @protocol.MoonIdeNavigationPayload = @json.from_json({
    "session": "thread-1",
    "root": "/work/project",
    "path": "src/main.mbt",
    "line": 8,
    "column": 13,
  })
  @debug.assert_eq(navigation.to_json(), {
    "session": "thread-1",
    "root": "/work/project",
    "path": "src/main.mbt",
    "line": 8,
    "column": 13,
  })
  let missing_root = try {
    let _ : @protocol.LspOpenPayload = @json.from_json({
      "session": "thread-1",
      "path": "src/main.mbt",
    })
    false
  } catch {
    _ => true
  }
  assert_true(missing_root)
  let malformed_position = try {
    let _ : @protocol.LspHoverPayload = @json.from_json({
      "session": "thread-1",
      "root": "/work/project",
      "path": "src/main.mbt",
      "line": "eight",
      "character": 13,
    })
    false
  } catch {
    _ => true
  }
  assert_true(malformed_position)
}

///|
test "worktree replies omit absent owners and reject ambiguous ownership" {
  let openseek : @protocol.WorktreeInfo = @json.from_json({
    "name": "wt-1",
    "branch": "openseek/wt-1",
    "base": "abc",
    "session": "session-1",
    "codex_thread": null,
    "path": "/work/project/.worktrees/wt-1",
    "present": true,
    "future_metadata": true,
  })
  @debug.assert_eq(openseek.to_json(), {
    "name": "wt-1",
    "branch": "openseek/wt-1",
    "base": "abc",
    "session": "session-1",
    "path": "/work/project/.worktrees/wt-1",
    "present": true,
  })
  let codex : @protocol.WorktreeInfo = @json.from_json({
    "name": "wt-2",
    "branch": "openseek/wt-2",
    "base": "def",
    "codex_thread": "thread-1",
    "path": "/work/project/.worktrees/wt-2",
    "present": false,
  })
  @debug.assert_eq(codex.to_json(), {
    "name": "wt-2",
    "branch": "openseek/wt-2",
    "base": "def",
    "codex_thread": "thread-1",
    "path": "/work/project/.worktrees/wt-2",
    "present": false,
  })
  let ownerless : @protocol.WorktreeInfo = @json.from_json({
    "name": "legacy",
    "branch": "openseek/legacy",
    "base": "ghi",
    "session": null,
    "codex_thread": null,
    "path": "/work/project/.worktrees/legacy",
    "present": false,
  })
  assert_eq(ownerless.session, None)
  assert_eq(ownerless.codex_thread, None)
  let ambiguous = try {
    let _ : @protocol.WorktreeInfo = @json.from_json({
      "name": "ambiguous",
      "branch": "openseek/ambiguous",
      "base": "jkl",
      "session": "session-1",
      "codex_thread": "thread-1",
      "path": "/work/project/.worktrees/ambiguous",
      "present": true,
    })
    false
  } catch {
    _ => true
  }
  assert_true(ambiguous)
  let malformed_present = try {
    let _ : @protocol.WorktreeInfo = @json.from_json({
      "name": "wt-3",
      "branch": "openseek/wt-3",
      "base": "mno",
      "path": "/work/project/.worktrees/wt-3",
      "present": "yes",
    })
    false
  } catch {
    _ => true
  }
  assert_true(malformed_present)
}

///|
test "Git history and commit-change protocol round-trip immutable identities" {
  let snapshot : @protocol.GitHistorySnapshot = {
    head: Some("1111111111111111111111111111111111111111"),
    branch: Some("feature/graph"),
    refs: [
      {
        name: "feature/graph",
        revision: "1111111111111111111111111111111111111111",
        kind: "current",
      },
    ],
    tips: ["1111111111111111111111111111111111111111"],
  }
  let history : @protocol.GitHistoryReply = {
    repository: true,
    snapshot,
    commits: [
      {
        id: "1111111111111111111111111111111111111111",
        parent_ids: ["0000000000000000000000000000000000000000"],
        subject: "Add graph",
        author: "OpenSeek",
        authored_at: "2026-08-19T10:00:00+08:00",
      },
    ],
    has_more: true,
  }
  let decoded : @protocol.GitHistoryReply = @json.from_json(history.to_json())
  assert_eq(decoded, history)
  let payload : @protocol.GitHistoryPayload = {
    session: "s1",
    workspace: Some("/workspace"),
    snapshot: Some(snapshot),
    skip: 50,
    limit: 50,
  }
  let decoded_payload : @protocol.GitHistoryPayload = @json.from_json(
    payload.to_json(),
  )
  assert_eq(decoded_payload, payload)
  let commit_payload : @protocol.GitCommitChangesPayload = {
    session: "s1",
    workspace: Some("/workspace"),
    commit: "1111111111111111111111111111111111111111",
  }
  let decoded_commit_payload : @protocol.GitCommitChangesPayload = @json.from_json(
    commit_payload.to_json(),
  )
  assert_eq(decoded_commit_payload, commit_payload)
  let changes : @protocol.GitCommitChangesReply = {
    commit: "1111111111111111111111111111111111111111",
    parent: Some("0000000000000000000000000000000000000000"),
    changes: [
      {
        path: "src/new.mbt",
        original_path: Some("src/old.mbt"),
        status: "renamed",
        kind: "file",
      },
    ],
  }
  let decoded_changes : @protocol.GitCommitChangesReply = @json.from_json(
    changes.to_json(),
  )
  assert_eq(decoded_changes, changes)
}

///|
test "Git history codecs ignore unknown fields and omit absent optionals" {
  let payload : @protocol.GitHistoryPayload = @json.from_json({
    "session": "s1",
    "workspace": null,
    "snapshot": null,
    "skip": 0,
    "limit": 0,
    "future_payload": true,
  })
  @debug.assert_eq(payload.to_json(), { "session": "s1", "skip": 0, "limit": 0 })
  let commit_payload : @protocol.GitCommitChangesPayload = @json.from_json({
    "session": "s1",
    "workspace": null,
    "commit": "1111111111111111111111111111111111111111",
    "future_payload": true,
  })
  @debug.assert_eq(commit_payload.to_json(), {
    "session": "s1",
    "commit": "1111111111111111111111111111111111111111",
  })
  let history : @protocol.GitHistoryReply = @json.from_json({
    "repository": true,
    "snapshot": {
      "head": null,
      "branch": null,
      "refs": [
        {
          "name": "HEAD",
          "revision": "1111111111111111111111111111111111111111",
          "kind": "head",
          "future_ref": true,
        },
      ],
      "tips": ["1111111111111111111111111111111111111111"],
      "future_snapshot": true,
    },
    "commits": [
      {
        "id": "1111111111111111111111111111111111111111",
        "parent_ids": [],
        "subject": "Initial commit",
        "author": "OpenSeek",
        "authored_at": "2026-08-19T10:00:00+08:00",
        "future_commit": true,
      },
    ],
    "has_more": false,
    "future_reply": true,
  })
  @debug.assert_eq(history.to_json(), {
    "repository": true,
    "snapshot": {
      "refs": [
        {
          "name": "HEAD",
          "revision": "1111111111111111111111111111111111111111",
          "kind": "head",
        },
      ],
      "tips": ["1111111111111111111111111111111111111111"],
    },
    "commits": [
      {
        "id": "1111111111111111111111111111111111111111",
        "parent_ids": [],
        "subject": "Initial commit",
        "author": "OpenSeek",
        "authored_at": "2026-08-19T10:00:00+08:00",
      },
    ],
    "has_more": false,
  })
  let changes : @protocol.GitCommitChangesReply = @json.from_json({
    "commit": "1111111111111111111111111111111111111111",
    "parent": null,
    "changes": [
      {
        "path": "README.md",
        "original_path": null,
        "status": "added",
        "kind": "file",
        "future_change": true,
      },
    ],
    "future_reply": true,
  })
  @debug.assert_eq(changes.to_json(), {
    "commit": "1111111111111111111111111111111111111111",
    "changes": [{ "path": "README.md", "status": "added", "kind": "file" }],
  })
}

///|
test "Git history codecs reject missing, null, and malformed required data" {
  let missing_session = try {
    let _ : @protocol.GitHistoryPayload = @json.from_json({
      "skip": 0,
      "limit": 50,
    })
    false
  } catch {
    _ => true
  }
  assert_true(missing_session)
  let null_commit = try {
    let _ : @protocol.GitCommitChangesPayload = @json.from_json({
      "session": "s1",
      "commit": null,
    })
    false
  } catch {
    _ => true
  }
  assert_true(null_commit)
  let malformed_ref = try {
    let _ : @protocol.GitHistoryRef = @json.from_json({
      "name": "HEAD",
      "revision": "1111111111111111111111111111111111111111",
      "kind": 1,
    })
    false
  } catch {
    _ => true
  }
  assert_true(malformed_ref)
  let null_refs = try {
    let _ : @protocol.GitHistorySnapshot = @json.from_json({
      "refs": null,
      "tips": [],
    })
    false
  } catch {
    _ => true
  }
  assert_true(null_refs)
  let malformed_parent = try {
    let _ : @protocol.GitHistoryCommit = @json.from_json({
      "id": "1111111111111111111111111111111111111111",
      "parent_ids": [1],
      "subject": "Initial commit",
      "author": "OpenSeek",
      "authored_at": "2026-08-19T10:00:00+08:00",
    })
    false
  } catch {
    _ => true
  }
  assert_true(malformed_parent)
  let null_snapshot = try {
    let _ : @protocol.GitHistoryReply = @json.from_json({
      "repository": true,
      "snapshot": null,
      "commits": [],
      "has_more": false,
    })
    false
  } catch {
    _ => true
  }
  assert_true(null_snapshot)
  let missing_status = try {
    let _ : @protocol.GitHistoricalChange = @json.from_json({
      "path": "README.md",
      "kind": "file",
    })
    false
  } catch {
    _ => true
  }
  assert_true(missing_status)
  let malformed_change = try {
    let _ : @protocol.GitCommitChangesReply = @json.from_json({
      "commit": "1111111111111111111111111111111111111111",
      "changes": [{ "path": "README.md", "status": false, "kind": "file" }],
    })
    false
  } catch {
    _ => true
  }
  assert_true(malformed_change)
}

///|
test "a run's close keeps its outcome and reports only the evidence it has" {
  // Absent, not null, for evidence a close does not have: that is what a host
  // writes for a turn with no answer and no process exit, and what an older
  // one writes for a field it never had.
  let bare : @protocol.FinishedPayload = {
    run_id: "r1",
    status: "failed",
    answer: None,
    exit_code: None,
  }
  @debug.assert_eq(bare.to_json(), { "run_id": "r1", "status": "failed" })
  let full : @protocol.FinishedPayload = {
    run_id: "r1",
    status: "finished",
    answer: Some("done"),
    exit_code: Some(0),
  }
  @debug.assert_eq(full.to_json(), {
    "run_id": "r1",
    "status": "finished",
    "answer": "done",
    "exit_code": 0,
  })

  // Every way of not reporting the optionals decodes the same, and a field a
  // newer host added is read past rather than refused.
  for
    thin in (
      [
        { "run_id": "r1", "status": "failed" },
        { "run_id": "r1", "status": "failed", "answer": Json::null() },
        { "run_id": "r1", "status": "failed", "exit_code": "9" },
        { "run_id": "r1", "status": "failed", "settled_by_a_newer_host": true },
      ] : Array[Json]) {
    let decoded : @protocol.FinishedPayload = @json.from_json(thin)
    assert_eq(decoded.run_id, "r1")
    assert_eq(decoded.status, "failed")
    assert_eq(decoded.answer, None)
    assert_eq(decoded.exit_code, None)
  }

  // The run and its outcome are the message. A report naming neither settles
  // anything, so it is refused rather than closing a run as "".
  for incomplete in ([{ "status": "failed" }, { "run_id": "r1" }] : Array[Json]) {
    let refused = try {
      let _ : @protocol.FinishedPayload = @json.from_json(incomplete)
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}

///|
test "a cancel reply spells \"nothing was open\" by omission" {
  let matched : @protocol.CancelReply = { run_id: Some("r1"), }
  @debug.assert_eq(matched.to_json(), { "run_id": "r1" })

  // Not `{"run_id": null}`: the key's absence IS the answer, so a reader that
  // only checks for the key agrees with one that inspects its value.
  let unmatched : @protocol.CancelReply = { run_id: None, }
  @debug.assert_eq(unmatched.to_json(), Json::empty_object())

  // Nothing here is worth failing a Stop over: every shape that is not a run
  // id decodes as "no run was cancelled", and a newer host's extra keys are
  // ignored rather than refused.
  for
    absent in (
      [
        Json::empty_object(),
        { "run_id": Json::null() },
        { "run_id": 7 },
        { "run_id": ["r1"] },
        { "cancelled": true, "withdrew_pending_prompt": false },
      ] : Array[Json]) {
    let decoded : @protocol.CancelReply = @json.from_json(absent)
    assert_eq(decoded.run_id, None)
  }
  let decoded : @protocol.CancelReply = @json.from_json({
    "run_id": "r1",
    "cancelled": true,
  })
  assert_eq(decoded.run_id, Some("r1"))

  // A reply that is not an object at all is a different host speaking a
  // different protocol, and that is worth refusing.
  let refused = try {
    let _ : @protocol.CancelReply = @json.from_json(Json("r1"))
    false
  } catch {
    _ => true
  }
  assert_true(refused)
}

///|
test "a reconnect settlement is refused unless it names run, session and outcome" {
  let bare : @protocol.RunSettlementPayload = {
    run_id: "r1",
    session: "s1",
    submission_id: None,
    status: "cancelled",
    exit_code: None,
  }
  @debug.assert_eq(bare.to_json(), {
    "run_id": "r1",
    "session": "s1",
    "status": "cancelled",
  })
  let full : @protocol.RunSettlementPayload = {
    run_id: "r1",
    session: "s1",
    submission_id: Some("sub-1"),
    status: "failed",
    exit_code: Some(9),
  }
  @debug.assert_eq(full.to_json(), {
    "run_id": "r1",
    "session": "s1",
    "status": "failed",
    "submission_id": "sub-1",
    "exit_code": 9,
  })
  let decoded : @protocol.RunSettlementPayload = @json.from_json({
    "run_id": "r1",
    "session": "s1",
    "status": "failed",
    "submission_id": Json::null(),
    "exit_code": true,
    "queued_by_a_newer_host": 1,
  })
  assert_eq(decoded.submission_id, None)
  assert_eq(decoded.exit_code, None)
  assert_eq(decoded.status, "failed")

  // A row that cannot be matched against a caller's selectors, or that names
  // no outcome, would settle the wrong run or none: refuse it.
  for
    incomplete in (
      [
        { "session": "s1", "status": "failed" },
        { "run_id": "r1", "status": "failed" },
        { "run_id": "r1", "session": "s1" },
      ] : Array[Json]) {
    let refused = try {
      let _ : @protocol.RunSettlementPayload = @json.from_json(incomplete)
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}

///|
test "file stats keep missing, present, and failed distinct on the wire" {
  let reply : @protocol.StatFilesReply = {
    stats: [
      { path: "/work/gone.mbt", signature: Missing, },
      { path: "/work/here.mbt", signature: Present("12:34"), },
      { path: "/work/locked.mbt", signature: Failed("permission denied"), },
    ],
  }
  let wire : Json = {
    "stats": [
      { "path": "/work/gone.mbt", "signature": { "kind": "missing" } },
      {
        "path": "/work/here.mbt",
        "signature": { "kind": "present", "sig": "12:34" },
      },
      {
        "path": "/work/locked.mbt",
        "signature": { "kind": "failed", "message": "permission denied" },
      },
    ],
  }
  @debug.assert_eq(reply.to_json(), wire)
  let decoded : @protocol.StatFilesReply = @json.from_json(wire)
  @debug.assert_eq(decoded, reply)
  // An empty signature string is not a deleted-file sentinel any more; a
  // reply spelled that way is malformed rather than silently "deleted".
  let legacy : @protocol.StatFilesReply = @json.from_json({
    "stats": [{ "path": "/work/gone.mbt", "sig": "" }],
  }) catch {
    _ => return
  }
  fail("an empty signature must not decode: \{Repr(legacy)}")
}
