///|
const DefaultCodexCommand : String = "codex"

///|
/// SeekMoon intentionally does not ship a Codex runtime. Desktop main has
/// already applied the user's login-shell environment before this value is
/// used, so process spawning resolves `codex` from that PATH. The actor's eager
/// `codex app-server` initialize handshake is the capability probe: a missing
/// command or an incompatible CLI reports the Codex source as unavailable.
pub fn command() -> String {
  DefaultCodexCommand
}
