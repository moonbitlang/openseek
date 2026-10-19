///|
pub(all) enum RouteError {
  OutsideApplication
  InvalidRoute
} derive(Eq)

///|
fn decode_segment(part : StringView) -> String? {
  guard !part.iter().any(ch => ch == '\\' || ch == '?' || ch == '#') else {
    return None
  }
  let decoded = @percent.decode(part) catch { _ => return None }
  guard !decoded.is_empty() &&
    decoded != "." &&
    decoded != ".." &&
    !decoded.iter().any(ch => ch.is_control()) else {
    return None
  }
  Some(decoded)
}

///|
/// Cloud pathnames, valid or not, do not belong to any device.
pub fn is_cloud_path(path : String) -> Bool {
  path == "/cloud" || path.has_prefix("/cloud/")
}

///|
/// Pathnames served by the application document, valid or not. Anything else
/// is outside the application, such as the bundle's own resources.
pub fn is_application_path(path : String) -> Bool {
  path.has_prefix("/device/") || is_cloud_path(path)
}

///|
/// Identify the device even when the remainder is an invalid application
/// target. None means that the pathname has no valid device identity.
pub fn device(path : String) -> String? {
  guard path.has_prefix("/device/") else { return None }
  path.split("/").drop(2).next().bind(decode_segment)
}

///|
/// Parse an application pathname, not a full URL. Reserved characters in
/// identities must be percent-encoded; query and fragment belong to the caller.
pub fn parse(path : String) -> Result[Location, RouteError] {
  guard is_application_path(path) else { return Err(OutsideApplication) }
  guard !path
    .iter()
    .any(ch => ch == '\\' || ch == '?' || ch == '#' || ch.is_control()) else {
    return Err(InvalidRoute)
  }
  if path == "/cloud" {
    return Ok({ device: None, target: Cloud, })
  }
  if path.has_prefix("/cloud/") {
    let parts = path.split("/").collect()
    return match parts {
      ["", "cloud", "session", id] =>
        match decode_segment(id) {
          Some(session) =>
            Ok({ device: None, target: CloudSession(account=None, session~), })
          None => Err(InvalidRoute)
        }
      ["", "cloud", "draft", id] =>
        match decode_segment(id) {
          Some(id) =>
            Ok({ device: None, target: CloudDraft(account=None, id~), })
          None => Err(InvalidRoute)
        }
      _ => Err(InvalidRoute)
    }
  }
  let parts : Array[String] = []
  for part in path.split("/").drop(2) {
    guard decode_segment(part) is Some(decoded) else {
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
  Ok({ device: Some(device), target, })
}

///|
/// Encode an application target; account identity never enters the URL.
pub fn Location::path(self : Location) -> String? {
  match self.target {
    Cloud => return Some("/cloud")
    CloudSession(session~, ..) =>
      return Some("/cloud/session/" + @percent.encode(session))
    CloudDraft(id~, ..) => return Some("/cloud/draft/" + @percent.encode(id))
    _ => ()
  }
  guard self.device is Some(device) else { return None }
  let suffix = match self.target {
    Cloud | CloudSession(..) | CloudDraft(..) => return None
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
  Some("/device/" + @percent.encode(device) + "/" + suffix)
}

///|
pub extend RouteError with Eq::{equal, not_equal}
