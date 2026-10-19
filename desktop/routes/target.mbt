///|
/// Addressable surfaces. Draft identities belong to this running client;
/// durable identities can be resolved after refresh. No content lives here.
pub(all) enum Target {
  Chat
  ChatNew
  Session(String)
  ChatDraft(String)
  Cloud
  // URL parsing leaves the account unresolved until authentication completes.
  CloudSession(account~ : String?, session~ : String)
  // A page-local composer entry; its ID is never a Cloud session ID.
  CloudDraft(account~ : String?, id~ : String)
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
/// Cloud destinations belong to the signed-in account, not to a device.
pub fn Target::is_cloud(self : Target) -> Bool {
  self is (Cloud | CloudSession(..) | CloudDraft(..))
}

///|
pub(all) struct Location {
  device : String?
  target : Target
} derive(Eq)

///|
pub extend Target with Eq::{equal, not_equal}

///|
pub extend Location with Eq::{equal, not_equal}
