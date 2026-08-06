// Prompt and steer delivery ownership transitions.

///|
fn is_steer_receipt(event : @transcript.EngineEvent) -> Bool {
  event is (SteerApplied(..) | SteerDropped(..))
}

///|
test "steer_applied only settles pending UI until its commit" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["go left"]),
  )
  let (_, next) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerApplied(content="go left", submission_id=Some("test-steer-0")),
      session=None,
    ),
    model,
  )
  inspect(next.active().pending_steers().length(), content="0")
  inspect(next.active().messages.length(), content="0")
  inspect(next.active().overlay.length(), content="0")
}

///|
test "a legacy text-only steer receipt cannot claim local ownership" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["go left"]),
  )
  let (_, next) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerApplied(content="go left", submission_id=None),
      session=None,
    ),
    model,
  )
  inspect(next.active().pending_steers().length(), content="1")
  inspect(next.active().input_ledger.length(), content="1")
}

///|
test "a live commit dates its row on arrival, buffered or applied straight" {
  let dispatch = test_dispatch()
  let stamped = (session, sequence, ts) => {
    SessionCommitted(
      session~,
      sequence~,
      ts=Some(ts),
      item=@protocol.User({ content: "question" }),
    )
  }
  // The contiguous-commit path a running conversation takes: the row must
  // carry its stamp now, not only after the next snapshot reload.
  let (_, direct) = update_dev(
    dispatch,
    stamped("desktop-test", 1, 1781144351123),
    running_model(),
  )
  assert_true(direct.active().messages[0].ts is Some(1781144351123))
  // The same stamp survives the buffer a reconnect drains commits through.
  let (_, reconnecting) = update_dev(dispatch, BridgeReady, running_model())
  let (_, buffered) = update_dev(
    dispatch,
    stamped("desktop-test", 1, 1781144352000),
    reconnecting,
  )
  let (_, drained) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[],
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    buffered,
  )
  assert_true(drained.active().messages[0].ts is Some(1781144352000))
}

///|
test "a canonical user commit never settles a local steer" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["go left"]),
  )
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "go left" }),
    ),
    model,
  )
  inspect(committed.active().messages.length(), content="1")
  inspect(committed.active().pending_steers().length(), content="1")
  inspect(committed.active().input_ledger.length(), content="1")
}

///|
test "a snapshot never settles a local steer by text" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      messages: [{ kind: User, content: "same", ts: None }],
      watermark: 1,
      sync: test_reloading([]),
    },
    ["same"],
  )
  let model = running_model().replace_conversation(conv)
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[{ kind: User, content: "same", ts: None }],
      watermark=1,
      event_boundaries=[],
      generation=1,
    ),
    model,
  )
  inspect(loaded.active().pending_steers().length(), content="1")
  inspect(loaded.active().input_ledger.length(), content="1")
}

///|
test "steer_dropped settles the pending steer with a visible notice" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["go left"]),
  )
  let (_, next) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerDropped(content="go left", submission_id=Some("test-steer-0")),
      session=None,
    ),
    model,
  )
  inspect(next.active().pending_steers().length(), content="0")
  inspect(next.active().overlay.length(), content="1")
  inspect(next.active().task, content="go left")
  guard next.active().overlay[0].kind is Assistant(is_danger=true) else {
    fail("expected an error bubble")
  }
  assert_true(next.active().overlay[0].content.contains("go left"))
}

///|
test "an identical-text settle removes exactly one pending entry" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["again", "again"]),
  )
  let (_, next) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerApplied(content="again", submission_id=Some("test-steer-0")),
      session=None,
    ),
    model,
  )
  inspect(next.active().pending_steers().length(), content="1")
  inspect(next.active().pending_steers()[0], content="again")
  inspect(next.active().input_ledger[0].submission_id, content="test-steer-1")
  inspect(next.active().overlay.length(), content="0")
}

///|
test "an undelivered steer is reported instead of vanishing" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["lost"]),
  )
  let (_, next) = update_dev(
    dispatch,
    SteerUndelivered(
      session="desktop-test",
      submission_id="test-steer-0",
      text="lost",
      run_id="r7",
    ),
    model,
  )
  inspect(next.active().pending_steers().length(), content="0")
  inspect(next.active().input_ledger.length(), content="1")
  assert_true(next.active().input_ledger[0].state is Unconfirmed)
  inspect(next.active().overlay.length(), content="1")
  guard next.active().overlay[0].kind is Assistant(is_danger=true) else {
    fail("expected an error bubble")
  }
  assert_true(next.active().overlay[0].content.contains("lost"))
}

