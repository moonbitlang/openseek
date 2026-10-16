///|
priv struct SessionShare {
  state : ApiState
  payload : @protocol.SessionSharePayload
  local_account : Bool
}

///|
priv enum ShareCredential {
  Account(@protocol.AccountSession)
  Grant(String)
}

///|
async fn SessionShare::publish(
  self : SessionShare,
  on_progress~ : async (@protocol.ShareProgress) -> Unit,
) -> @protocol.SessionShareReply {
  let store = self.state.auth_store()
  // Capture account and issuer before reading records or awaiting HTTP.
  let (credential, server_url) = match self.payload.authorization {
    LocalAccount(user_id~) => {
      guard self.local_account else {
        return Failed(message="Remote sharing requires an upload grant.")
      }
      guard store.account() is Some(account) &&
        store.session_server() is Some(server_url) else {
        return SignInRequired
      }
      guard account.user.user_id == user_id else {
        return Failed(
          message="Sign-in changed before sharing. Try sharing again.",
        )
      }
      (Account(account), server_url)
    }
    UploadGrant(upload_token~) => (Grant(upload_token), @auth.AccountOrigin)
  }
  try {
    on_progress(Preparing)
    let (shell, bundle) = self.state.host_state().viz_assets().read()
    let files = @engine.ConversationExport::capture(
      self.state.manager(),
      self.payload.source,
      shell,
      bundle,
    )
    self.upload(files, credential, server_url~, on_progress~)
  } catch {
    error if @async.is_being_cancelled() => raise error
    @shares.EmptyTitle | @shares.Oversized as refusal =>
      Failed(message="\{refusal}")
    error => {
      @xlog.error(category="shares") <?
        { "event": "share_failed", "error": "\{error}" }
      Failed(message="Could not share the conversation: \{error}")
    }
  }
}

///|
async fn SessionShare::upload(
  self : SessionShare,
  files : @engine.ConversationExport,
  credential : ShareCredential,
  server_url~ : String,
  on_progress~ : async (@protocol.ShareProgress) -> Unit = _ => (),
) -> @protocol.SessionShareReply {
  let token = match credential {
    Account(account) => account.token
    Grant(token) => token
  }
  let reply = @shares.Snapshot(
    title=self.payload.source.title,
    html=files.html,
    json=files.json,
    key=self.payload.idempotency_key,
  ).publish(server_url~, token~, on_progress~)
  guard reply is SignInRequired else { return reply }
  guard credential is Account(account) else {
    return Failed(
      message="The share upload permission was rejected. Try sharing again.",
    )
  }
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
