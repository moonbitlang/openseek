///|
test "local preview codecs retain source paths and distinguish absent optional fields" {
  let payload : @protocol.BrowserPreviewPayload = @json.from_json({
    "id": 3,
    "path": "/work/pages/index.htm",
    "dark": false,
  })
  assert_eq(payload.root, None)
  assert_eq(payload.session, None)
  assert_eq(payload.to_json(), {
    "id": 3,
    "path": "/work/pages/index.htm",
    "dark": false,
  })
  let rooted : @protocol.BrowserPreviewPayload = {
    ..payload,
    root: Some("/work"),
    session: Some("s-1"),
  }
  assert_eq(@json.from_json(rooted.to_json()), rooted)
  let malformed_cases : Array[Json] = [
    { "id": 3, "path": "/work/index.html" },
    { "id": "3", "path": "/work/index.html", "dark": false },
    { "id": 3, "path": null, "dark": false },
    { "id": 3, "path": "/work/index.html", "dark": false, "root": 4 },
  ]
  for malformed in malformed_cases {
    let refused = try {
      let _ : @protocol.BrowserPreviewPayload = @json.from_json(malformed)
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
  let reply : @protocol.BrowserPreviewReply = {
    url: "http://127.0.0.1:1234/token/index.html",
  }
  assert_eq(@json.from_json(reply.to_json()), reply)
}
