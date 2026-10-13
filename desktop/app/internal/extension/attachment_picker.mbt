///|
/// Native selection preserves the source path, so workspace files can be
/// referenced directly. Browser and remote clients use their File picker.
async fn pick_attachment(
  context : @proton.CommandContext,
) -> @protocol.PickAttachmentReply {
  guard context.window() is Some(window) else {
    raise @host.HostError(
      "could not open the attachment picker: window is unavailable",
    )
  }
  guard window.open_file(Some("Attach a file"), None) is Some(path) else {
    return { path: None, }
  }
  guard @pathx.Path(path).to_absolute().bind(path => path.to_uri_path())
    is Some(path) else {
    raise @host.HostError("the selected attachment path cannot be represented")
  }
  { path: Some(path), }
}
