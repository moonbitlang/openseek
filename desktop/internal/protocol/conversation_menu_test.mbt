///|
test "conversation popup payload round-trips and ignores unknown fields" {
  let payload : @protocol.ConversationMenuPayload = @json.from_json({
    "x": 12,
    "y": 34,
    "kind": "live",
    "archive_enabled": false,
    "delete_enabled": false,
    "future": true,
  })
  assert_eq(payload.x, 12)
  assert_eq(payload.y, 34)
  assert_eq(payload.kind, LiveConversationMenu)
  assert_false(payload.archive_enabled)
  assert_false(payload.delete_enabled)
  @debug.assert_eq(payload.to_json(), {
    "x": 12,
    "y": 34,
    "kind": "live",
    "archive_enabled": false,
    "delete_enabled": false,
  })
}

///|
test "conversation rename payload requires its durable identity and title" {
  let payload : @protocol.SessionRenamePayload = @json.from_json({
    "session": "desktop-1",
    "workspace": "/work/project",
    "title": "Renamed",
  })
  assert_eq(payload.session, "desktop-1")
  assert_eq(payload.workspace, "/work/project")
  assert_eq(payload.title, "Renamed")
  @debug.assert_eq(payload.to_json(), {
    "session": "desktop-1",
    "workspace": "/work/project",
    "title": "Renamed",
  })
  for
    raw in (
      [
        { "workspace": "/work/project", "title": "Renamed" },
        { "session": "desktop-1", "workspace": null, "title": "Renamed" },
        { "session": "desktop-1", "workspace": "/work/project", "title": 3 },
      ] : Array[Json]) {
    let decoded : @protocol.SessionRenamePayload? = Some(@json.from_json(raw)) catch {
      _ => None
    }
    assert_true(decoded is None)
  }
}

///|
test "Codex rename payload matches thread name set" {
  let payload : @protocol.CodexThreadRenamePayload = @json.from_json({
    "threadId": "thread-1",
    "name": "Renamed task",
  })
  assert_eq(payload.thread_id, "thread-1")
  assert_eq(payload.name, "Renamed task")
  @debug.assert_eq(payload.to_json(), {
    "threadId": "thread-1",
    "name": "Renamed task",
  })
}
