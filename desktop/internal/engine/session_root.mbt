// Where a conversation's durable record lives: the session store root shared
// with the CLI/TUI.

///|
/// Where durable sessions live when a run names a session: the payload's
/// explicit root, then the OPENSEEK_SESSION_ROOT environment, then a stable
/// absolute default under the user's home directory. The absolute fallback
/// matters because a packaged app can run with `/` as its working directory,
/// where the engine's relative `.openseek` default could never be created.
fn resolved_session_root(payload_root? : @path.Path) -> @path.Path? {
  if payload_root is Some(root) {
    return Some(root.resolve())
  }
  if @env.get("OPENSEEK_SESSION_ROOT") is Some(root) {
    return Some(@path.Path(root).resolve())
  }
  home_session_root()
}

///|
fn home_session_root() -> @path.Path? {
  guard @home.dir() is Some(home) else { return None }
  Some(home.join(".openseek").normalize())
}