///|
test "a run that ends with steers in flight marks delivery unconfirmed" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["orphaned"]),
  )
  let (_, next) = update_dev(
    dispatch,
    Finished(
      run_id="r7",
      status="finished",
      answer=Some(""),
      durable_sequence=None,
    ),
    model,
  )
  inspect(next.active().pending_steers().length(), content="0")
  inspect(next.active().input_ledger.length(), content="1")
  inspect(next.active().is_running(), content="false")
  guard next.active().overlay[0].kind is Assistant(is_danger=true) else {
    fail("expected an error bubble")
  }
  assert_true(next.active().overlay[0].content.contains("orphaned"))
}

///|
test "a late exact applied receipt retracts a run-end unconfirmed notice" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["lost"]),
  )
  let (_, finished) = update_dev(
    dispatch,
    Finished(
      run_id="r7",
      status="finished",
      answer=Some(""),
      durable_sequence=None,
    ),
    model,
  )
  let (_, next) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerApplied(content="lost", submission_id=Some("test-steer-0")),
      session=None,
    ),
    finished,
  )
  inspect(next.active().pending_steers().length(), content="0")
  inspect(next.active().input_ledger.length(), content="0")
  inspect(next.active().overlay.length(), content="0")
}

///|
test "a trailing applied receipt for run A settles after run B Started" {
  let dispatch = test_dispatch()
  guard second_run_started_before_first_steer_receipt() is Some(started) else {
    fail("expected the second prompt to be starting")
  }
  let (_, next) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerApplied(content="late steer", submission_id=Some("test-steer-0")),
      session=None,
    ),
    started,
  )
  assert_true(next.active().run is Open(run_id="r8", ..))
  assert_true(next.active().last_run_id is Some("r8"))
  inspect(next.active().input_ledger.length(), content="1")
  assert_true(next.active().input_ledger[0].kind is InitialPrompt)
  inspect(next.active().overlay.length(), content="0")
}

///|
test "a trailing dropped receipt for run A restores input without closing run B" {
  let dispatch = test_dispatch()
  guard second_run_started_before_first_steer_receipt() is Some(started) else {
    fail("expected the second prompt to be starting")
  }
  let (_, next) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerDropped(content="late steer", submission_id=Some("test-steer-0")),
      session=None,
    ),
    started,
  )
  assert_true(next.active().run is Open(run_id="r8", ..))
  assert_true(next.active().last_run_id is Some("r8"))
  inspect(next.active().input_ledger.length(), content="1")
  assert_true(next.active().input_ledger[0].kind is InitialPrompt)
  inspect(next.active().task, content="late steer")
  inspect(next.active().overlay.length(), content="1")
  assert_true(next.active().overlay[0].content.contains("late steer"))
}

///|
test "run-end unconfirmed notice follows assistant and terminal before freezing" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      messages: [{ kind: User, content: "question", ts: None }],
      watermark: 1,
    },
    ["late steer"],
  )
  let (_, finished) = update_dev(
    dispatch,
    Finished(
      run_id="r7",
      status="finished",
      answer=Some("answer"),
      durable_sequence=None,
    ),
    running_model().replace_conversation(conv),
  )
  let (_, buffered) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.Assistant({
        content: "answer",
        tool_calls: None,
        reasoning_content: None,
      }),
    ),
    finished,
  )
  let (_, buffered_terminal) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=3,
      ts=None,
      item=@protocol.Terminal(@protocol.Finished("answer")),
    ),
    buffered,
  )
  let (_, answered) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[
        { kind: User, content: "question", ts: None },
        { kind: Assistant(is_danger=false), content: "answer", ts: None },
      ],
      watermark=3,
      event_boundaries=[(3, true, 2)],
      generation=1,
    ),
    buffered_terminal,
  )
  let visible = answered.active().visible_items()
  inspect(visible.length(), content="3")
  inspect(visible[1].content, content="answer")
  assert_true(visible[2].content.contains("late steer"))
  let (_, next_turn) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=4,
      ts=None,
      item=@protocol.User({ content: "next question" }),
    ),
    answered,
  )
  let visible = next_turn.active().visible_items()
  inspect(visible.length(), content="4")
  inspect(visible[1].content, content="answer")
  assert_true(visible[2].content.contains("late steer"))
  inspect(visible[3].content, content="next question")
}

