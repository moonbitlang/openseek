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

///|
/// Windows npm installs a codex.cmd shim. Native process spawning only
/// searches for .exe, so let cmd resolve the fixed default command through
/// PATH/PATHEXT. Explicit executable paths still use direct spawning.
fn app_server_launch(
  command : String,
  windows~ : Bool,
) -> (String, Array[String]) {
  if windows && command == DefaultCodexCommand {
    ("cmd.exe", ["/d", "/c", "codex", "app-server"])
  } else {
    (command, ["app-server"])
  }
}
