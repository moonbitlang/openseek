///|
fn run(emit : @cmd.Emit[Msg], task : async () -> Msg) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => scheduler.add(emit(task()))) |> ignore
  })
}

///|
fn State::replace(
  self : State,
  id : String,
  conversation : Conversation,
) -> State {
  let conversations = self.conversations.copy()
  conversations[id] = conversation
  { ..self, conversations, }
}

///|
fn State::list(
  self : State,
  token : String?,
  emit : @cmd.Emit[Msg],
) -> (State, @cmd.Cmd) {
  guard token is Some(token) else { return (self, @cmd.none) }
  let request = self.sequence + 1
  (
    { ..self, sequence: request, list_request: request, },
    run(emit, () => {
      Listed(self.epoch, request, list_sessions(token)) catch {
        @cloud_client.RequestError(error) =>
          ListFailed(self.epoch, request, error)
        _ => ListFailed(self.epoch, request, Unreachable)
      }
    }),
  )
}

///|
fn State::load(
  self : State,
  id : String,
  token : String?,
  emit : @cmd.Emit[Msg],
) -> (State, @cmd.Cmd) {
  guard token is Some(token) else { return (self, @cmd.none) }
  let conversation = self.conversations.get(id).unwrap_or(Conversation::empty())
  guard !conversation.sending else { return (self, @cmd.none) }
  let request = self.sequence + 1
  let next = self.replace(id, { ..conversation, request, })
  (
    { ..next, sequence: request, },
    run(emit, () => {
      Loaded(self.epoch, id, request, load_history(token, id)) catch {
        @cloud_client.RequestError(error) =>
          LoadFailed(self.epoch, id, request, error)
        _ => LoadFailed(self.epoch, id, request, Unreachable)
      }
    }),
  )
}

///|
fn State::fence_archived_history(
  self : State,
  id : String,
  request : Int32,
  token : String?,
  emit : @cmd.Emit[Msg],
) -> (State, @cmd.Cmd) {
  // A response stream owns its request until StreamEnded; load() cannot
  // issue a history read while sending, so there is no history to fence yet.
  guard self.conversations.get(id) is Some(conversation) &&
    !conversation.sending else {
    return (self, @cmd.none)
  }
  // Fence pre-archive reads even after a later restore. Replace an unfinished
  // read through the existing loader so the retained transcript can complete.
  let loading = conversation.loading ||
    conversation.generating ||
    conversation.history_required
  let next = self.replace(id, {
    ..conversation,
    request,
    generating: false,
    loading,
    history_required: conversation.history_required || loading,
  })
  if loading {
    next.load(id, token, emit)
  } else {
    (next, @cmd.none)
  }
}

///|
fn State::failed(self : State, error : Failure) -> (State, @cmd.Cmd) {
  (
    {
      ..self,
      needs_sign_in: error is Unauthorized,
      notice: Some(error.label()),
    },
    @cmd.none,
  )
}

///|
fn State::create(
  self : State,
  token : String?,
  emit : @cmd.Emit[Msg],
) -> (State, @cmd.Cmd) {
  guard token is Some(token) && self.creation is Some(creation) else {
    return (self, @cmd.none)
  }
  (
    self,
    run(emit, () => {
      Created(
        self.epoch,
        creation.request,
        required_string(
          request(CloudOrigin, "/v1/sessions", Post, token~),
          "id",
        ),
      ) catch {
        @cloud_client.RequestError(error) =>
          CreateFailed(self.epoch, creation.request, error)
        _ => CreateFailed(self.epoch, creation.request, Unreachable)
      }
    }),
  )
}

///|
fn poll(
  epoch : Int32,
  id : String,
  request : Int32,
  emit : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @base_browser.schedule_timeout(
      () => scheduler.add(emit(Poll(epoch, id, request))),
      1500,
    )
    |> ignore
  })
}

///|
pub fn State::can_delete(self : State, id : String) -> Bool {
  self.sessions.any(session => session.id == id && !session.generating) &&
  !self.deletions.contains(id) &&
  !self.metadata_saves.contains(id) &&
  !self.retired.contains(id) &&
  self.conversations
  .get(id)
  .map_or(true, conversation => {
    !conversation.sending && !conversation.generating
  })
}

///|
pub fn State::can_edit(self : State, id : String, edit : SessionEdit) -> Bool {
  guard !self.retired.contains(id) &&
    !self.deletions.contains(id) &&
    !self.metadata_saves.contains(id) &&
    self.sessions.iter().find_first(session => session.id == id)
    is Some(session) else {
    return false
  }
  match edit {
    Rename(_) => !session.archived
    Archive(archived) => session.archived != archived && self.can_delete(id)
  }
}

