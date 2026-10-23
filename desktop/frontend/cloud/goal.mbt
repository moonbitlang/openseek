///|
/// The shared composer owns editing and prompt drafts. This adapter retains
/// the existing GoalInput until the engine confirms a saved goal, independently
/// of HTTP acceptance and chatting tasks.
fn State::update_goal(
  self : State,
  message : Msg,
  emit : @cmd.Emit[Msg],
  token : String?,
) -> (State, @cmd.Cmd)? {
  let callback = match message {
    GoalFinished(epoch, session, request, result) =>
      Some((epoch, session, request, Ok(result)))
    GoalFailed(epoch, session, request, failure) =>
      Some((epoch, session, request, Err(failure)))
    _ => None
  }
  if callback is Some((epoch, session, request, result)) {
    guard epoch == self.epoch &&
      self.conversations.get(session) is Some(conversation) &&
      conversation.goal_request == request &&
      conversation.goal.pending is Some(pending) else {
      return Some((self, @cmd.none))
    }
    let notice = match result {
      Ok(Accepted) => return Some((self, @cmd.none))
      Ok(Rejected(reason)) => "Cloud rejected the operation: " + reason + "."
      Err(failure) => failure.label()
    }
    let definite = result
      is (Ok(Rejected(_))
      | Err(ServiceNotConfigured | Unauthorized | Http(400 | 404)))
    let goal = if definite {
      {
        ..conversation.goal,
        pending: None,
        draft: if conversation.goal.draft is Some(_) {
          conversation.goal.draft
        } else {
          match pending {
            @composer.GoalSetting(text) => Some(text)
            @composer.GoalClearing => None
          }
        },
      }
    } else {
      conversation.goal
    }
    let next = self.replace(session, {
      ..conversation,
      goal,
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
  guard message is ControlAction(owner, action) &&
    action
    is (@composer.SlashCommand(command="goal", ..)
    | @composer.GoalEditStarted(..)
    | @composer.GoalCancelled(..)
    | @composer.GoalCleared(..)
    | @composer.GoalSubmitted(..)) else {
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
  let goal = conversation.goal
  let command : @wire.Command = match action {
    @composer.SlashCommand(..) | @composer.GoalEditStarted(..) => {
      let seed = match goal.pending {
        Some(@composer.GoalSetting(text)) => text
        _ => goal.standing.map_or("", goal => goal.text)
      }
      return Some(
        (
          self.replace(session, {
            ..conversation,
            goal: { ..goal, draft: Some(seed), },
          }),
          @cmd.none,
        ),
      )
    }
    @composer.GoalCancelled(..) =>
      return Some(
        (
          self.replace(session, {
            ..conversation,
            goal: { ..goal, draft: None, },
          }),
          @cmd.none,
        ),
      )
    @composer.GoalSubmitted(draft~, ..) => {
      guard goal.draft is Some(_) && !draft.trim().is_empty() else {
        return Some((self, @cmd.none))
      }
      @wire.GoalSet(text=draft.trim().to_owned(), auto=false)
    }
    @composer.GoalCleared(..) => @wire.GoalClear
    _ => return None
  }
  let pending : @composer.GoalPending = match command {
    @wire.GoalSet(text~, ..) => @composer.GoalSetting(text)
    _ => @composer.GoalClearing
  }
  guard token is Some(token) &&
    !conversation.loading &&
    conversation.watch_status == Watching &&
    conversation.stream is Some({ active: true, .. }) &&
    conversation.last_seq is Some(_) else {
    return Some((self, @cmd.none))
  }
  let request = self.sequence + 1
  let next = self.replace(session, {
    ..conversation,
    goal: { ..goal, draft: None, pending: Some(pending), },
    goal_request: request,
    goal_since: conversation.session_view().watermark,
    submission_sequence: conversation.submission_sequence + 1,
    notice: None,
  })
  Some(
    (
      { ..next, sequence: request, },
      run(emit, () => {
        GoalFinished(
          self.epoch,
          session,
          request,
          send_command(
            token,
            session,
            command,
            task_id?=conversation.control.bind(control => control.active_task_id),
          ),
        ) catch {
          @cloud_client.RequestError(failure) =>
            GoalFailed(self.epoch, session, request, failure)
          _ => GoalFailed(self.epoch, session, request, Unreachable)
        }
      }),
    ),
  )
}

///|
fn Conversation::goal_event(
  self : Conversation,
  event : @wire.Event,
) -> Conversation {
  let marker : @transcript.GoalMarker = match event {
    @wire.GoalUpdated(goal=Some(text)) => @transcript.GoalSet(text)
    @wire.GoalUpdated(goal=None) => @transcript.GoalCleared
    @wire.GoalBlocked(reason~) => @transcript.GoalBlocked(reason)
    @wire.GoalUnblocked => @transcript.GoalUnblocked
    _ => return self
  }
  let settled = match (self.goal.pending, marker) {
    (Some(@composer.GoalSetting(text)), @transcript.GoalSet(recorded)) =>
      text == recorded
    (Some(@composer.GoalClearing), @transcript.GoalCleared) => true
    _ => false
  }
  {
    ..self,
    goal: {
      ..self.goal,
      standing: @transcript.apply_goal_marker(self.goal.standing, marker),
      pending: if settled {
        None
      } else {
        self.goal.pending
      },
    },
  }
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
  let settled = view.goal_markers.any(entry => {
    entry.0 > self.goal_since &&
    (match (self.goal.pending, entry.1) {
      (Some(@composer.GoalSetting(text)), @transcript.GoalSet(saved)) =>
        text == saved
      (Some(@composer.GoalClearing), @transcript.GoalCleared) => true
      _ => false
    })
  })
  {
    ..self,
    goal: {
      ..self.goal,
      standing: view.goal,
      pending: if settled {
        None
      } else {
        self.goal.pending
      },
    },
  }
}
