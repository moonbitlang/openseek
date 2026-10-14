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
  if edit.through is Some(through) {
    self.request_fork(emit, slot, through, draft~)
  } else {
    let pending : ConversationFork = {
      source,
      source_title: self.selected_conversation_title(),
      source_sequence: conv.watermark,
      kind: FirstMessage(draft),
      engine_model: conv.engine_model,
      connection_generation: self.focused_connection_generation(),
    }
    (
      fork_conversation(emit, pending),
      { ..self, conversation_fork: Some(pending), },
    )
  }
}

///|
fn Model::send_edited_fork(
  self : Model,
  emit : @cmd.Emit[Msg],
  pending : ConversationFork,
  session : String,
  draft : @composer.Draft,
) -> @cmd.Cmd {
  emit(
    ComposerAction(
      @composer.DraftSubmitted(
        identity={
          owner: { channel: pending.source.channel, session, },
          archive_generation: self.composer_entry_retirements.length(),
        },
        draft~,
      ),
    ),
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
