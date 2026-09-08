///|
/// Keep the selected jobs visible even when the arguments disclosure is shut.
/// Pending is already part of the normal tool lifecycle; no new run state.
fn pending_job_wait_label(call : @transcript.ToolCall) -> String? {
  guard call.name == "job_wait" &&
    call.outcome is Pending(..) &&
    call.arguments is Some(arguments) else {
    return None
  }
  let args = @json.parse(arguments) catch { _ => return None }
  guard args is { "job_ids": Array(values), .. } && !values.is_empty() else {
    return None
  }
  let ids : Array[String] = []
  for value in values {
    guard value is String(id) && !id.is_blank() else { return None }
    if !ids.contains(id) {
      ids.push(id)
    }
  }
  Some("Waiting for \{ids.join(", ")}")
}
