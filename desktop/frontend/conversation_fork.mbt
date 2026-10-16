///|
priv enum ConversationForkKind {
  AfterAnswer(through~ : Int32)
  EditedMessage(@protocol.SessionEditPayload)
} derive(Eq)

///|
priv struct ConversationFork {
  source : ConversationSelection
  source_title : String
  kind : ConversationForkKind
  engine_model : EngineModel
  connection_generation : Int32
  source_sequence : Int32
} derive(Eq)

///|
/// Whether a conversation can be forked from its answers: a live record of
/// its own, wherever it works. The fork of a worktree conversation shares
/// that worktree.
fn Conversation::can_fork(self : Conversation) -> Bool {
  self.record is LiveRecord &&
  @transcript.subrun_parent(self.session_id) is None
}

///|
fn Model::request_fork(
  self : Model,
  emit : @cmd.Emit[Msg],
  slot : String,
  through : Int32,
) -> (@cmd.Cmd, Model) {
  guard self.conversation_fork is None &&
    self.transcript_slot().map(value => value.key()) == Some(slot) &&
    self.screen is Chat &&
    self.active_conversation() is Some(conv) &&
    conv.can_fork() &&
    conv.messages.any(item => item.fork_through() == Some(through)) &&
    self.conversation_selection() is Some(source) else {
    return (@cmd.none, self)
  }
  let pending : ConversationFork = {
    source,
    source_title: self.selected_conversation_title(),
    source_sequence: conv.durable_frontier(),
    kind: AfterAnswer(through~),
    engine_model: conv.engine_model,
    connection_generation: self.focused_connection_generation(),
  }
  (
    fork_conversation(emit, pending),
    { ..self, conversation_fork: Some(pending), },
  )
}

///|
fn Model::finish_fork(
  self : Model,
  emit : @cmd.Emit[Msg],
  pending : ConversationFork,
  result : Result[@protocol.SessionForkReply, String],
  fresh_session~ : String,
) -> (@cmd.Cmd, Model) {
  guard self.conversation_fork == Some(pending) else {
    return (@cmd.none, self)
  }
  let model = { ..self, conversation_fork: None, }
  match result {
    Err(message) =>
      model
      .retire_deleted_edit_source(pending, fresh_session)
      .notify_error(emit, message)
    Ok(reply) => {
      let should_open = model.screen is Chat &&
        model.conversation_selection() == Some(pending.source) &&
        model.navigation.location.map_or(true, location => {
          model.navigation.phase is Active &&
          location.target == @navigation.Session(pending.source.session)
        })
      guard model.device_state(pending.source.channel) is Some(dev) &&
        dev.connection_generation == pending.connection_generation &&
        dev.projects.contains(pending.source.workspace) else {
        return (
          @cmd.none,
          model.retire_deleted_edit_source(pending, fresh_session),
        )
      }
      let sessions = dev.sessions.filter(item => {
        item.id != reply.session || item.workspace != pending.source.workspace
      })
      sessions.push({
        id: reply.session,
        title: Some(reply.title),
        workspace: pending.source.workspace,
        workspace_name: @resource.label(pending.source.workspace),
        updated_at_ms: None,
      })
      let mut model = model
        .replace_device({ ..dev, sessions, })
        .remember_model(
          pending.source.channel,
          reply.session,
          pending.engine_model,
        )
      if pending.is_edit() {
        let conv = model
          .find_conversation(pending.source.channel, reply.session)
          .unwrap_or_else(() => {
            empty_conversation(
              pending.source.channel,
              reply.session,
              pending.source.workspace,
              model=pending.engine_model,
            )
          })
        model = model.replace_conversation({
          ..conv,
          workspace: dev.conversation_workspace(
            pending.source.workspace,
            reply.session,
            conv.workspace,
          ),
          worktree_mode: false,
        })
        model = {
          ..model,
          conversations: model.conversations.filter(conv => {
            !pending.source.matches_record(
              conv.device,
              conv.session_id,
              conv.project(),
              conv.record,
            )
          }),
        }
      }
      let save = save_conversation_model(
        conversation_model_key(pending.source.channel, reply.session),
        pending.engine_model,
      )
      // A completed background request must not take the reader away from
      // another conversation or screen they chose while it was pending.
      guard should_open else { return (save, model) }
      let (open, model) = update_msg(
        emit,
        OpenSession(pending.source.channel, reply.session),
        model,
      )
      (
        @cmd.batch([save, open]),
        { ..model, fork_focus: model.selected_conversation, },
      )
    }
  }
}

///|
/// A failed edit still reports its error. If a deletion notification already
/// removed the source, finish the ordinary local deletion transition too.
fn Model::retire_deleted_edit_source(
  self : Model,
  pending : ConversationFork,
  fresh_session : String,
) -> Model {
  let source = pending.source
  guard pending.is_edit() &&
    self.archive_override(source.channel, {
      session: source.session,
      workspace: source.workspace,
    })
    is Some(ArchiveDeleted) else {
    return self
  }
  let model = replace_removed_selection(
    self,
    source.channel,
    source.session,
    fresh_session,
    source.workspace,
    source.record,
  )
  {
    ..model,
    screen: self.screen,
    conversations: model.conversations.filter(conv => {
      conv.device != source.channel ||
      conv.session_id != source.session ||
      conv.project() != source.workspace
    }),
  }
}

