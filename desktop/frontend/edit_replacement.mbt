///|
priv enum EditReplacementState {
  Unsubmitted
  Waiting(String)
  Deleting(String)
  Failed(String, String)
} derive(Eq)

///|
priv struct EditReplacement {
  source : ConversationSelection
  source_sequence : Int32
  source_descendants : Array[@protocol.SessionEditDescendant]
  state : EditReplacementState
} derive(Eq)

///|
fn EditReplacement::EditReplacement(
  pending : ConversationFork,
  source_descendants : Array[@protocol.SessionEditDescendant],
) -> EditReplacement {
  {
    source: pending.source,
    source_sequence: pending.source_sequence,
    source_descendants,
    state: Unsubmitted,
  }
}

///|
fn EditReplacement::submitting(
  self : EditReplacement,
  id : String,
) -> EditReplacement {
  match self.state {
    Unsubmitted | Waiting(_) => { ..self, state: Waiting(id), }
    Deleting(_) | Failed(_, _) => self
  }
}

///|
fn Model::observe_edited_message(
  self : Model,
  emit : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  item : @protocol.SessionItem,
) -> (@cmd.Cmd, Model) {
  guard item is User(message) &&
    self.find_conversation(channel, session) is Some(conv) &&
    conv.edit_replacement is Some(edit) &&
    edit.state is Waiting(id) &&
    message.submission_id == Some(id) else {
    return (@cmd.none, self)
  }
  self.remove_edited_source(emit, { channel, session, })
}

///|
fn Model::remove_edited_source(
  self : Model,
  emit : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
) -> (@cmd.Cmd, Model) {
  guard self.find_conversation(owner.channel, owner.session) is Some(conv) &&
    conv.edit_replacement is Some(edit) else {
    return (@cmd.none, self)
  }
  let id = match edit.state {
    Waiting(id) | Failed(id, _) => id
    Unsubmitted | Deleting(_) => return (@cmd.none, self)
  }
  let pending = { ..edit, state: Deleting(id), }
  let command = @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[@protocol.SessionDeleteReply, String] = Ok(
        @interop.bridge_request(owner.channel, @commands.session_edit_commit, {
          session: edit.source.session,
          workspace: edit.source.workspace.path,
          replacement: owner.session,
          source_sequence: edit.source_sequence,
          source_descendants: edit.source_descendants,
          submission_id: id,
        }),
      ) catch {
        error => Err(@interop.bridge_error_text(error))
      }
      scheduler.add(emit(EditCleanupCompleted(owner, pending, result)))
    })
    |> ignore
  })
  (
    command,
    self.replace_conversation({ ..conv, edit_replacement: Some(pending), }),
  )
}

///|
fn Model::finish_edit_cleanup(
  self : Model,
  emit : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  pending : EditReplacement,
  result : Result[@protocol.SessionDeleteReply, String],
) -> (@cmd.Cmd, Model) {
  guard self.find_conversation(owner.channel, owner.session) is Some(conv) &&
    conv.edit_replacement == Some(pending) &&
    pending.state is Deleting(id) else {
    return (@cmd.none, self)
  }
  let failure = match result {
    Ok(Deleted) => None
    Ok(Unconfirmed(_)) =>
      Some(
        "The original chat was kept because deleting it would remove a worktree.",
      )
    Err(message) => Some(message)
  }
  let next = self.replace_conversation({
    ..conv,
    edit_replacement: failure.map(message => {
      ..pending,
      state: Failed(id, message),
    }),
  })
  match failure {
    None => (@cmd.none, next)
    Some(message) => next.notify_error(emit, message)
  }
}

///|
test "edited cleanup waits for the exact receipt and retries only deletion" {
  let model = test_model()
  let emit = test_dispatch()
  guard model.conversation_selection() is Some(source) else { fail("source") }
  let pending : EditReplacement = {
    source,
    source_sequence: 8,
    source_descendants: [{ session: "source-sr-1", sequence: 3, }],
    state: Waiting("edit-1"),
  }
  let conv = {
    ..model.active(),
    session_id: "edited",
    edit_replacement: Some(pending),
  }
  let model = model.replace_conversation(conv)
  let owner : @interop.ConversationKey = {
    channel: conv.device,
    session: conv.session_id,
  }
  let receipt = (id : String) => {
    @protocol.User({
      content: Content([Text("edited")]),
      submission_id: Some(id),
    })
  }
  let (_, wrong) = model.observe_edited_message(
    emit,
    owner.channel,
    owner.session,
    receipt("another"),
  )
  assert_true(
    wrong.find_conversation(owner.channel, owner.session).unwrap().edit_replacement ==
    Some(pending),
  )
  let (_, removing) = model.observe_edited_message(
    emit,
    owner.channel,
    owner.session,
    receipt("edit-1"),
  )
  let (_, again) = model.observe_edited_message(
    emit,
    owner.channel,
    owner.session,
    receipt("edit-1"),
  )
  let removing_edit = removing
  .find_conversation(owner.channel, owner.session)
  .unwrap().edit_replacement.unwrap()
  assert_true(removing_edit.state is Deleting("edit-1"))
  assert_true(
    again.find_conversation(owner.channel, owner.session).unwrap().edit_replacement ==
    Some(removing_edit),
  )
  assert_true(
    model.find_conversation(owner.channel, owner.session).unwrap().edit_replacement ==
    Some(pending),
  )
  let (_, failed) = removing.finish_edit_cleanup(
    emit,
    owner,
    removing_edit,
    Err("busy"),
  )
  assert_true(
    failed.find_conversation(owner.channel, owner.session).unwrap().edit_replacement.unwrap().state
    is Failed("edit-1", "busy"),
  )
  let (_, retry) = failed.remove_edited_source(emit, owner)
  assert_true(
    retry.find_conversation(owner.channel, owner.session).unwrap().edit_replacement ==
    Some(removing_edit),
  )
  assert_true(retry.conversation_fork is None)
  let (_, done) = retry.finish_edit_cleanup(
    emit,
    owner,
    removing_edit,
    Ok(Deleted),
  )
  assert_true(
    done.find_conversation(owner.channel, owner.session).unwrap().edit_replacement
    is None,
  )
}

///|
test "a first-message replacement retains its late receipt across navigation" {
  let model = test_model()
  guard model.conversation_selection() is Some(source) else { fail("source") }
  let edited = {
    ..empty_conversation(Local, "edited", model.active().project()),
    edit_replacement: Some({
      source,
      source_sequence: 2,
      source_descendants: [],
      state: Waiting("late-edit"),
    }),
  }
  // An indeterminate start has returned to NoRun with no pending prompt or
  // transcript. The replacement receipt is still allowed to arrive later.
  assert_false(edited.has_begun())
  assert_true(edited.draft_empty())
  let away = model
    .replace_conversation(edited)
    .activate(Local, "another", source.workspace)
  assert_true(away.find_conversation(Local, "edited") is Some(_))
  let (_, received) = away.observe_edited_message(
    test_dispatch(),
    Local,
    "edited",
    User({
      content: Content([Text("edited")]),
      submission_id: Some("late-edit"),
    }),
  )
  assert_eq(received.active_session, "another")
  assert_true(
    received.find_conversation(Local, "edited").unwrap().edit_replacement
    is Some({ state: Deleting("late-edit"), .. }),
  )
}
