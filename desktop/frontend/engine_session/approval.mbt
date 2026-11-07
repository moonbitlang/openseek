///|
/// The text an approval card shows for a question's body. Write arguments
/// become the file contents they carry; any other body, including one that
/// is not a write argument object, is shown as sent. Hosts decode once when
/// an approval arrives, including replayed approvals.
pub fn approval_display_body(tool_name : String, body : String?) -> String? {
  if tool_name == "write" && body is Some(raw) {
    let value = @json.parse(raw) catch { _ => return body }
    if value is Object(fields) && fields.get("content") is Some(String(content)) {
      return Some(content)
    }
  }
  body
}
