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
