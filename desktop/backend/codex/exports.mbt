// Deliberate exports with no consumer inside the root `moon.work`; see
// shrink_package.md. Each block names the consumer `moon ide analyze` cannot
// see: the Desktop window host lives in `desktop/app`, a separate module with
// its own `moon.work`, and it uses these three items.

///|
/// The default `codex` executable name. `desktop/app` logs it and passes it to
/// its `CodexSettings`.
///
/// SeekMoon intentionally does not ship a Codex runtime. Desktop main has
/// already applied the user's login-shell environment before this value is
/// used, so process spawning resolves `codex` from that PATH. The actor's eager
/// `codex app-server` initialize handshake is the capability probe: a missing
/// command or an incompatible CLI reports the Codex source as unavailable.
pub fn command() -> String {
  DefaultCodexCommand
}

///|
/// The isolated Codex home for this Desktop process: a `codex` subdirectory of
/// the per-user runtime directory. Pure, so tests and callers can predict the
/// path without touching the filesystem.
///
/// `desktop/app` derives `CodexSettings.home` from it after resolving the
/// runtime directory.
pub fn home_dir(runtime_dir : @pathx.Path) -> @pathx.Path {
  runtime_dir.join(HomeDirName).normalize()
}

///|
/// Explicit settings with the given command and isolated home. `desktop/app`
/// is the only caller: it needs a non-default command and an isolated home,
/// while the rest of the workspace uses `default()`.
pub fn CodexSettings::CodexSettings(
  command~ : String,
  home~ : @pathx.Path?,
  require_home~ : Bool = false,
) -> CodexSettings {
  { command, home, require_home, }
}
