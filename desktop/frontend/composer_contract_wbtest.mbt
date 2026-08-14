///|
test "composer input is a projection instead of the root model" {
  let mention : Mention = { ref_: Skill(name="review"), range: None }
  let model = test_model().replace_conversation({
    ..test_conversation(),
    task: "local draft",
    mentions: [mention],
  })
  let input = model.composer_input(test_dispatch())
  inspect(input.identity.owner.session, content="desktop-test")
  inspect(input.draft.task, content="local draft")
  assert_true(input.draft.mentions == [mention])
  assert_eq(input.identity.archive_generation, 0)
}

///|
test "composer submission stays bound to its originating conversation" {
  let origin = test_conversation()
  let visible = empty_conversation(@interop.ChannelId::Local, "visible-session")
  let model = {
    ..test_model(),
    active_session: visible.session_id,
    conversations: [origin, visible],
  }
  let identity : @composer.Identity = {
    owner: { channel: @interop.ChannelId::Local, session: origin.session_id },
    archive_generation: 0,
  }
  let (_, submitted) = update(
    test_dispatch(),
    ComposerAction(
      @composer.DraftSubmitted(identity~, draft={
        task: "send to origin",
        mentions: [],
      }),
    ),
    model,
  )
  // Running the root operation may temporarily select the owner, but the
  // user's visible navigation is restored before the action returns.
  inspect(submitted.active_session, content="visible-session")
  guard submitted.find_conversation(
      @interop.ChannelId::Local,
      origin.session_id,
    )
    is Some(origin_after) else {
    fail("the originating conversation disappeared")
  }
  guard submitted.find_conversation(
      @interop.ChannelId::Local,
      visible.session_id,
    )
    is Some(visible_after) else {
    fail("the visible conversation disappeared")
  }
  assert_true(origin_after.run is Starting(..))
  assert_false(visible_after.run is Starting(..))
}

///|
test "archive cursor separates transferred actions from a reopened id" {
  let archived : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "desktop-test",
  }
  let fresh : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "archive-replacement",
  }
  let reopened = test_conversation()
  let replacement = empty_conversation(fresh.channel, fresh.session)
  let model = {
    ..test_model(),
    conversations: [reopened, replacement],
    composer_entry_retirements: [archived],
    composer_entry_replacements: [{ archived, fresh, archive_generation: 1 }],
  }
  let old_identity : @composer.Identity = {
    owner: archived,
    archive_generation: 0,
  }
  let reopened_identity : @composer.Identity = {
    owner: archived,
    archive_generation: 1,
  }
  guard model.conversation_for_composer_action(old_identity) is Some(old) else {
    fail("the old entry should follow its recorded replacement")
  }
  guard model.conversation_for_composer_action(reopened_identity) is Some(new) else {
    fail("the reopened entry should resolve to the reused id")
  }
  inspect(old.session_id, content="archive-replacement")
  inspect(new.session_id, content="desktop-test")
}

///|
test "a background retirement expires old actions without poisoning a reopened id" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "desktop-test",
  }
  let model = {
    ..test_model(),
    composer_entry_retirements: [owner],
    composer_entry_replacements: [],
  }
  assert_true(
    model.conversation_for_composer_action({ owner, archive_generation: 0 })
    is None,
  )
  assert_true(
    model.conversation_for_composer_action({ owner, archive_generation: 1 })
    is Some(_),
  )
}
