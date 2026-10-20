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

///|
/// The jobs owner when the overview describes its conversation, so the
/// overview's card may read the jobs listing.
fn Model::overview_jobs_owner(self : Model) -> @jobs.Owner? {
  guard self.overview_conversation() is Some(conversation) &&
    self.jobs_owner() is Some(owner) &&
    owner.channel == conversation.channel &&
    owner.scope.session == conversation.session else {
    return None
  }
  Some(owner)
}