///|
test "a snapshot freezes a prior run-tail notice before its next turn" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      messages: [{ kind: User, content: "question", ts: None }],
      watermark: 1,
    },
    ["late steer"],
  )
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=None, durable_sequence=None),
    running_model().replace_conversation(conv),
  )
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[
        { kind: User, content: "question", ts: None },
        { kind: Assistant(is_danger=false), content: "first answer", ts: None },
        { kind: User, content: "next question", ts: None },
        { kind: Assistant(is_danger=false), content: "next answer", ts: None },
      ],
      watermark=7,
      event_boundaries=[(3, true, 2), (7, true, 4)],
      generation=1,
    ),
    finished,
  )
  let visible = loaded.active().visible_items()
  inspect(visible.length(), content="5")
  inspect(visible[0].content, content="question")
  inspect(visible[1].content, content="first answer")
  assert_true(visible[2].content.contains("late steer"))
  inspect(visible[3].content, content="next question")
  inspect(visible[4].content, content="next answer")
}

///|
test "a snapshot does not mistake a same-run steer User for the terminal boundary" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      messages: [{ kind: User, content: "question", ts: None }],
      watermark: 1,
      sync: test_reloading([]),
    },
    ["late steer"],
  )
  let model = running_model().replace_conversation(conv)
  let (_, steer_buffered) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.User({ content: "late steer" }),
    ),
    model,
  )
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=None, durable_sequence=None),
    steer_buffered,
  )
  let (_, answered) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=3,
      ts=None,
      item=@protocol.Assistant({
        content: "answer",
        tool_calls: None,
        reasoning_content: None,
      }),
    ),
    finished,
  )
  let (_, terminal) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=4,
      ts=None,
      item=@protocol.Terminal(@protocol.Finished("answer")),
    ),
    answered,
  )
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[
        { kind: User, content: "question", ts: None },
        { kind: User, content: "late steer", ts: None },
        { kind: Assistant(is_danger=false), content: "answer", ts: None },
      ],
      watermark=4,
      event_boundaries=[(4, true, 3)],
      generation=1,
    ),
    terminal,
  )
  let visible = loaded.active().visible_items()
  inspect(visible.length(), content="4")
  inspect(visible[1].content, content="late steer")
  inspect(visible[2].content, content="answer")
  assert_true(visible[3].content.contains("late steer"))
}

///|
test "an unknown terminal before Finished still owns the run-tail notice" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      messages: [
        { kind: User, content: "question", ts: None },
        { kind: Assistant(is_danger=false), content: "answer", ts: None },
      ],
      watermark: 2,
    },
    ["late steer"],
  )
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=3,
      ts=None,
      item=@protocol.UnknownTerminal({
        "kind": "terminal",
        "payload": { "kind": "future_terminal", "message": "answer" },
      }),
    ),
    running_model().replace_conversation(conv),
  )
  inspect(committed.active().last_terminal_sequence, content="3")
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=None, durable_sequence=None),
    committed,
  )
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[
        { kind: User, content: "question", ts: None },
        { kind: Assistant(is_danger=false), content: "answer", ts: None },
      ],
      watermark=3,
      event_boundaries=[(3, true, 2)],
      generation=1,
    ),
    finished,
  )
  let visible = loaded.active().visible_items()
  inspect(visible.length(), content="3")
  inspect(visible[1].content, content="answer")
  assert_true(visible[2].content.contains("late steer"))
}

