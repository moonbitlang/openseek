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
      body=Some("fn main { @myshell.Cmd(\"npm\", [\"ci\"]) }"),
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
    ApprovalRequested(
      id="ap-1",
      tool_name="run_moonbit",
      detail="escalate",
      body=Some("fn main { println(1) }"),
    ),
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
    ApprovalRequested(
      id="ap-1",
      tool_name="run_moonbit",
      detail="escalate",
      body=Some("fn main { println(1) }"),
    ),
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
    ApprovalRequested(
      id="ap-1",
      tool_name="run_moonbit",
      detail="escalate",
      body=Some("fn main { println(1) }"),
    ),
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
/// The card states who is asking, what would be granted, WHAT WOULD RUN, and
/// offers both answers.
///
/// The program is the point. An earlier version left it out on the theory that
/// the transcript already showed it — but this card docks above the composer,
/// detached from a tool-call row that is collapsed by default and may be
/// scrolled away, so the user was being asked to allow unsandboxed code with
/// the code nowhere on screen.
#warnings("-alert_unstable")
test "the card shows the question and both answers" {
  let asked = fold_engine(
    running_conversation(),
    ApprovalRequested(
      id="ap-1",
      tool_name="run_moonbit",
      detail="run this snippet with no sandbox policy",
      body=Some("fn main { @myshell.Cmd(\"npm\", [\"ci\"]) }"),
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
  // And the container is a plain notice, with no surface of its own, widened
  // to stack the program under the question.
  assert_true(
    markup.contains(
      "class=\"composer-notice composer-approval composer-approval-full\"",
    ),
  )
  // The program is rendered in full, not summarised and not behind a
  // disclosure: a permission prompt whose subject takes a click to see is the
  // thing this card exists to prevent.
  assert_true(markup.contains("<pre class=\"composer-approval-body\">"))
  // Highlighted by the same helper the transcript's run_moonbit card uses, so
  // the program reads identically in the place it is approved and the place it
  // is recorded. That helper emits `code.language-moonbit` with per-token
  // spans, which is why the assertions below look for fragments rather than
  // the source string: it is no longer one text node.
  assert_true(markup.contains("<code class=\"language-moonbit\">"))
  assert_true(markup.contains("myshell"))
  assert_true(markup.contains("npm"))
}

///|
/// Once answered both buttons are gone: the card says it is waiting rather
/// than continuing to offer a decision that has already been made.
#warnings("-alert_unstable")
test "an answered card offers no second decision" {
  let asked = fold_engine(
    running_conversation(),
    ApprovalRequested(
      id="ap-1",
      tool_name="run_moonbit",
      detail="escalate",
      body=Some("fn main { println(1) }"),
    ),
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

///|
/// Replay: a page that reloaded while a question stood gets it back.
///
/// This is the whole reason the host retains it. An approval request is a live
/// event and was never in the durable record, so a reloaded page rebuilds the
/// transcript perfectly and recovers everything about the turn EXCEPT the
/// question holding it up — leaving a run that shows Working forever with no
/// way to unblock it but cancelling.
test "a rejoining page is handed the question it lost" {
  let conv = running_conversation()
  guard conv.run is Open(run_id~, ..) else { fail("expected an open run") }
  let model = test_model().replace_conversation(conv)
  // No card: this page was not here when the question was asked.
  assert_true(conv.pending_approval is None)
  let (_, resynced) = update(
    test_dispatch(),
    runs_loaded_with_approvals(model, [
      {
        session: conv.session_id,
        approval: {
          id: "ap-1",
          run_id: Some(run_id),
          tool_name: "run_moonbit",
          detail: "run this snippet with no sandbox policy",
          body: Some("fn main { println(1) }"),
          answered: false,
        },
      },
    ]),
    model,
  )
  guard resynced.active_conversation() is Some(back) else {
    fail("expected the conversation")
  }
  guard back.pending_approval is Some(pending) else {
    fail("the standing question was not replayed")
  }
  // The SAME id: a rejoining page answers the question the engine is blocked
  // on, not a new one.
  assert_eq(pending.id, "ap-1")
  assert_eq(pending.body, Some("fn main { println(1) }"))
  assert_false(pending.answered)
}

///|
/// The resync runs on every reconnect, not only after a reload — so it must
/// not undo a decision this page already sent. Handing the buttons back to a
/// card whose answer is in flight is one question with two decisions.
test "a resync does not re-offer a question already answered here" {
  let conv = running_conversation()
  guard conv.run is Open(run_id~, ..) else { fail("expected an open run") }
  let asked = fold_engine(
    conv,
    ApprovalRequested(
      id="ap-1",
      tool_name="run_moonbit",
      detail="escalate",
      body=Some("fn main { println(1) }"),
    ),
  )
  let model = test_model().replace_conversation(asked)
  let (_, answered) = update(
    test_dispatch(),
    ApprovalAnswered(allow=true),
    model,
  )
  // The host still lists it: our decision has not reached the engine yet.
  let (_, resynced) = update(
    test_dispatch(),
    runs_loaded_with_approvals(answered, [
      {
        session: conv.session_id,
        approval: {
          id: "ap-1",
          run_id: Some(run_id),
          tool_name: "run_moonbit",
          detail: "escalate",
          body: Some("fn main { println(1) }"),
          answered: false,
        },
      },
    ]),
    answered,
  )
  guard resynced.active_conversation() is Some(back) else {
    fail("expected the conversation")
  }
  guard back.pending_approval is Some(pending) else {
    fail("expected the card to stand")
  }
  assert_true(pending.answered)
}

///|
/// Build the `agent.runs` resync message for a model, replaying `approvals`
/// and asserting nothing about runs: the frontier is taken from the model as
/// it stands, so the snapshot reads as "everything unchanged, plus these
/// standing questions".
fn runs_loaded_with_approvals(
  model : Model,
  approvals : Array[RecoveredApproval],
) -> Msg {
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let live : Array[String] = []
  for conv in model.conversations {
    if conv.run is Open(run_id~, ..) {
      live.push(run_id)
    }
  }
  FromDevice(
    @interop.ChannelId::Local,
    RunsLoaded(
      runs=[],
      settled=[],
      approvals~,
      live~,
      frontier~,
      connection_generation=0,
    ),
  )
}

///|
/// A decision that never reached the engine must leave the card answerable.
///
/// This is the pairing that makes it load-bearing: answering marks the card so
/// a second click cannot double-decide, and the question behind it has no
/// deadline. If a failed send left the mark in place, the card would read
/// "Sending…" forever with the engine still blocked, and cancelling the run
/// would be the only way out.
test "a decision that never left the page restores the card" {
  let asked = fold_engine(
    running_conversation(),
    ApprovalRequested(
      id="ap-1",
      tool_name="run_moonbit",
      detail="escalate",
      body=Some("fn main { println(1) }"),
    ),
  )
  let model = test_model().replace_conversation(asked)
  let (_, answered) = update(
    test_dispatch(),
    ApprovalAnswered(allow=true),
    model,
  )
  guard answered.active_conversation() is Some(sending) else {
    fail("expected the conversation")
  }
  assert_true(sending.pending_approval is Some({ answered: true, .. }))
  let (_, restored) = update(
    test_dispatch(),
    ApprovalAnswerFailed(
      channel=@interop.ChannelId::Local,
      session=asked.session_id,
      id="ap-1",
    ),
    answered,
  )
  guard restored.active_conversation() is Some(conv) else {
    fail("expected the conversation")
  }
  guard conv.pending_approval is Some(pending) else {
    fail("the card must survive a failed send")
  }
  assert_false(pending.answered)
  // And it is answerable again, for real: the guard that refuses a second
  // decision keys on the same flag.
  let (_, again) = update(
    test_dispatch(),
    ApprovalAnswered(allow=false),
    restored,
  )
  guard again.active_conversation() is Some(conv) else {
    fail("expected the conversation")
  }
  assert_true(conv.pending_approval is Some({ answered: true, .. }))
}

///|
/// A stale failure must not unlock a newer question: the restoration is
/// addressed by id, not by "whatever card is up".
test "a failure for an older question leaves the current one alone" {
  let asked = fold_engine(
    running_conversation(),
    ApprovalRequested(
      id="ap-2",
      tool_name="run_moonbit",
      detail="escalate",
      body=None,
    ),
  )
  let model = test_model().replace_conversation(asked)
  let (_, answered) = update(
    test_dispatch(),
    ApprovalAnswered(allow=true),
    model,
  )
  let (_, unchanged) = update(
    test_dispatch(),
    ApprovalAnswerFailed(
      channel=@interop.ChannelId::Local,
      session=asked.session_id,
      id="ap-1",
    ),
    answered,
  )
  guard unchanged.active_conversation() is Some(conv) else {
    fail("expected the conversation")
  }
  assert_true(conv.pending_approval is Some({ answered: true, .. }))
}

///|
/// The resync reconciles both ways. A question this page was showing that the
/// host no longer lists was answered while the page was away — by another
/// client, or by the run ending — and its `approval_resolved` is gone for
/// good, so nothing else would ever take the card down. Pressing it would send
/// a decision the engine's desk silently discards.
test "a resync retires a question the host no longer has" {
  let asked = fold_engine(
    running_conversation(),
    ApprovalRequested(
      id="ap-1",
      tool_name="run_moonbit",
      detail="escalate",
      body=None,
    ),
  )
  let model = test_model().replace_conversation(asked)
  let (_, resynced) = update(
    test_dispatch(),
    runs_loaded_with_approvals(model, []),
    model,
  )
  guard resynced.active_conversation() is Some(conv) else {
    fail("expected the conversation")
  }
  assert_true(conv.pending_approval is None)
}

///|
/// But only for the question that was on screen when the request went out. One
/// asked afterwards is equally absent from the reply, and clearing it would
/// take a live card off screen and leave the turn blocked with nothing to
/// press.
test "a resync leaves a question asked after the request went out" {
  let model = test_model().replace_conversation(running_conversation())
  // Captured while nothing was pending...
  let resync = runs_loaded_with_approvals(model, [])
  // ...and the question arrives before the reply is folded in.
  guard model.active_conversation() is Some(conv) else {
    fail("expected the conversation")
  }
  let racing = model.replace_conversation(
    fold_engine(
      conv,
      ApprovalRequested(
        id="ap-9",
        tool_name="run_moonbit",
        detail="escalate",
        body=None,
      ),
    ),
  )
  let (_, resynced) = update(test_dispatch(), resync, racing)
  guard resynced.active_conversation() is Some(after) else {
    fail("expected the conversation")
  }
  guard after.pending_approval is Some(pending) else {
    fail("a question asked after the request was wrongly retired")
  }
  assert_eq(pending.id, "ap-9")
}

///|
/// A snapshot that has been overtaken must not put its dead question back.
///
/// The request goes out while `ap-1` stands. In flight, `ap-1` resolves and
/// `ap-2` is asked. Seeding on "the reply lists a question this page does not
/// have" would then replace the live `ap-2` card with the dead `ap-1` — and
/// answering a dead question is discarded by the engine, so the real one stays
/// blocked with nothing on screen and only cancelling the run recovers.
test "a stale snapshot does not overwrite a newer question" {
  let asked = fold_engine(
    running_conversation(),
    ApprovalRequested(
      id="ap-1",
      tool_name="run_moonbit",
      detail="escalate",
      body=None,
    ),
  )
  let model = test_model().replace_conversation(asked)
  // Captured while ap-1 stood.
  let resync = runs_loaded_with_approvals(model, [
    {
      session: asked.session_id,
      approval: {
        id: "ap-1",
        run_id: None,
        tool_name: "run_moonbit",
        detail: "escalate",
        body: None,
        answered: false,
      },
    },
  ])
  // In flight: ap-1 settles and ap-2 is asked.
  let moved_on = model.replace_conversation(
    fold_engine(
      fold_engine(asked, ApprovalResolved(id="ap-1")),
      ApprovalRequested(
        id="ap-2",
        tool_name="run_moonbit",
        detail="escalate again",
        body=None,
      ),
    ),
  )
  let (_, resynced) = update(test_dispatch(), resync, moved_on)
  guard resynced.active_conversation() is Some(conv) else {
    fail("expected the conversation")
  }
  guard conv.pending_approval is Some(pending) else {
    fail("the live question was cleared by a stale snapshot")
  }
  assert_eq(pending.id, "ap-2")
}

///|
/// Absence is matched on session AND id. Ids repeat across engines — every desk
/// starts at `ap-1` — so another conversation still holding that number is not
/// evidence that this one's question survives; matching by id alone would keep
/// a dead card up for as long as any other session happened to share it.
test "another session's identical id does not keep a dead card alive" {
  let mine = running_conversation()
  let theirs = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "other-session",
      @interop.ChannelId::Local.test_project(),
    ),
    run: Open(run_id="r-other", stage=Opened),
  }
  let asked = fold_engine(
    mine,
    ApprovalRequested(
      id="ap-1",
      tool_name="run_moonbit",
      detail="escalate",
      body=None,
    ),
  )
  let model = {
    ..test_model(),
    active_session: asked.session_id,
    conversations: [asked, theirs],
  }
  // The host lists `ap-1` — but for the OTHER session. Mine is gone.
  let (_, resynced) = update(
    test_dispatch(),
    runs_loaded_with_approvals(model, [
      {
        session: theirs.session_id,
        approval: {
          id: "ap-1",
          run_id: Some("r-other"),
          tool_name: "run_moonbit",
          detail: "escalate",
          body: None,
          answered: false,
        },
      },
    ]),
    model,
  )
  guard resynced.find_conversation(@interop.ChannelId::Local, asked.session_id)
    is Some(conv) else {
    fail("expected my conversation")
  }
  assert_true(conv.pending_approval is None)
  // And theirs was seeded, since it is genuinely standing.
  guard resynced.find_conversation(@interop.ChannelId::Local, theirs.session_id)
    is Some(other) else {
    fail("expected the other conversation")
  }
  assert_true(other.pending_approval is Some(_))
}
