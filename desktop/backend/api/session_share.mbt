///|
priv struct SessionShare {
  state : ApiState
  payload : @protocol.SessionSharePayload
}

///|
priv enum ShareCredential {
  Account(@protocol.AccountSession)
  Grant(String)
}

///|
async fn ApiState::share_conversation(
  self : ApiState,
  payload : @protocol.SessionSharePayload,
  local_account~ : Bool,
  on_share_progress~ : async (@protocol.SessionShareProgress) -> Unit,
) -> @protocol.SessionShareReply {
  let (credential, server_url) = match
    self.share_access(payload.authorization, local_account) {
    Ok(access) => access
    Err(reply) => return reply
  }
  SessionShare::{ state: self, payload, }.publish(credential, server_url~, on_progress=progress => {
    on_share_progress({ generation: payload.generation, progress, }) catch {
      _ => ()
    }
  })
}

///|
async fn SessionShare::publish(
  self : SessionShare,
  credential : ShareCredential,
  server_url~ : String,
  on_progress~ : async (@protocol.ShareProgress) -> Unit,
) -> @protocol.SessionShareReply {
  try {
    on_progress(Preparing)
    let files = self.state.capture_conversation(self.payload.source)
    self.upload(files, credential, server_url~, on_progress~)
  } catch {
    @shares.EmptyTitle | @shares.Oversized as refusal =>
      Failed(message="\{refusal}")
    error => {
      if @xlog.error(category="shares") is Some(w) {
        w
        ..write_object_begin()
        ..write_object_field("event", "share_failed")
        ..write_object_field("error", "\{error}")
        .write_object_end()
      }
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
  credential.settle(self.state, reply)
}

///|
fn ApiState::share_access(
  self : ApiState,
  authorization : @protocol.ShareAuthorization,
  local_account : Bool,
) -> Result[(ShareCredential, String), @protocol.SessionShareReply] {
  let store = self.auth_store()
  let access = match authorization {
    LocalAccount(user_id~) => {
      guard local_account else {
        return Err(Failed(message="Remote sharing requires an upload grant."))
      }
      guard store.account() is Some(account) &&
        store.session_server() is Some(server_url) else {
        return Err(SignInRequired)
      }
      guard account.user.user_id == user_id else {
        return Err(
          Failed(message="Sign-in changed before sharing. Try sharing again."),
        )
      }
      (Account(account), server_url)
    }
    UploadGrant(upload_token~) => (Grant(upload_token), @auth.AccountOrigin)
  }
  Ok(access)
}

///|
async fn ShareCredential::settle(
  credential : ShareCredential,
  state : ApiState,
  reply : @protocol.SessionShareReply,
) -> @protocol.SessionShareReply {
  guard reply is SignInRequired else { return reply }
  guard credential is Account(account) else {
    return Failed(
      message="The share upload permission was rejected. Try sharing again.",
    )
  }
  state.expire_upload_account(account) catch {
    @host.HostError(message) => return Failed(message~)
    error => raise error
  }
  SignInRequired
}

///|
async fn ApiState::expire_upload_account(
  self : ApiState,
  account : @protocol.AccountSession,
) -> Unit {
  @async.protect_from_cancel(() => {
    let store = self.auth_store()
    if store.account() is Some(current) && current.token != account.token {
      raise @host.HostError(
        "Sign-in changed during the upload. Please try again.",
      )
    }
    defer self.publish(AuthChanged(store.status()))
    store.expire_account(account.token) catch {
      @auth.AuthError(message) =>
        raise @host.HostError(
          "Could not clear the rejected sign-in: \{message}",
        )
      error => raise error
    }
  })
}
