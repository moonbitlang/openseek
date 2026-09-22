///|
test "resumed transcript renders text and inline image thumbnails" {
  let item : @desktop_protocol.SessionItem = @json.from_json({
    "kind": "user",
    "payload": {
      "content": [
        { "type": "text", "text": "compare " },
        {
          "type": "image",
          "media_type": "image/png",
          "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==",
        },
        { "type": "text", "text": " with " },
        {
          "type": "image",
          "media_type": "image/png",
          "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==",
        },
      ],
    },
  })
  let items : Array[@transcript.TranscriptItem] = []
  assert_true(@transcript.apply_session_item(items, item, sequence=1))
  assert_eq(items.length(), 1)
  assert_eq(items[0].text(), Some("compare  with"))
  assert_true(
    items[0].kind is User(images~, ..) &&
    images.length() == 2 &&
    images[0].has_prefix("data:image/png;base64,"),
  )
}
