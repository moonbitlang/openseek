///|
test "preview codec accepts only supported document MIME types and required content" {
  for
    media_type in [
      "image/png", "image/jpeg", "image/gif", "image/webp", "application/pdf",
    ] {
    let content : @protocol.FilePreviewContent = {
      media_type,
      data_base64: "AA==",
    }
    let decoded : @protocol.FilePreviewContent = @json.from_json(
      content.to_json(),
    )
    assert_eq(decoded, content)
  }
  for
    value in [
      Json::null(),
      { "media_type": "image/png" },
      { "media_type": "image/png", "data_base64": 0 },
      { "media_type": "text/html", "data_base64": "AA==" },
      { "media_type": "image/svg+xml", "data_base64": "AA==" },
    ] {
    let decoded : @protocol.FilePreviewContent? = Some(@json.from_json(value)) catch {
      _ => None
    }
    assert_true(decoded is None)
  }
}
