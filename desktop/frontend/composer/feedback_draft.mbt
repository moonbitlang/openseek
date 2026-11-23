///|
fn Identity::message_owner_key(self : Identity) -> String {
  "\{self.archive_generation}:\{self.owner.key()}"
}

///|
/// The browser may still hold the typed command when typing and submission are
/// processed in one render. Both rendered values are empty, so the DOM diff
/// skips the value write. Clear only the submitted text in its own empty draft.
fn clear_submitted_feedback_draft(
  identity : Identity,
  command : String,
) -> @cmd.Cmd {
  let owner = identity.message_owner_key()
  @cmd.custom_cmd(kind=@cmd.after_render, _ => {
    guard @dom.document().get_element_by_id(MessageInputId).to_option()
      is Some(input) &&
      input.get_attribute("data-empty-message-owner") == Some(owner) &&
      input.get_property("value").to_option() == Some(command) else {
      return
    }
    input.set_property("value", @js.Value::cast_from(""))
  })
}
