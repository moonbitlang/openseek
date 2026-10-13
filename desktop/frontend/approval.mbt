///|
/// Decode write contents once when an approval arrives, including replayed
/// approvals. Preserve the original body if it is not a write argument object.
fn approval_display_body(tool_name : String, body : String?) -> String? {
  if tool_name == "write" && body is Some(raw) {
    let value = @json.parse(raw) catch { _ => return body }
    if value is Object(fields) && fields.get("content") is Some(String(content)) {
      return Some(content)
    }
  }
  body
}
