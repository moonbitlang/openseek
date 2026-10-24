///|
fn browser_event_is_rejected(wire : Json) -> Bool {
  let decoded : @protocol.BrowserEventPayload? = Some(@json.from_json(wire)) catch {
    _ => None
  }
  decoded is None
}

///|
test "native browser events preserve their wire payloads" {
  let cases : Array[(@protocol.BrowserEventPayload, Json)] = [
    (
      OpenRequested(request="r-1", session="s-1", url="https://example.test/"),
      {
        "kind": "open_requested",
        "request": "r-1",
        "session": "s-1",
        "url": "https://example.test/",
      },
    ),
    (
      Navigated(id=3, url="https://example.test/"),
      { "kind": "navigated", "id": 3, "url": "https://example.test/" },
    ),
    (
      LoadingChanged(id=3, loading=false),
      { "kind": "loading", "id": 3, "loading": false },
    ),
    (TitleUpdated(id=3, title=""), { "kind": "title", "id": 3, "title": "" }),
    (
      LoadFailed(id=3, url="https://example.test/", code=-3, text="ERR_ABORTED"),
      {
        "kind": "load_failed",
        "id": 3,
        "url": "https://example.test/",
        "code": -3,
        "text": "ERR_ABORTED",
      },
    ),
    (
      RendererProcessTerminated(
        id=3,
        url="https://example.test/",
        code=-3,
        text="Renderer process terminated (status 1): fixture exit",
      ),
      {
        "kind": "renderer_process_terminated",
        "id": 3,
        "url": "https://example.test/",
        "code": -3,
        "text": "Renderer process terminated (status 1): fixture exit",
      },
    ),
  ]
  for (event, wire) in cases {
    assert_eq(event.to_json(), wire)
    assert_eq(@json.from_json(wire), event)
    guard wire is Object(fields) else { fail("expected object") }
    let extended = fields.copy()
    extended["future"] = true
    assert_eq(@json.from_json(Json(extended)), event)
    for key, value in fields {
      let missing = fields.copy()
      missing.remove(key)
      assert_true(browser_event_is_rejected(Json(missing)))
      for
        invalid in [
          null,
          if value is String(_) {
            Json(0)
          } else {
            Json("invalid")
          },
        ] {
        let malformed = fields.copy()
        malformed[key] = invalid
        assert_true(browser_event_is_rejected(Json(malformed)))
      }
    }
  }
}

///|
test "browser event decoding rejects unsupported events and nonobjects" {
  let invalid : Array[Json] = [
    null,
    [],
    "navigated",
    {},
    { "id": 3, "kind": "closed" },
    { "id": 3, "kind": "found_in_page" },
    { "id": 3, "kind": "future" },
  ]
  for wire in invalid {
    assert_true(browser_event_is_rejected(wire))
  }
}
