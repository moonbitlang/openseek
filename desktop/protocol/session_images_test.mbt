///|
test "session image references round trip without image data" {
  let reference : @protocol.SessionImageRef = {
    record: "/workspace/.openseek/sessions/a/record.jsonl",
    offset: 123L,
    length: 456,
    sequence: 2,
    part: 1,
  }
  let content : @protocol.SessionContent = SessionContent([
    Text("before"),
    ImageRef(reference),
    Text("after"),
  ])
  let encoded = content.to_json()
  let decoded : @protocol.SessionContent = @json.from_json(encoded)
  assert_eq(decoded, content)
  assert_eq(decoded.text(), "beforeafter")
  assert_false(encoded.stringify().contains("base64"))
  for field in ["record", "offset", "length", "sequence", "part"] {
    guard reference.to_json() is Object(fields) else { fail("expected object") }
    fields[field] = Json::null()
    let rejected : @protocol.SessionImageRef? = Some(
      @json.from_json(Json(fields)),
    ) catch {
      _ => None
    }
    assert_eq(rejected, None)
  }
  for
    invalid in [
      { ..reference, record: "", },
      { ..reference, offset: -1L, },
      { ..reference, length: 0, },
      { ..reference, sequence: 0, },
      { ..reference, part: -1, },
    ] {
    let rejected : @protocol.SessionImageRef? = Some(
      @json.from_json(invalid.to_json()),
    ) catch {
      _ => None
    }
    assert_eq(rejected, None)
  }
}
