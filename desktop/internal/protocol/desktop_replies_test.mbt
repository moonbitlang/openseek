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
test "agent connected requires concrete store roots" {
  assert_true(
    @protocol.Notification::from_wire("agent.connected", { "ready": true })
    is None,
  )
  // The scratch base alone is no longer enough: readiness names the global
  // session store too, so clients can classify broadcast roots exactly.
  assert_true(
    @protocol.Notification::from_wire("agent.connected", {
      "ready": true,
      "scratch_root": "/scratch",
    })
    is None,
  )
  guard @protocol.Notification::from_wire("agent.connected", {
      "ready": true,
      "scratch_root": "/scratch",
      "session_root": "/sessions/global",
    })
    is Some(AgentConnected(payload)) else {
    fail("connected notification with both roots did not decode")
  }
  assert_eq(payload.scratch_root, "/scratch")
  assert_eq(payload.session_root, "/sessions/global")
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
  @debug.assert_eq(legacy, {
    opened: true,
    editor_target: None,
    directory_target: None,
  })
  let system : @protocol.OpenPathReply = {
    opened: true,
    editor_target: None,
    directory_target: None,
  }
  let ordinary : @protocol.OpenPathReply = {
    opened: false,
    editor_target: Some({ path: "README.md", line: None, column: None }),
    directory_target: None,
  }
  let positioned : @protocol.OpenPathReply = {
    opened: false,
    editor_target: Some({
      path: "src/main.mbt",
      line: Some(2738),
      column: Some(17),
    }),
    directory_target: None,
  }
  let directory : @protocol.OpenPathReply = {
    opened: false,
    editor_target: None,
    directory_target: Some({ path: "src" }),
  }
  for reply in [system, ordinary, positioned, directory] {
    let decoded : @protocol.OpenPathReply = @json.from_json(reply.to_json())
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