///|
test "a successor resolves an old terminal tail only from its causal snapshot" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      messages: [
        { kind: User, content: "first question", ts: None },
        { kind: Assistant(is_danger=false), content: "first answer", ts: None },
      ],
      watermark: 2,
      run_durable_floor: Some(0),
      sync: test_reloading([]),
    },
    ["late steer"],
  )
  let model = {
    ..running_model().replace_conversation(conv),
    transcript_request_generation: 1,
  }
  // The old terminal commit beat Finished, so no future live commit can be
  // assumed to be the boundary for the notice Finished is about to create.
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=3,
      ts=None,
      item=@protocol.Terminal(@protocol.Finished("first answer")),
    ),
    model,
  )
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=None, durable_sequence=None),
    committed,
  )
  assert_true(
    finished.active().overlay[0].anchor
    is PriorTerminalTail(floor=0, snapshot_generation=2),
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r8",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("second question"),
      submission_id=None,
    ),
    finished,
  )
  assert_true(
    started.active().overlay[0].anchor
    is PriorTerminalTail(floor=0, snapshot_generation=2),
  )
  let (_, second_user) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=4,
      ts=None,
      item=@protocol.User({ content: "second question" }),
    ),
    started,
  )
  let (_, second_terminal) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=5,
      ts=None,
      item=@protocol.Terminal(@protocol.Finished("second answer")),
    ),
    second_user,
  )
  // Generation 1 predates Finished and Started. It drains both runs' buffered
  // terminals, but neither anonymous live commit may place the notice.
  let (_, old_cut) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[
        { kind: User, content: "first question", ts: None },
        { kind: Assistant(is_danger=false), content: "first answer", ts: None },
      ],
      watermark=2,
      event_boundaries=[(1, false, 1), (2, false, 2)],
      generation=1,
    ),
    second_terminal,
  )
  assert_true(old_cut.active().sync is Reloading(generation=2, ..))
  assert_true(old_cut.active().overlay[0].anchor is PriorTerminalTail(..))
  let (_, causal) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[
        { kind: User, content: "first question", ts: None },
        { kind: Assistant(is_danger=false), content: "first answer", ts: None },
        { kind: User, content: "second question", ts: None },
        { kind: Assistant(is_danger=false), content: "second answer", ts: None },
      ],
      watermark=5,
      event_boundaries=[
        (1, false, 1),
        (2, false, 2),
        (3, true, 2),
        (4, false, 3),
        (5, true, 4),
      ],
      generation=2,
    ),
    old_cut,
  )
  assert_true(causal.active().overlay[0].anchor is AfterMessages(2))
  let visible = causal.active().visible_items()
  inspect(visible.length(), content="5")
  assert_true(visible[2].content.contains("late steer"))
  inspect(visible[3].content, content="second question")
}

///|
test "a successor terminal cannot claim a setup-failed run's snapshot cut" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      watermark: 1,
      last_terminal_sequence: 1,
      run_durable_floor: Some(1),
    },
    ["late steer"],
  )
  let (_, setup_failed) = update_dev(
    dispatch,
    Error(
      run_id=Some("r7"),
      message="agent setup failed: boom",
      diagnostics=None,
      exit_code=None,
    ),
    running_model().replace_conversation(conv),
  )
  inspect(setup_failed.active().overlay.length(), content="0")
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="failed", answer=None, durable_sequence=None),
    setup_failed,
  )
  assert_true(
    finished.active().overlay[0].anchor is SnapshotCut(snapshot_generation=1),
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r8",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("next question"),
      submission_id=None,
    ),
    finished,
  )
  assert_true(
    started.active().overlay[0].anchor is SnapshotCut(snapshot_generation=2),
  )
  let (_, old_cut) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[],
      watermark=1,
      event_boundaries=[(1, true, 0)],
      generation=1,
    ),
    started,
  )
  assert_true(old_cut.active().sync is Reloading(generation=2, ..))
  assert_true(
    old_cut.active().overlay[0].anchor is SnapshotCut(snapshot_generation=2),
  )
  let (_, causal) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[
        { kind: User, content: "next question", ts: None },
        { kind: Assistant(is_danger=false), content: "next answer", ts: None },
      ],
      watermark=3,
      event_boundaries=[(1, true, 0), (2, false, 1), (3, true, 2)],
      generation=2,
    ),
    old_cut,
  )
  assert_true(causal.active().overlay[0].anchor is AfterMessages(2))
  assert_false(causal.active().has_unresolved_run_tail_notice())
  let visible = causal.active().visible_items()
  inspect(visible.length(), content="3")
  inspect(visible[0].content, content="next question")
  inspect(visible[1].content, content="next answer")
  assert_true(visible[2].content.contains("late steer"))
}

///|
test "an offline successor snapshot fences without claiming its terminal" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      watermark: 1,
      last_terminal_sequence: 1,
      run_durable_floor: Some(1),
    },
    ["unconfirmed steer"],
  )
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="failed", answer=None, durable_sequence=None),
    running_model().replace_conversation(conv),
  )
  // This page missed every lifecycle event for r8 while it was offline. The
  // snapshot's terminal therefore has no identity tying it to r7.
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[
        { kind: User, content: "offline successor", ts: None },
        {
          kind: Assistant(is_danger=false),
          content: "successor answer",
          ts: None,
        },
      ],
      watermark=3,
      event_boundaries=[(1, true, 0), (2, false, 1), (3, true, 2)],
      generation=1,
    ),
    finished,
  )
  assert_true(loaded.active().overlay[0].anchor is AfterMessages(2))
  assert_false(loaded.active().has_unresolved_run_tail_notice())
}

