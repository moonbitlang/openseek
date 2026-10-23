///|
fn Conversation::session_view(
  self : Conversation,
) -> @transcript.SessionLoadView {
  @transcript.session_from_reply({
    session: self.document,
    watermark: None,
    prediction: None,
  })
}

///|
pub fn Conversation::items(
  self : Conversation,
) -> Array[@transcript.TranscriptItem] {
  let items = self.session_view().items
  if !self.history_required && self.notice is Some(message) {
    items.push({ kind: Failure(message), ts: None, sequence: None, })
  }
  items
}
