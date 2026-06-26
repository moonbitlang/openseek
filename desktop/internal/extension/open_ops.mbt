// Opening a transcript-referenced file in the user's system: the host makes
// the path absolute against the conversation's working directory and hands it
// to the platform's default "open" command, which routes the file to whatever
// app the user has associated with it. The agent surfaced the path and the
// user clicked it, so there is no workspace-containment check.

///|
async fn open_path_op(payload : OpenPathPayload) -> OpenPathReply {
  // A live run hands us its cwd; a resumed conversation has none, so fall back
  // to the directory the session's engine runs in.
  let base = if payload.cwd.is_empty() {
    @engine.session_cwd(payload.session)
  } else {
    payload.cwd
  }
  let target = @engine.open_target(base, expand_home(payload.path))
  guard !target.is_empty() else { raise HostError("Empty path") }
  let code = run_system_open(target) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("Could not open \{target}: \{error}")
  }
  guard code == 0 else { raise HostError("Could not open \{target}") }
  { opened: true }
}

///|
/// Expand a leading `~` (the agent often writes paths home-relative) to the
/// user's home directory; other paths pass through for `open_target` to take
/// against the working directory.
fn expand_home(path : String) -> String {
  if path == "~" && @home.dir() is Some(home) {
    home.to_string()
  } else if path.strip_prefix("~/") is Some(rest) && @home.dir() is Some(home) {
    home.join(Path(rest.to_owned())).to_string()
  } else {
    path
  }
}

///|
/// Launch the platform's default opener for `path`. The opener returns as soon
/// as it has handed the file off (LaunchServices on macOS, the desktop portal
/// on Linux), so its exit code reports the hand-off, not the app's lifetime.
#cfg(platform="windows")
async fn run_system_open(path : String) -> Int {
  // `start` is a `cmd` builtin, so it cannot be spawned directly; the empty
  // "" is its (otherwise required) window-title argument.
  @process.run("cmd", ["/c", "start", "", path])
}

///|
/// MoonBit's `platform` cfg only distinguishes Windows, so macOS and Linux —
/// which need different openers (`open` vs `xdg-open`) — are told apart at
/// runtime by `uname`.
#cfg(not(platform="windows"))
async fn run_system_open(path : String) -> Int {
  if uname_is_darwin() {
    // Respect the file's app association, but fall back to the default text
    // editor for types with none — source files like `.mbt` have no associated
    // app, and plain `open` rejects them with "no application knows how to
    // open" (exit non-zero) rather than showing their contents.
    let code = @process.run("open", [path])
    if code == 0 {
      code
    } else {
      @process.run("open", ["-t", path])
    }
  } else {
    @process.run("xdg-open", [path])
  }
}

///|
#cfg(not(platform="windows"))
async fn uname_is_darwin() -> Bool {
  let (code, stdout, _) = @process.collect_output("uname", ["-s"]) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  guard code == 0 else { return false }
  let name = (stdout.text() catch { _ => "" }).trim()
  name == "Darwin"
}
