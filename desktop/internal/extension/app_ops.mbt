// IPC adapters for the app launcher: resolve the conversation's working
// directory (mirroring `open_path`), apply the session/workspace guards, and
// delegate detection and launching to the `applauncher` package.

///|
async fn list_apps_op() -> ListAppsReply {
  let apps = @applauncher.list()
  { apps: apps.map(app => { id: app.id, name: app.name, icon: app.icon }) }
}

///|
async fn launch_app_op(payload : LaunchAppPayload) -> LaunchAppReply {
  // A live run hands us its cwd; a resumed conversation has none, so fall back
  // to the directory the session's engine runs in (same as `open_path`).
  let dir = if payload.cwd.is_empty() {
    @engine.session_cwd(payload.session)
  } else {
    payload.cwd
  }
  guard !dir.is_empty() else {
    raise HostError("This conversation has no working directory yet")
  }
  // The engine creates a conversation's workspace on its first run, so a chat
  // that has never run has no directory to open. The frontend disables the
  // launcher in that case; this is the backstop if one slips through.
  guard (@fs.exists(dir) catch { _ => true }) else {
    raise HostError(
      "This chat has no workspace yet — send a message to start it",
    )
  }
  @applauncher.launch(id=payload.app, dir~) catch {
    error if @async.is_being_cancelled() => raise error
    @applauncher.LauncherError(message) => raise HostError(message)
    error => raise error
  }
  { launched: true }
}
