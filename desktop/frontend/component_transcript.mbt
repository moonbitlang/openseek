///|
/// Project the application data that the transcript package renders. The
/// component owns scroll position; the root owns durable conversation data.
fn Model::transcript_input(self : Model) -> @transcript_component.Input {
  let conversation = self.active()
  @transcript_component.Input(
    focused=self.focused,
    active_session=self.active_session,
    root=self.conversation_root(conversation),
    submission_generation=self.submission_sequence,
    items=conversation.visible_transcript_rows(),
    streaming_response=conversation.streaming_response,
    streaming_identity=conversation.streaming_render_identity(),
    subruns=conversation.visible_subruns(),
  )
}
