///|
/// The selected host route owns the source; dialogs and share credentials
/// stay on this desktop. Both actions capture the same bounded remote export.
async fn capture_session_export(
  state : @api.DesktopState,
  payload : @protocol.SessionExportPayload,
) -> @protocol.SessionExportContent {
  let files = state.service().export_session(payload)
  { html: files.html, json: files.json, }
}

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
    raise @host.HostError::HostError(
      "could not open the save dialog: window is unavailable",
    )
  }
  window.save_file(Some("Export conversation"), Some("\{self.session}.html")) catch {
    error =>
      raise @host.HostError::HostError(
        "could not open the save dialog: \{error}",
      )
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
  state : @api.DesktopState,
  payload : @protocol.SessionExportPayload,
) -> @protocol.SessionExportReply {
  let html = capture_session_export(state, payload).html
  let dialog = SessionExportDialog(payload.session)
  guard dialog.destination(context) is Some(path) else {
    return { path: None, opened: false, }
  }
  // The native dialog has already confirmed replacement for this exact path.
  // `CreateNew` would incorrectly reject an overwrite the user approved.
  @fs.write_file(path, html, create_mode=CreateOrTruncate) catch {
    error =>
      raise @host.HostError::HostError(
        "could not save the conversation export: \{error}",
      )
  }
  let opened = (@platform.open_path(path) == 0) catch { _ => false }
  { path: Some(path), opened, }
}
