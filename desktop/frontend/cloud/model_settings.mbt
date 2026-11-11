///|
/// The shown choice may still be pending or failed; Session keeps only values
/// confirmed by the server, so inventory refreshes cannot erase an unsaved pick.
pub fn State::inference(
  self : State,
  id : String,
) -> (@deepseek.DsVariant, @protocol.OpenSeekThinking) {
  if self.creation is Some({ id: draft, model, thinking, .. }) && draft == id {
    return (model, thinking)
  }
  if self.metadata_saves.get(id)
    is Some({ edit: SetInference(model~, thinking~), .. }) {
    return (model, thinking)
  }
  match self.sessions.iter().find_first(session => session.id == id) {
    Some(session) => (session.model, session.thinking)
    None => (V4Flash, ThinkingHigh)
  }
}

///|
pub fn State::saving_metadata(self : State, id : String) -> Bool {
  self.metadata_saves.get(id).map_or(false, save => save.error is None)
}

///|
pub fn State::inference_ready(self : State, id : String) -> Bool {
  !(self.metadata_saves.get(id) is Some({ edit: SetInference(..), .. }))
}

///|
/// Changing the next turn's model is allowed while the current turn runs.
/// One metadata request at a time keeps PATCH and subsequent sends ordered.
/// TODO: An already queued turn can start before PATCH reaches the server;
/// atomically changing its settings would require a server-side ordering contract.
pub fn State::can_choose_inference(self : State, id : String) -> Bool {
  self.user_id is Some(_) &&
  self.can_compose(id) &&
  !self.retired.contains(id) &&
  !self.deletions.contains(id) &&
  (
    !self.metadata_saves.contains(id) ||
    self.metadata_saves.get(id)
    is Some({ edit: SetInference(..), error: Some(_), .. })
  ) &&
  self.conversations
  .get(id)
  .map_or(true, conversation => {
    conversation.outgoing is None && !conversation.sending
  })
}
