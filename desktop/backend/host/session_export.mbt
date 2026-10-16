///|
/// A windowless export saves a concrete standalone file in the host's export
/// directory. The Proton window overrides this endpoint with its save dialog.
async fn export_session_op(
  state : HostState,
  manager : @engine.EngineManager,
  payload : @protocol.SessionExportPayload,
) -> @protocol.SessionExportReply {
  let (shell, bundle) = state.viz_assets().read()
  let files = @engine.ConversationExport::capture(
    manager, payload, shell, bundle,
  )
  let path = state.save_export(payload.session, files.html)
  { path: Some(path), opened: false, }
}

///|
async fn HostState::save_export(
  self : HostState,
  session : String,
  html : String,
) -> String {
  let directory = if self.runtime_dir is Some(runtime) {
    let directory = runtime.join("exports").to_string()
    @fs.mkdir(directory, recursive=true, allow_exist=true)
    directory
  } else {
    @fs.tmpdir(prefix="seekmoon-exports-")
  }
  let path = directory + "/" + session + "-" + @uuid.mint() + ".html"
  @fs.write_file(path, html, create_mode=CreateNew)
  path
}
