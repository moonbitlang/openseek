///|
/// Capture the issuer and credential together before rendering or uploading.
/// A settings switch must never send an old token to a newly selected server.
priv struct SessionShare {
  state : @api.ApiState
  payload : @protocol.SessionExportPayload
}

///|
async fn SessionShare::publish(
  self : SessionShare,
) -> @protocol.SessionShareReply {
  guard self.state.auth_store().desired_connector() is Some(config) else {
    return SignInRequired
  }
  try {
    let (shell, bundle) = @host.viz_assets().read()
    let files = @engine.ConversationExport::capture(
      self.state.manager(),
      self.payload,
      shell,
      bundle,
    )
    let snapshot = @shares.Snapshot(
      title=self.payload.title,
      html=files.html,
      json=files.json,
    )
    snapshot.publish(
      server_url=@auth.origin_from_relay_url(config.relay_url),
      token=config.device_token,
    )
  } catch {
    error if @async.is_being_cancelled() => raise error
    @shares.ShareError(message) => Failed(message~)
    _ =>
      Failed(
        message="Could not prepare the conversation export. Check that the conversation is still available.",
      )
  }
}