///|
fn fork_conversation(
  emit : @cmd.Emit[Msg],
  pending : ConversationFork,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[@protocol.SessionForkReply, String] = try {
        let reply = match pending.kind {
          EditedMessage(payload) =>
            @interop.bridge_request(
              pending.source.channel,
              @commands.session_edit,
              payload,
            )
          AfterAnswer(through~) =>
            @interop.bridge_request(
              pending.source.channel,
              @commands.session_fork,
              {
                session: pending.source.session,
                workspace: pending.source.workspace.path,
                through,
                model: pending.engine_model.wire(),
                source_title: pending.source_title,
              },
            )
        }
        Ok(reply)
      } catch {
        error => Err(@interop.bridge_error_text(error))
      }
      scheduler.add(
        emit(
          ForkCompleted(pending, result, fresh_session=generated_session_id()),
        ),
      )
    })
    |> ignore
  })
}

///|
test "fork is unavailable for archived records and subruns" {
  let conv = test_conversation()
  assert_true(conv.can_fork())
  assert_true(
    (
      { ..conv, workspace: Worktree(project=conv.project(), name="example"), } :
      Conversation).can_fork(),
  )
  for session_id in ["desktop-test-sr-1", "desktop-test-sr-1-sr-2"] {
    assert_false(({ ..conv, session_id, } : Conversation).can_fork())
  }
  assert_false(({ ..conv, record: ArchivedRecord, } : Conversation).can_fork())
}

