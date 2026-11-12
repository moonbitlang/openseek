///|
fn run(emit : @cmd.Emit[Msg], task : async () -> Msg) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => scheduler.add(emit(task()))) |> ignore
  })
}

///|
/// Replace conversation `id` in a copy of the conversation map.
pub fn State::replace(
  self : State,
  id : String,
  conversation : Conversation,
) -> State {
  let conversations = self.conversations.copy()
  conversations[id] = conversation
  { ..self, conversations, }
}

///|
pub fn State::mark_read(self : State, id : String) -> State {
  guard self.conversations.get(id) is Some(conversation) &&
    conversation.unseen_finish else {
    return self
  }
  self.replace(id, { ..conversation, unseen_finish: false, })
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
    {
      ..self,
      sequence: request,
      list_request: request,
      list_status: if self.list_status is Idle {
        Idle
      } else {
        Retrying
      },
    },
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
  reuse~ : Bool = false,
) -> (State, @cmd.Cmd) {
  guard token is Some(token) else { return (self, @cmd.none) }
  let conversation = self.conversations.get(id).unwrap_or(Conversation::empty())
  if conversation.history_reading {
    // One latest-page read at a time. A revisit shares it. A durable SSE
    // boundary needs a snapshot that started after it, so the settled read
    // is applied and then followed by exactly one more read.
    return if reuse {
      (self, @cmd.none)
    } else {
      (
        self.replace(id, { ..conversation, history_refresh_after_read: true, }),
        @cmd.none,
      )
    }
  }
  let request = self.sequence + 1
  let next = self.replace(id, {
    ..conversation,
    request,
    history_reading: true,
    history_refresh_after_read: false,
  })
  (
    { ..next, sequence: request, },
    run(emit, () => {
      load_latest_history(
        token,
        id,
        conversation.history_etag,
        self.epoch,
        request,
      ) catch {
        @cloud_client.RequestError(error) =>
          LoadFailed(self.epoch, id, request, error)
        _ => LoadFailed(self.epoch, id, request, Unreachable)
      }
    }),
  )
}

///|
/// Read again the first turn cached while it was running once a later turn
/// became the latest page. Its records, and any preview waiting for them,
/// are otherwise never refreshed.
fn State::reread_turn(
  self : State,
  id : String,
  token : String?,
  emit : @cmd.Emit[Msg],
) -> (State, @cmd.Cmd) {
  guard token is Some(token) &&
    self.conversations.get(id) is Some(conversation) &&
    conversation.history_turn_request is None &&
    conversation.history_window.stale_offset() is Some(offset) else {
    return (self, @cmd.none)
  }
  let request = self.sequence + 1
  let next = self.replace(id, {
    ..conversation,
    history_turn_request: Some((request, offset)),
  })
  (
    { ..next, sequence: request, },
    run(emit, () => {
      TurnLoaded(self.epoch, id, request, load_turn_history(token, id, offset)) catch {
        @cloud_client.RequestError(error) =>
          TurnFailed(self.epoch, id, request, error)
        _ => TurnFailed(self.epoch, id, request, Unreachable)
      }
    }),
  )
}

///|
fn Conversation::fence_history(
  self : Conversation,
  request : Int32,
) -> Conversation {
  {
    ..self,
    request,
    // A fresh observation baseline must be able to recover even if a
    // read from the previous connection is still waiting on the network.
    history_reading: false,
    history_refresh_after_read: false,
  }
}

///|
fn State::fence_archived_history(
  self : State,
  id : String,
  request : Int32,
  token : String?,
  emit : @cmd.Emit[Msg],
) -> (State, @cmd.Cmd) {
  // A prompt being prepared or submitted still owns its admission request.
  guard self.conversations.get(id) is Some(conversation) &&
    !conversation.sending &&
    conversation.history_cache_request != Some(conversation.request) else {
    return (self, @cmd.none)
  }
  // Fence pre-archive reads even after a later restore. Replace an unfinished
  // read through the existing loader so the retained transcript can complete.
  let refresh = conversation.history_reading ||
    conversation.loading ||
    conversation.generating ||
    conversation.history_required
  let loading = refresh && !conversation.history_cached
  let next = self.replace(id, {
    ..conversation.fence_history(request),
    generating: false,
    loading,
    history_required: conversation.history_required || loading,
  })
  if refresh {
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
      notice: Some(Notice::Failure(error)),
    },
    @cmd.none,
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
fn State::is_draft(self : State, id : String) -> Bool {
  self.creation.map_or(false, creation => creation.id == id)
}

///|
pub fn State::creating_session(self : State) -> Bool {
  self.creation
  .bind(creation => self.conversations.get(creation.id))
  .map_or(false, conversation => conversation.outgoing is Some(_))
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
    !conversation.sending &&
    conversation.outgoing is None &&
    !conversation.generating
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
    SetApproval(mode) =>
      session.approval != mode && self.can_choose_settings(id)
    SetModel(model) => session.model != model && self.can_choose_settings(id)
    SetThinking(thinking) =>
      session.thinking != thinking && self.can_choose_settings(id)
  }
}

