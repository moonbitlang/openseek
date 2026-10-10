///|
/// Only unsent client data is retained. Server account, thread activity,
/// requests and catalogs always remain the current state.
priv struct NavigationDraft {
  task : CodexDraftTask
  addressed : Bool
  text : String
  mentions : Array[@composer.Mention]
  images : Array[@composer.Image]
  placement : @composer.WorktreeChoice
} derive(Eq)

///|
fn State::retain_navigation_draft(self : State) -> State {
  guard self.active_draft() is Some(task) else { return self }
  let saved : NavigationDraft = {
    task,
    addressed: self.navigation_target() is CodexDraft(_),
    text: self.draft,
    mentions: self.mentions,
    images: self.images,
    placement: self.placement,
  }
  let drafts = self.saved_drafts.filter(entry => entry.task.id != task.id)
  drafts.push(saved)
  { ..self, saved_drafts: drafts, }
}

///|
pub fn State::restore_navigation_draft(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  id : String,
) -> (@cmd.Cmd, State)? {
  if self.active_draft() is Some(task) && task.id == id {
    return Some((@cmd.none, self))
  }
  let retained = self.retain_navigation_draft()
  guard retained.saved_drafts.iter().find_first(entry => entry.task.id == id)
    is Some(saved) else {
    return None
  }
  let restored = {
    ..retained.select_draft(saved.task.id, saved.task.cwd),
    selection: CodexDraftTask(saved.task),
    draft: saved.text,
    draft_addressed: saved.addressed,
    mentions: saved.mentions,
    images: saved.images,
    placement: saved.placement,
  }
  Some(restored.activate_draft_context(dispatch, channel))
}

///|
/// New and restored drafts acquire their context through the same effects.
/// A pending workspace acknowledgement must be reissued when returning to a
/// draft; an already confirmed workspace still needs a fresh skills catalog.
fn State::activate_draft_context(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> (@cmd.Cmd, State) {
  guard self.active_draft() is Some(task) else { return (@cmd.none, self) }
  if task.project_root is Some(_) {
    let next = self.loading_context(false)
    (next.load_skills(dispatch, channel, force_reload=false), next)
  } else if !task.cwd.is_empty() {
    (
      self.open_draft(dispatch, channel, task.id, task.cwd),
      self.begin_foreground(CodexDraftOpenReply(task.id)),
    )
  } else {
    (@cmd.none, self)
  }
}

///|
pub fn State::navigation_target(self : State) -> @navigation.Target {
  if self.requested_thread is Some(id) {
    return Thread(id)
  }
  match self.selection {
    CodexNoTask => CodexNew
    CodexDraftTask(task) =>
      if self.draft_addressed ||
        !self.draft.is_empty() ||
        !self.mentions.is_empty() ||
        !self.images.is_empty() {
        CodexDraft(task.id)
      } else {
        CodexNew
      }
    CodexStoredTask(thread) => Thread(thread.id)
  }
}

///|
/// Leave the selected task without discarding an unsent draft's content.
pub fn State::prepare_new_navigation(self : State) -> State {
  {
    ..self.retain_navigation_draft(),
    selection: CodexNoTask,
    requested_thread: None,
    foreground: None,
    loading: false,
    draft: "",
    mentions: [],
    images: [],
    draft_addressed: false,
    submitted_first_prompt: None,
    notice: "",
  }
}
