///|
async fn ApiState::share_file(
  self : ApiState,
  payload : @protocol.FileSharePayload,
  local_account~ : Bool,
) -> @protocol.SessionShareReply {
  let (credential, server_url) = match
    self.share_access(payload.authorization, local_account) {
    Ok(access) => access
    Err(reply) => return reply
  }
  try {
    let (name, bytes) = @files.capture(payload.source)
    let token = match credential {
      Account(account) => account.token
      Grant(token) => token
    }
    let reply = @shares.Snapshot::file(
      name~,
      bytes~,
      key=payload.idempotency_key,
    ).publish(server_url~, token~)
    credential.settle(self, reply)
  } catch {
    error => Failed(message="Could not share the file: \{error}")
  }
}