///|
test "fork and message editing are pure and preserve navigation" {
  let model = test_model().replace_conversation({
    ..test_conversation(),
    sync: Synced,
    task: "自动标题",
    messages: [
      { kind: @transcript.Answer("done"), sequence: Some(4), ts: None, },
    ],
  })
  guard model.transcript_slot() is Some(slot) else {
    fail("missing transcript")
  }
  let emit = test_dispatch()
  let (_, requested) = model.request_fork(emit, slot.key(), 4)
  let (_, again) = model.request_fork(emit, slot.key(), 4)
  assert_true(again.conversation_fork == requested.conversation_fork)
  assert_true(model.conversation_fork is None)
  guard requested.conversation_fork is Some(pending) else {
    fail("missing fork")
  }
  // E2E covers the sidebar title; an unlisted conversation uses its task.
  assert_eq(pending.source_title, "自动标题")
  let (_, invalid) = model.request_fork(emit, slot.key(), 3)
  assert_true(invalid.conversation_fork is None)
  let (_, repeat) = requested.request_fork(emit, slot.key(), 4)
  assert_true(repeat.conversation_fork == requested.conversation_fork)
  // E2E covers chat-to-chat navigation. Also preserve a non-chat page.
  let away = { ..requested, screen: Settings, }
  let result : Result[@protocol.SessionForkReply, String] = Ok({
    session: "desktop-fork",
    title: pending.source_title,
  })
  let (_, done) = away.finish_fork(
    emit,
    pending,
    result,
    fresh_session="desktop-fallback",
  )
  let (_, done_again) = away.finish_fork(
    emit,
    pending,
    result,
    fresh_session="desktop-fallback",
  )
  assert_true(done.dev().sessions == done_again.dev().sessions)
  assert_true(away.dev().sessions == model.dev().sessions)
  assert_true(done.screen is Settings)
  assert_eq(done.active_session, model.active_session)
  assert_true(done.conversation_fork is None)
  assert_true(done.dev().sessions.any(item => item.id == "desktop-fork"))

  // The edit entry point shares these guards and pending-completion rules.
  let source = {
    ..model.active(),
    messages: [
      {
        kind: User(content=Content([Text("first")])),
        sequence: Some(1),
        ts: None,
      },
      { kind: Answer("done"), sequence: Some(4), ts: None, },
      {
        kind: User(content=Content([Text("second")])),
        sequence: Some(5),
        ts: None,
      },
      {
        kind: User(content=Content([Text("steer")])),
        sequence: Some(6),
        ts: None,
      },
    ],
  }
  let editable = model.replace_conversation(source)
  for sequence in [1, 5] {
    let draft : @composer.Draft = {
      task: if sequence == 1 {
        "first revised"
      } else {
        "second revised"
      },
      images: [],
      mentions: [],
    }
    let message = UserMessageEditRequested(slot=slot.key(), sequence~, draft~)
    let (_, requested) = update_msg(emit, message, editable)
    let (_, repeated) = update_msg(emit, message, editable)
    assert_true(requested.conversation_fork == repeated.conversation_fork)
    assert_true(editable.conversation_fork is None)
    guard requested.conversation_fork is Some(pending) else {
      fail("edit pending")
    }
    assert_true(pending.kind is EditedMessage(_))
    let failed : Result[@protocol.SessionForkReply, String] = Err("edit failed")
    let (_, retained) = requested.finish_fork(
      emit,
      pending,
      failed,
      fresh_session="desktop-fallback",
    )
    assert_true(
      retained.find_conversation(source.device, source.session_id) is Some(_),
    )
    let deleted = requested.with_archive_override(
      source.device,
      { session: source.session_id, workspace: source.project(), },
      ArchiveDeleted,
    )
    for screen in [Chat, Settings] {
      let (_, retired) = { ..deleted, screen, }.finish_fork(
        emit,
        pending,
        failed,
        fresh_session="desktop-fallback",
      )
      assert_true(retired.screen == screen)
      assert_true(
        retired.find_conversation(source.device, source.session_id) is None,
      )
      assert_eq(retired.active_session, "desktop-fallback")
      assert_true(retired.conversation_fork is None)
    }
    // Only a still-current deletion fact may retire the source.
    let live = deleted.with_archive_override(
      source.device,
      { session: source.session_id, workspace: source.project(), },
      ArchiveLive,
    )
    let (_, retained) = live.finish_fork(
      emit,
      pending,
      failed,
      fresh_session="desktop-fallback",
    )
    assert_true(
      retained.find_conversation(source.device, source.session_id) is Some(_),
    )
    let (_, done) = requested.finish_fork(
      emit,
      pending,
      result,
      fresh_session="desktop-fallback",
    )
    let (_, again) = requested.finish_fork(
      emit,
      pending,
      result,
      fresh_session="desktop-fallback",
    )
    guard done.find_conversation(source.device, "desktop-fork") is Some(created) &&
      again.find_conversation(source.device, "desktop-fork") is Some(repeated) else {
      fail("edit destination")
    }
    assert_eq(created.task, "")
    assert_eq(created.task, repeated.task)
    assert_true(created.engine_model == source.engine_model)
    assert_false(created.composer_draft_present)
    assert_true(done.conversation_fork is None)
    assert_true(
      done.find_conversation(source.device, source.session_id) is None,
    )
    if sequence == 5 {
      let arrived = requested.replace_conversation({
        ..created,
        messages: [
          { kind: Answer("already loaded"), sequence: Some(4), ts: None, },
        ],
      })
      let (_, preserved) = arrived.finish_fork(
        emit,
        pending,
        result,
        fresh_session="desktop-fallback",
      )
      assert_true(
        preserved
        .find_conversation(source.device, "desktop-fork")
        .map(conv => conv.messages.length()) ==
        Some(1),
      )
    }
    let (_, stale) = requested.finish_fork(
      emit,
      pending,
      result,
      fresh_session="desktop-fallback",
    )
    let (_, replayed) = stale.finish_fork(
      emit,
      pending,
      result,
      fresh_session="desktop-fallback",
    )
    assert_true(stale.conversations == replayed.conversations)
  }
  for sequence in [4, 6, 99] {
    let (_, invalid) = editable.edit_user_message(emit, slot.key(), sequence, {
      task: "revised",
      images: [],
      mentions: [],
    })
    assert_true(invalid.conversation_fork is None)
  }
  let (_, invalid) = editable.edit_user_message(emit, "stale-slot", 5, {
    task: "revised",
    images: [],
    mentions: [],
  })
  assert_true(invalid.conversation_fork is None)
}

///|
test "the fork of a worktree conversation opens in the same worktree" {
  let channel = @interop.ChannelId::Local
  let project = channel.test_project()
  let source : Conversation = {
    ..test_conversation(),
    workspace: Worktree(project~, name="wt-1"),
    sync: Synced,
    messages: [
      { kind: @transcript.Answer("done"), sequence: Some(4), ts: None, },
    ],
  }
  let model = test_model().replace_conversation(source)
  // The host reports the worktree's new member before it replies.
  let model = model.replace_device({
    ..model.dev(),
    worktrees: [
      {
        project,
        rows: [
          {
            name: "wt-1",
            sessions: ["desktop-test", "desktop-fork"],
            codex_thread: None,
            path: None,
            present: true,
          },
        ],
        generation: 0,
      },
    ],
  })
  guard model.transcript_slot() is Some(slot) else {
    fail("missing transcript")
  }
  let emit = test_dispatch()
  let (_, requested) = model.request_fork(emit, slot.key(), 4)
  guard requested.conversation_fork is Some(pending) else {
    fail("a worktree conversation must be forkable")
  }
  let (_, done) = requested.finish_fork(
    emit,
    pending,
    Ok({ session: "desktop-fork", title: pending.source_title, }),
    fresh_session="desktop-fallback",
  )
  guard done.find_conversation(channel, "desktop-fork") is Some(fork) else {
    fail("the fork was not opened")
  }
  assert_true(fork.workspace == Worktree(project~, name="wt-1"))
}

///|
fn ConversationFork::is_edit(self : ConversationFork) -> Bool {
  self.kind is EditedMessage(_)
}
