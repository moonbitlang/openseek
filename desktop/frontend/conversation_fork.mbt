///|
priv enum ConversationForkKind {
  AfterAnswer(through~ : Int32, draft~ : @composer.Draft?)
  FirstMessage(@composer.Draft)
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
  draft? : @composer.Draft,
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
    source_sequence: conv.watermark,
    kind: AfterAnswer(through~, draft~),
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
) -> (@cmd.Cmd, Model) {
  guard self.conversation_fork == Some(pending) else {
    return (@cmd.none, self)
  }
  let model = { ..self, conversation_fork: None, }
  match result {
    Err(message) => model.notify_error(emit, message)
    Ok(reply) => {
      guard model.device_state(pending.source.channel) is Some(dev) &&
        dev.connection_generation == pending.connection_generation &&
        dev.projects.contains(pending.source.workspace) else {
        return (@cmd.none, model)
      }
      if pending.kind is FirstMessage(draft) {
        let (rotate, model) = if model.screen is Chat &&
          model.conversation_selection() == Some(pending.source) {
          update_msg(
            emit,
            SessionRotated({
              channel: pending.source.channel,
              session: reply.session,
            }),
            model.with_active_project(Some(pending.source.workspace)),
          )
        } else {
          let conv = empty_conversation(
            pending.source.channel,
            reply.session,
            pending.source.workspace,
            model=pending.engine_model,
          )
          (
            @cmd.none,
            model.replace_conversation({ ..conv, worktree_mode: false, }),
          )
        }
        guard model.find_conversation(pending.source.channel, reply.session)
          is Some(conv) else {
          return (rotate, model)
        }
        let model = model.replace_conversation({
          ..conv,
          engine_model: pending.engine_model,
          worktree_mode: false,
          workspace: dev.conversation_workspace(
            pending.source.workspace,
            reply.session,
            conv.workspace,
          ),
          edit_replacement: Some(EditReplacement(pending)),
          task: draft.task,
          mentions: draft.mentions,
          images: draft.images,
          composer_draft_present: true,
        })
        return (
          @cmd.batch([
            rotate,
            model.send_edited_fork(emit, pending, reply.session, draft),
          ]),
          model,
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
      // Seed the new owner before submitting its draft, including when the
      // reader has navigated away while the fork was pending.
      if pending.kind is AfterAnswer(draft=Some(draft), ..) {
        // The host may announce the new session before replying to the fork.
        // Preserve any transcript/run already opened from that announcement.
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
          task: draft.task,
          mentions: draft.mentions,
          images: draft.images,
          composer_draft_present: true,
          edit_replacement: Some(EditReplacement(pending)),
        })
      }
      let save = save_conversation_model(
        conversation_model_key(pending.source.channel, reply.session),
        pending.engine_model,
      )
      let submit = if pending.kind is AfterAnswer(draft=Some(draft), ..) {
        model.send_edited_fork(emit, pending, reply.session, draft)
      } else {
        @cmd.none
      }
      // A completed background request must not take the reader away from
      // another conversation or screen they chose while it was pending.
      guard model.screen is Chat &&
        model.conversation_selection() == Some(pending.source) else {
        return (@cmd.batch([save, submit]), model)
      }
      let (open, model) = update_msg(
        emit,
        OpenSession(pending.source.channel, reply.session),
        model,
      )
      (
        @cmd.batch([save, open, submit]),
        { ..model, fork_focus: model.selected_conversation, },
      )
    }
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
          AfterAnswer(through~, draft=None) =>
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
          kind =>
            @interop.bridge_request(
              pending.source.channel,
              @commands.session_edit_prepare,
              {
                session: pending.source.session,
                workspace: pending.source.workspace.path,
                through: match kind {
                  AfterAnswer(through~, ..) => Some(through)
                  FirstMessage(_) => None
                },
                model: pending.engine_model.wire(),
                source_title: pending.source_title,
              },
            )
        }
        Ok(reply)
      } catch {
        error => Err(@interop.bridge_error_text(error))
      }
      scheduler.add(emit(ForkCompleted(pending, result)))
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
  let (_, done) = away.finish_fork(emit, pending, result)
  let (_, done_again) = away.finish_fork(emit, pending, result)
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
    if sequence == 1 {
      assert_true(pending.kind is FirstMessage(_))
    } else {
      assert_true(pending.kind is AfterAnswer(through=4, draft=Some(_)))
    }
    let (_, done) = requested.finish_fork(emit, pending, result)
    let (_, again) = requested.finish_fork(emit, pending, result)
    guard done.find_conversation(source.device, "desktop-fork") is Some(created) &&
      again.find_conversation(source.device, "desktop-fork") is Some(repeated) else {
      fail("edit destination")
    }
    assert_eq(
      created.task,
      if sequence == 1 {
        "first revised"
      } else {
        "second revised"
      },
    )
    assert_eq(created.task, repeated.task)
    assert_true(created.engine_model == source.engine_model)
    assert_true(created.composer_draft_present)
    assert_true(done.conversation_fork is None)
    assert_true(
      done
      .find_conversation(source.device, source.session_id)
      .map(conv => conv.task) ==
      Some(source.task),
    )
    if sequence == 5 {
      let arrived = requested.replace_conversation({
        ..created,
        messages: [
          { kind: Answer("already loaded"), sequence: Some(4), ts: None, },
        ],
      })
      let (_, preserved) = arrived.finish_fork(emit, pending, result)
      assert_true(
        preserved
        .find_conversation(source.device, "desktop-fork")
        .map(conv => conv.messages.length()) ==
        Some(1),
      )
    }
    let (_, stale) = requested.finish_fork(emit, pending, result)
    let (_, replayed) = stale.finish_fork(emit, pending, result)
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
  )
  guard done.find_conversation(channel, "desktop-fork") is Some(fork) else {
    fail("the fork was not opened")
  }
  assert_true(fork.workspace == Worktree(project~, name="wt-1"))
}
