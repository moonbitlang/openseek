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
  let assets = @host.viz_assets()
  let (shell, bundle) = assets.read()
  let html = @engine.export_session_html(
    state.manager(),
    payload,
    shell,
    bundle,
  )
  let dialog = SessionExportDialog(payload.session)
  guard dialog.destination(context) is Some(path) else {
    return { path: None, opened: false, }
  }
  // The native dialog has already confirmed replacement for this exact path.
  // `CreateNew` would incorrectly reject an overwrite the user approved.
  @fs.write_file(path, html, create_mode=CreateOrTruncate) catch {
    error =>
      raise @host.HostError("could not save the conversation export: \{error}")
  }
  let open_code = @platform.open_path(path) catch {
    error if @async.is_being_cancelled() => raise error
    _ => -1
  }
  { path: Some(path), opened: open_code == 0, }
}