///|
/// A running engine keeps the options it started with, so the server refuses
/// a change until the turn ends. A draft keeps its choice until creation;
/// creation and metadata saves in flight hold the picker.
pub fn State::can_choose_settings(self : State, id : String) -> Bool {
  !self.retired.contains(id) &&
  !self.deletions.contains(id) &&
  !self.metadata_saves.contains(id) &&
  (
    self.is_draft(id) ||
    self.sessions.any(session => {
      session.id == id && !session.archived && !session.generating
    })
  ) &&
  self.conversations
  .get(id)
  .map_or(true, conversation => {
    !conversation.sending &&
    conversation.outgoing is None &&
    !conversation.generating &&
    !conversation.controls.is_compacting() &&
    !conversation.controls.is_compact_queued()
  })
}

///|
/// The mode the session's next engine starts with, including a draft's choice.
pub fn State::approval(self : State, id : String) -> @protocol.OpenSeekApproval {
  if self.creation is Some({ id: draft, approval, .. }) && draft == id {
    return approval
  }
  match self.sessions.iter().find_first(session => session.id == id) {
    Some(session) => session.approval
    None => ApprovalAsk
  }
}

///|
pub fn State::model(self : State, id : String) -> @deepseek.DsVariant {
  if self.creation is Some({ id: draft, model, .. }) && draft == id {
    return model
  }
  self.sessions
  .iter()
  .find_first(session => session.id == id)
  .map(session => session.model)
  .unwrap_or(V4Flash)
}

///|
pub fn State::thinking(self : State, id : String) -> @protocol.Thinking {
  if self.creation is Some({ id: draft, thinking, .. }) && draft == id {
    return thinking
  }
  self.sessions
  .iter()
  .find_first(session => session.id == id)
  .map(session => session.thinking)
  .unwrap_or(ThinkingHigh)
}

///|
pub fn State::is_archived(self : State, id : String) -> Bool {
  self.sessions.any(session => session.id == id && session.archived)
}

///|
/// Direct links can load history before the catalog confirms editability.
pub fn State::can_compose(self : State, id : String) -> Bool {
  self.is_draft(id) ||
  self.sessions.any(session => session.id == id && !session.archived)
}

