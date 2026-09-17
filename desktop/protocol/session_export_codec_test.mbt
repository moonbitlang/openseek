///|
test "session export payload round-trips and ignores unknown fields" {
  let payload : @protocol.SessionExportPayload = @json.from_json({
    "session": "desktop-1",
    "workspace": "/work/project",
    "title": "Export me",
    "archived": true,
    "future_field": "ignored",
  })
  assert_eq(payload.session, "desktop-1")
  assert_eq(payload.workspace, "/work/project")
  assert_eq(payload.title, "Export me")
  assert_true(payload.archived)
  @debug.assert_eq(payload.to_json(), {
    "session": "desktop-1",
    "workspace": "/work/project",
    "title": "Export me",
    "archived": true,
  })
}

///|
test "session export payload rejects missing null and malformed fields" {
  for
    raw in (
      [
        {
          "workspace": "/work/project",
          "title": "Missing session",
          "archived": false,
        },
        {
          "session": null,
          "workspace": "/work/project",
          "title": "Null session",
          "archived": false,
        },
        {
          "session": "desktop-1",
          "workspace": 7,
          "title": "Malformed workspace",
          "archived": false,
        },
        {
          "session": "desktop-1",
          "workspace": "/work/project",
          "title": false,
          "archived": false,
        },
        {
          "session": "desktop-1",
          "workspace": "/work/project",
          "title": "Malformed archive flag",
          "archived": "no",
        },
        Json("not an object"),
      ] : Array[Json]) {
    let decoded : @protocol.SessionExportPayload? = Some(@json.from_json(raw)) catch {
      _ => None
    }
    assert_true(decoded is None)
  }
}

///|
test "session save payload flattens the export identity beside its destination" {
  let payload : @protocol.SessionSavePayload = @json.from_json({
    "session": "desktop-1",
    "workspace": "/work/project",
    "title": "Export me",
    "archived": false,
    "destination": "/tmp/conversation.html",
  })
  assert_eq(payload.source.session, "desktop-1")
  assert_eq(payload.destination, "/tmp/conversation.html")
  @debug.assert_eq(payload.to_json(), {
    "session": "desktop-1",
    "workspace": "/work/project",
    "title": "Export me",
    "archived": false,
    "destination": "/tmp/conversation.html",
  })
  for
    raw in (
      [
        {
          "session": "desktop-1",
          "workspace": "/work/project",
          "title": "No destination",
          "archived": false,
        },
        {
          "session": "desktop-1",
          "workspace": "/work/project",
          "title": "Null destination",
          "archived": false,
          "destination": null,
        },
        { "destination": "/tmp/conversation.html" },
      ] : Array[Json]) {
    let decoded : @protocol.SessionSavePayload? = Some(@json.from_json(raw)) catch {
      _ => None
    }
    assert_true(decoded is None)
  }
}

///|
test "save file dialog payload and reply codecs" {
  let payload : @protocol.SaveFileDialogPayload = @json.from_json({
    "title": "Export conversation",
    "suggested_name": "desktop-1.html",
  })
  assert_eq(payload.suggested_name, "desktop-1.html")
  @debug.assert_eq(payload.to_json(), {
    "title": "Export conversation",
    "suggested_name": "desktop-1.html",
  })
  let missing : @protocol.SaveFileDialogPayload? = Some(
    @json.from_json({ "title": "Export conversation" }),
  ) catch {
    _ => None
  }
  assert_true(missing is None)
  let dismissed : @protocol.SaveFileDialogReply = @json.from_json({})
  assert_eq(dismissed.path, None)
  @debug.assert_eq(dismissed.to_json(), {})
  let null_path : @protocol.SaveFileDialogReply = @json.from_json({
    "path": null,
  })
  assert_eq(null_path.path, None)
  let chosen : @protocol.SaveFileDialogReply = @json.from_json({
    "path": "/tmp/conversation.html",
  })
  assert_eq(chosen.path, Some("/tmp/conversation.html"))
  @debug.assert_eq(chosen.to_json(), { "path": "/tmp/conversation.html" })
}

///|
test "session export reply omits an absent path and ignores unknown fields" {
  let missing : @protocol.SessionExportReply = @json.from_json({
    "opened": false,
    "future_field": true,
  })
  assert_eq(missing.path, None)
  assert_false(missing.opened)
  @debug.assert_eq(missing.to_json(), { "opened": false })
  let null_path : @protocol.SessionExportReply = @json.from_json({
    "path": null,
    "opened": false,
  })
  assert_eq(null_path.path, None)
  @debug.assert_eq(null_path.to_json(), { "opened": false })
  let saved : @protocol.SessionExportReply = @json.from_json({
    "path": "/tmp/conversation.html",
    "opened": true,
  })
  assert_eq(saved.path, Some("/tmp/conversation.html"))
  assert_true(saved.opened)
  @debug.assert_eq(saved.to_json(), {
    "path": "/tmp/conversation.html",
    "opened": true,
  })
}

///|
test "session export reply rejects missing null and malformed required fields" {
  for
    raw in (
      [
        { "path": "/tmp/conversation.html" },
        { "path": "/tmp/conversation.html", "opened": null },
        { "path": "/tmp/conversation.html", "opened": "yes" },
        { "path": 7, "opened": false },
        Json(([] : Array[Json])),
      ] : Array[Json]) {
    let decoded : @protocol.SessionExportReply? = Some(@json.from_json(raw)) catch {
      _ => None
    }
    assert_true(decoded is None)
  }
}
