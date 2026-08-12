///|
/// Project the application data that the transcript package renders. The
/// component owns scroll position; the root owns durable conversation data.
fn Model::transcript_input(self : Model) -> @transcript_component.Input {
  let conversation = self.active()
  @transcript_component.Input(
    focused=self.focused,
    active_session=self.active_session,
    items=conversation.visible_items(),
    streaming_response=conversation.streaming_response,
    subruns=conversation.visible_subruns(),
  )
}
