///|
/// Render at request time and write to the destination the window's native
/// save dialog already confirmed (`dialog.save_file` runs before this method
/// is sent, so a dismissed dialog never reaches the host). Opening is
/// best-effort after the durable write: its failure is returned separately
/// so the UI never reports a saved export as failed.
async fn export_session(
  state : @api.ApiState,
  payload : @protocol.SessionSavePayload,
) -> @protocol.SessionExportReply {
  let assets = @host.viz_assets()
  let (shell, bundle) = assets.read()
  let files = @engine.ConversationExport::capture(
    state.manager(),
    payload.source,
    shell,
    bundle,
  )
  // The native dialog has already confirmed replacement for this exact path.
  // `CreateNew` would incorrectly reject an overwrite the user approved.
  @fs.write_file(payload.destination, files.html, create_mode=CreateOrTruncate) catch {
    error =>
      raise @host.HostError("could not save the conversation export: \{error}")
  }
  let open_code = @platform.open_path(payload.destination) catch {
    error if @async.is_being_cancelled() => raise error
    _ => -1
  }
  { path: Some(payload.destination), opened: open_code == 0, }
}
