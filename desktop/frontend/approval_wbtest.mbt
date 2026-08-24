// The permission-question flow, from the engine's event to the card and back
// out as a decision. Everything here goes through the same public state the
// root shell uses: the pending question is folded by `apply_engine_event` and
// answered by `update`, so the test cannot pass by reaching past either.

///|
/// Fold one engine event into the running test conversation.
fn fold_engine(
  conv : Conversation,
  event : @transcript.EngineEvent,
) -> Conversation {
  let (_, next) = apply_engine_event(conv, event, Some("r-test"))
  next
}

///|
test "a permission question becomes the conversation's pending approval" {
  let conv = fold_engine(
    running_conversation(),
    ApprovalRequested(
      id="ap-1",
      tool_name="run_moonbit",
      detail="run this snippet with no sandbox policy",
    ),
  )
  guard conv.pending_approval is Some(pending) else {
    fail("expected a pending approval")
  }
  assert_eq(pending.id, "ap-1")
  assert_eq(pending.tool_name, "run_moonbit")
  // The engine's sentence is kept verbatim: a client that paraphrases a
  // permission is a client that can get it wrong.
  assert_eq(pending.detail, "run this snippet with no sandbox policy")
  assert_false(pending.answered)
  // It belongs to the run it was asked in, so a slow decision cannot settle a
  // question in a later one.
  assert_eq(pending.run_id, Some("r-test"))
}

///|
/// Settlement retires the card whoever answered — this client, another one, or
/// the engine's own deadline. Matching on the id is what stops a late
/// settlement for an older question from retiring a newer one.
test "settlement retires the matching question and nothing else" {
  let asked = fold_engine(
    running_conversation(),
    ApprovalRequested(id="ap-1", tool_name="run_moonbit", detail="escalate"),
  )
  let stale = fold_engine(asked, ApprovalResolved(id="ap-0"))
  assert_true(stale.pending_approval is Some(_))
  let settled = fold_engine(asked, ApprovalResolved(id="ap-1"))
  assert_true(settled.pending_approval is None)
}

///|
/// A turn cannot end with a tool still blocked inside it, so a terminal event
/// means the question died with the turn. Leaving the card up would offer to
/// answer something that no longer exists.
test "a finished turn takes its unanswered question with it" {
  let asked = fold_engine(
    running_conversation(),
    ApprovalRequested(id="ap-1", tool_name="run_moonbit", detail="escalate"),
  )
  assert_true(
    fold_engine(asked, AgentFinished("done")).pending_approval is None,
  )
  assert_true(
    fold_engine(asked, AgentAborted("interrupted")).pending_approval is None,
  )
  assert_true(fold_engine(asked, MaxStepsExhausted).pending_approval is None)
}

///|
/// Answering marks the question rather than removing it: the card comes off
/// screen when the engine says it settled, which is the only evidence the
/// decision reached the blocked tool. A second click is refused so one
/// question cannot produce two decisions.
test "answering is recorded once and does not retire the card" {
  let asked = fold_engine(
    running_conversation(),
    ApprovalRequested(id="ap-1", tool_name="run_moonbit", detail="escalate"),
  )
  let model = test_model().replace_conversation(asked)
  let (_, answered) = update(
    test_dispatch(),
    ApprovalAnswered(allow=true),
    model,
  )
  guard answered.active_conversation() is Some(conv) else {
    fail("expected the answered conversation")
  }
  guard conv.pending_approval is Some(pending) else {
    fail("the card must stand until the engine settles it")
  }
  assert_true(pending.answered)
  // The second click is refused: the guard sees `answered` and returns before
  // building a command, so the opposite decision cannot follow the first one
  // out to the engine.
  let (_, again) = update(
    test_dispatch(),
    ApprovalAnswered(allow=false),
    answered,
  )
  guard again.active_conversation() is Some(conv) else {
    fail("expected the conversation")
  }
  assert_true(conv.pending_approval is Some({ answered: true, .. }))
}

///|
/// The card states who is asking and what would be granted, and offers both
/// answers. It deliberately does NOT restate the program: that tool call is
/// already committed and rendered above the composer, and a second copy could
/// drift from the one the decision is actually about.
#warnings("-alert_unstable")
test "the card shows the question and both answers" {
  let asked = fold_engine(
    running_conversation(),
    ApprovalRequested(
      id="ap-1",
      tool_name="run_moonbit",
      detail="run this snippet with no sandbox policy",
    ),
  )
  let input = test_model()
    .replace_conversation(asked)
    .composer_input(test_dispatch())
  let markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(@html.div(input.presentation.context))
  })
  assert_true(markup.contains("run this snippet with no sandbox policy"))
  assert_true(markup.contains("Allow once"))
  assert_true(markup.contains("Deny"))
  assert_false(markup.contains("Sending…"))
  // A tool name is code, so it is a `code` element — that is where the app's
  // monospace stack comes from now that the UI itself is sans.
  assert_true(
    markup.contains("<code class=\"composer-approval-tool\">run_moonbit</code>"),
  )
  // Both decisions wear the borderless chip shape, carrying only an emphasis
  // modifier on top of it. Three earlier versions gave the card an accent
  // outline, then filled accent/danger buttons, then outlined ones; each time
  // it stopped looking like part of this app. Pinning the exact class pair is
  // what holds that line — nothing else here can tell a chip from a dialog
  // button.
  assert_true(
    markup.contains("class=\"composer-approval-action composer-approval-deny\""),
  )
  assert_true(
    markup.contains(
      "class=\"composer-approval-action composer-approval-allow\"",
    ),
  )
  // And the container is a plain notice, with no surface of its own.
  assert_true(markup.contains("class=\"composer-notice composer-approval\""))
}

///|
/// Once answered both buttons are gone: the card says it is waiting rather
/// than continuing to offer a decision that has already been made.
#warnings("-alert_unstable")
test "an answered card offers no second decision" {
  let asked = fold_engine(
    running_conversation(),
    ApprovalRequested(id="ap-1", tool_name="run_moonbit", detail="escalate"),
  )
  let model = test_model().replace_conversation(asked)
  let (_, answered) = update(
    test_dispatch(),
    ApprovalAnswered(allow=true),
    model,
  )
  let input = answered.composer_input(test_dispatch())
  let markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(@html.div(input.presentation.context))
  })
  assert_true(markup.contains("Sending…"))
  assert_false(markup.contains("Allow once"))
  assert_false(markup.contains("Deny"))
}
