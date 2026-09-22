///|
test "session message content preserves blocks and accepts legacy strings" {
  let blocks : Json = [
    { "type": "text", "text": "before " },
    {
      "type": "image",
      "media_type": "image/png",
      "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==",
    },
    { "type": "text", "text": " after" },
  ]
  for kind in ["user", "tool_result"] {
    for content in [Json("legacy"), blocks] {
      let record : Json = {
        "kind": kind,
        "payload": {
          "content": content,
          "tool_calls": [],
          "tool_call_id": "call-one",
          "tool_name": "read_image",
          "is_error": false,
        },
      }
      let item : @protocol.SessionItem = @json.from_json(record)
      let actual = match item {
        User(message) => message.content
        ToolResult(result) => result.content
        _ => fail("failed to decode message content")
      }
      if content == blocks {
        assert_eq(Json(actual), blocks)
        assert_eq(actual.text(), "before  after")
        assert_true(actual.0 is [Text(_), Image(_), Text(_)])
      } else {
        assert_eq(Json(actual), "legacy")
      }
    }
  }
}

///|
test "invalid content blocks remain unknown records instead of losing parts" {
  let record : Json = {
    "kind": "user",
    "payload": { "content": [{ "type": "file", "file_id": 123 }] },
  }
  let item : @protocol.SessionItem = @json.from_json(record)
  assert_true(item is Unknown(_))
  assert_eq(Json(item), record)
}

///|
test "session images use the shared content decoder and preserve invalid records" {
  for
    image in [
      { "type": "image", "media_type": "image/jpeg", "data": "iVBORw0KGgo=" },
      { "type": "image", "media_type": "image/png", "data": "dGV4dA==" },
    ] {
    let record : Json = { "kind": "user", "payload": { "content": [image] } }
    let item : @protocol.SessionItem = @json.from_json(record)
    assert_true(item is Unknown(_))
    assert_eq(Json(item), record)
  }
}
