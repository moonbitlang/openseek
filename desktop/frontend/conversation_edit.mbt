///|
priv struct UserMessageEdit {
  sequence : Int32
  through : Int32?
}

///|
/// Use full history, not the visible transcript page. A second user input
/// without a completed answer between them has no existing fork boundary;
/// never silently drop that intervening input by using an older answer.
fn Conversation::editable_messages(
  self : Conversation,
) -> Array[UserMessageEdit] {
  guard self.can_fork() else { return [] }
  let edits : Array[UserMessageEdit] = []
  let mut first = true
  let mut through : Int32? = None
  for item in self.messages {
    if item.kind is User(content~) {
      if (first || through is Some(_)) &&
        item.sequence is Some(sequence) &&
        content.0.all(part => !(part is File(..))) {
        edits.push({ sequence, through, })
      }
      first = false
      through = None
    } else if item.fork_through() is Some(boundary) {
      through = Some(boundary)
    }
  }
  edits
}

///|
fn Model::message_edit_busy(self : Model, source : Conversation) -> Bool {
  self.conversations.any(conv => {
    guard conv.device == source.device && conv.project() == source.project() else {
      return false
    }
    let mut current = conv.session_id
    while current != source.session_id {
      guard @transcript.subrun_parent(current) is Some(parent) else {
        return false
      }
      current = parent
    }
    conv.is_running() ||
    !(conv.compaction is NotCompacting) ||
    !conv.shell_commands.is_empty() ||
    !conv.queued_inputs.is_empty() ||
    !conv.pending_steers.is_empty() ||
    conv.pending_semantic_submission is Some(_)
  })
}

///|
fn Model::edit_user_message(
  self : Model,
  emit : @cmd.Emit[Msg],
  slot : String,
  sequence : Int32,
  draft : @composer.Draft,
) -> (@cmd.Cmd, Model) {
  guard !draft.is_blank() &&
    self.conversation_fork is None &&
    self.screen is Chat &&
    self.transcript_slot().map(value => value.key()) == Some(slot) &&
    self.active_conversation() is Some(conv) &&
    !self.message_edit_busy(conv) &&
    self.conversation_selection() is Some(source) &&
    conv
    .editable_messages()
    .iter()
    .find_first(edit => edit.sequence == sequence)
    is Some(edit) else {
    return (@cmd.none, self)
  }
  let paths = draft.mentions
    .iter()
    .filter_map(mention => {
      match mention.ref_ {
        @mention_context.File(path~) if path.has_prefix(
            ".openseek/attachments/",
          ) => Some(path)
        _ => None
      }
    })
    .collect()
  let payload : @protocol.SessionEditPayload = {
    session: source.session,
    workspace: source.workspace.path,
    through: edit.through,
    model: conv.engine_model.wire(),
    source_title: self.selected_conversation_title(),
    source_sequence: conv.durable_frontier(),
    task: draft.prompt(),
    images: draft.images.map(image => image.url),
    attachment_paths: paths,
    thinking: conv.engine_model.thinking(self.reasoning_for(conv.engine_model)),
    max_steps: parsed_max_steps(self.max_steps),
  }
  let pending : ConversationFork = {
    source,
    source_title: payload.source_title,
    source_sequence: payload.source_sequence,
    kind: EditedMessage(payload),
    engine_model: conv.engine_model,
    connection_generation: self.focused_connection_generation(),
  }
  (
    fork_conversation(emit, pending),
    { ..self, conversation_fork: Some(pending), },
  )
}

///|
test "message editing is blocked by active work in its own conversation family" {
  let model = test_model()
  let source = model.active()
  assert_false(model.message_edit_busy(source))
  for phase in [Requested, Queued, Compacting] {
    let busy = model.replace_conversation({ ..source, compaction: phase, })
    assert_true(busy.message_edit_busy(source))
  }
  let busy = model.replace_conversation({
    ..source,
    run: Starting(submission_id="pending"),
  })
  assert_true(busy.message_edit_busy(source))
  let child = {
    ..source,
    session_id: source.session_id + "-sr-1-sr-2",
    run: Starting(submission_id="child"),
  }
  assert_true(model.replace_conversation(child).message_edit_busy(source))
  let unrelated = { ..child, session_id: source.session_id + "-sr-unrelated", }
  assert_false(model.replace_conversation(unrelated).message_edit_busy(source))
}

///|
test "first and later message edits capture commits buffered during reload" {
  let base = test_model()
  let emit = test_dispatch()
  let buffered : Array[BufferedCommit] = [
    {
      sequence: 7,
      ts: None,
      item: RuntimeNotice({ content: "saved notice", }),
    },
  ]
  let states : Array[TranscriptSync] = [
    Reloading(generation=1, attempt=1, reload_after_current=false, buffered~),
    ReloadFailed(generation=1, buffered~),
  ]
  for sync in states {
    let source = {
      ..base.active(),
      watermark: 5,
      sync,
      messages: [
        {
          kind: User(content=Content([Text("first")])),
          sequence: Some(1),
          ts: None,
        },
        { kind: Answer("done"), sequence: Some(4), ts: None, },
        {
          kind: User(content=Content([Text("later")])),
          sequence: Some(5),
          ts: None,
        },
      ],
    }
    let model = base.replace_conversation(source)
    guard model.transcript_slot() is Some(slot) else { fail("missing slot") }
    for sequence in [1, 5] {
      let message = UserMessageEditRequested(slot=slot.key(), sequence~, draft={
        task: "edited",
        images: [],
        mentions: [],
      })
      let (_, requested) = update_msg(emit, message, model)
      let (_, repeated) = update_msg(emit, message, model)
      assert_true(requested.conversation_fork == repeated.conversation_fork)
      assert_true(model.conversation_fork is None)
      guard requested.conversation_fork is Some(pending) else {
        fail("edit not prepared")
      }
      assert_eq(pending.source_sequence, 7)
      assert_eq(model.active().watermark, 5)
    }
  }
}
