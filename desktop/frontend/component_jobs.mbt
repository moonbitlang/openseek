///|
fn Model::jobs_owner(self : Model) -> @jobs.Owner? {
  guard self.screen is Chat &&
    self.active_conversation() is Some(conv) &&
    conv.has_begun() else {
    return None
  }
  Some({
    channel: conv.device,
    scope: {
      session: conv.session_id,
      workspace: Some(conv.project().path),
      archived: conv.is_archived_read_only(),
    },
  })
}
