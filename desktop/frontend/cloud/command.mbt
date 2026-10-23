///|
/// Views over the existing conversation storage keep transport bookkeeping
/// separate from the shared command reducer.
fn Conversation::engine_controls(self : Conversation) -> @engine_session.State {
  {
    goal: self.goal.standing,
    edit: self.goal.draft,
    pending: self.goal.pending.map(pending => {
      id: self.goal_request.to_string(),
      since: self.goal_since,
      request: match pending {
        @composer.GoalSetting(text) => @engine_session.Setting(text)
        @composer.GoalClearing => @engine_session.Clearing
      },
    }),
    compaction: if self.compact_queued {
      @engine_session.Queued
    } else if self.compacting {
      @engine_session.Compacting
    } else {
      @engine_session.NotCompacting
    },
  }
}

///|
fn Conversation::with_engine_controls(
  self : Conversation,
  state : @engine_session.State,
) -> Conversation {
  let same_phase = state.compaction == self.engine_controls().compaction
  {
    ..self,
    goal: state.input(),
    compact_queued: if same_phase {
      self.compact_queued
    } else {
      state.compaction is (@engine_session.Queued | @engine_session.Requested)
    },
    compacting: if same_phase {
      self.compacting
    } else {
      state.compaction is @engine_session.Compacting
    },
  }
}

///|
/// The adapter owns only Cloud identity, readiness, HTTP and callback fencing.
/// Command-specific interaction and settlement live in engine_session.
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
      (match command {
        @wire.Compact => conversation.compact_request == Some(request)
        @wire.GoalSet(..) | @wire.GoalClear =>
          conversation.goal_request == request &&
          conversation.goal.pending is Some(_)
        _ => true
      }) else {
      return Some((self, @cmd.none))
    }
    let notice = match result {
      Ok(Accepted) =>
        return Some(
          (
            self.replace(session, {
              ..conversation,
              compact_request: if command is @wire.Compact {
                None
              } else {
                conversation.compact_request
              },
            }),
            @cmd.none,
          ),
        )
      Ok(Rejected(reason)) => "Cloud rejected the operation: " + reason
      Err(failure) => failure.label()
    }
    let definite = result
      is (Ok(Rejected(_))
      | Err(ServiceNotConfigured | Unauthorized | Http(400 | 404)))
    let controls = conversation.engine_controls()
    let next = self.replace(session, {
      ..conversation.with_engine_controls(
        if definite {
          controls.reject(command, request.to_string())
        } else {
          controls
        },
      ),
      compact_request: if definite && command is @wire.Compact {
        None
      } else {
        conversation.compact_request
      },
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
  let request = self.sequence + 1
  let (controls, command) = conversation
    .engine_controls()
    .act(
      action,
      request.to_string(),
      conversation.session_view().watermark,
      running=conversation.generating,
    )
  let conversation = conversation.with_engine_controls(controls)
  guard command is Some(command) && token is Some(token) else {
    return Some((self.replace(session, conversation), @cmd.none))
  }
  let conversation = {
    ..conversation,
    goal_request: if command is (@wire.GoalSet(..) | @wire.GoalClear) {
      request
    } else {
      conversation.goal_request
    },
    goal_since: controls.pending.map_or(conversation.goal_since, p => p.since),
    compact_request: if command is @wire.Compact {
      Some(request)
    } else {
      conversation.compact_request
    },
    submission_sequence: conversation.submission_sequence +
    (if command is (@wire.GoalSet(..) | @wire.GoalClear) { 1 } else { 0 }),
    notice: None,
  }
  Some(
    (
      { ..self.replace(session, conversation), sequence: request, },
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
  // Automatic compaction is a turn activity, independent of manual commands.
  let controls = self.engine_controls()
  let next = controls.event(event, live_goal=true)
  if event
    is (@wire.CompactionStarted(..)
    | @wire.CompactionFinished(..)
    | @wire.CompactionFailed(..)) {
    { ..self.with_engine_controls(next), compact_request: None, }
  } else {
    { ..self, goal: next.input(), }
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
  {
    ..self,
    goal: self
    .engine_controls()
    .restore_goal(view.goal, view.goal_markers)
    .input(),
  }
}
