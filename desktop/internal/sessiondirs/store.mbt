// Where a conversation's durable record lives: the session store root shared
// with the CLI/TUI.

///|
/// Where durable sessions live when a run names a session: the payload's
/// explicit root, then the OPENSEEK_SESSION_ROOT environment, then a stable
/// absolute default under the user's home directory. The absolute fallback
/// matters because a packaged app can run with `/` as its working directory,
/// where the engine's relative `.openseek` default could never be created.
pub fn resolved_session_root(payload_root : String?) -> String? {
  if payload_root is Some(root) {
    return Some(resolve_explicit_session_root(root))
  }
  if @env.get("OPENSEEK_SESSION_ROOT") is Some(root) {
    return Some(resolve_explicit_session_root(root))
  }
  home_session_root()
}

///|
fn resolve_explicit_session_root(root : String) -> String {
  (root : @mbpath.Path).resolve().to_string()
}

///|
fn home_session_root() -> String? {
  guard @home.dir() is Some(home) else { return None }
  Some((home : @mbpath.Path).join(".openseek").normalize().to_string())
}