///|
pub fn State::is_archived(self : State, id : String) -> Bool {
  self.sessions.any(session => session.id == id && session.archived)
}

///|
/// Direct links can load history before the catalog confirms editability.
pub fn State::can_compose(self : State, id : String) -> Bool {
  self.sessions.any(session => session.id == id && !session.archived)
}

///|
pub fn State::can_send(self : State, id : String) -> Bool {
  self.conversations.get(id) is Some(conversation) &&
  self.can_compose(id) &&
  !self.deletions.contains(id) &&
  !(self.metadata_saves.get(id) is Some({ edit: Archive(true), .. })) &&
  !conversation.loading &&
  !conversation.sending &&
  !conversation.generating &&
  !conversation.history_required
}

///|
fn State::forget(self : State, id : String) -> State {
  let conversations = self.conversations.copy()
  conversations.remove(id)
  let deletions = self.deletions.copy()
  deletions.remove(id)
  let metadata_saves = self.metadata_saves.copy()
  metadata_saves.remove(id)
  {
    ..self,
    sessions: self.sessions.filter(session => session.id != id),
    conversations,
    deletions,
    metadata_saves,
    retired: if self.retired.contains(id) {
      self.retired
    } else {
      [..self.retired, id]
    },
  }
}

///|
/// The optional result is a completed creation's navigation intent. The root
/// owns selection; opening and background responses never select a page.
pub fn update(
  state : State,
  msg : Msg,
  emit : @cmd.Emit[Msg],
  token? : String,
  navigation~ : Int32,
) -> (State, @cmd.Cmd, String?) {
  let (next, command, select) = match msg {
    AccountChanged(user_id) => {
      let next = {
        ..State::empty(),
        user_id,
        epoch: state.epoch + 1,
        sequence: state.sequence,
      }
      let (next, command) = next.list(token, emit)
      (next, command, None)
    }
    Refresh => {
      let (next, command) = { ..state, notice: None, }.list(token, emit)
      (next, command, None)
    }
    Listed(epoch, request, sessions) => {
      guard epoch == state.epoch &&
        request == state.list_request &&
        token is Some(_) else {
        return (state, @cmd.none, None)
      }
      let mut next = state
      for item in state.sessions {
        if !sessions.any(session => session.id == item.id) {
          next = next.forget(item.id)
        }
      }
      let sessions = sessions.filter(item => !next.retired.contains(item.id))
      let history : Array[@cmd.Cmd] = []
      for session in sessions {
        if session.archived && !state.is_archived(session.id) {
          let (archived, command) = next.fence_archived_history(
            session.id,
            request,
            token,
            emit,
          )
          next = archived
          history.push(command)
        }
      }
      ({ ..next, sessions, }, @cmd.batch(history), None)
    }
    ListFailed(epoch, request, error) => {
      guard epoch == state.epoch && request == state.list_request else {
        return (state, @cmd.none, None)
      }
      let (next, command) = state.failed(error)
      (next, command, None)
    }
    Create => {
      if state.creation is Some(creation) {
        return (
          { ..state, creation: Some({ ..creation, navigation, }), },
          @cmd.none,
          None,
        )
      }
      let request = state.sequence + 1
      let next = {
        ..state,
        sequence: request,
        creation: Some({
          id: "draft:\{request}",
          request,
          navigation,
          submission: None,
          attachments: [],
        }),
        notice: None,
      }
      (next, @cmd.none, None)
    }
    Created(epoch, request, id) => {
      guard epoch == state.epoch &&
        state.creation is Some(creation) &&
        creation.request == request &&
        creation.submission is Some(draft) &&
        state.user_id is Some(account) else {
        return (state, @cmd.none, None)
      }
      let sessions = [
        {
          id,
          title: None,
          updated_at: None,
          generating: false,
          archived: false,
        },
        ..state.sessions.filter(session => session.id != id),
      ]
      let ready = {
        ..Conversation::empty(),
        loading: false,
        history_required: false,
        initial_submission: Some(draft),
        initial_attachments: creation.attachments,
      }
      let (next, command) = { ..state, sessions, creation: None, }
        .replace(id, ready)
        .list(token, emit)
      let (next, send, _) = next.submit(
        @interop.Cloud(account~, session=id),
        draft,
        creation.attachments,
        emit,
        token?,
        navigation~,
      )
      (
        next,
        @cmd.batch([command, send]),
        if creation.navigation == navigation {
          Some(id)
        } else {
          None
        },
      )
    }
    CreateFailed(epoch, request, error) => {
      guard epoch == state.epoch &&
        state.creation is Some(creation) &&
        creation.request == request &&
        creation.submission is Some(_) else {
        return (state, @cmd.none, None)
      }
      let (next, command) = {
        ..state,
        creation: Some({ ..creation, submission: None, }),
      }.failed(error)
      (next, command, None)
    }
    Edit(account~, session=id, edit~) => {
      let edit = match edit {
        Rename(title) => Rename(title.trim().to_owned())
        other => other
      }
      guard state.user_id == Some(account) &&
        token is Some(token) &&
        state.can_edit(id, edit) &&
        !(edit is Rename(title) && title.is_empty()) else {
        return (state, @cmd.none, None)
      }
      let request = state.sequence + 1
      let metadata_saves = state.metadata_saves.copy()
      metadata_saves[id] = { request, edit, navigation, }
      (
        { ..state, sequence: request, metadata_saves, notice: None, },
        run(emit, () => {
          try {
            edit_session(token, id, edit)
            Edited(state.epoch, id, request)
          } catch {
            @cloud_client.RequestError(error) =>
              EditFailed(state.epoch, id, request, error)
            _ => EditFailed(state.epoch, id, request, Unreachable)
          }
        }),
        None,
      )
    }
    Edited(epoch, id, request) => {
      guard epoch == state.epoch &&
        state.metadata_saves.get(id) is Some(save) &&
        save.request == request else {
        return (state, @cmd.none, None)
      }
      let metadata_saves = state.metadata_saves.copy()
      metadata_saves.remove(id)
      let sessions = state.sessions.map(session => {
        if session.id != id {
          session
        } else {
          match save.edit {
            Rename(title) => { ..session, title: Some(title), }
            Archive(archived) =>
              {
                ..session,
                archived,
                generating: session.generating && !archived,
              }
          }
        }
      })
      // The new list request fences every inventory that began before the
      // completed PATCH, including reads issued while the save was pending.
      let next = { ..state, sessions, metadata_saves, }
      let (next, history) = if save.edit is Archive(true) {
        next.fence_archived_history(id, request, token, emit)
      } else {
        (next, @cmd.none)
      }
      let (next, command) = next.list(token, emit)
      (next, @cmd.batch([history, command]), None)
    }
    EditFailed(epoch, id, request, error) => {
      guard epoch == state.epoch &&
        state.metadata_saves.get(id) is Some(save) &&
        save.request == request else {
        return (state, @cmd.none, None)
      }
      if error is Http(404) {
        return (state.forget(id), @cmd.none, None)
      }
      let metadata_saves = state.metadata_saves.copy()
      metadata_saves.remove(id)
      let (next, command) = { ..state, metadata_saves, }.failed(error)
      (next, command, None)
    }
    Delete(id) => {
      guard state.can_delete(id) && token is Some(token) else {
        return (state, @cmd.none, None)
      }
      let request = state.sequence + 1
      let deletions = state.deletions.copy()
      deletions[id] = request
      (
        { ..state, sequence: request, deletions, notice: None, },
        run(emit, () => {
          try {
            delete_session(token, id)
            Deleted(state.epoch, id, request)
          } catch {
            @cloud_client.RequestError(error) =>
              DeleteFailed(state.epoch, id, request, error)
            _ => DeleteFailed(state.epoch, id, request, Unreachable)
          }
        }),
        None,
      )
    }
    Deleted(epoch, id, request) => {
      guard epoch == state.epoch && state.deletions.get(id) == Some(request) else {
        return (state, @cmd.none, None)
      }
      (state.forget(id), @cmd.none, None)
    }
    DeleteFailed(epoch, id, request, error) => {
      guard epoch == state.epoch && state.deletions.get(id) == Some(request) else {
        return (state, @cmd.none, None)
      }
      if error is Http(404) {
        return (state.forget(id), @cmd.none, None)
      }
      let deletions = state.deletions.copy()
      deletions.remove(id)
      let (next, command) = { ..state, deletions, }.failed(error)
      (
        if error is Busy {
          {
            ..next,
            notice: Some(
              "This conversation is generating. Try deleting it after it finishes.",
            ),
          }
        } else {
          next
        },
        command,
        None,
      )
    }
    Open(id) => {
      guard token is Some(_) && !state.retired.contains(id) else {
        return (state, @cmd.none, None)
      }
      let conversation = state.conversations
        .get(id)
        .unwrap_or(Conversation::empty())
      let next = if conversation.sending {
        state
      } else {
        state.replace(id, {
          ..conversation.clear_progress(),
          loading: true,
          history_required: true,
          notice: None,
        })
      }
      let (next, command) = next.load(id, token, emit)
      (next, command, None)
    }
    Loaded(epoch, id, request, history) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.request == request &&
        !conversation.sending else {
        return (state, @cmd.none, None)
      }
      let accepted = conversation.pending is Some(submission) &&
        history.messages.any(record => {
          record.kind == "user" &&
          !submission.known_tasks.contains(record.task_id)
        })
      let next = state.replace(id, {
        ..conversation.clear_progress(),
        records: history.messages,
        events: [],
        loading: false,
        generating: history.generating,
        history_required: false,
        pending: None,
        uploads: if accepted {
          []
        } else {
          conversation.uploads
        },
        // A successful read does not mean the failed send was admitted.
        notice: if conversation.pending is Some(_) && !accepted {
          conversation.notice
        } else {
          None
        },
        submission_sequence: conversation.submission_sequence +
        (if accepted { 1 } else { 0 }),
        initial_submission: if accepted {
          None
        } else {
          conversation.initial_submission
        },
        initial_attachments: if accepted {
          []
        } else {
          conversation.initial_attachments
        },
      })
      let next = {
        ..next,
        sessions: next.sessions.map(session => {
          if session.id == id {
            { ..session, generating: history.generating, }
          } else {
            session
          }
        }),
      }
      (
        next,
        if history.generating {
          poll(epoch, id, request, emit)
        } else {
          @cmd.none
        },
        None,
      )
    }
    LoadFailed(epoch, id, request, error) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.request == request else {
        return (state, @cmd.none, None)
      }
      if error is Http(404) {
        return (state.forget(id), @cmd.none, None)
      }
      let next = state.replace(id, {
        ..conversation,
        loading: false,
        notice: Some(error.label()),
      })
      let (next, command) = next.failed(error)
      (
        next,
        @cmd.batch([
          command,
          if conversation.generating && !(error is Unauthorized) {
            poll(epoch, id, request, emit)
          } else {
            @cmd.none
          },
        ]),
        None,
      )
    }
    Poll(epoch, id, request) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.request == request &&
        conversation.generating &&
        !conversation.sending else {
        return (state, @cmd.none, None)
      }
      let (next, command) = state.load(id, token, emit)
      (next, command, None)
    }
    Submit(owner, draft) =>
      state.submit(owner, draft, [], emit, token?, navigation~)
    SubmitAttachments(owner, draft, attachments) =>
      state.submit(owner, draft, attachments, emit, token?, navigation~)
    StreamEvent(epoch, id, request, event) => {
      guard epoch == state.epoch &&
        event.session_id == id &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.request == request &&
        conversation.sending &&
        (conversation.task is None || conversation.generating) &&
        (conversation.task is None || conversation.task == Some(event.task_id)) &&
        (
          conversation.last_seq is None ||
          (conversation.last_seq is Some(seq) && event.seq > seq)
        ) else {
        return (state, @cmd.none, None)
      }
      let admitted = event.kind == "task_started" &&
        conversation.pending is Some(_)
      let events = if admitted && conversation.pending is Some(submission) {
        [
          {
            ..event,
            kind: "user",
            data: { "content": submission.content.to_json() },
          },
        ]
      } else if event.is_live_progress() {
        conversation.events
      } else {
        conversation.events + [event]
      }
      let conversation = conversation.live_progress(event)
      let next = state.replace(id, {
        ..conversation,
        events,
        task: Some(event.task_id),
        last_seq: Some(event.seq),
        generating: event.kind != "task_finished",
        pending: if admitted {
          None
        } else {
          conversation.pending
        },
        uploads: if admitted {
          []
        } else {
          conversation.uploads
        },
        submission_sequence: conversation.submission_sequence +
        (if admitted { 1 } else { 0 }),
        initial_submission: if admitted {
          None
        } else {
          conversation.initial_submission
        },
      })
      let (next, command) = if admitted {
        next.list(token, emit)
      } else {
        (next, @cmd.none)
      }
      (next, command, None)
    }
    StreamEnded(epoch, id, request) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.request == request &&
        conversation.sending else {
        return (state, @cmd.none, None)
      }
      let (next, history) = state
        .replace(id, {
          ..conversation.clear_progress(),
          sending: false,
          stream: None,
        })
        .load(id, token, emit)
      let (next, list) = next.list(token, emit)
      (next, @cmd.batch([history, list]), None)
    }
    SendFailed(epoch, id, request, error) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.request == request else {
        return (state, @cmd.none, None)
      }
      let configuration = error is ServiceNotConfigured
      let next = state.replace(id, {
        ..conversation.clear_progress(),
        sending: false,
        stream: None,
        notice: Some(error.label()),
        history_required: if configuration {
          false
        } else {
          conversation.history_required
        },
        pending: if configuration || error is Busy {
          None
        } else {
          conversation.pending
        },
      })
      if configuration {
        return ({ ..next, notice: Some(error.label()), }, @cmd.none, None)
      }
      let (next, command) = if error is Unauthorized {
        next.failed(error)
      } else {
        next.load(id, token, emit)
      }
      (next, command, None)
    }
    AttachmentStored(epoch, id, request, source, path) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.request == request &&
        conversation.sending else {
        return (state, @cmd.none, None)
      }
      (
        state.replace(id, {
          ..conversation,
          uploads: [..conversation.uploads, { source, path, }],
        }),
        @cmd.none,
        None,
      )
    }
    MessagePrepared(epoch, id, request, draft, content) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.request == request &&
        conversation.sending &&
        conversation.pending is Some(pending) else {
        return (state, @cmd.none, None)
      }
      (
        state.replace(id, {
          ..conversation,
          pending: Some({ ..pending, content, }),
          initial_submission: conversation.initial_submission.map(_ => draft),
          initial_attachments: [],
        }),
        @cmd.none,
        None,
      )
    }
  }
  (next, command, select)
}

