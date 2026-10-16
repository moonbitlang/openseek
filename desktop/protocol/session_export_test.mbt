///|
test "export content requires both files and preserves their exact bytes" {
  let content : @protocol.SessionExportContent = {
    html: "<p>中文</p>",
    json: "{\"text\":\"quote\\\"\"}",
  }
  let decoded : @protocol.SessionExportContent = @json.from_json(
    content.to_json(),
  )
  assert_eq(decoded, content)
  for
    value in [
      Json::null(),
      { "html": "ok" },
      { "json": "{}" },
      { "html": Json::null(), "json": "{}" },
      { "html": "ok", "json": 7 },
    ] {
    let decoded : @protocol.SessionExportContent? = Some(@json.from_json(value)) catch {
      _ => None
    }
    assert_true(decoded is None)
  }
}
