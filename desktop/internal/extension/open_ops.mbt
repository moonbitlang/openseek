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
  let code = @platform.open_path(target) catch {
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
