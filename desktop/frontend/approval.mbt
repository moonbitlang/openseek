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

///|
/// Host message approvals outlive a turn. Restore the next outstanding card
/// after lifecycle transitions clear an engine-owned question. Engine questions
/// have priority, since their tool is blocked until the user answers.
fn Model::restore_message_approvals(self : Model) -> Model {
  if !self.devices.any(device => {
      device.approval_snapshot.map_or(false, snapshot => {
        snapshot.approvals.any(item => item.approval.run_id is None)
      })
    }) &&
    !self.conversations.any(conv => {
      conv.pending_approval is Some({ run_id: None, .. })
    }) {
    return self
  }
  {
    ..self,
    conversations: self.conversations.map(conv => {
      if conv.pending_approval is Some({ run_id: Some(_), .. }) {
        return conv
      }
      guard self.device_state(conv.device) is Some(device) &&
        device.approval_snapshot is Some(snapshot) else {
        return conv
      }
      let pending = snapshot.approvals
        .iter()
        .find_first(item => {
          item.session == conv.session_id && item.approval.run_id is None
        })
        .map(item => {
          let answered_here = conv.pending_approval.map_or(false, previous => {
            previous.id == item.approval.id && previous.answered
          })
          {
            ..item.approval,
            answered: item.approval.answered || answered_here,
          }
        })
      { ..conv, pending_approval: pending, }
    }),
  }
}
