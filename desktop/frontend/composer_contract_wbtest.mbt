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
    is Some({ stage: Thinking, started_ms: None, tokens: 0, }) else {
    fail("expected the open turn's heartbeat facts")
  }
  assert_eq(
    running.composer_input().turn_id,
    match conv.run {
      Open(run_id~, ..) => Some(run_id)
      _ => None
    },
  )
  let idle = running.replace_conversation({ ..conv, run: NoRun(ended=None), })
  assert_eq(idle.composer_input().run, None)
  assert_eq(idle.composer_input().turn_id, None)
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
        images: [],
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
        images: [],
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
    images: [],
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

///|
test "composer follow-up overrides route the message without changing the default" {
  for
    pair in [
      (@composer.QueueNext, FollowupSteer),
      (@composer.SteerNow, FollowupQueue),
    ] {
    let (choice, default) = pair
    let model = { ..running_model(), followup_behavior: default, }
    let identity = model.composer_input().identity
    let (_, submitted) = update(
      test_dispatch(),
      ComposerAction(
        @composer.FollowupSubmitted(
          identity~,
          draft={ images: [], task: "one message", mentions: [], },
          choice~,
        ),
      ),
      model,
    )
    assert_true(submitted.followup_behavior == default)
    let conv = submitted.active()
    assert_eq(conv.pending_steers.length(), 1)
    match choice {
      @composer.QueueNext => {
        assert_true(conv.pending_steers[0].behavior is FollowupQueue)
        assert_eq(conv.queued_inputs.length(), 1)
      }
      @composer.SteerNow => {
        assert_true(conv.pending_steers[0].behavior is FollowupSteer)
        assert_true(conv.queued_inputs.is_empty())
      }
    }
  }
}

///|
test "queued save rejects duplicate actions and unlocks after rejection" {
  let model = running_model()
  let conv = {
    ..model.active(),
    queued_inputs: [{ id: "queued", content: "original", images: [], }],
    queue_edit: Some(Editing(id="queued")),
    task: "saved revision",
  }
  let model = model.replace_conversation(conv)
  let (_, saving) = update(test_dispatch(), Send, model)
  assert_true(saving.active().saving_queue_edit())
  assert_true(saving.composer_input().presentation.disabled)
  let (_, duplicate) = update(
    test_dispatch(),
    ComposerAction(
      @composer.DraftSubmitted(identity=saving.composer_input().identity, draft={
        task: "unsent revision",
        images: [],
        mentions: [],
      }),
    ),
    saving,
  )
  assert_eq(duplicate.active().task, "saved revision")
  assert_eq(duplicate.submission_sequence, saving.submission_sequence)
  guard saving.active().queue_edit is Some(Saving(id~, run_id~, ..)) else {
    fail("expected a pending queued save")
  }
  let (_, failed) = update(
    test_dispatch(),
    FromDevice(
      conv.device,
      QueueEditRejected(
        session=conv.session_id,
        id~,
        run_id~,
        message="save failed",
      ),
    ),
    duplicate,
  )
  assert_eq(failed.active().task, "saved revision")
  assert_true(
    failed.active().queue_edit is Some(Editing(id=failed_id)) && failed_id == id,
  )
  assert_false(failed.composer_input().presentation.disabled)
  let (_, retry) = update(test_dispatch(), Send, failed)
  assert_true(retry.active().saving_queue_edit())
}

///|
test "queued save settles after its item is consumed without unlocking early" {
  let model = running_model()
  let conv = {
    ..model.active(),
    queued_inputs: [{ id: "queued", content: "original", images: [], }],
    queue_edit: Some(Editing(id="queued")),
    task: "saved revision",
  }
  let (_, saving) = update(
    test_dispatch(),
    Send,
    model.replace_conversation(conv),
  )
  guard saving.active().queue_edit is Some(Saving(id~, run_id~, ..)) else {
    fail("expected a pending queued save")
  }
  let (consumed, _) = saving.active().remove_queued_input(id)
  assert_true(consumed.saving_queue_edit())
  let (_, accepted) = update(
    test_dispatch(),
    FromDevice(
      conv.device,
      QueueAccepted(
        session=conv.session_id,
        action=QueueEdit(id~, text="saved revision", images=[]),
        run_id~,
      ),
    ),
    saving.replace_conversation(consumed),
  )
  assert_true(accepted.active().queue_edit is None)
  assert_eq(accepted.active().task, "")
  assert_true(accepted.active().queued_inputs.is_empty())
  assert_false(accepted.composer_input().presentation.disabled)
  assert_eq(accepted.submission_sequence, saving.submission_sequence + 1)
}

///|
test "queued save clears its snapshot but retains context added by the editor" {
  let submitted : Mention = { ref_: Skill(name="review"), range: None, }
  let base = running_model()
  let base = base.replace_conversation({
    ..base.active(),
    queued_inputs: [{ id: "queued", content: "original", images: [], }],
    queue_edit: Some(Editing(id="queued")),
    task: "saved revision",
    mentions: [submitted],
  })
  let (_, saving) = update(test_dispatch(), Send, base)
  guard saving.active().queue_edit is Some(Saving(id~, run_id~, ..)) else {
    fail("expected a pending queued save")
  }
  let (_, annotated) = update(
    test_dispatch(),
    FileEditor(
      EditorCommentAdded(
        resource=@fileeditor.ModelUri::of(
          @interop.ChannelId::Local.test_resource("/work/project/src/main.mbt"),
        ),
        file=Relative("src/main.mbt"),
        range=@common.Range(5, 1, 6, 3),
        quote="fn parse() {",
        comment="Context added during save",
        feedback_id="queued-save-context",
      ),
    ),
    saving,
  )
  assert_eq(annotated.active().mentions.length(), 2)
  let added = annotated.active().mentions[1]
  let msg : Msg = FromDevice(
    annotated.active().device,
    QueueAccepted(
      session=annotated.active().session_id,
      action=QueueEdit(id~, text="saved revision", images=[]),
      run_id~,
    ),
  )
  let (_, accepted) = update(test_dispatch(), msg, annotated)
  let (_, repeated) = update(test_dispatch(), msg, annotated)
  assert_eq(accepted.active().mentions, [added])
  assert_eq(repeated.active().mentions, [added])
  assert_eq(accepted.active().task, "")
  assert_eq(repeated.active().task, "")
  assert_true(accepted.active().queue_edit is None)
  assert_true(repeated.active().queue_edit is None)
  assert_eq(accepted.submission_sequence, saving.submission_sequence + 1)
  assert_eq(repeated.submission_sequence, accepted.submission_sequence)
  assert_eq(annotated.active().mentions, [submitted, added])
  assert_eq(saving.active().mentions, [submitted])
}
