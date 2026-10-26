///|
/// Mark a programmatic submission without consuming or recovering the user's
/// editable draft. The shared composer owns recovery of the result itself.
pub fn Conversation::with_command_result(
  self : Conversation,
  before : Conversation,
  id : String,
) -> (Conversation, Bool) {
  let mut found = false
  let pending = self.pending.map(pending => {
    found = true
    { ..pending, result_id: Some(id), }
  })
  let control_inputs = self.control_inputs.map(input => {
    if !before.control_inputs.any(old => old.key == input.key) {
      found = true
      { ..input, result_id: Some(id), }
    } else {
      input
    }
  })
  (
    {
      ..self,
      pending,
      control_inputs,
      queue_edit: before.queue_edit,
      initial_submission: before.initial_submission,
      initial_attachments: before.initial_attachments,
    },
    found,
  )
}
