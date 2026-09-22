///|
test "durable content writes single text as a string and other content as arrays" {
  for text in ["hello", ""] {
    let content : @openseek_protocol.Content = @json.from_json(Json(text))
    assert_eq(content, Content([Text(text)]))
    assert_eq(Json(content), Json(text))
    let from_array : @openseek_protocol.Content = @json.from_json([
      { "type": "text", "text": text },
    ])
    assert_eq(from_array, content)
    assert_eq(Json(from_array), Json(text))
  }
  let texts = @openseek_protocol.Content([Text("first"), Text("second")])
  assert_eq(Json(texts), [
    { "type": "text", "text": "first" },
    { "type": "text", "text": "second" },
  ])
  let parts : Json = [
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
  ]
  let content : @openseek_protocol.Content = @json.from_json(parts)
  assert_eq(Json(content), parts)
  assert_eq(content.text(), "compare  with ")
  let empty : @openseek_protocol.Content = @json.from_json([])
  assert_eq(empty.0.length(), 0)
  assert_eq(Json(empty), [])
}

///|
test "durable content rejects malformed parts without dropping them" {
  let invalid : Array[Json] = [
    Json::null(),
    1,
    {},
    ["text"],
    [{ "type": "text" }],
    [{ "type": "text", "text": 1 }],
    [{ "type": "file" }],
    [{ "type": "file", "file_id": " " }],
    [{ "type": "image", "url": "example" }],
    [{ "type": "image", "media_type": "image/png", "data": null }],
    [{ "type": "image", "media_type": "image/png", "data": "%%%" }],
    [{ "type": "image", "media_type": "image/png", "data": "" }],
    [{ "type": "image", "media_type": "image/png", "data": "dGV4dA==" }],
    [{ "type": "image", "media_type": "image/jpeg", "data": "iVBORw0KGgo=" }],
  ]
  for json in invalid {
    try {
      let _ : @openseek_protocol.Content = @json.from_json(json)
    } catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("accepted invalid content")
    }
  }
}

///|
test "images validate size before decoding and reject noncanonical base64" {
  try
    @openseek_protocol.Image::from_base64(
      media_type="image/png",
      "A".repeat(6990509),
    )
  catch {
    TooLarge => ()
    error => raise error
  } noraise {
    _ => fail("oversized encoded data accepted")
  }
  for data in ["iVBORw0KGgo", "iVBORw0KGgp=", "iVBORw0KGgo=\n"] {
    try
      @openseek_protocol.Image::from_base64(media_type="image/png", data)
    catch {
      InvalidBase64 => ()
      error => raise error
    } noraise {
      _ => fail("noncanonical base64 accepted")
    }
  }
}

///|
test "text helpers ignore image bytes but search across text parts" {
  let image = @openseek_protocol.Image::from_base64(
    media_type="image/png",
    "iVBORw0KGgo=",
  )
  let content = @openseek_protocol.Content([
    Text("be"),
    Image(image),
    Text("fore"),
  ])
  assert_eq(content.text(), "before")
  assert_true(content.contains("before"))
  assert_false(content.contains("iVBOR"))
  assert_false(content.is_text_only())
  assert_eq(image.data_url(), "data:image/png;base64,iVBORw0KGgo=")
}
