///|
test "remote export limits the escaped UTF-8 wire reply" {
  let html = "<p>中文</p>"
  let json = "{\"text\":\"\\u0000\"}"
  let expected : @protocol.SessionExportContent = { html, json, }
  let wire_bytes = @utf8.encode(expected.to_json().stringify()).length()
  assert_eq(checked_export_content(html, json, max_bytes=wire_bytes), expected)
  try {
    ignore(checked_export_content(html, json, max_bytes=wire_bytes - 1))
    fail("oversized encoded reply entered the transport")
  } catch {
    @host.HostError(_) => ()
    error => raise error
  }
}
