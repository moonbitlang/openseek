///|
const DefaultCodexCommand : String = "codex"

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
