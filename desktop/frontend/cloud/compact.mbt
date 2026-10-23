///|
/// HTTP acceptance queues the native command; only engine events or an
/// authoritative control snapshot settle it. Chat turn completion is unrelated.
fn State::update_compact(
  self : State,
  message : Msg,
  emit : @cmd.Emit[Msg],
  token : String?,
) -> (State, @cmd.Cmd)? {
  let callback = match message {
    CompactFinished(epoch, session, request, result) =>
      Some((epoch, session, request, Ok(result)))
    CompactFailed(epoch, session, request, failure) =>
      Some((epoch, session, request, Err(failure)))
    _ => None
  }
  if callback is Some((epoch, session, request, result)) {
    guard epoch == self.epoch &&
      self.conversations.get(session) is Some(conversation) &&
      conversation.compact_request == Some(request) else {
      return Some((self, @cmd.none))
    }
    let notice = match result {
      Ok(Accepted) =>
        return Some(
          (
            self.replace(session, { ..conversation, compact_request: None, }),
            @cmd.none,
          ),
        )
      Ok(Rejected(reason)) => "Cloud rejected the operation: " + reason + "."
      Err(failure) => failure.label()
    }
    let definite = result
      is (Ok(Rejected(_)) | Err(Unauthorized | Http(400 | 404)))
    let next = self.replace(session, {
      ..conversation,
      compact_request: if definite {
        None
      } else {
        conversation.compact_request
      },
      compact_queued: !definite,
      notice: Some(notice),
    })
    return Some(
      (
        if result is Err(Unauthorized) {
          { ..next, needs_sign_in: true, }
        } else {
          next
        },
        @cmd.none,
      ),
    )
  }
  guard message
    is ControlAction(owner, @composer.SlashCommand(command="compact", ..)) else {
    return None
  }
  guard owner is @interop.Cloud(account~, session~) &&
    self.user_id == Some(account) &&
    self.can_compose(session) &&
    !self.deletions.contains(session) &&
    !(self.metadata_saves.get(session) is Some({ edit: Archive(true), .. })) &&
    self.conversations.get(session) is Some(conversation) &&
    !conversation.loading &&
    !conversation.compacting &&
    !conversation.compact_queued &&
    conversation.watch_status == Watching &&
    conversation.stream is Some({ active: true, .. }) &&
    conversation.last_seq is Some(_) &&
    token is Some(token) else {
    return Some((self, @cmd.none))
  }
  let request = self.sequence + 1
  let next = self.replace(session, {
    ..conversation,
    compact_queued: true,
    compact_request: Some(request),
    notice: None,
  })
  Some(
    (
      { ..next, sequence: request, },
      run(emit, () => {
        CompactFinished(
          self.epoch,
          session,
          request,
          send_command(
            token,
            session,
            @wire.Compact,
            task_id?=conversation.control.bind(control => control.active_task_id),
          ),
        ) catch {
          @cloud_client.RequestError(failure) =>
            CompactFailed(self.epoch, session, request, failure)
          _ => CompactFailed(self.epoch, session, request, Unreachable)
        }
      }),
    ),
  )
}