///|
fn State::submit(
  self : State,
  owner : @interop.ConversationIdentity,
  draft : @composer.Draft,
  attachments : Array[@protocol.AttachmentSource],
  emit : @cmd.Emit[Msg],
  token? : String,
  navigation~ : Int32,
) -> (State, @cmd.Cmd, String?) {
  let state = self
  if state.draft_identity() == Some(owner) && state.creation is Some(creation) {
    guard creation.submission is None &&
      token is Some(_) &&
      (!draft.is_blank() || !attachments.is_empty()) &&
      draft.mentions.all(mention => {
        mention.ref_ is (File(..) | OfficeSelection(..))
      }) else {
      return (state, @cmd.none, None)
    }
    let request = state.sequence + 1
    let next = {
      ..state,
      sequence: request,
      notice: None,
      creation: Some({
        ..creation,
        request,
        navigation,
        submission: Some(draft),
        attachments,
      }),
    }
    let (next, command) = next.create(token, emit)
    return (next, command, None)
  }
  guard owner is @interop.Cloud(account~, session=id) &&
    state.user_id == Some(account) &&
    token is Some(token) &&
    state.conversations.get(id) is Some(conversation) &&
    state.can_send(id) &&
    (!draft.is_blank() || !attachments.is_empty()) &&
    draft.mentions.all(mention => {
      mention.ref_
      is (File(..)
      | OfficeSelection(..)
      | Annotation(side=WorkingRevision, ..)
      | SemanticSearch(_)
      | SemanticSearchArtifact(_))
    }) else {
    return (state, @cmd.none, None)
  }
  let request = state.sequence + 1
  let stream = StreamLease::new()
  let prompt = prompt_content(draft) catch {
    @cloud_client.RequestError(failure) =>
      return (
        state.replace(id, { ..conversation, notice: Some(failure.label()), }),
        @cmd.none,
        None,
      )
  }
  let next = state.replace(id, {
    ..conversation.clear_progress(),
    request,
    sending: true,
    heartbeat: Some({ stage: @composer.Starting, started_ms: None, tokens: 0, }),
    stream: Some(stream),
    history_required: true,
    events: [],
    task: None,
    last_seq: None,
    notice: None,
    pending: Some({
      content: prompt,
      known_tasks: conversation.records
      .filter(record => record.kind == "user")
      .map(record => record.task_id),
    }),
  })
  let command = @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let task : async () -> Msg = () => {
        try {
          guard stream.active else {
            return StreamEnded(state.epoch, id, request)
          }
          let prepared = prepare_submission(
            token,
            id,
            draft,
            attachments,
            conversation.uploads,
            (source, path) => {
              scheduler.add(
                emit(AttachmentStored(state.epoch, id, request, source, path)),
              )
            },
          )
          let prompt = prompt_content(prepared)
          scheduler.add(
            emit(MessagePrepared(state.epoch, id, request, prepared, prompt)),
          )
          send_message(token, id, prompt, stream, event => {
            scheduler.add(emit(StreamEvent(state.epoch, id, request, event)))
          })
          StreamEnded(state.epoch, id, request)
        } catch {
          @cloud_client.RequestError(error) =>
            SendFailed(state.epoch, id, request, error)
          _ => SendFailed(state.epoch, id, request, Unreachable)
        }
      }
      scheduler.add(emit(task()))
    })
    |> ignore
  })
  ({ ..next, sequence: request, notice: None, }, command, None)
}
