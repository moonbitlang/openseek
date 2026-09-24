// Where a conversation's durable record lives: the session store root shared
// with the CLI/TUI.

///|
/// Where durable sessions live when a run names a session: the payload's
/// explicit root, then a stable absolute default under the user's home
/// directory. The absolute fallback matters because a packaged app can run
/// with `/` as its working directory, where the engine's relative `.openseek`
/// default could never be created.
pub fn global_store_root(payload_root? : @pathx.Path) -> @pathx.Absolute? {
  if payload_root is Some(root) {
    return Some(root.resolve())
  }
  home_session_root()
}

///|
fn home_session_root() -> @pathx.Absolute? {
  guard @home.dir() is Some(home) else { return None }
  // HOME remains unclassified input, but resolving the derived store here
  // establishes the guarantee consumed by the session subsystem.
  Some(home.join(".openseek").resolve())
}

// Tests for resolving explicit durable-session roots before the host shares
// them with engine processes and one-shot session queries.