///|
test "failure and abort statuses never assume a durable terminal" {
  let dispatch = test_dispatch()
  for status in ["failed", "aborted", "cancelled", "future_failure"] {
    let conv = with_pending_steers(running_conversation(), ["unconfirmed"])
    let (_, finished) = update_dev(
      dispatch,
      Finished(run_id="r7", status~, answer=None, durable_sequence=None),
      running_model().replace_conversation(conv),
    )
    guard finished.active().overlay is [notice] else {
      fail("expected one notice for " + status)
    }
    assert_true(notice.anchor is SnapshotCut(snapshot_generation=1))
  }
}

///|
test "a foreign run gains a floor only after snapshot data follows the prior terminal" {
  let dispatch = test_dispatch()
  let conv = {
    ..test_conversation(),
    messages: [
      { kind: Assistant(is_danger=false), content: "previous", ts: None },
    ],
    watermark: 2,
    last_terminal_sequence: 2,
    sync: test_reloading([]),
  }
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="foreign",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("current"),
      submission_id=None,
    ),
    test_model().replace_conversation(conv),
  )
  assert_true(started.active().run_durable_floor is None)
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[
        { kind: Assistant(is_danger=false), content: "previous", ts: None },
        { kind: User, content: "current", ts: None },
      ],
      watermark=3,
      event_boundaries=[(2, true, 1)],
      generation=1,
    ),
    started,
  )
  assert_true(loaded.active().run_durable_floor is Some(2))
}

///|
test "a foreign background run waits for a snapshot cut after Started" {
  let dispatch = test_dispatch()
  let session = "desktop-background"
  let conv = {
    ..empty_conversation(@interop.ChannelId::Local, session),
    watermark: 1,
    last_terminal_sequence: 1,
    sync: test_reloading([]),
  }
  let model = {
    ..test_model().replace_conversation(conv),
    transcript_request_generation: 1,
  }
  // This previous-run answer arrived behind a snapshot whose read cut was
  // already taken, but before the next run's lifecycle announcement.
  let (_, buffered_answer) = update_dev(
    dispatch,
    SessionCommitted(
      session~,
      sequence=2,
      ts=None,
      item=@protocol.Assistant({
        content: "previous answer",
        tool_calls: None,
        reasoning_content: None,
      }),
    ),
    model,
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="foreign-next",
      session~,
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("current question"),
      submission_id=None,
    ),
    buffered_answer,
  )
  guard started.find_conversation(@interop.ChannelId::Local, session)
    is Some(started_conv) else {
    fail("missing background conversation")
  }
  assert_true(started_conv.run_durable_floor is None)
  assert_true(started_conv.run_floor_generation is Some(2))
  assert_true(
    started_conv.sync is Reloading(generation=1, reload_after_current=true, ..),
  )
  let (_, buffered_terminal) = update_dev(
    dispatch,
    SessionCommitted(
      session~,
      sequence=3,
      ts=None,
      item=@protocol.Terminal(@protocol.Finished("previous answer")),
    ),
    started,
  )
  let (_, buffered_user) = update_dev(
    dispatch,
    SessionCommitted(
      session~,
      sequence=4,
      ts=None,
      item=@protocol.User({ content: "current question" }),
    ),
    buffered_terminal,
  )
  // Generation 1 predates Started. It may drain the ordered buffer, but it
  // cannot let the old answer claim the new run's floor.
  let (_, after_old_cut) = update_dev(
    dispatch,
    SessionRefreshed(
      session~,
      items=[],
      watermark=1,
      event_boundaries=[(1, true, 0)],
      generation=1,
    ),
    buffered_user,
  )
  guard after_old_cut.find_conversation(@interop.ChannelId::Local, session)
    is Some(after_old) else {
    fail("missing conversation after old snapshot")
  }
  assert_true(after_old.run_durable_floor is None)
  assert_true(after_old.run_floor_generation is Some(2))
  assert_true(after_old.sync is Reloading(generation=2, ..))
  inspect(after_old.last_terminal_sequence, content="3")
  let (_, causal) = update_dev(
    dispatch,
    SessionRefreshed(
      session~,
      items=[
        {
          kind: Assistant(is_danger=false),
          content: "previous answer",
          ts: None,
        },
        { kind: User, content: "current question", ts: None },
      ],
      watermark=4,
      event_boundaries=[
        (1, true, 0),
        (2, false, 1),
        (3, true, 1),
        (4, false, 2),
      ],
      generation=2,
    ),
    after_old_cut,
  )
  guard causal.find_conversation(@interop.ChannelId::Local, session)
    is Some(current) else {
    fail("missing conversation after causal snapshot")
  }
  assert_true(current.run_durable_floor is Some(3))
  assert_true(current.run_floor_generation is None)
}

