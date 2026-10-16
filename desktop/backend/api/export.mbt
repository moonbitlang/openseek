///|
/// Render on the working host using assets from its own build. The client
/// owns the destination dialog or relay upload and never passes credentials
/// into this operation.
pub async fn ApiState::export_session(
  self : ApiState,
  payload : @protocol.SessionExportPayload,
) -> @engine.ConversationExport {
  guard self.config.resources.viz is Some(assets) else {
    raise @host.HostError("Session visualizer assets are unavailable")
  }
  let (shell, bundle) = assets.read()
  @engine.ConversationExport::capture(self.manager, payload, shell, bundle)
}

///|
/// A bounded wire export. The record budget covers the parent and all direct
/// subruns together; the encoded-reply budget includes JSON escaping and is
/// below the transport's 32 MiB frame limit.
async fn ApiState::export_content(
  self : ApiState,
  payload : @protocol.SessionExportPayload,
) -> @protocol.SessionExportContent {
  guard self.config.resources.viz is Some(assets) else {
    raise @host.HostError("Session visualizer assets are unavailable")
  }
  let (shell, bundle) = assets.read()
  let files = @engine.ConversationExport::capture(
    self.manager,
    payload,
    shell,
    bundle,
    max_record_bytes=4 * 1024 * 1024,
  )
  checked_export_content(files.html, files.json)
}

///|
fn checked_export_content(
  html : String,
  json : String,
  max_bytes~ : Int32 = 24 * 1024 * 1024,
) -> @protocol.SessionExportContent raise {
  let content : @protocol.SessionExportContent = { html, json, }
  guard @utf8.encode(content.to_json().stringify()).length() <= max_bytes else {
    raise @host.HostError(
      "Rendered remote export exceeds the 24 MiB response limit",
    )
  }
  content
}
