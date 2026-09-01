///|
test "composer input is a projection instead of the root model" {
  let mention : Mention = { ref_: Skill(name="review"), range: None, }
  let model = test_model().replace_conversation({
    ..test_conversation(),
    task: "local draft",
    mentions: [mention],
  })
  let input = model.composer_input()
  inspect(input.identity.owner.session, content="desktop-test")
  inspect(input.draft.task, content="local draft")
  assert_true(input.draft.mentions == [mention])
  assert_eq(input.identity.archive_generation, 0)
}

///|
test "the composer is handed the turn's facts, not a rendered row" {
  let running = running_model()
  guard running.active_conversation() is Some(conv) else {
    fail("expected a running conversation")
  }
  // Facts only. The wording, the clock, and the tick that advances it belong
  // to the component, so a span that changes every second costs one
  // component's render instead of reprojecting every component's input.
  guard running.composer_input().run
    is Some({ stage: Thinking, started_ms: None, tokens: None, }) else {
    fail("expected the open turn's heartbeat facts")
  }
  let idle = running.replace_conversation({ ..conv, run: NoRun(ended=None), })
  assert_eq(idle.composer_input().run, None)
}

///|
test "composer submission stays bound to its originating conversation" {
  let origin = test_conversation()
  let visible = empty_conversation(
    @interop.ChannelId::Local,
    "visible-session",
    @interop.ChannelId::Local.test_project(),
  )
  let model = {
    ..test_model(),
    active_session: visible.session_id,
    conversations: [origin, visible],
  }
  let identity : @composer.Identity = {
    owner: { channel: @interop.ChannelId::Local, session: origin.session_id, },
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
test "annotation-only composer submission starts its conversation" {
  let model = test_model()
  let identity : @composer.Identity = {
    owner: {
      channel: @interop.ChannelId::Local,
      session: model.active().session_id,
    },
    archive_generation: 0,
  }
  let mention : Mention = {
    ref_: @mention_context.Annotation(
      file="bench/bench.mbt",
      start_line=69,
      end_line=69,
      quote="bench()",
      comment="inspect this selection",
      side=@mention_context.WorkingRevision,
    ),
    range: Some(@common.Range(69, 1, 69, 1)),
  }
  let (_, submitted) = update(
    test_dispatch(),
    ComposerAction(
      @composer.DraftSubmitted(identity~, draft={
        task: "",
        mentions: [mention],
      }),
    ),
    model,
  )
  assert_true(submitted.active().run is Starting(..))
  assert_true(submitted.active().task.is_empty())
  assert_true(submitted.active().mentions.is_empty())
  guard submitted.active().pending_prompt is Some(pending) else {
    fail("expected the annotation-only submission to be in flight")
  }
  // The chips alone make a non-empty prompt: the envelope is itself valid
  // content, which is what lets an annotation be sent with no typed text.
  // Built from the entry actually in flight, not from a literal beside it —
  // otherwise this asserts on a value the test made up.
  assert_true(pending.mentions == [mention])
  let sent = @composer.Draft::{
    task: pending.draft,
    mentions: pending.mentions,
  }.prompt()
  assert_true(sent.contains("<user_mentions>"))
  assert_true(sent.contains("bench/bench.mbt"))
}

///|
test "a background retirement expires old actions without poisoning a reopened id" {
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "desktop-test",
  }
  let model = { ..test_model(), composer_entry_retirements: [owner], }
  assert_true(
    model.conversation_for_composer_action({ owner, archive_generation: 0, })
    is None,
  )
  assert_true(
    model.conversation_for_composer_action({ owner, archive_generation: 1, })
    is Some(_),
  )
}
