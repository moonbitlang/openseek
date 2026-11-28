///|
/// The native save-dialog operation for one already-rendered export.
priv struct SessionExportDialog {
  session : String
}

///|
fn SessionExportDialog::SessionExportDialog(
  session : String,
) -> SessionExportDialog {
  { session, }
}

///|
/// Open Proton's window-scoped save dialog. Closing it returns `None` and
/// creates no file.
async fn SessionExportDialog::destination(
  self : SessionExportDialog,
  context : @proton.CommandContext,
) -> String? {
  guard context.window() is Some(window) else {
    raise @host.HostError(
      "could not open the save dialog: window is unavailable",
    )
  }
  window.save_file(Some("Export conversation"), Some("\{self.session}.html")) catch {
    error => raise @host.HostError("could not open the save dialog: \{error}")
  }
}

///|
/// Render at click time, then ask for a destination and write only after the
/// user confirms it. Rendering first keeps record locks out of the time the
/// native dialog is open. Opening is best-effort after the durable write: its
/// failure is returned separately so the UI never reports a saved export as
/// failed.
async fn export_session(
  context : @proton.CommandContext,
  state : @api.ApiState,
  payload : @protocol.SessionExportPayload,
) -> @protocol.SessionExportReply {
  let assets = state.host_state().viz_assets()
  let (shell, bundle) = assets.read()
  let files = @engine.ConversationExport::capture(
    state.manager(),
    payload,
    shell,
    bundle,
  )
  save_export(context, payload.session, files.html)
}

///|
async fn save_export(
  context : @proton.CommandContext,
  session : String,
  html : String,
) -> @protocol.SessionExportReply {
  let dialog = SessionExportDialog(session)
  guard dialog.destination(context) is Some(path) else {
    return { path: None, opened: false, }
  }
  // The native dialog has already confirmed replacement for this exact path.
  // `CreateNew` would incorrectly reject an overwrite the user approved.
  @fs.write_file(path, html, create_mode=CreateOrTruncate) catch {
    error =>
      raise @host.HostError("could not save the conversation export: \{error}")
  }
  let open_code = @platform.open_path(path) catch { _ => -1 }
  { path: Some(path), opened: open_code == 0, }
}

///|
fn inject_initial_hash(html : String, hash : String) -> String {
  let script = "<script>window.__OPENSEEK_INITIAL_HASH__ = \{Json(hash).stringify()};</script>\n"
  match html.split_once("</head>") {
    Some((before, after)) => "\{before}\{script}\{after}"
    None => "\{script}\{html}"
  }
}

///|
const MaxRetainedTrajectoryDirs : Int32 = 3

///|
let retained_trajectory_dirs : Array[String] = []

///|
fn trajectory_initial_hash(
  session : String,
  job_id : String?,
  job_started_at_ms : Int64?,
) -> String {
  match (job_id, job_started_at_ms) {
    (Some(job), Some(start_ms)) => "#t=\{session}&job=\{job}&start=\{start_ms}"
    (Some(job), None) => "#t=\{session}&job=\{job}"
    (None, _) => "#t=\{session}"
  }
}

///|
/// Render one run's trajectory snapshot into a temporary HTML file and open it
/// in the browser, bypassing the save dialog.
async fn open_session_trajectory(
  state : @api.ApiState,
  payload : @protocol.SessionTrajectoryPayload,
) -> @protocol.SessionExportReply {
  let assets = state.host_state().viz_assets()
  let (shell, bundle) = assets.read()
  let files = @engine.ConversationExport::capture(
    state.manager(),
    {
      session: payload.session,
      workspace: payload.workspace,
      title: payload.title,
      archived: payload.archived,
    },
    shell,
    bundle,
  )
  let html = inject_initial_hash(
    files.html,
    trajectory_initial_hash(
      payload.session,
      payload.job_id,
      payload.job_started_at_ms,
    ),
  )
  let dir = @fs.tmpdir(prefix="openseek-trajectory-") catch {
    error =>
      raise @host.HostError(
        "could not create temporary trajectory directory: \{error}",
      )
  }
  while retained_trajectory_dirs.length() >= MaxRetainedTrajectoryDirs {
    let stale = retained_trajectory_dirs.remove(0)
    @fs.rmdir(stale, recursive=true) catch {
      _ => ()
    }
  }
  retained_trajectory_dirs.push(dir)
  let path = "\{dir}/trajectory.html"
  @fs.write_file(path, html, create_mode=CreateOrTruncate) catch {
    error =>
      raise @host.HostError("could not write trajectory snapshot: \{error}")
  }
  let open_code = @platform.open_path(path) catch { _ => -1 }
  { path: Some(path), opened: open_code == 0, }
}
