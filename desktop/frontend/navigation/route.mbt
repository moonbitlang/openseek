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
pub(all) enum RouteError {
  OutsideApplication
  InvalidRoute
} derive(Eq)

///|
pub fn parse(path : String) -> Result[Location, RouteError] {
  guard path.has_prefix("/device/") else { return Err(OutsideApplication) }
  let parts : Array[String] = []
  for part in path.split("/").drop(2) {
    let decoded = @percent.decode(part) catch { _ => return Err(InvalidRoute) }
    guard !decoded.is_empty() &&
      decoded != "." &&
      decoded != ".." &&
      !decoded.iter().any(ch => ch.is_control()) else {
      return Err(InvalidRoute)
    }
    parts.push(decoded)
  }
  guard parts is [device, .. rest] else { return Err(InvalidRoute) }
  let target = match rest {
    ["chat"] => Chat
    ["chat", "new"] => ChatNew
    ["chat", "session", id] => Session(id)
    ["chat", "draft", id] => ChatDraft(id)
    ["codex"] => Codex
    ["codex", "new"] => CodexNew
    ["codex", "thread", id] => Thread(id)
    ["codex", "draft", id] => CodexDraft(id)
    ["settings"] => Settings
    ["skills"] => Skills
    ["skills", "installed", id] => InstalledSkill(id)
    ["skills", "market", source] => MarketSkill(source)
    ["schedules"] => Schedules
    _ => return Err(InvalidRoute)
  }
  Ok({ device, target, })
}

///|
pub fn Location::path(self : Location) -> String {
  let suffix = match self.target {
    Chat => "chat"
    ChatNew => "chat/new"
    Session(id) => "chat/session/" + @percent.encode(id)
    ChatDraft(id) => "chat/draft/" + @percent.encode(id)
    Codex => "codex"
    CodexNew => "codex/new"
    Thread(id) => "codex/thread/" + @percent.encode(id)
    CodexDraft(id) => "codex/draft/" + @percent.encode(id)
    Settings => "settings"
    Skills => "skills"
    InstalledSkill(id) => "skills/installed/" + @percent.encode(id)
    MarketSkill(source) => "skills/market/" + @percent.encode(source)
    Schedules => "schedules"
  }
  "/device/" + @percent.encode(self.device) + "/" + suffix
}

///|
pub extend Target with Eq::{equal, not_equal}

///|
pub extend Location with Eq::{equal, not_equal}

///|
pub extend RouteError with Eq::{equal, not_equal}
