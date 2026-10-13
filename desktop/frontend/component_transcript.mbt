///|
/// The conversation whose transcript the root view places on screen. It keys
/// the transcript component's lifetime (`Val::switch_by` in `boot`): a new
/// slot builds a fresh component whose `init` places the scroller and clears
/// overview state, and `None` disposes the current one. It derives from the
/// same `console_gate` and `chat_column` the view places the column from, so
/// the component exists exactly while its DOM does.
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
/// A page is gated on both its account session and its page device. Until
/// both exist the view shows the gate instead of the console frame, so no
/// transcript is on screen either. The desktop window has both from the
/// first render and is never gated.
fn Model::is_console_gated(self : Model) -> Bool {
  self.console.page_device is None ||
  !(self.console.auth is AuthSignedIn(..)) ||
  self.focused_device() is None
}

///|
/// What the Chat screen's conversation column shows. A chat needs a
/// conversation, and a conversation needs a project to work in, so with none
/// on screen — the registry has not arrived, or no project is attached — the
/// column is onboarding instead. The view places the column from this value
/// and the transcript component's lifetime follows it, so the fork is decided
/// once.
priv enum ChatColumn {
  LoadFailed(message~ : String)
  Loading
  Onboarding
  Transcript(slot~ : TranscriptSlot, conversation~ : Conversation)
}

///|
fn Model::chat_column(self : Model) -> ChatColumn {
  if self.conversation_load_failure is Some(failure) &&
    self.selected_conversation is Some(selected) &&
    selected == failure.target {
    return LoadFailed(message=failure.message)
  }
  if !self.selected_conversation_loaded() {
    return Loading
  }
  match self.active_conversation() {
    None => Onboarding
    Some(conversation) =>
      Transcript(
        slot={
          source: OpenSeek,
          channel: self.focused,
          session: Some(self.active_session),
        },
        conversation~,
      )
  }
}

///|
fn Model::transcript_slot(self : Model) -> TranscriptSlot? {
  guard !self.is_console_gated() else { return None }
  match self.screen {
    Codex =>
      Some({
        source: Codex,
        channel: self.focused,
        session: self.codex.active_id(),
      })
    Chat =>
      match self.chat_column() {
        Transcript(slot~, ..) => Some(slot)
        LoadFailed(..) | Loading | Onboarding => None
      }
    Skills | Schedules | Settings => None
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
    for root in dev.projects if !dev.is_chat_workspace(root) => {
      { root, label: @resource.label(root), }
    }
  ]
}

///|
/// Engine-owned content normalized before the shared transcript presentation.
priv struct TranscriptContent {
  source : @transcript_component.Source
  session : String
  project : @common.Uri?
  root : @common.Uri?
  items : Array[@transcript_component.VisibleRow]
  streaming_response : String?
  streaming_reasoning : String?
  reasoning_complete : Bool
  streaming_identity : String
}

///|
fn Model::transcript_content(self : Model) -> TranscriptContent {
  if self.screen is Codex {
    let placement = self.codex.active_placement(self.focused)
    {
      source: Codex,
      session: self.codex.active_id().unwrap_or("none"),
      project: match self.new_chat_project() {
        Ok(Some(project)) => Some(project)
        Ok(None) => placement.bind(value => value.project_root())
        // The root page renders this error beside the transcript.
        Err(_) => None
      },
      root: placement.bind(value => value.checkout_root()),
      items: @transcript_component.VisibleRow::history(
        self.codex.transcript_items(locale=self.locale),
      ),
      streaming_response: None,
      streaming_reasoning: None,
      reasoning_complete: false,
      streaming_identity: "idle",
    }
  } else if self.active_conversation() is Some(conversation) {
    let (streaming_reasoning, reasoning_complete) = conversation.reasoning_for_render()
    {
      source: OpenSeek,
      session: self.active_session,
      project: Some(conversation.project()),
      root: self
      .conversation_placement(conversation)
      .bind(value => value.checkout_root()),
      items: conversation.visible_transcript_rows(),
      streaming_response: conversation.turn.streaming_response,
      streaming_reasoning,
      reasoning_complete,
      streaming_identity: conversation.streaming_render_identity(),
    }
  } else {
    {
      source: OpenSeek,
      session: self.active_session,
      project: None,
      root: None,
      items: [],
      streaming_response: None,
      streaming_reasoning: None,
      reasoning_complete: false,
      streaming_identity: "",
    }
  }
}

///|
fn Model::transcript_input(self : Model) -> @transcript_component.Input {
  let content = self.transcript_content()
  let can_choose_project = self.can_choose_new_chat_project()
  @transcript_component.Input(
    locale=self.locale,
    dark_mode=self.theme.is_dark(self.system_dark),
    minimal=self.minimal_transcript_effective(),
    source=content.source,
    focused=self.focused,
    active_session=content.session,
    scroll=self.remembered_scroll(),
    project_label?=content.project.bind(project => {
      self.project_display_label(project)
    }),
    current_project=content.project,
    projects=self.transcript_projects(),
    can_choose_project~,
    project_menu_open=can_choose_project &&
      self.select_menu is Some(ProjectMenu),
    project_query=self.project_menu_query,
    root=content.root,
    items=content.items,
    streaming_response=content.streaming_response,
    streaming_reasoning?=content.streaming_reasoning,
    reasoning_complete=content.reasoning_complete,
    streaming_identity=content.streaming_identity,
  )
}

///|
fn Model::project_display_label(self : Model, project : @common.Uri) -> String? {
  if self.focused_device() is Some(dev) && dev.is_chat_workspace(project) {
    None
  } else {
    Some(@resource.label(project))
  }
}
