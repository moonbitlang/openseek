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
  feedback? : @protocol.FeedbackMetadata,
  on_share_progress~ : async (@protocol.SessionShareProgress) -> Unit,
) -> @protocol.SessionShareReply {
  let (credential, server_url) = match
    self.share_access(payload.authorization, local_account) {
    Ok(access) => access
    Err(reply) => return reply
  }
  SessionShare::{ state: self, payload, }.publish(
    credential,
    server_url~,
    feedback?,
    on_progress=progress => {
      on_share_progress({ generation: payload.generation, progress, }) catch {
        _ => ()
      }
    },
  )
}

///|
async fn SessionShare::publish(
  self : SessionShare,
  credential : ShareCredential,
  server_url~ : String,
  feedback? : @protocol.FeedbackMetadata,
  on_progress~ : async (@protocol.ShareProgress) -> Unit,
) -> @protocol.SessionShareReply {
  try {
    on_progress(Preparing)
    let (shell, bundle) = self.state.host_state().viz_assets().read()
    let files = @engine.ConversationExport::capture(
      self.state.manager(),
      self.payload.source,
      shell,
      bundle,
    )
    self.upload(files, credential, server_url~, feedback?, on_progress~)
  } catch {
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
  feedback? : @protocol.FeedbackMetadata,
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
    feedback?=feedback.map(metadata => {
      "message": metadata.message,
      "environment": Json::object(metadata.environment),
      "source": { "mode": "local", "session_id": self.payload.source.session },
    }),
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
  @async.protect_from_cancel(() => {
    let store = state.auth_store()
    if store.account() is Some(current) && current.token != account.token {
      return Failed(
        message="Sign-in changed during the upload. Try sharing again.",
      )
    }
    defer state.publish(AuthChanged(store.status()))
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
