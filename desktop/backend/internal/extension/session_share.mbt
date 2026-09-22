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
  let store = self.state.auth_store()
  guard store.desired_connector() is Some(config) else {
    return if store.managed_by_env() {
      Failed(
        message="The configured device token is unavailable. Update OPENSEEK_DEVICE_TOKEN and restart the app.",
      )
    } else {
      SignInRequired
    }
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
    self.upload(snapshot, config)
  } catch {
    @shares.EmptyTitle
    | @shares.EntropyUnavailable
    | @shares.Oversized as refusal => Failed(message="\{refusal}")
    error => {
      // This scope includes capture, upload and rejected-login cleanup. Do not
      // mislabel an unrelated failure as a missing conversation.
      @xlog.error(category="shares") <?
        { "event": "share_failed", "error": "\{error}" }
      Failed(message="Could not share the conversation: \{error}")
    }
  }
}

///|
/// A 401 must retire the rejected registration before offering auth.connect,
/// which otherwise treats the persisted login as already signed in. Compare
/// the captured config first so a late response cannot clear a newer login.
async fn SessionShare::upload(
  self : SessionShare,
  snapshot : @shares.Snapshot,
  config : @auth.ConnectorConfig,
) -> @protocol.SessionShareReply {
  let reply = snapshot.publish(
    server_url=@auth.origin_from_relay_url(config.relay_url),
    token=config.device_token,
  )
  guard reply is SignInRequired else { return reply }
  @async.protect_from_cancel(() => {
    let store = self.state.auth_store()
    // The relay actor may already have retired this same login for its own
    // refusal, leaving no connector: that is the signed-out outcome below,
    // not a newer sign-in.
    if store.desired_connector() is Some(current) && current != config {
      return Failed(
        message="Sign-in changed during the upload. Try sharing again.",
      )
    }
    // Publish the truthful local state even when clearing the persisted login
    // fails. The existing refusal transition also clears memory and parks the
    // connector; cancellation must not strand the UI on the rejected login.
    defer self.state.publish(AuthChanged(store.status()))
    store.handle_refusal() catch {
      @auth.AuthError(message) =>
        return Failed(
          message="Could not clear the rejected sign-in: \{message}",
        )
      error => raise error
    }
    store.poke()
    if store.managed_by_env() {
      Failed(
        message="The configured device token was rejected. Update OPENSEEK_DEVICE_TOKEN and restart the app.",
      )
    } else {
      SignInRequired
    }
  })
}
