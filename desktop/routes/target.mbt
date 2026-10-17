///|
/// Addressable surfaces. Draft identities belong to this running client;
/// durable identities can be resolved after refresh. No content lives here.
pub(all) enum Target {
  Chat
  ChatNew
  Session(String)
  ChatDraft(String)
  Codex
  CodexNew
  Thread(String)
  CodexDraft(String)
  Settings
  Skills
  InstalledSkill(String)
  MarketSkill(String)
  Schedules
} derive(Eq)

///|
pub(all) struct Location {
  device : String
  target : Target
} derive(Eq)

///|
pub extend Target with Eq::{equal, not_equal}

///|
pub extend Location with Eq::{equal, not_equal}
