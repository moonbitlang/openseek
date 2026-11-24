///|
/// The continuation offer the composer was handed, or `None` when its context
/// column carries none. `Some(false)` is the notice without the button: the
/// person's own draft has to be sent or cleared first.
fn context_yield_offer(model : Model) -> Bool? {
  for component in model.composer_input().presentation.context {
    if component is @composer.ContextYieldNotice(continue_available~) {
      return Some(continue_available)
    }
  }
  None
}

///|
/// An idle conversation whose last turn stopped at the model's context
/// ceiling.
fn context_yielded_model() -> Model {
  test_model().replace_conversation({
    ..test_conversation(),
    run: NoRun(ended=Some(RunFinished(ContextYield))),
  })
}

///|
/// A yield ends the turn without an assistant message, so the transcript has
/// nothing to read and nothing to click. The composer is where the next turn
/// is sent from, so that is where the fact and its offer belong.
test "a context yield offers the turn that continues it" {
  let yielded = context_yielded_model()
  assert_eq(context_yield_offer(yielded), Some(true))
  guard yielded.composer_input().presentation.primary_action is Send(available~) else {
    fail("an idle conversation offers Send")
  }
  // The offer is only real if the turn it starts would be accepted.
  assert_true(available)
}

///|
/// Only a yield is this kind of ending: a finished answer, an idle chat, and
/// a running turn all read as themselves.
test "only a context yield offers to continue" {
  assert_eq(context_yield_offer(test_model()), None)
  assert_eq(context_yield_offer(running_model()), None)
  let completed = test_model().replace_conversation({
    ..test_conversation(),
    run: NoRun(ended=Some(RunFinished(Completed))),
  })
  assert_eq(context_yield_offer(completed), None)
}

///|
/// Continuing sends a prompt of the composer's own making. It is offered as a
/// button only while the draft is empty, so accepting it can never discard
/// what the person already typed, attached, or mentioned.
test "a typed draft keeps the offer without the button" {
  let typed = context_yielded_model().replace_conversation({
    ..test_conversation(),
    task: "rename the parser",
    composer_draft_present: true,
    run: NoRun(ended=Some(RunFinished(ContextYield))),
  })
  assert_eq(context_yield_offer(typed), Some(false))
}

///|
/// Accepting the offer is an ordinary prompt submission: the same Send starts
/// the next turn from the checkpoint, and the notice gives way to it.
test "accepting the offer starts the next turn" {
  let model = context_yielded_model()
  let identity = model.composer_input().identity
  let (_, sent) = update(
    test_dispatch(),
    ComposerAction(@composer.ContextContinueRequested(identity~)),
    model,
  )
  guard sent.active_conversation() is Some(conv) else {
    fail("expected the conversation to stay selected")
  }
  assert_true(conv.run is Starting(..))
  assert_eq(conv.task, "")
  guard conv.pending_prompt is Some({ draft: prompt, .. }) else {
    fail("expected the continuation to be the submitted prompt")
  }
  inspect(
    prompt,
    content="Continue the task from the checkpoint summary. Do not redo finished work; take the next step.",
  )
  // The next turn is the answer to the notice, so the notice is gone.
  assert_eq(context_yield_offer(sent), None)
}

///|
/// A conversation that is not on screen, or whose entry the composer can no
/// longer address, must not start a turn from a stale click.
test "a stale continuation click starts nothing" {
  let model = context_yielded_model()
  let identity : @composer.Identity = {
    ..model.composer_input().identity,
    archive_generation: model.composer_input().identity.archive_generation + 1,
  }
  let (_, ignored) = update(
    test_dispatch(),
    ComposerAction(@composer.ContextContinueRequested(identity~)),
    model,
  )
  assert_false(ignored.active().is_running())
  assert_eq(ignored.active().task, "")
}
