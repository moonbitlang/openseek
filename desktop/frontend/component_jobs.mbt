///|
fn Model::jobs_owner(self : Model) -> @jobs.Owner? {
  if self.screen is Chat &&
    self.cloud_identity() is Some(Cloud(account~, session~)) &&
    self.account is Some(credentials) &&
    credentials.user.user_id == account &&
    !self.cloud_archived() {
    let connection = self
      .cloud_conversation()
      .bind(conv => conv.job_connection(credentials.token, session))
    return Some(Cloud(session, connection))
  }
  guard self.screen is Chat &&
    self.active_conversation() is Some(conv) &&
    conv.has_begun() else {
    return None
  }
  Some(
    Host(conv.device, {
      session: conv.session_id,
      workspace: Some(conv.project().path),
      archived: conv.is_archived_read_only(),
    }),
  )
}
