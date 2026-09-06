///|
/// Project the application data that the transcript package renders. The
/// component owns scroll position; the root owns durable conversation data.
///
/// The component stays mounted while onboarding is on screen — the root view
/// simply does not place it — so a model with no conversation projects an
/// empty transcript rather than inventing one to read.
fn Model::transcript_projects(
  self : Model,
) -> Array[@transcript_component.ProjectChoice] {
  guard self.focused_device() is Some(dev) else { return [] }
  [
    for root in dev.projects => { root, label: @resource.label(root), }
  ]
}

///|
fn Model::transcript_input(self : Model) -> @transcript_component.Input {
  let projects = self.transcript_projects()
  match self.screen {
    Codex => {
      let placement = self.codex.active_placement(self.focused)
      let project_label = placement
        .bind(value => value.project_root())
        .map(project => @resource.label(project))
      @transcript_component.Input(
        source=@transcript_component.Codex,
        focused=self.focused,
        active_session=self.codex.active_id().unwrap_or("none"),
        project_label?,
        current_project=placement.bind(value => value.project_root()),
        projects~,
        can_choose_project=false,
        project_menu_open=false,
        project_query="",
        root=placement.bind(value => value.checkout_root()),
        submission_generation=0,
        items=@transcript_component.VisibleRow::history(
          self.codex.transcript_items(),
        ),
        streaming_response=None,
        streaming_identity="idle",
      )
    }
    _ =>
      match self.active_conversation() {
        None =>
          @transcript_component.Input(
            source=@transcript_component.OpenSeek,
            focused=self.focused,
            active_session=self.active_session,
            current_project=None,
            projects~,
            can_choose_project=false,
            project_menu_open=false,
            project_query="",
            root=None,
            submission_generation=self.submission_sequence,
            items=[],
            streaming_response=None,
            streaming_identity="",
          )
        Some(conversation) => {
          let (streaming_reasoning, reasoning_complete) = conversation.reasoning_for_render()
          let can_choose_project = self.can_choose_new_chat_project()
          @transcript_component.Input(
            source=@transcript_component.OpenSeek,
            focused=self.focused,
            active_session=self.active_session,
            project_label=@resource.label(conversation.project()),
            current_project=Some(conversation.project()),
            projects~,
            can_choose_project~,
            project_menu_open=can_choose_project &&
              self.select_menu == Some(ProjectMenu),
            project_query=self.project_menu_query,
            root=self
              .conversation_placement(conversation)
              .bind(value => value.checkout_root()),
            submission_generation=self.submission_sequence,
            items=conversation.visible_transcript_rows(),
            streaming_response=conversation.turn.streaming_response,
            streaming_reasoning?,
            reasoning_complete~,
            streaming_identity=conversation.streaming_render_identity(),
          )
        }
      }
  }
}
