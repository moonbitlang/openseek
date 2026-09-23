///|
test "desktop notifications round-trip at the wire edge" {
  let event = @protocol.Notification::from_wire("terminal.exit", {
    "id": "terminal-1",
    "code": 0,
  })
  guard event is Some(event) else { fail("known notification was rejected") }
  assert_eq(event.wire_name(), "terminal.exit")
  assert_eq(event.params(), { "id": "terminal-1", "code": 0 })
  let settings = @protocol.Notification::from_wire(
    "workspace.settings_changed",
    {
      "workspace": "/home/u/proj",
      "worktree_mode": true,
      "checkout_submodules": false,
      "submodule_checkout_timeout_seconds": 30,
    },
  )
  guard settings is Some(settings) else {
    fail("workspace settings notification was rejected")
  }
  assert_eq(settings.wire_name(), "workspace.settings_changed")
  assert_eq(settings.params(), {
    "workspace": "/home/u/proj",
    "worktree_mode": true,
    "checkout_submodules": false,
    "submodule_checkout_timeout_seconds": 30,
  })
  assert_eq(@protocol.Notification::from_wire("future.event", {}), None)
}

///|
test "malformed agent errors remain visible notifications" {
  let cases : Array[Json] = [{}, { "message": 42 }]
  for params in cases {
    guard @protocol.Notification::from_wire("agent.error", params)
      is Some(AgentError(payload)) else {
      fail("malformed agent error was dropped")
    }
    assert_eq(payload.message, None)
  }
}

///|
test "semantic search progress notifications round-trip at the wire edge" {
  let wire : Json = {
    "root": "/work",
    "session_key": "semantic-search:local:one:/work",
    "generation": 3,
    "matches": [
      {
        "path": "src/main.mbt",
        "rule_id": "pattern",
        "description": "a desc",
        "start_line": 1,
        "start_column": 1,
        "end_line": 1,
        "end_column": 5,
        "matched_source": "moon",
        "source_context": [{ "line": 1, "text": "moon", "is_match": true }],
      },
    ],
    "match_count": 1,
    "file_count": 1,
  }
  guard @protocol.Notification::from_wire("semantic.search_progress", wire)
    is Some(SemanticSearchProgress(payload)) else {
    fail("known notification was rejected")
  }
  assert_eq(payload.root, "/work")
  assert_eq(payload.session_key, "semantic-search:local:one:/work")
  assert_eq(payload.generation, 3)
  assert_eq(payload.match_count, 1)
  assert_eq(payload.file_count, 1)
  assert_eq(payload.matches.length(), 1)
  assert_eq(payload.matches[0].path, "src/main.mbt")
  assert_eq(
    @protocol.Notification::SemanticSearchProgress(payload).params(),
    wire,
  )
}

///|
test "a workflow entry round-trips at the wire edge" {
  let params : Json = {
    "workflow": "wf-5",
    "session": "run7",
    "child": "run7-sr-5",
    "kind": "explore",
    "label": "scout:x",
    "phase": "survey",
    "status": "captured",
    "steps": 12,
    "prompt_tokens": 3000,
    "completion_tokens": 400,
    "started_at": 1788535817640,
    "finished_at": 1788535817648,
  }
  // `cost_usd` is absent, not null: an optional field that is not there
  // decodes as None, and encodes back to nothing — the round trip below
  // pins that the params come back exactly as sent.
  guard @protocol.Notification::from_wire("workflow.entry", params)
    is Some(event) else {
    fail("known notification was rejected")
  }
  assert_eq(event.wire_name(), "workflow.entry")
  assert_eq(event.kind(), WorkflowEntry)
  guard event is WorkflowEntry(payload) else { fail("wrong case") }
  assert_eq(payload.child, "run7-sr-5")
  assert_eq(payload.phase, Some("survey"))
  assert_eq(payload.cost_usd, None)
  assert_eq(payload.finished_at, Some(1788535817648.0))
  assert_eq(event.params(), params)
}
