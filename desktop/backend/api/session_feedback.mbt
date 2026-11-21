///|
async fn ApiState::submit_feedback(
  self : ApiState,
  payload : @protocol.SessionFeedbackPayload,
) -> @protocol.SessionFeedbackReply {
  let store = self.auth_store()
  guard store.account() is Some(account) &&
    store.session_server() is Some(server_url) else {
    return SignInRequired
  }
  guard account.user.user_id == payload.user_id else {
    return Failed(
      message="Sign-in changed before submitting feedback. Please try again.",
    )
  }
  self.publish_feedback(payload, account, server_url~)
}

///|
async fn ApiState::publish_feedback(
  self : ApiState,
  payload : @protocol.SessionFeedbackPayload,
  account : @protocol.AccountSession,
  server_url~ : String,
) -> @protocol.SessionFeedbackReply {
  let reply = try {
    let files = self.capture_conversation(payload.source)
    @shares.submit_feedback(
      title=payload.source.title,
      html=files.html,
      json=files.json,
      key=payload.idempotency_key,
      metadata={
        "message": payload.metadata.message,
        "environment": Json::object(payload.metadata.environment),
        "source": { "mode": "local", "session_id": payload.source.session },
      },
      server_url~,
      token=account.token,
    )
  } catch {
    @shares.Oversized =>
      return Failed(message="This feedback exceeds the 20 MiB upload limit.")
    error => return Failed(message="Could not submit feedback: \{error}")
  }
  guard reply is SignInRequired else { return reply }
  self.expire_upload_account(account) catch {
    @host.HostError(message) => return Failed(message~)
    error => raise error
  }
  SignInRequired
}
