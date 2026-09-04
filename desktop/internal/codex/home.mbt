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
/// The isolated Codex home for this Desktop process: a `codex` subdirectory
/// of the per-user runtime directory. Pure, so tests and callers can predict
/// the path without touching the filesystem.
pub fn home_dir(runtime_dir : @pathx.Path) -> @pathx.Path {
  runtime_dir.join(HomeDirName).normalize()
}

///|
/// Create the isolated Codex home so the app-server can write auth, config,
/// threads, and worktrees before its first spawn, and restrict it to the
/// owner on POSIX hosts (auth.json and private tool credentials live here).
/// Best-effort: `None` leaves the app-server on the inherited environment,
/// which is the pre-isolation behavior.
pub async fn prepared_home(runtime_dir : @pathx.Path) -> @pathx.Path? {
  let home = home_dir(runtime_dir)
  // Recursive mkdir on an existing directory raises EEXIST; the steady
  // state is "created by an earlier launch", not an error.
  @fs.mkdir(home.to_string(), recursive=true) catch {
    error if @async.is_being_cancelled() => raise error
    @os_error.OSError(_) as os_error if os_error.is_EEXIST() => ()
    error => {
      @xlog.warn(category="codex") <?
        {
          "event": "codex_home_mkdir_failed",
          "path": home.to_string(),
          "error": "\{error}",
        }
      return None
    }
  }
  // `auth.json` is encrypted by the OS keychain, but the home also holds
  // MCP server config and private tool state; keep it owner-only on POSIX.
  // Windows has no chmod, so the ACLs of the per-user runtime directory
  // are the protection boundary there.
  if !(@platform.win32 || @platform.win64) {
    @fs.chmod(home.to_string(), 0o700) catch {
      error if @async.is_being_cancelled() => raise error
      error =>
        @xlog.warn(category="codex") <?
          {
            "event": "codex_home_chmod_failed",
            "path": home.to_string(),
            "error": "\{error}",
          }
    }
  }
  Some(home)
}

///|
test "codex home is a codex subdirectory of the runtime dir" {
  let home = home_dir(Path("/tmp/openseek-state"))
  assert_eq(home.to_string(), "/tmp/openseek-state/codex")
}

///|
async test "prepared codex home creates the directory" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-codex-home-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let home = prepared_home(root)
  guard home is Some(home) else { fail("codex home was not prepared") }
  assert_eq(home, home_dir(root))
  assert_true(@fs.kind(home.to_string()) is Directory)
  // Preparing an existing home must succeed too: that is the steady state
  // of every launch after the first.
  guard prepared_home(root) is Some(_) else {
    fail("codex home was not prepared again")
  }
}
