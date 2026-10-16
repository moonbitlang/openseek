///|
fn Model::navigation_location(self : Model) -> @navigation.Location? {
  guard self.console.page_device is Some(device) else { return None }
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
      if self.selected_conversation is Some(selection) &&
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
  Some({ device, target, })
}

///|
fn navigation_screen(target : @navigation.Target) -> Screen {
  match target {
    Chat | ChatNew | Session(_) | ChatDraft(_) => Chat
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
    Some(location.device) == self.console.page_device &&
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
