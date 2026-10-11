// One Codex app-server configuration for a Desktop process: the command the
// login-shell PATH resolves, and the isolated home handed to every spawn.

///|
/// `command` is the executable name resolved from the login-shell `PATH`
/// (`codex` by default); `home` is the isolated `CODEX_HOME` the app-server
/// spawn receives. `None` falls back to the inherited environment.
pub struct CodexSettings {
  command : String
  home : @pathx.Path?
}

///|
/// The default settings: the `codex` command with no isolated home.
pub fn CodexSettings::default() -> CodexSettings {
  { command: DefaultCodexCommand, home: None, }
}

///|
/// Explicit settings with the given command and isolated home.
pub fn CodexSettings::CodexSettings(
  command~ : String,
  home~ : @pathx.Path?,
) -> CodexSettings {
  { command, home, }
}
