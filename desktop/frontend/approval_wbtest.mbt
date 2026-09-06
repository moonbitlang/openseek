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
      tool_name="mbtx",
      detail="run this snippet with no sandbox policy",
      body=Some("fn main { @myshell.Cmd(\"npm\", [\"ci\"]) }"),
    ),
  )
  guard conv.pending_approval is Some(pending) else {
    fail("expected a pending approval")
  }
  assert_eq(pending.id, "ap-1")
  assert_eq(pending.tool_name, "mbtx")
  // The engine's sentence is kept verbatim: a client that paraphrases a
  // permission is a client that can get it wrong.
  assert_eq(pending.detail, "run this snippet with no sandbox policy")
  assert_false(pending.answered)
  // It belongs to the run it was asked in, so a slow decision cannot settle a
  // question in a later one.
  assert_eq(pending.run_id, Some("r-test"))
  assert_eq(
    test_model().replace_conversation(conv).notification_badge_count(),
    1,
  )
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
      tool_name="mbtx",
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
      tool_name="mbtx",
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
      tool_name="mbtx",
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
  assert_eq(answered.notification_badge_count(), 0)
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
test "notification badge counts local conversations needing attention" {
  let pending : PendingApproval = {
    id: "ap-local",
    run_id: Some("r-local"),
    tool_name: "mbtx",
    detail: "escalate",
    body: None,
    answered: false,
  }
  let active = { ..running_conversation(), pending_approval: Some(pending), }
  let background = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "desktop-background",
      @interop.ChannelId::Local.test_project(),
    ),
    run: Open(run_id="r-background", stage=Opened),
    pending_approval: Some({
      ..pending,
      id: "ap-background",
      run_id: Some("r-background"),
    }),
  }
  let answered = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "desktop-answered",
      @interop.ChannelId::Local.test_project(),
    ),
    pending_approval: Some({ ..pending, id: "ap-answered", answered: true, }),
  }
  let finished = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "desktop-finished",
      @interop.ChannelId::Local.test_project(),
    ),
    unseen_finish: true,
  }
  let remote_channel = @interop.ChannelId::Remote("device-1")
  let remote = {
    ..empty_conversation(
      remote_channel,
      "desktop-remote",
      remote_channel.test_project(),
    ),
    pending_approval: Some({ ..pending, id: "ap-remote", }),
    unseen_finish: true,
  }
  let model = {
    ..test_model(),
    conversations: [active, background, answered, finished, remote],
  }
  assert_eq(model.notification_badge_count(), 3)
  let seen = model.activate(
    @interop.ChannelId::Local,
    "desktop-finished",
    @interop.ChannelId::Local.test_project(),
  )
  assert_eq(seen.notification_badge_count(), 2)
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
          tool_name: "mbtx",
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
  assert_eq(resynced.notification_badge_count(), 1)
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
      tool_name="mbtx",
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
          tool_name: "mbtx",
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
  let live : Array[String] = [
    for conv in model.conversations if conv.run is Open(run_id~, ..) => run_id
  ]
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
      tool_name="mbtx",
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
  assert_eq(answered.notification_badge_count(), 0)
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
  assert_eq(restored.notification_badge_count(), 1)
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
  assert_eq(again.notification_badge_count(), 0)
}

