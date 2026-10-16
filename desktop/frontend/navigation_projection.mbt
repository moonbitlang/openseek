///|
fn Model::navigation_location(self : Model) -> @navigation.Location? {
  let device = self.console.page_device
  if self.screen is Chat &&
    self.cloud.creating_at(self.chat_navigation_generation) {
    return None
  }
  let target : @navigation.Target = match self.screen {
    Settings => Settings
    Schedules => Schedules
    Skills =>
      match self.skills.detail() {
        Some(InstalledRef(id)) => InstalledSkill(id)
        Some(MarketRef(source)) => MarketSkill(source)
        None => Skills
      }
    Codex => self.codex.navigation_target()
    Chat =>
      if self.cloud_identity() is Some(@interop.Cloud(account~, session~)) {
        CloudSession(account~, session~)
      } else if self.host_selection() is Some(selection) &&
        self.loading_conversation is Some(_) {
        Session(selection.session)
      } else if self.active_conversation() is Some(conv) {
        if conv.has_begun() ||
          self
          .focused_device()
          .map_or(false, dev => {
            dev.sessions.any(item => item.id == conv.session_id) ||
            dev.archived.any(item => item.id == conv.session_id)
          }) {
          Session(conv.session_id)
        } else if conv.draft_addressed || !conv.draft_empty() {
          ChatDraft(conv.session_id)
        } else {
          ChatNew
        }
      } else {
        ChatNew
      }
  }
  match target {
    CloudSession(..) => Some({ device: None, target, })
    Settings => Some({ device, target, })
    _ => if device is Some(_) { Some({ device, target, }) } else { None }
  }
}

///|
fn navigation_screen(target : @navigation.Target) -> Screen {
  match target {
    Chat | ChatNew | Session(_) | ChatDraft(_) | CloudSession(..) => Chat
    Codex | CodexNew | Thread(_) | CodexDraft(_) => Codex
    Settings => Settings
    Skills | InstalledSkill(_) | MarketSkill(_) => Skills
    Schedules => Schedules
  }
}

///|
/// A management page can cover the draft whose project add is still pending.
/// Leaving that owner for a different work destination cancels its adoption.
fn Model::project_adoption_at(
  self : Model,
  location : @navigation.Location,
) -> ProjectAdoption? {
  guard self.pending_project_adoption is Some(pending) &&
    pending.channel == self.focused &&
    location.device is Some(device) &&
    Some(device) == self.console.page_device &&
    pending.codex_draft is Some(id) else {
    return None
  }
  match location.target {
    Settings | Skills | InstalledSkill(_) | MarketSkill(_) | Schedules =>
      self.pending_project_adoption
    CodexDraft(target) if target == id => self.pending_project_adoption
    CodexNew if self.codex.active_id() == Some(id) &&
      self.codex.navigation_target() is CodexNew =>
      self.pending_project_adoption
    _ => None
  }
}
