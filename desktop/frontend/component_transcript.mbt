///|
/// The conversation whose transcript the root view places on screen. It keys
/// the transcript component's lifetime (`Val::switch_by` in `boot`): a new
/// slot builds a fresh component whose `init` places the scroller and clears
/// overview state, and `None` disposes the current one. The view's own fork
/// — the console gate, Chat onboarding, loading, and load failure — is
/// mirrored here so the component exists exactly while its DOM does.
priv struct TranscriptSlot {
  source : @transcript_component.Source
  channel : @interop.ChannelId
  // The Codex page shows a transcript even before a task is selected.
  session : String?
} derive(Eq)

///|
fn TranscriptSlot::key(self : TranscriptSlot) -> String {
  let key = self.source.wire() + "\u{0}" + self.channel.uri_authority()
  match self.session {
    Some(session) => key + "\u{0}" + session
    None => key
  }
}

///|
fn Model::transcript_slot(self : Model) -> TranscriptSlot? {
  if self.console is Some(console) &&
    (
      console.page_device is None ||
      !(console.auth is AuthSignedIn(..)) ||
      self.focused_device() is None
    ) {
    return None
  }
  match self.screen {
    Codex =>
      Some({
        source: Codex,
        channel: self.focused,
        session: self.codex.active_id(),
      })
    Chat => {
      if self.conversation_load_failure is Some(failure) &&
        self.selected_conversation == Some(failure.target) {
        return None
      }
      guard self.selected_conversation_loaded() &&
        self.active_conversation() is Some(_) else {
        return None
      }
      Some({
        source: OpenSeek,
        channel: self.focused,
        session: Some(self.active_session),
      })
    }
    Skills | Settings | WorkspaceSettings(..) => None
  }
}

///|
/// Where the reader left the conversation on screen, if it has been on screen
/// before. A conversation never visited, or one that was pinned when left,
/// opens at its tail.
fn Model::remembered_scroll(
  self : Model,
) -> @transcript_component.ScrollPosition {
  guard self.transcript_slot() is Some(slot) else { return Pinned }
  self.transcript_scroll.get(slot.key()).unwrap_or(Pinned)
}

///|
/// Project the application data that the transcript package renders. The
/// component owns scroll position; the root owns durable conversation data.
///
/// The input is read only while a slot is on screen, but the switch may
/// recompute it while disposing a branch, so a model with no conversation
/// projects an empty transcript rather than inventing one to read.
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
        scroll=self.remembered_scroll(),
        project_label?,
        current_project=placement.bind(value => value.project_root()),
        projects~,
        can_choose_project=false,
        project_menu_open=false,
        project_query="",
        root=placement.bind(value => value.checkout_root()),
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
            scroll=self.remembered_scroll(),
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