///|
/// A stale failure must not unlock a newer question: the restoration is
/// addressed by id, not by "whatever card is up".
test "a failure for an older question leaves the current one alone" {
  let asked = fold_engine(
    running_conversation(),
    ApprovalRequested(id="ap-2", tool_name="mbtx", detail="escalate", body=None),
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
    ApprovalRequested(id="ap-1", tool_name="mbtx", detail="escalate", body=None),
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
        tool_name="mbtx",
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
    ApprovalRequested(id="ap-1", tool_name="mbtx", detail="escalate", body=None),
  )
  guard asked.run is Open(run_id~, ..) else { fail("expected an open run") }
  let model = test_model().replace_conversation(asked)
  // Captured while ap-1 stood. The run matches, so the frontier guard is the
  // only thing that can stop this from being seeded.
  let resync = runs_loaded_with_approvals(model, [
    {
      session: asked.session_id,
      approval: {
        id: "ap-1",
        run_id: Some(run_id),
        tool_name: "mbtx",
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
        tool_name="mbtx",
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
/// The frontier guard compares two endpoints, so it cannot see a value that
/// changed and changed back. With no question captured, one asked and resolved
/// in flight, and its run replaced, both endpoints read `None` — and the
/// reply's dead question would be seeded onto the new run, where answering it
/// is rejected and the failure handler puts the buttons back. The run fence is
/// what stops it.
test "a question from a finished run is not seeded onto its successor" {
  let conv = running_conversation()
  guard conv.run is Open(run_id~, ..) else { fail("expected an open run") }
  let model = test_model().replace_conversation(conv)
  // Captured with no question standing.
  let resync = runs_loaded_with_approvals(model, [
    {
      session: conv.session_id,
      approval: {
        id: "ap-1",
        run_id: Some(run_id),
        tool_name: "mbtx",
        detail: "escalate",
        body: None,
        answered: false,
      },
    },
  ])
  // In flight: ap-1 was asked and resolved, and r1 gave way to r2.
  let moved_on = model.replace_conversation({
    ..conv,
    run: Open(run_id="r-successor", stage=Opened),
    pending_approval: None,
  })
  let (_, resynced) = update(test_dispatch(), resync, moved_on)
  guard resynced.active_conversation() is Some(after) else {
    fail("expected the conversation")
  }
  assert_true(after.pending_approval is None)
}

///|
/// The reload path the replay exists for. `BridgeReady` captures the frontier
/// and issues `agent.runs` alongside `session.list`, so on a fresh page the
/// frontier is EMPTY — no conversation exists yet to capture. By the time the
/// reply lands the conversation does exist, materialized by this snapshot's own
/// run row or by the listing that raced it, and its standing question has to
/// arrive with it.
///
/// Visiting only sessions named in the frontier drops exactly this case, which
/// is the case the whole replay was built for.
test "a session missing from the frontier still gets its question" {
  let conv = running_conversation()
  guard conv.run is Open(run_id~, ..) else { fail("expected an open run") }
  let model = test_model().replace_conversation(conv)
  let (_, resynced) = update(
    test_dispatch(),
    FromDevice(
      @interop.ChannelId::Local,
      RunsLoaded(
        runs=[],
        settled=[],
        approvals=[
          {
            session: conv.session_id,
            approval: {
              id: "ap-1",
              run_id: Some(run_id),
              tool_name: "mbtx",
              detail: "escalate",
              body: Some("fn main { println(1) }"),
              answered: false,
            },
          },
        ],
        live=[run_id],
        // Captured before this page knew the conversation.
        frontier=[],
        connection_generation=0,
      ),
    ),
    model,
  )
  guard resynced.active_conversation() is Some(after) else {
    fail("expected the conversation")
  }
  guard after.pending_approval is Some(pending) else {
    fail("a question for a session absent from the frontier was dropped")
  }
  assert_eq(pending.id, "ap-1")
}

///|
/// The run handoff Codex described: the snapshot carries r1's settlement, r2's
/// active row, and r2's question, while this page still shows r1's. The
/// settlement does not touch the card — only the run phase — so the captured
/// and current ids still agree and r2's question is seeded over the stale one.
test "a question survives a run handoff inside one snapshot" {
  let conv = running_conversation()
  guard conv.run is Open(run_id~, ..) else { fail("expected an open run") }
  let asked = fold_engine(
    conv,
    ApprovalRequested(id="ap-1", tool_name="mbtx", detail="escalate", body=None),
  )
  let model = test_model().replace_conversation(asked)
  let (_, resynced) = update(
    test_dispatch(),
    FromDevice(
      @interop.ChannelId::Local,
      RunsLoaded(
        runs=[
          {
            run_id: "r-successor",
            session: asked.session_id,
            model: DsPro,
            max_steps: 1000,
            session_root: None,
            submission_id: None,
          },
        ],
        settled=[
          {
            run_id,
            session: asked.session_id,
            submission_id: None,
            status: "finished",
          },
        ],
        approvals=[
          {
            session: asked.session_id,
            approval: {
              id: "ap-2",
              run_id: Some("r-successor"),
              tool_name: "mbtx",
              detail: "escalate again",
              body: None,
              answered: false,
            },
          },
        ],
        live=["r-successor"],
        frontier=[
          {
            session: asked.session_id,
            state: SnapshotOpen(run_id~),
            initial_ids: [],
            pending_approval_id: Some("ap-1"),
          },
        ],
        connection_generation=0,
      ),
    ),
    model,
  )
  guard resynced.active_conversation() is Some(after) else {
    fail("expected the conversation")
  }
  guard after.pending_approval is Some(pending) else {
    fail("the successor's question was dropped in the handoff")
  }
  assert_eq(pending.id, "ap-2")
}

///|
/// A run that ends without resolving its question takes the card with it.
///
/// The engine settles its own on the way out, so this covers the engine that
/// could not: a killed process emits no `approval_resolved`, and the host
/// reports the run finished instead. Nothing else would ever retire the card —
/// there is no deadline behind the question — and pressing it sends a decision
/// to an engine that is gone. The host already drops its copy on the same
/// evidence (`Hub::forget_run_approvals`).
test "a finished run takes its unanswered question with it" {
  let conv = running_conversation()
  guard conv.run is Open(run_id~, ..) else { fail("expected an open run") }
  // The engine stamps its events with the run they belong to, so a real
  // pending approval always names the conversation's open run.
  let asked = {
    ..conv,
    pending_approval: Some({
      id: "ap-1",
      run_id: Some(run_id),
      tool_name: "mbtx",
      detail: "escalate",
      body: None,
      answered: false,
    }),
  }
  let (_, ended) = update_device_msg(
    test_dispatch(),
    @interop.ChannelId::Local,
    Finished(run_id~, status="finished", answer=None),
    test_model().replace_conversation(asked),
  )
  guard ended.active_conversation() is Some(after) else {
    fail("expected the conversation")
  }
  assert_true(after.pending_approval is None)
  assert_eq(ended.notification_badge_count(), 0)
}

///|
/// But only its own. A question belonging to a live successor must survive an
/// older run's terminal event arriving late.
test "a finished run leaves a question belonging to another run" {
  let successor = {
    ..running_conversation(),
    run: Open(run_id="r-successor", stage=Opened),
    pending_approval: Some({
      id: "ap-2",
      run_id: Some("r-successor"),
      tool_name: "mbtx",
      detail: "escalate",
      body: None,
      answered: false,
    }),
  }
  let (_, ended) = update_device_msg(
    test_dispatch(),
    @interop.ChannelId::Local,
    Finished(run_id="r-stale", status="finished", answer=None),
    test_model().replace_conversation(successor),
  )
  guard ended.active_conversation() is Some(after) else {
    fail("expected the conversation")
  }
  assert_true(after.pending_approval is Some(_))
  assert_eq(ended.notification_badge_count(), 1)
}
