///|
/// Cloud owns identity, observation readiness and HTTP transport. Command
/// interaction and delivery settlement use the same state as Local.
fn State::update_command(
  self : State,
  message : Msg,
  emit : @cmd.Emit[Msg],
  token : String?,
) -> (State, @cmd.Cmd)? {
  let callback = match message {
    CommandFinished(epoch, session, request, command, result) =>
      Some((epoch, session, request, command, Ok(result)))
    CommandFailed(epoch, session, request, command, failure) =>
      Some((epoch, session, request, command, Err(failure)))
    _ => None
  }
  if callback is Some((epoch, session, request, command, result)) {
    guard epoch == self.epoch &&
      self.conversations.get(session) is Some(conversation) &&
      conversation.controls.awaits(command, request) else {
      return Some((self, @cmd.none))
    }
    let (delivery, notice) = match result {
      Ok(Accepted) => (@engine_session.Accepted, None)
      Ok(Rejected(reason)) =>
        (
          @engine_session.Rejected,
          Some("Cloud rejected the operation: " + reason),
        )
      Err(failure) =>
        (
          if failure is (ServiceNotConfigured | Unauthorized | Http(400 | 404)) {
            @engine_session.Rejected
          } else {
            @engine_session.Unknown
          },
          Some(failure.label()),
        )
    }
    let next = self.replace(session, {
      ..conversation,
      controls: conversation.controls.delivered(command, request, delivery),
      notice: if notice is Some(_) {
        notice
      } else {
        conversation.notice
      },
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
  guard message is ControlAction(owner, action) &&
    @engine_session.composer_action(action) is Some(action) else {
    return None
  }
  guard owner is @interop.Cloud(account~, session~) &&
    self.user_id == Some(account) &&
    self.can_compose(session) &&
    !self.deletions.contains(session) &&
    !(self.metadata_saves.get(session) is Some({ edit: Archive(true), .. })) &&
    self.conversations.get(session) is Some(conversation) else {
    return Some((self, @cmd.none))
  }
  let local_edit = action
    is (@engine_session.EditGoal | @engine_session.CloseGoal)
  guard local_edit ||
    (
      !conversation.loading &&
      conversation.watch_status == Watching &&
      conversation.stream is Some({ active: true, .. }) &&
      conversation.last_seq is Some(_) &&
      token is Some(_)
    ) else {
    return Some((self, @cmd.none))
  }
  let sequence = self.sequence + 1
  let request = sequence.to_string()
  let (controls, command) = conversation.controls.act(
    action,
    request,
    conversation.session_view().watermark,
    running=conversation.generating,
  )
  let consumes_draft = controls.pending != conversation.controls.pending
  let conversation = { ..conversation, controls, }
  guard command is Some(command) && token is Some(token) else {
    return Some((self.replace(session, conversation), @cmd.none))
  }
  let conversation = {
    ..conversation,
    submission_sequence: conversation.submission_sequence +
    (if consumes_draft { 1 } else { 0 }),
    notice: None,
  }
  Some(
    (
      { ..self.replace(session, conversation), sequence, },
      run(emit, () => {
        CommandFinished(
          self.epoch,
          session,
          request,
          command,
          send_command(
            token,
            session,
            command,
            task_id?=conversation.control.bind(c => c.active_task_id),
          ),
        ) catch {
          @cloud_client.RequestError(failure) =>
            CommandFailed(self.epoch, session, request, command, failure)
          _ => CommandFailed(self.epoch, session, request, command, Unreachable)
        }
      }),
    ),
  )
}

///|
fn Conversation::command_event(
  self : Conversation,
  event : @wire.Event,
) -> Conversation {
  { ..self, controls: self.controls.event(event, live_goal=true), }
}

///|
fn Conversation::restore_goal(
  self : Conversation,
  document : @protocol.SessionDocument,
) -> Conversation {
  let view = @transcript.session_from_reply({
    session: document,
    watermark: None,
    prediction: None,
  })
  {
    ..self,
    controls: self.controls.restore_goal(view.goal, view.goal_markers),
  }
}
