///|
/// Capture the issuer and credential together before rendering or uploading.
/// A settings switch must never send an old token to a newly selected server.
priv struct SessionShare {
  state : ApiState
  payload : @protocol.SessionExportPayload
}

///|
async fn SessionShare::publish(
  self : SessionShare,
  on_progress~ : async (@protocol.ShareProgress) -> Unit,
) -> @protocol.SessionShareReply {
  let store = self.state.auth_store()
  guard store.account() is Some(account) &&
    store.session_server() is Some(server_url) else {
    return SignInRequired
  }
  try {
    on_progress(Preparing)
    let (shell, bundle) = self.state.host_state().viz_assets().read()
    let files = @engine.ConversationExport::capture(
      self.state.manager(),
      self.payload,
      shell,
      bundle,
    )
    self.upload(files, account, server_url~, on_progress~)
  } catch {
    error if @async.is_being_cancelled() => raise error
    @shares.EmptyTitle as refusal => Failed(message="\{refusal}")
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
/// A late rejection must not retire a newer account.
async fn SessionShare::upload(
  self : SessionShare,
  files : @engine.ConversationExport,
  account : @protocol.AccountSession,
  server_url~ : String,
  on_progress~ : async (@protocol.ShareProgress) -> Unit = _ => (),
) -> @protocol.SessionShareReply {
  let reply = @shares.publish(
    on_progress~,
    title=self.payload.title,
    files,
    server_url~,
    token=account.token,
  )
  guard reply is SignInRequired else { return reply }
  @async.protect_from_cancel(() => {
    let store = self.state.auth_store()
    if store.account() is Some(current) && current.token != account.token {
      return Failed(
        message="Sign-in changed during the upload. Try sharing again.",
      )
    }
    defer self.state.publish(AuthChanged(store.status()))
    store.expire_account(account.token) catch {
      @auth.AuthError(message) =>
        return Failed(
          message="Could not clear the rejected sign-in: \{message}",
        )
      error => raise error
    }
    SignInRequired
  })
}
