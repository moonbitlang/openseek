///|
/// The native save-dialog operation for one captured export.
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
/// Capture at click time, then ask for a destination and write only after the
/// user confirms it. Capturing first keeps record locks out of the time the
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
  let dialog = SessionExportDialog(payload.session)
  guard dialog.destination(context) is Some(path) else {
    return { path: None, opened: false, }
  }
  // The native dialog has already confirmed replacement for this exact path.
  // `CreateNew` would incorrectly reject an overwrite the user approved.
  try {
    let file = @fs.open(path, mode=WriteOnly, create_mode=CreateOrTruncate)
    defer file.close()
    for chunk in files.html() {
      file.write(chunk)
    }
  } catch {
    error =>
      raise @host.HostError("could not save the conversation export: \{error}")
  }
  let open_code = @platform.open_path(path) catch { _ => -1 }
  { path: Some(path), opened: open_code == 0, }
}