///|
pub fn State::can_send(self : State, id : String) -> Bool {
  self.conversations.get(id) is Some(conversation) &&
  self.can_compose(id) &&
  !self.deletions.contains(id) &&
  // The next turn starts with saved options, never a pending edit.
  !(self.metadata_saves.get(id)
  is Some(
    { edit: Archive(true) | SetApproval(_) | SetModel(_) | SetThinking(_), .. },
  )) &&
  !conversation.loading &&
  !conversation.sending &&
  conversation.outgoing is None &&
  !conversation.generating &&
  !conversation.controls.is_compacting() &&
  !conversation.controls.is_compact_queued() &&
  conversation.watch_status == Watching &&
  (self.is_draft(id) || conversation.last_seq is Some(_)) &&
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
    cached_sessions: self.cached_sessions.filter(session => session.id != id),
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
  client_tools~ : Bool = false,
) -> (State, @cmd.Cmd, String?) {
  let state = { ..state, client_tools, }
  // A boundary observed while this read was in flight may be missing from it.
  // Settle the read first so its records are not discarded, then read again.
  let follow_up = match msg {
    Loaded(epoch, id, request, _)
    | HistoryUnchanged(epoch, id, request, _)
    | LoadFailed(epoch, id, request, _) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.request == request else {
        return (state, @cmd.none, None)
      }
      if conversation.history_refresh_after_read {
        Some(id)
      } else {
        None
      }
    }
    _ => None
  }
  if state.update_command(msg, emit, token, navigation) is Some((next, command)) {
    return (next, command, None)
  }
  if state.update_control(msg, emit, token) is Some((next, command)) {
    return (next, command, None)
  }
  let (next, command, select) = match msg {
    ClientToolsReady(epoch, id, ready) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) else {
        return (state, @cmd.none, None)
      }
      let next = state.replace(id, {
        ..conversation,
        client_tools_ready: ready,
      })
      let (next, command) = if ready && conversation.last_seq is Some(_) {
        next.send_pending(id, token, emit)
      } else {
        (next, @cmd.none)
      }
      (next, command, None)
    }
    QuestionInput(account~, session~, text~, id~) => {
      guard state.user_id == Some(account) &&
        token is Some(token) &&
        !state.retired.contains(session) else {
        return (state, @cmd.none, None)
      }
      (
        state,
        run(emit, () => {
          try deliver_question_input(token, session, text, id) catch {
            @cloud_client.RequestError(failure) =>
              QuestionInputFailed(
                state.epoch,
                session,
                QuestionAnswerFailed(failure),
              )
            error =>
              QuestionInputFailed(
                state.epoch,
                session,
                QuestionAnswerDetail("\{error}"),
              )
          } noraise {
            Accepted => QuestionInputDelivered(state.epoch, session)
            Rejected(reason) =>
              QuestionInputFailed(
                state.epoch,
                session,
                QuestionAnswerDetail(reason),
              )
          }
        }),
        None,
      )
    }
    QuestionInputDelivered(epoch, id) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) else {
        return (state, @cmd.none, None)
      }
      (
        state.replace(id, {
          ..conversation,
          generating: true,
          watch_status: Watching,
          history_required: true,
        }),
        @cmd.none,
        None,
      )
    }
    QuestionInputFailed(epoch, id, error) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) else {
        return (state, @cmd.none, None)
      }
      (
        state.replace(id, { ..conversation, notice: Some(error), }),
        @cmd.none,
        None,
      )
    }
    AccountChanged(user_id) => {
      let cache_catalog = user_id is Some(_) && token is Some(_)
      let next = {
        ..State::empty(),
        client_tools,
        user_id,
        epoch: state.epoch + 1,
        sequence: state.sequence,
        cached_catalog_pending: cache_catalog,
      }
      let (next, command) = next.list(token, emit)
      let catalog = if cache_catalog && token is Some(token) {
        run(emit, () => {
          let entries = match next.history_cache(token, List) {
            Entries(entries) => entries
            _ => []
          }
          CachedCatalog(next.epoch, entries)
        })
      } else {
        @cmd.none
      }
      (
        next,
        @cmd.batch([next.cache_account_changed(state.user_id), command, catalog]),
        None,
      )
    }
    Refresh => {
      guard !(state.list_status is Retrying) else {
        return (state, @cmd.none, None)
      }
      let (next, command) = state.list(token, emit)
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
      let metadata_saves = next.metadata_saves.copy()
      for id, save in next.metadata_saves {
        if save.confirming && request > save.request {
          metadata_saves.remove(id)
        }
      }
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
      (
        {
          ..next,
          sessions,
          metadata_saves,
          cached_sessions: [],
          cached_catalog_pending: false,
          list_status: Idle,
        },
        @cmd.batch(history),
        None,
      )
    }
    ListFailed(epoch, request, error) => {
      guard epoch == state.epoch && request == state.list_request else {
        return (state, @cmd.none, None)
      }
      if error is Unauthorized {
        let (next, command) = state.failed(error)
        (next, command, None)
      } else {
        ({ ..state, list_status: Failed, }, @cmd.none, None)
      }
    }
    CachedCatalog(epoch, entries) => {
      guard epoch == state.epoch && state.cached_catalog_pending else {
        return (state, @cmd.none, None)
      }
      let cached_sessions = entries.filter_map(entry => {
        if state.retired.contains(entry.session) {
          None
        } else {
          Some({
            id: entry.session,
            title: Some(entry.label),
            updated_at: None,
            generating: false,
            archived: false,
            approval: ApprovalAsk,
            model: V4Flash,
            thinking: ThinkingHigh,
          })
        }
      })
      (
        { ..state, cached_sessions, cached_catalog_pending: false, },
        @cmd.none,
        None,
      )
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
      let id = "draft:\{request}"
      let next = {
        ..state,
        sequence: request,
        creation: Some({
          id,
          request,
          navigation,
          approval: ApprovalAsk,
          model: V4Flash,
          thinking: ThinkingHigh,
        }),
        notice: None,
      }.replace(id, {
        ..Conversation::empty(),
        loading: false,
        history_required: false,
      })
      (next, @cmd.none, None)
    }
    TerminalRequested(owner, shell) => {
      guard owner is @interop.Cloud(account~, session=id) &&
        state.user_id == Some(account) &&
        token is Some(token) &&
        state.can_compose(id) &&
        !state.retired.contains(id) &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.outgoing is None else {
        return (state, @cmd.none, None)
      }
      let (next, command) = state.submit_command(
        id,
        { request: state.sequence + 1, input: Terminal(shell), },
        emit,
        token,
        navigation,
      )
      (next, command, None)
    }
    TerminalReady(_, _, _) => (state, @cmd.none, None)
    Created(epoch, request, id) => {
      guard epoch == state.epoch &&
        state.creation is Some(creation) &&
        creation.request == request &&
        state.conversations.get(creation.id) is Some(conversation) &&
        conversation.outgoing is Some(_) &&
        state.user_id is Some(_) else {
        return (state, @cmd.none, None)
      }
      let sessions = [
        {
          id,
          title: None,
          updated_at: None,
          generating: false,
          archived: false,
          approval: creation.approval,
          model: creation.model,
          thinking: creation.thinking,
        },
        ..state.sessions.filter(session => session.id != id),
      ]
      let conversations = state.conversations.copy()
      conversations.remove(creation.id)
      conversations[id] = conversation
      let (next, command) = {
        ..state,
        sessions,
        conversations,
        creation: None,
      }.list(token, emit)
      let (next, terminal) = if conversation.outgoing
        is Some({ input: Terminal(_), .. }) {
        next.send_pending(id, token, emit)
      } else {
        (next, @cmd.none)
      }
      (
        next,
        @cmd.batch([command, terminal]),
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
        state.conversations.get(creation.id) is Some(conversation) &&
        conversation.outgoing is Some(submission) else {
        return (state, @cmd.none, None)
      }
      let controls = match submission.input {
        Native(command) =>
          conversation.controls.delivered(
            command,
            submission.request.to_string(),
            @engine_session.Rejected,
          )
        Prompt(..) | Terminal(_) => conversation.controls
      }
      let next = { ..state, needs_sign_in: error is Unauthorized, }.replace(
        creation.id,
        {
          ..conversation,
          outgoing: None,
          controls,
          notice: match submission.input {
            Prompt(..) | Native(_) => Some(Notice::Failure(error))
            Terminal(_) => None
          },
        },
      )
      (next, @cmd.none, None)
    }
    Edit(account~, session=id, edit~) => {
      if state.creation is Some(creation) && creation.id == id {
        guard state.user_id == Some(account) &&
          token is Some(_) &&
          state.can_choose_settings(id) else {
          return (state, @cmd.none, None)
        }
        let creation = match edit {
          SetApproval(approval) => { ..creation, approval, }
          SetModel(model) => { ..creation, model, }
          SetThinking(thinking) => { ..creation, thinking, }
          _ => return (state, @cmd.none, None)
        }
        return ({ ..state, creation: Some(creation), }, @cmd.none, None)
      }
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
      metadata_saves[id] = { request, edit, navigation, confirming: false, }
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
            SetApproval(approval) => { ..session, approval, }
            SetModel(model) => { ..session, model, }
            SetThinking(thinking) => { ..session, thinking, }
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
      let uncertain = match error {
        Unreachable => true
        Http(status) => status == 408 || status >= 500
        _ => false
      }
      if save.edit is (SetApproval(_) | SetModel(_) | SetThinking(_)) &&
        uncertain {
        let metadata_saves = state.metadata_saves.copy()
        metadata_saves[id] = { ..save, confirming: true, }
        let (next, _) = { ..state, metadata_saves, }.failed(error)
        let (next, command) = next.list(token, emit)
        return (next, command, None)
      }
      let metadata_saves = state.metadata_saves.copy()
      metadata_saves.remove(id)
      let (next, command) = { ..state, metadata_saves, }.failed(error)
      // A turn admitted before the PATCH holds its startup options.
      if save.edit is (SetApproval(_) | SetModel(_) | SetThinking(_)) &&
        error is Http(409) {
        return ({ ..next, notice: Some(SettingsSaveRaced), }, command, None)
      }
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
      (state.forget(id), state.cache_mutation(token, Remove(session=id)), None)
    }
    DeleteFailed(epoch, id, request, error) => {
      guard epoch == state.epoch && state.deletions.get(id) == Some(request) else {
        return (state, @cmd.none, None)
      }
      if error is Http(404) {
        return (
          state.forget(id),
          state.cache_mutation(token, Remove(session=id)),
          None,
        )
      }
      let deletions = state.deletions.copy()
      deletions.remove(id)
      let (next, command) = { ..state, deletions, }.failed(error)
      (
        if error is Busy {
          { ..next, notice: Some(DeleteWhileGenerating), }
        } else {
          next
        },
        command,
        None,
      )
    }
    WatchOpened(epoch, id, stream) => {
      guard epoch == state.epoch &&
        stream.active &&
        state.conversations.get(id) is Some(conversation) else {
        return (state, @cmd.none, None)
      }
      (
        state.replace(id, {
          ..conversation,
          stream: Some(stream),
          last_seq: None,
          // Frames before this connection's baseline may have been missed.
          live_task: None,
        }),
        @cmd.none,
        None,
      )
    }
    WatchEvent(epoch, id, stream, incoming) => {
      guard epoch == state.epoch &&
        stream.active &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.stream == Some(stream) else {
        return (state, @cmd.none, None)
      }
      match incoming {
        Snapshot(snapshot) => {
          let baseline = conversation.last_seq is None
          guard baseline ||
            conversation.last_seq.map_or(true, seq => snapshot.seq > seq) else {
            return (state, @cmd.none, None)
          }
          let admitted = conversation.pending is Some(submitted) &&
            snapshot.task_id is Some(task) &&
            !submitted.known_tasks.contains(task)
          let refresh_history = baseline &&
            conversation.history_resume_baseline is Some((task, seq)) &&
            (snapshot.task_id != task || seq != Some(snapshot.seq))
          let conversation = conversation.control_snapshot(
            snapshot.task_id,
            snapshot.data,
          )
          let next = state.replace(id, {
            ..conversation,
            queue_edit: conversation.queue_edit.filter(id => {
              snapshot.data.queue.any(item => item.id == id)
            }),
            task: snapshot.task_id,
            notification_answer: if snapshot.task_id == conversation.task {
              conversation.notification_answer
            } else {
              None
            },
            events: if snapshot.task_id != conversation.task {
              []
            } else {
              conversation.events
            },
            last_seq: Some(snapshot.seq),
            history_resume_baseline: None,
            generating: snapshot.data.active_task_id is Some(_),
            observed_task: match snapshot.data.active_task_id {
              Some(task) => Some(task)
              None => conversation.observed_task
            },
            controls: if conversation.outgoing is Some(_) {
              conversation.controls
            } else {
              conversation.controls.observe_compaction(
                queued=snapshot.data.compact_queued,
                compacting=snapshot.data.compacting,
                baseline~,
              )
            },
            sending: conversation.sending && !admitted,
            pending: if admitted {
              None
            } else {
              conversation.pending
            },
            submission_sequence: conversation.submission_sequence +
            (if admitted &&
              conversation.pending.map_or(false, p => p.result_id is None) {
              1
            } else {
              0
            }),
            initial_submission: if admitted &&
              conversation.pending.map_or(false, p => p.result_id is None) {
              None
            } else {
              conversation.initial_submission
            },
            initial_attachments: if admitted &&
              conversation.pending.map_or(false, p => p.result_id is None) {
              []
            } else {
              conversation.initial_attachments
            },
            uploads: if admitted {
              []
            } else {
              conversation.uploads
            },
          })
          if baseline && conversation.outgoing is Some(_) {
            let (next, command) = next.send_pending(id, token, emit)
            return (next, command, None)
          }
          if admitted ||
            (baseline && conversation.watch_status == Reconnecting) ||
            refresh_history {
            let (next, command) = next.load(id, token, emit)
            (next, command, None)
          } else {
            (next, @cmd.none, None)
          }
        }
        EngineEvent(event) => {
          // Only the connection's first snapshot establishes its baseline.
          guard conversation.last_seq is Some(_) else {
            return (state, @cmd.none, None)
          }
          update(
            state,
            StreamEvent(epoch, id, conversation.request, event),
            emit,
            token?,
            navigation~,
          )
        }
        EngineFailed(session~, seq~, error~) => {
          guard session == id &&
            conversation.last_seq is Some(last) &&
            seq > last else {
            return (state, @cmd.none, None)
          }

          (
            state.replace(id, {
              ..conversation,
              controls: conversation.controls.host_failed(),
              last_seq: Some(seq),
              notice: Some(EngineDetail(error)),
            }),
            @cmd.none,
            None,
          )
        }
        NativeEvent(frame) => {
          guard conversation.last_seq is Some(seq) && frame.seq > seq else {
            return (state, @cmd.none, None)
          }
          state.engine_event(id, frame, token, emit)
        }
      }
    }
    WatchEnded(epoch, id, stream, error) => {
      guard epoch == state.epoch &&
        stream.active &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.stream == Some(stream) else {
        return (state, @cmd.none, None)
      }
      stream.close()
      if error is Some(Http(404)) {
        return (state.forget(id), @cmd.none, None)
      }
      let retry = retry_observation(error)
      let request = state.sequence + 1
      let next = state.replace(id, {
        ..conversation.clear_progress().fence_history(request),
        live_task: None,
        // Fence history reads from the interrupted connection. Only a fresh
        // snapshot can establish the run state for the following history read.
        stream: None,
        history_resume_baseline: None,
        watch_request: conversation.watch_request + 1,
        watch_status: if retry {
          Reconnecting
        } else {
          Disconnected
        },
        notice: if retry {
          conversation.notice
        } else {
          error.map(error => Notice::Failure(error))
        },
      })
      let next = { ..next, sequence: request, }
      let (next, command) = if error is Some(Unauthorized) {
        next.failed(Unauthorized)
      } else {
        (next, @cmd.none)
      }
      (next, command, None)
    }
    ControlPreparationFailed(_, _, _, _, _)
    | CommandFinished(_, _, _, _, _)
    | CommandFailed(_, _, _, _, _)
    | ControlAction(_, _)
    | ControlPrepared(_, _, _, _, _, _)
    | ControlAttachmentStored(_, _, _, _, _, _)
    | ControlFinished(_, _, _, _, _)
    | ControlChecked(_, _, _, _)
    | ControlFailed(_, _, _, _, _) => (state, @cmd.none, None)
    Open(id) => {
      guard token is Some(_) && !state.retired.contains(id) else {
        return (state, @cmd.none, None)
      }
      let conversation = state.conversations
        .get(id)
        .unwrap_or(Conversation::empty())
      let next = if (
          conversation.outgoing is Some(_) &&
          conversation.watch_status != Disconnected
        ) ||
        conversation.sending ||
        conversation.stream is Some({ active: true, .. }) {
        state
      } else {
        state.replace(id, {
          ..conversation.clear_progress(),
          loading: !conversation.history_cached,
          history_required: !conversation.history_cached ||
          conversation.history_required,
          history_resume_baseline: if conversation.history_reading &&
            conversation.history_resume_baseline is None {
            Some((conversation.task, conversation.last_seq))
          } else {
            conversation.history_resume_baseline
          },
          watch_request: conversation.watch_request + 1,
          watch_status: Watching,
          stream: None,
          last_seq: None,
          notice: None,
        })
      }
      let (next, command) = if token is Some(token) &&
        !conversation.history_cached &&
        !conversation.history_reading &&
        conversation.history_cache_request is None {
        next.read_persistent_history(id, token, emit)
      } else {
        next.load(id, token, emit, reuse=true)
      }
      (next, command, None)
    }
    CachedHistoryLoaded(epoch, id, request, history) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.history_cache_request == Some(request) else {
        return (state, @cmd.none, None)
      }
      let awaiting_cache = conversation.request == request &&
        conversation.history_reading
      // A boundary observed during the cache read is covered by the network
      // read that follows it, which starts after that boundary.
      let conversation = {
        ..conversation,
        history_cache_request: None,
        history_reading: conversation.history_reading && !awaiting_cache,
      }
      let next = state.replace(
        id,
        if history is Some(history) && !conversation.history_cached {
          let cached = conversation
            .with_latest_page(history)
            .with_prediction(history.prediction)
          {
            ..cached.restore_goal(cached.document),
            history_cached: true,
            history_etag: history.etag,
            history_required: false,
            loading: false,
          }
        } else {
          conversation
        },
      )
      if !awaiting_cache {
        return (next, @cmd.none, None)
      }
      let (next, command) = next.load(id, token, emit)
      (next, command, None)
    }
    LoadOlder(id) => {
      guard state.conversations.get(id) is Some(conversation) &&
        conversation.older_history_offset() is Some(offset) else {
        return (state, @cmd.none, None)
      }
      let window = conversation.history_window.reattach()
      if window != conversation.history_window {
        let next = conversation.with_history_window(window)
        return (state.replace(id, next), @cmd.none, None)
      }
      guard token is Some(token) else { return (state, @cmd.none, None) }
      let request = state.sequence + 1
      let next = state.replace(id, {
        ..conversation,
        history_older_request: Some((request, offset, navigation)),
      })
      (
        { ..next, sequence: request, },
        run(emit, () => {
          OlderLoaded(
            state.epoch,
            id,
            request,
            load_turn_history(token, id, offset),
          ) catch {
            @cloud_client.RequestError(error) =>
              OlderFailed(state.epoch, id, request, error)
            _ => OlderFailed(state.epoch, id, request, Unreachable)
          }
        }),
        None,
      )
    }
    OlderLoaded(epoch, id, request, history) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.history_older_request is Some((pending, offset, owner)) &&
        request == pending else {
        return (state, @cmd.none, None)
      }
      let conversation = { ..conversation, history_older_request: None, }
      let next = if owner == navigation && history.offset == Some(offset) {
        conversation.with_older_page({ ..history, generating: false, }, request)
      } else {
        conversation
      }
      (state.replace(id, next), @cmd.none, None)
    }
    TurnLoaded(epoch, id, request, history) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.history_turn_request is Some((pending, offset)) &&
        request == pending else {
        return (state, @cmd.none, None)
      }
      // A later turn exists, so this one is finished whatever the
      // session-wide generating flag says.
      let settled = conversation.with_turn_page(
        offset,
        { ..history, generating: false, },
        request,
      )
      let next = state.replace(id, { ..settled, history_turn_request: None, })
      // A reply that no longer fits the window waits for the next latest
      // read rather than asking for the same turn again.
      if settled.history_window == conversation.history_window {
        return (next, @cmd.none, None)
      }
      let (next, command) = next.reread_turn(id, token, emit)
      (next, command, None)
    }
    TurnFailed(epoch, id, request, error) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.history_turn_request is Some((pending, _)) &&
        request == pending else {
        return (state, @cmd.none, None)
      }
      // Previews stay. The next latest read tries the stale turn again.
      let next = state.replace(id, {
        ..conversation,
        history_turn_request: None,
      })
      let (next, command) = if error is Unauthorized {
        next.failed(error)
      } else {
        (next, @cmd.none)
      }
      (next, command, None)
    }
    OlderFailed(epoch, id, request, error) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.history_older_request is Some((pending, _, _)) &&
        request == pending else {
        return (state, @cmd.none, None)
      }
      let next = state.replace(id, {
        ..conversation,
        history_older_request: None,
      })
      let (next, command) = if error is Unauthorized {
        next.failed(error)
      } else {
        (next, @cmd.none)
      }
      (next, command, None)
    }
    Loaded(epoch, id, request, history) => {
      let conversation = state.conversations[id].with_latest_page(
        history,
        request~,
      )
      let accepted = conversation.pending is Some(submission) &&
        history.messages.any(record => {
          record.kind == "user" &&
          !submission.known_tasks.contains(record.task_id)
        })
      let observed = conversation.stream.map_or(false, stream => stream.active)
      let control = if !observed && !history.generating {
        conversation.control.map(control => {
          ..control,
          active_task_id: None,
          status: Idle,
        })
      } else {
        conversation.control
      }
      let settled = if !history.generating && !observed {
        conversation.clear_progress()
      } else {
        conversation
      }
      let restored = {
        ..settled.restore_goal(conversation.document),
        control,
        history_cached: true,
        history_etag: history.etag,
        history_reading: false,
        history_cache_request: None,
        events: conversation.events.filter(event => {
          !conversation.records.any(record => {
            record.task_id == event.task_id &&
            (record.kind == event.kind || record.kind == "task_finished")
          })
        }),
        loading: false,
        watch_status: if observed && conversation.last_seq is Some(_) {
          Watching
        } else {
          conversation.watch_status
        },
        generating: if conversation.stream is Some(stream) && stream.active {
          control.map_or(history.generating, control => {
            control.active_task_id is Some(_)
          })
        } else {
          history.generating
        },
        history_required: false,
        observed_task: conversation.observed_task.filter(task => {
          conversation.watch_status != Reconnecting ||
          control.map_or(false, control => control.active_task_id == Some(task)) ||
          !history.messages.any(record => {
            record.task_id == task && record.kind == "task_finished"
          })
        }),
        sending: conversation.sending && !accepted,
        pending: if accepted ||
          (
            !conversation.sending &&
            conversation.pending.map_or(true, p => p.result_id is None)
          ) {
          None
        } else {
          conversation.pending
        },
        uploads: if accepted {
          []
        } else {
          conversation.uploads
        },
        // A successful read does not mean the failed send was admitted.
        notice: if (conversation.pending is Some(_) && !accepted) ||
          (!observed && conversation.control is Some(_)) {
          conversation.notice
        } else {
          None
        },
        submission_sequence: conversation.submission_sequence +
        (if accepted &&
          conversation.pending.map_or(false, p => p.result_id is None) {
          1
        } else {
          0
        }),
        initial_submission: if accepted &&
          conversation.pending.map_or(false, p => p.result_id is None) {
          None
        } else {
          conversation.initial_submission
        },
        initial_attachments: if accepted &&
          conversation.pending.map_or(false, p => p.result_id is None) {
          []
        } else {
          conversation.initial_attachments
        },
      }
      let next = state.replace(id, restored.with_prediction(history.prediction))
      let next = {
        ..next,
        sessions: next.sessions.map(session => {
          if session.id == id {
            { ..session, generating: next.conversations[id].generating, }
          } else {
            session
          }
        }),
      }
      let refresh = if history.generating &&
        !conversation.stream.map_or(false, stream => stream.active) {
        poll(epoch, id, request, emit)
      } else {
        @cmd.none
      }
      let (next, turn) = next.reread_turn(id, token, emit)
      (
        next,
        @cmd.batch([
          refresh,
          turn,
          state.cache_mutation(
            token,
            Write(session=id, page=history.cache_page()),
          ),
        ]),
        None,
      )
    }
    HistoryUnchanged(epoch, id, request, etag) => {
      let conversation = state.conversations[id]
      let observing = conversation.stream is Some({ active: true, .. })
      let conversation = match conversation.history_window.latest() {
        Some(page) =>
          conversation.acknowledge_assistants(
            request,
            page.session,
            page.messages,
          )
        None =>
          conversation.acknowledge_assistants(
            request,
            conversation.document,
            conversation.records,
          )
      }
      let next = state.replace(id, {
        ..conversation,
        history_etag: Some(etag),
        history_reading: false,
        history_cache_request: None,
        loading: false,
        history_required: false,
        watch_status: if observing && conversation.last_seq is Some(_) {
          Watching
        } else {
          conversation.watch_status
        },
      })
      let (next, turn) = next.reread_turn(id, token, emit)
      (
        next,
        @cmd.batch([
          turn,
          if conversation.generating && !observing {
            poll(epoch, id, request, emit)
          } else {
            @cmd.none
          },
        ]),
        None,
      )
    }
    LoadFailed(epoch, id, request, error) => {
      let conversation = state.conversations[id]
      if error is Http(404) {
        return (state.forget(id), @cmd.none, None)
      }
      let recovering = conversation.watch_status == Reconnecting
      let retry = retry_observation(Some(error))
      if recovering && !retry && conversation.stream is Some(stream) {
        stream.close()
      }
      let next = state.replace(id, {
        ..conversation,
        history_reading: false,
        loading: false,
        watch_status: if recovering && !retry {
          Disconnected
        } else {
          conversation.watch_status
        },
        notice: if recovering && retry {
          conversation.notice
        } else {
          Some(Notice::Failure(error))
        },
      })
      (
        { ..next, needs_sign_in: error is Unauthorized, },
        if (recovering && retry) ||
          (!recovering && conversation.generating && !(error is Unauthorized)) {
          poll(epoch, id, request, emit)
        } else {
          @cmd.none
        },
        None,
      )
    }
    Poll(epoch, id, request) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.request == request &&
        (conversation.generating || conversation.watch_status == Reconnecting) &&
        // Recovery polling belongs to the selected subscription, just like
        // its reconnect timer. Unloading it makes an already queued poll inert.
        (
          conversation.watch_status != Reconnecting ||
          conversation.stream is Some({ active: true, .. })
        ) &&
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
        conversation.request == request else {
        return (state, @cmd.none, None)
      }
      let same_task = conversation.task == Some(event.task_id)
      let next_task = event.kind == "task_started" && !same_task
      if next_task &&
        event.data is { "previous_task_id": String(previous), .. } &&
        conversation.task != Some(previous) {
        return (state, @cmd.none, None)
      }
      guard conversation.last_seq.map_or(true, seq => event.seq > seq) else {
        return (state, @cmd.none, None)
      }
      guard next_task || same_task || conversation.task is None else {
        // A late receipt can settle its own input, never the current run.
        return (
          state.replace(id, {
            ..conversation.control_receipt(event),
            last_seq: Some(event.seq),
          }),
          @cmd.none,
          None,
        )
      }
      guard event.kind == "task_started" ||
        (same_task && event.kind == "task_finished") ||
        conversation.generating ||
        conversation.task is None else {
        return (
          state.replace(id, conversation.control_receipt(event)),
          @cmd.none,
          None,
        )
      }
      let admitted = event.kind == "task_started" &&
        conversation.pending is Some(_)
      let conversation = if event.kind == "task_started" {
        {
          ..conversation.clear_streams(),
          reasoning_frontier: conversation.durable_frontier(),
          notification_answer: None,
          heartbeat: Some({
            stage: @composer.Thinking,
            started_ms: None,
            tokens: 0,
          }),
          retrying: None,
        }
      } else if event.kind == "task_finished" {
        conversation.clear_progress()
      } else {
        conversation
      }
      let conversation = conversation.control_receipt(event)
      let control = conversation.control.map(control => {
        if event.kind == "task_started" {
          {
            ..control,
            active_task_id: Some(event.task_id),
            status: Running,
            paused: false,
            steers: [],
          }
        } else if event.kind == "task_finished" {
          { ..control, active_task_id: None, status: Idle, }
        } else {
          control
        }
      })
      let next = state.replace(id, {
        ..conversation,
        control,
        events: if event.kind is ("task_started" | "task_finished") {
          [event]
        } else {
          conversation.events
        },
        task: Some(event.task_id),
        live_task: if event.kind == "task_started" {
          Some(event.task_id)
        } else {
          conversation.live_task
        },
        last_seq: Some(event.seq),
        generating: event.kind != "task_finished",
        observed_task: if event.kind == "task_finished" {
          None
        } else {
          Some(event.task_id)
        },
        sending: conversation.sending && !admitted,
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
        (if admitted &&
          conversation.pending.map_or(false, p => p.result_id is None) {
          1
        } else {
          0
        }),
        initial_submission: if admitted &&
          conversation.pending.map_or(false, p => p.result_id is None) {
          None
        } else {
          conversation.initial_submission
        },
        initial_attachments: if admitted &&
          conversation.pending.map_or(false, p => p.result_id is None) {
          []
        } else {
          conversation.initial_attachments
        },
      })
      if event.kind is ("task_finished" | "task_started") {
        let (next, history) = next.load(id, token, emit)
        let (next, list) = next.list(token, emit)
        (next, @cmd.batch([history, list]), None)
      } else {
        (next, @cmd.none, None)
      }
    }
    SendAccepted(epoch, id, request) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.send_request == request else {
        return (state, @cmd.none, None)
      }
      // HTTP acceptance cannot settle the run or clear the submitted draft.
      if conversation.stream is None {
        let (next, command) = state.load(id, token, emit)
        (next, command, None)
      } else {
        (state, @cmd.none, None)
      }
    }
    SendFailed(epoch, id, request, error) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.send_request == request &&
        conversation.pending is Some(_) else {
        return (state, @cmd.none, None)
      }
      let configuration = error is ServiceNotConfigured
      let conversation = if configuration {
        conversation.fence_history(state.sequence + 1)
      } else {
        conversation
      }
      let next = state.replace(id, {
        ..conversation.clear_progress(),
        sending: false,
        notice: Some(Notice::Failure(error)),
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
        return ({ ..next, sequence: state.sequence + 1, }, @cmd.none, None)
      }
      let (next, command) = if error is Unauthorized {
        ({ ..next, needs_sign_in: true, }, @cmd.none)
      } else {
        next.load(id, token, emit)
      }
      (next, command, None)
    }
    AttachmentStored(epoch, id, request, source, path) => {
      guard epoch == state.epoch &&
        state.conversations.get(id) is Some(conversation) &&
        conversation.send_request == request &&
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
        conversation.send_request == request &&
        conversation.sending &&
        conversation.pending is Some(pending) else {
        return (state, @cmd.none, None)
      }
      (
        state.replace(id, {
          ..conversation,
          pending: Some({ ..pending, content, }),
          initial_submission: if pending.result_id is None {
            conversation.initial_submission.map(_ => draft)
          } else {
            conversation.initial_submission
          },
          initial_attachments: if pending.result_id is None {
            []
          } else {
            conversation.initial_attachments
          },
        }),
        @cmd.none,
        None,
      )
    }
  }
  guard follow_up is Some(id) &&
    next.conversations.get(id) is Some(conversation) &&
    !conversation.history_reading &&
    !next.needs_sign_in else {
    return (next, command, select)
  }
  let (next, history) = next.load(id, token, emit)
  (next, @cmd.batch([command, history]), select)
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
  guard owner is @interop.Cloud(account~, session=id) &&
    state.user_id == Some(account) &&
    token is Some(token) &&
    state.can_send(id) &&
    (!draft.is_blank() || !attachments.is_empty()) &&
    draft.mentions.all(mention => {
      mention.ref_
      is (File(..)
      | OfficeSelection(..)
      | Annotation(..)
      | ReviewChanges(_)
      | SemanticSearch(_)
      | SemanticSearchArtifact(_))
    }) else {
    return (state, @cmd.none, None)
  }
  let content = prompt_content(draft) catch {
    @cloud_client.RequestError(failure) =>
      return (
        state.replace(id, {
          ..state.conversations[id],
          notice: Some(Notice::Failure(failure)),
        }),
        @cmd.none,
        None,
      )
  }
  let (next, command) = state.submit_command(
    id,
    {
      request: state.sequence + 1,
      input: Prompt(content~, draft~, attachments~),
    },
    emit,
    token,
    navigation,
  )
  (next, command, None)
}
