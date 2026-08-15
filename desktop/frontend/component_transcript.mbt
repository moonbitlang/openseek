///|
/// Project the application data that the transcript package renders. The
/// component owns scroll position; the root owns durable conversation data.
fn Model::transcript_input(self : Model) -> @transcript_component.Input {
  match self.screen {
    Codex => {
      let placement = self.codex.active_placement(self.focused)
      @transcript_component.Input(
        source=@transcript_component.Codex,
        focused=self.focused,
        active_session=self.codex.active_id().unwrap_or("none"),
        root=placement.bind(value => value.checkout_root()),
        submission_generation=0,
        items=@transcript_component.VisibleRow::history(
          self.codex.transcript_items(),
        ),
        streaming_reasoning="",
        streaming_response="",
        streaming_identity="idle",
        subruns=[],
      )
    }
    _ => {
      let conversation = self.active()
      let placement = self.conversation_placement(conversation)
      @transcript_component.Input(
        source=@transcript_component.OpenSeek,
        focused=self.focused,
        active_session=self.active_session,
        root=placement.bind(value => value.checkout_root()),
        submission_generation=self.submission_sequence,
        items=conversation.visible_transcript_rows(),
        streaming_reasoning=conversation.streaming_reasoning,
        streaming_response=conversation.streaming_response,
        streaming_identity=conversation.streaming_render_identity(),
        subruns=conversation.visible_subruns(),
      )
    }
  }
}
