///|
priv struct ConversationFork {
  source : ConversationSelection
  source_title : String
  through : Int32
  engine_model : EngineModel
  connection_generation : Int32
} derive(Eq)

///|
fn Conversation::can_fork(self : Conversation) -> Bool {
  self.record is LiveRecord &&
  self.workspace is Project(..) &&
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
    through,
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
      let model = model
        .replace_device({ ..dev, sessions, })
        .remember_model(
          pending.source.channel,
          reply.session,
          pending.engine_model,
        )
      let save = save_conversation_model(
        conversation_model_key(pending.source.channel, reply.session),
        pending.engine_model,
      )
      // A completed background request must not take the reader away from
      // another conversation or screen they chose while it was pending.
      guard model.screen is Chat &&
        model.conversation_selection() == Some(pending.source) else {
        return (save, model)
      }
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
fn fork_conversation(
  emit : @cmd.Emit[Msg],
  pending : ConversationFork,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[@protocol.SessionForkReply, String] = try {
        let reply = @interop.bridge_request(
          pending.source.channel,
          @commands.session_fork,
          {
            session: pending.source.session,
            workspace: pending.source.workspace.path,
            through: pending.through,
            model: pending.engine_model.wire(),
            source_title: pending.source_title,
          },
        )
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
test "fork is unavailable for worktrees, archived records, and subruns" {
  let conv = test_conversation()
  assert_true(conv.can_fork())
  for session_id in ["desktop-test-sr-1", "desktop-test-sr-1-sr-2"] {
    assert_false(({ ..conv, session_id, } : Conversation).can_fork())
  }
  assert_false(({ ..conv, record: ArchivedRecord, } : Conversation).can_fork())
  assert_false(
    (
      { ..conv, workspace: Worktree(project=conv.project(), name="example"), } :
      Conversation).can_fork(),
  )
}

///|
test "fork validates requests without effects and preserves a non-chat page" {
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
}
