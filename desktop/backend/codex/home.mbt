// The isolated Codex home this Desktop process hands to its app-server.
//
// Codex's own `CODEX_HOME` (default `~/.codex`) holds the CLI's auth, config,
// threads, logs, and managed worktrees. The Desktop deliberately does not
// share it: the app-server it spawns gets a dedicated home under the per-user
// runtime directory, so nothing the integration runs can read or write the
// CLI's state, and clearing the app's runtime state removes every Codex
// artifact the Desktop ever created. The costs are deliberate too: a fresh
// login (auth.json lives in the home), Codex's default sandbox and approval
// configuration instead of the user's CLI config, an empty sidebar until
// Desktop threads exist, and separate managed worktrees.
// See docs/codex-app-server.md.

///|
/// The directory name for the isolated Codex home inside the per-user
/// runtime directory.
const HomeDirName : String = "codex"

///|
/// Prepare the isolated home before spawning Codex. Failure is explicit:
/// callers must never fall back to the inherited global CODEX_HOME.
async fn prepare_home_directory(home : @pathx.Path) -> Unit {
  try {
    @fs.mkdir(home.to_string(), recursive=true, permission=0o700) catch {
      @os_error.OSError(_) as error if error.is_EEXIST() => ()
      error => raise error
    }
    guard @fs.kind(home.to_string()) is Directory else {
      raise CodexError::Unavailable(
        "The isolated Codex home is not a directory",
      )
    }
    if !(@async.platform is Windows) {
      @fs.chmod(home.to_string(), 0o700)
    }
  } catch {
    error =>
      raise CodexError::Unavailable(
        "Could not prepare isolated Codex home \{home}: \{error}",
      )
  }
}