///|
test "buffered future terminal cannot become its own run floor" {
  let dispatch = test_dispatch()
  let conv = {
    ..running_conversation(),
    watermark: 1,
    last_terminal_sequence: 1,
    run_durable_floor: None,
    sync: test_reloading([]),
  }
  let model = test_model().replace_conversation(conv)
  let (_, user) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.User({ content: "current question" }),
    ),
    model,
  )
  let (_, answer) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=3,
      ts=None,
      item=@protocol.Assistant({
        content: "current answer",
        tool_calls: None,
        reasoning_content: None,
      }),
    ),
    user,
  )
  let (_, terminal) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=4,
      ts=None,
      item=@protocol.Terminal(@protocol.Finished("current answer")),
    ),
    answer,
  )
  // Buffered state is delivery, not applied chronology.
  inspect(terminal.active().last_terminal_sequence, content="1")
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[],
      watermark=1,
      event_boundaries=[(1, true, 0)],
      generation=1,
    ),
    terminal,
  )
  assert_true(loaded.active().run_durable_floor is Some(1))
  inspect(loaded.active().last_terminal_sequence, content="4")
}

///|
test "a late durable EOF finalizes an unconfirmed steer without a terminal" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      watermark: 1,
      last_terminal_sequence: 1,
      run_durable_floor: Some(1),
    },
    ["late steer"],
  )
  let (_, errored) = update_dev(
    dispatch,
    Error(
      run_id=Some("r7"),
      message="engine exited without a result",
      diagnostics=None,
      exit_code=Some(1),
    ),
    test_model().replace_conversation(conv),
  )
  let (_, synthetic) = update_dev(
    dispatch,
    Finished(run_id="r7", status="failed", answer=None, durable_sequence=None),
    errored,
  )
  guard synthetic.active().overlay is [_, steer_notice] else {
    fail("expected the process error and unconfirmed steer notices")
  }
  assert_true(steer_notice.anchor is SnapshotCut(snapshot_generation=1))
  let (_, partial) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.Assistant({
        content: "partial answer",
        tool_calls: None,
        reasoning_content: None,
      }),
    ),
    synthetic,
  )
  // The real EOF consumer publishes a non-lifecycle boundary only after its
  // final scan, carrying the exact last sequence even though no Terminal was
  // appended.
  let (_, finalized) = update_dev(
    dispatch,
    DurableBoundary(run_id="r7", session="desktop-test", sequence=2),
    partial,
  )
  assert_true(finalized.active().overlay[1].anchor is DurableTail(2))
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[
        {
          kind: Assistant(is_danger=false),
          content: "partial answer",
          ts: None,
        },
      ],
      watermark=2,
      event_boundaries=[(1, true, 0), (2, false, 1)],
      generation=1,
    ),
    finalized,
  )
  assert_true(loaded.active().overlay[1].anchor is AfterMessages(1))
  assert_false(loaded.active().has_unresolved_run_tail_notice())
  let visible = loaded.active().visible_items()
  inspect(visible.length(), content="3")
  inspect(visible[0].content, content="partial answer")
  assert_true(visible[1].content.contains("engine exited"))
  assert_true(visible[2].content.contains("late steer"))
}

///|
test "two run-tail notice groups freeze only at their own terminals" {
  let first = { ..test_conversation(), run_durable_floor: Some(1) }.append_run_tail_notice(
    Assistant(is_danger=true),
    "first",
    Retained,
  )
  let second = { ..first, run_durable_floor: Some(5) }.append_run_tail_notice(
    Assistant(is_danger=true),
    "second",
    Retained,
  )
  let frozen = second.freeze_run_tail_notices_from_snapshot(
    [(4, true, 2), (8, true, 4)],
    1,
  )
  assert_true(frozen.overlay[0].anchor is AfterMessages(2))
  assert_true(frozen.overlay[1].anchor is AfterMessages(4))
}
