// Run reconciliation and reconnect recovery transitions.

///|
test "runs settled closes runs the host no longer has, sparing live and starting ones" {
  let dispatch = test_dispatch()
  // A run that ended while this client was away: its terminal event is
  // gone for good, so only the `agent.runs` reply can close it.
  let stale = {
    ..empty_conversation(@interop.ChannelId::Local, "desktop-stale"),
    run: Open(run_id="r9", stage=AtStep(Some(4))),
    streaming_response: "mid-step",
  }
  // A send still in flight has no run id yet; its own `started` (or
  // failure) is coming and must be the one to settle it.
  let starting = {
    ..empty_conversation(@interop.ChannelId::Local, "desktop-starting"),
    run: Starting(submission_id="pending-start"),
  }
  let model = running_model()
    .replace_conversation(stale)
    .replace_conversation(starting)
  let (_, next) = update_dev(
    dispatch,
    RunsSettled(live=["r7"], frontier=[
      {
        session: "desktop-test",
        state: SnapshotOpen(run_id="r7"),
        initial_ids: [],
        steer_ids: [],
      },
      {
        session: "desktop-stale",
        state: SnapshotOpen(run_id="r9"),
        initial_ids: [],
        steer_ids: [],
      },
    ]),
    model,
  )
  // Run 7 is still in flight on the host: untouched.
  inspect(next.active().is_running(), content="true")
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-stale")
    is Some(settled) else {
    fail("expected the stale conversation")
  }
  inspect(settled.is_running(), content="false")
  inspect(settled.streaming_response, content="")
  guard settled.run is NoRun(ended=None) else {
    fail("expected the stale run to settle without a verdict")
  }
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-starting")
    is Some(sending) else {
    fail("expected the starting conversation")
  }
  assert_true(sending.run is Starting(..))
}

///|
test "reconnect runs snapshot settles only its captured Starting submission" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="pre-gap-start") },
    "pre-gap-start",
    "maybe accepted",
  )
  let (_, bridged) = update_dev(
    dispatch,
    BridgeReady,
    test_model().replace_conversation(conv),
  )
  assert_true(bridged.active().input_ledger[0].state is Unconfirmed)
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(
      live=[],
      frontier=bridged.run_snapshot_frontier(@interop.ChannelId::Local),
    ),
    bridged,
  )
  assert_true(settled.active().run is NoRun(ended=None))
}

///|
test "an old empty runs snapshot cannot close a start sent after reconnect" {
  let dispatch = test_dispatch()
  let (_, ready) = update_dev(dispatch, BridgeReady, test_model())
  let (_, drafted) = update(dispatch, TaskChanged("new prompt"), ready)
  let (_, sent) = update(dispatch, Send, drafted)
  assert_true(sent.active().run is Starting(..))
  let (_, stale_snapshot) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier=[]),
    sent,
  )
  assert_true(stale_snapshot.active().run is Starting(..))
}

///|
test "an older recovered ledger entry cannot adjudicate the current start" {
  let dispatch = test_dispatch()
  let old = with_initial_submission(
    test_conversation(),
    "pre-gap-start",
    "older prompt",
  )
  let (old, _) = old.mark_submission_unconfirmed(
    "pre-gap-start", "older delivery unconfirmed", false,
  )
  let current = with_initial_submission(
    { ..old, run: Starting(submission_id="current-start") },
    "current-start",
    "current prompt",
  )
  let (_, next) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier=[
      {
        session: "desktop-test",
        state: SnapshotStarting(submission_id="pre-gap-start"),
        initial_ids: ["pre-gap-start"],
        steer_ids: [],
      },
    ]),
    test_model().replace_conversation(current),
  )
  assert_true(next.active().run is Starting(submission_id="current-start"))
  inspect(next.active().input_ledger.length(), content="2")
}

///|
test "an older start rejection cannot close the current start" {
  let dispatch = test_dispatch()
  let old = with_initial_submission(
    test_conversation(),
    "older-start",
    "older prompt",
  )
  let current = with_initial_submission(
    { ..old, run: Starting(submission_id="current-start") },
    "current-start",
    "current prompt",
  )
  let (_, next) = update_dev(
    dispatch,
    StartRejected(
      session="desktop-test",
      submission_id="older-start",
      message="older start rejected",
    ),
    test_model().replace_conversation(current),
  )
  assert_true(next.active().run is Starting(submission_id="current-start"))
  inspect(next.active().input_ledger.length(), content="1")
  inspect(next.active().input_ledger[0].submission_id, content="current-start")
}

///|
test "a Started racing ahead of an older runs response stays open" {
  let dispatch = test_dispatch()
  let frontier = test_model().run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r-after-snapshot",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("new foreign run"),
      submission_id=Some("foreign-new"),
    ),
    test_model(),
  )
  let (_, stale_snapshot) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier~),
    started,
  )
  assert_true(
    stale_snapshot.active().run is Open(run_id="r-after-snapshot", ..),
  )
}

///|
test "a stale runs snapshot cannot replay a foreign run after BridgeReady" {
  let dispatch = test_dispatch()
  let (_, generation_one) = update_dev(dispatch, BridgeReady, test_model())
  let stale = RunsLoaded(
    runs=[
      {
        run_id: "old-run",
        session: "old-session",
        model: High,
        max_steps: 1000,
        cwd: None,
        session_root: None,
        task: Some("from the old engine epoch"),
        submission_id: None,
      },
    ],
    settled=[],
    live=["old-run"],
    frontier=generation_one.run_snapshot_frontier(@interop.ChannelId::Local),
    connection_generation=generation_one.dev().connection_generation,
  )
  let (_, generation_two) = update_dev(dispatch, BridgeReady, generation_one)
  // The current generation's empty answer wins first. The delayed older
  // answer must then be rejected whole, before replaying its Started row.
  let (_, current) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[],
      settled=[],
      live=[],
      frontier=generation_two.run_snapshot_frontier(@interop.ChannelId::Local),
      connection_generation=generation_two.dev().connection_generation,
    ),
    generation_two,
  )
  let (_, once) = update_dev(dispatch, stale, current)
  let (_, twice) = update_dev(dispatch, stale, current)
  assert_true(
    once.find_conversation(@interop.ChannelId::Local, "old-session") is None,
  )
  assert_true(
    twice.find_conversation(@interop.ChannelId::Local, "old-session") is None,
  )
  inspect(once.dev().connection_generation, content="2")
  inspect(twice.dev().connection_generation, content="2")
}

///|
test "runs settlement restores a Starting prompt that reached exact-zero EOF offline" {
  let dispatch = test_dispatch()
  let submission_id = "offline-start"
  let before = test_model().replace_conversation(
    with_initial_submission(
      { ..test_conversation(), run: Starting(submission_id~), task: "" },
      submission_id,
      "restore after reconnect",
    ),
  )
  let frontier = before.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, bridged) = update_dev(dispatch, BridgeReady, before)
  assert_true(bridged.active().sync is Reloading(..))
  let (_, recovered) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[],
      settled=[
        {
          run_id: "run-offline-zero",
          session: "desktop-test",
          submission_id: Some(submission_id),
          status: "failed",
          durable_sequence: Some(0),
        },
      ],
      live=[],
      frontier~,
      connection_generation=bridged.dev().connection_generation,
    ),
    bridged,
  )
  assert_true(
    recovered.active().run is NoRun(ended=Some(RunFinished(RunFailed))),
  )
  assert_true(recovered.active().sync is Synced)
  inspect(recovered.active().task, content="restore after reconnect")
  inspect(recovered.active().input_ledger.length(), content="0")
  assert_true(recovered.active().overlay[0].reconciliation is Retained)
}

///|
test "a late durable boundary refetches a Starting settlement hidden by the first runs snapshot" {
  let dispatch = test_dispatch()
  let submission_id = "late-boundary-start"
  let before = test_model().replace_conversation(
    with_initial_submission(
      { ..test_conversation(), run: Starting(submission_id~), task: "" },
      submission_id,
      "restore after the boundary",
    ),
  )
  let first_frontier = before.run_snapshot_frontier(@interop.ChannelId::Local)
  // Finished has already removed the run, but its failed final scan has not
  // made the abnormal settlement replayable yet.
  let (_, absent) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[],
      settled=[],
      live=[],
      frontier=first_frontier,
      connection_generation=before.dev().connection_generation,
    ),
    before,
  )
  assert_true(absent.active().run is NoRun(ended=None))
  assert_true(absent.active().last_run_id is None)
  assert_true(absent.active().has_recovering_initial())

  // The boundary cannot route by run id yet. It keeps the exact local owner
  // unchanged and schedules another current-generation agent.runs query.
  let (_, after_boundary) = update_dev(
    dispatch,
    DurableBoundary(
      run_id="run-late-boundary",
      session="desktop-test",
      sequence=0,
    ),
    absent,
  )
  assert_true(after_boundary.active().last_run_id is None)
  let second_frontier = after_boundary.run_snapshot_frontier(
    @interop.ChannelId::Local,
  )
  guard second_frontier is [captured] else {
    fail("late boundary lost the settlement selector")
  }
  assert_true(captured.initial_ids.contains(submission_id))

  // The host recorded agent.durable before broadcasting it, so that query
  // returns the newly replayable settlement and restores exact-zero input.
  let (_, recovered) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[],
      settled=[
        {
          run_id: "run-late-boundary",
          session: "desktop-test",
          submission_id: Some(submission_id),
          status: "failed",
          durable_sequence: Some(0),
        },
      ],
      live=[],
      frontier=second_frontier,
      connection_generation=after_boundary.dev().connection_generation,
    ),
    after_boundary,
  )
  assert_true(recovered.active().sync is Synced)
  inspect(recovered.active().task, content="restore after the boundary")
  inspect(recovered.active().input_ledger.length(), content="0")
  assert_true(recovered.active().overlay[0].reconciliation is Retained)
}

///|
test "runs settlement recovers a transport-undelivered prompt by submission id" {
  let dispatch = test_dispatch()
  let submission_id = "socket-lost-start"
  let starting = test_model().replace_conversation(
    with_initial_submission(
      { ..test_conversation(), run: Starting(submission_id~), task: "" },
      submission_id,
      "restore after socket loss",
    ),
  )
  let (_, undelivered) = update_dev(
    dispatch,
    StartUndelivered(
      session="desktop-test",
      submission_id~,
      message="connection closed",
    ),
    starting,
  )
  assert_true(undelivered.active().run is NoRun(ended=Some(RunFailed)))
  assert_true(undelivered.active().input_ledger[0].run_id is None)
  let frontier = undelivered.run_snapshot_frontier(@interop.ChannelId::Local)
  let selectors = runs_payload(frontier).to_json()
  assert_true(
    selectors
    is {
      "known": Array(
        [
          {
            "session": "desktop-test",
            "submission_id": "socket-lost-start",
            ..
          },
        ]
      ),
      ..
    },
  )
  let (_, bridged) = update_dev(dispatch, BridgeReady, undelivered)
  let (_, recovered) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[],
      settled=[
        {
          run_id: "run-socket-lost-zero",
          session: "desktop-test",
          submission_id: Some(submission_id),
          status: "failed",
          durable_sequence: Some(0),
        },
      ],
      live=[],
      frontier~,
      connection_generation=bridged.dev().connection_generation,
    ),
    bridged,
  )
  assert_true(recovered.active().sync is Synced)
  inspect(recovered.active().task, content="restore after socket loss")
  inspect(recovered.active().input_ledger.length(), content="0")
  assert_true(recovered.active().overlay[0].reconciliation is Retained)
}

///|
test "runs settlement restores an Open prompt whose zero boundary was missed" {
  let dispatch = test_dispatch()
  let before = fresh_started_model(
    "offline-open", "run-offline-open", "restore open after reconnect",
  )
  let frontier = before.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, bridged) = update_dev(dispatch, BridgeReady, before)
  let (_, recovered) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[],
      settled=[
        {
          run_id: "run-offline-open",
          session: "desktop-test",
          submission_id: Some("offline-open"),
          status: "failed",
          durable_sequence: Some(0),
        },
      ],
      live=[],
      frontier~,
      connection_generation=bridged.dev().connection_generation,
    ),
    bridged,
  )
  assert_true(recovered.active().sync is Synced)
  inspect(recovered.active().task, content="restore open after reconnect")
  inspect(recovered.active().input_ledger.length(), content="0")
}

///|
test "one runs snapshot keeps an active successor after settling its predecessor" {
  let dispatch = test_dispatch()
  let before = fresh_started_model(
    "old-submission", "run-predecessor", "restore predecessor prompt",
  )
  let frontier = before.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, next) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[
        {
          run_id: "run-successor",
          session: "desktop-test",
          model: High,
          max_steps: 1000,
          cwd: None,
          session_root: None,
          task: Some("foreign successor"),
          submission_id: Some("foreign-submission"),
        },
      ],
      settled=[
        {
          run_id: "run-predecessor",
          session: "desktop-test",
          submission_id: Some("old-submission"),
          status: "failed",
          durable_sequence: Some(0),
        },
      ],
      live=["run-successor"],
      frontier~,
      connection_generation=before.dev().connection_generation,
    ),
    before,
  )
  assert_true(next.active().run is Open(run_id="run-successor", ..))
  assert_true(next.active().last_run_id is Some("run-successor"))
  inspect(next.active().task, content="restore predecessor prompt")
  inspect(next.active().input_ledger.length(), content="0")
  assert_true(
    next.active().overlay
    .iter()
    .any(notice => {
      notice.reconciliation is Retained &&
      notice.content.contains("restored for resubmission")
    }),
  )
}

///|
test "a settlement captured for an older Starting owner cannot close its successor" {
  let dispatch = test_dispatch()
  let old = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="old-owner") },
    "old-owner",
    "old prompt",
  )
  let frontier = test_model()
    .replace_conversation(old)
    .run_snapshot_frontier(@interop.ChannelId::Local)
  let current = with_initial_submission(
    { ..old, run: Starting(submission_id="new-owner") },
    "new-owner",
    "new prompt",
  )
  let model = test_model().replace_conversation(current)
  let (_, unchanged) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[],
      settled=[
        {
          run_id: "old-run",
          session: "desktop-test",
          submission_id: Some("old-owner"),
          status: "failed",
          durable_sequence: Some(0),
        },
      ],
      live=[],
      frontier~,
      connection_generation=model.dev().connection_generation,
    ),
    model,
  )
  assert_true(unchanged.active().run is Starting(submission_id="new-owner"))
  inspect(unchanged.active().input_ledger.length(), content="2")
}

///|
test "an older positive runs row cannot replace a newer Started" {
  let dispatch = test_dispatch()
  let model = running_model()
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=None, durable_sequence=None),
    model,
  )
  let (_, newer) = update_dev(
    dispatch,
    Started(
      run_id="r8",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("newer run"),
      submission_id=None,
    ),
    finished,
  )
  let (_, stale) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[
        {
          run_id: "r7",
          session: "desktop-test",
          model: High,
          max_steps: 1000,
          cwd: None,
          session_root: None,
          task: Some("older run"),
          submission_id: None,
        },
      ],
      settled=[],
      live=["r7"],
      frontier~,
      connection_generation=0,
    ),
    newer,
  )
  assert_true(stale.active().run is Open(run_id="r8", ..))
  assert_true(stale.active().last_run_id is Some("r8"))
}

///|
test "an older positive runs row cannot resurrect a finished run" {
  let dispatch = test_dispatch()
  let model = running_model()
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=None, durable_sequence=None),
    model,
  )
  let (_, stale) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[
        {
          run_id: "r7",
          session: "desktop-test",
          model: High,
          max_steps: 1000,
          cwd: None,
          session_root: None,
          task: Some("already finished"),
          submission_id: None,
        },
      ],
      settled=[],
      live=["r7"],
      frontier~,
      connection_generation=0,
    ),
    finished,
  )
  assert_true(stale.active().run is NoRun(ended=Some(RunFinished(Completed))))
  assert_true(stale.active().last_run_id is Some("r7"))
}

///|
test "Finished after RunsSettled fills the last run outcome idempotently" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    last_run_id: Some("r7"),
  })
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(
      live=[],
      frontier=model.run_snapshot_frontier(@interop.ChannelId::Local),
    ),
    model,
  )
  assert_true(settled.active().run is NoRun(ended=None))
  let finish : DeviceMsg = Finished(
    run_id="r7",
    status="finished",
    answer=None,
    durable_sequence=None,
  )
  let (_, once) = update_dev(dispatch, finish, settled)
  let (_, twice) = update_dev(dispatch, finish, once)
  assert_true(once.active().run is NoRun(ended=Some(RunFinished(Completed))))
  assert_true(twice.active().run is NoRun(ended=Some(RunFinished(Completed))))
  inspect(twice.active().overlay.length(), content="0")
}

///|
test "a failed start response keeps its prompt through an empty snapshot" {
  let dispatch = test_dispatch()
  let conv = {
    ..test_conversation(),
    run: Starting(submission_id="failed-start"),
  }.enqueue_input(
    InitialPrompt,
    "failed-start",
    None,
    "<user_mentions>serialized context</user_mentions>\nprompt",
    "prompt",
    [],
  )
  let (_, failed) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="failed-start",
      run_id="r-failed",
      status="failed",
      exit_code=1,
    ),
    test_model().replace_conversation(conv),
  )
  assert_true(failed.active().run is NoRun(ended=Some(RunFailed)))
  assert_true(failed.active().sync is Reloading(..))
  inspect(failed.active().input_ledger.length(), content="1")
  assert_true(failed.active().input_ledger[0].state is Unconfirmed)
  inspect(failed.active().input_ledger[0].draft, content="prompt")
  inspect(failed.active().overlay.length(), content="1")
  assert_true(failed.active().overlay[0].content.contains("prompt"))
  assert_false(failed.active().overlay[0].content.contains("<user_mentions>"))
  let (_, empty) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[],
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    failed,
  )
  inspect(empty.active().input_ledger.length(), content="1")
  assert_true(empty.active().input_ledger[0].state is Unconfirmed)
  inspect(empty.active().visible_items().length(), content="1")
  assert_true(empty.active().visible_items()[0].content.contains("prompt"))
  let (_, late_started) = update_dev(
    dispatch,
    Started(
      run_id="r-failed",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=Some(@interop.ChannelId::Local.test_resource("/workspace")),
      session_root=None,
      task=Some("prompt"),
      submission_id=Some("failed-start"),
    ),
    empty,
  )
  assert_true(late_started.active().run is NoRun(ended=Some(RunFailed)))
  assert_true(
    late_started.active().cwd is Some(resource) && resource.path == "/workspace",
  )
}

///|
test "a failed response after durable Finished cannot resurrect its prompt" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="fast-start") },
    "fast-start",
    "fast prompt",
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r-fast",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("fast prompt"),
      submission_id=Some("fast-start"),
    ),
    test_model().replace_conversation(conv),
  )
  inspect(started.active().input_ledger.length(), content="1")
  let (_, finished) = update_dev(
    dispatch,
    Finished(
      run_id="r-fast",
      status="finished",
      answer=None,
      durable_sequence=None,
    ),
    started,
  )
  assert_true(
    finished.active().run is NoRun(ended=Some(RunFinished(Completed))),
  )
  let (_, failed) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="fast-start",
      run_id="r-fast",
      status="failed",
      exit_code=1,
    ),
    finished,
  )
  assert_true(failed.active().run is NoRun(ended=Some(RunFinished(Completed))))
  inspect(failed.active().input_ledger.length(), content="0")
  inspect(failed.active().overlay.length(), content="0")
  let (_, empty) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[],
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    failed,
  )
  assert_true(empty.active().run is NoRun(ended=Some(RunFinished(Completed))))
  inspect(empty.active().input_ledger.length(), content="0")
  inspect(empty.active().overlay.length(), content="0")
}

///|
test "an accepted response consumes a fast-finished prompt without reopening" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    {
      ..test_conversation(),
      run: NoRun(ended=Some(RunFinished(Completed))),
      last_run_id: Some("r-fast"),
    },
    "fast-start",
    "fast prompt",
  )
  let (conv, _) = conv.mark_submission_unconfirmed(
    "fast-start", "delivery unconfirmed: fast prompt", false,
  )
  let (_, accepted) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="fast-start",
      run_id="r-fast",
      status="accepted",
      exit_code=0,
    ),
    test_model().replace_conversation(conv),
  )
  assert_true(
    accepted.active().run is NoRun(ended=Some(RunFinished(Completed))),
  )
  inspect(accepted.active().input_ledger.length(), content="0")
  inspect(accepted.active().overlay.length(), content="0")
}

///|
test "a newer Started retires an older unconfirmed start ledger entry" {
  let dispatch = test_dispatch()
  let old = with_initial_submission(
    { ..test_conversation(), run: NoRun(ended=Some(RunFailed)) },
    "old-start",
    "old prompt",
  )
  let (old, _) = old.mark_submission_unconfirmed(
    "old-start", "old delivery unconfirmed", false,
  )
  let current = with_initial_submission(
    { ..old, run: Starting(submission_id="new-start") },
    "new-start",
    "new prompt",
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r-new",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("new prompt"),
      submission_id=Some("new-start"),
    ),
    test_model().replace_conversation(current),
  )
  inspect(started.active().input_ledger.length(), content="1")
  inspect(started.active().input_ledger[0].submission_id, content="new-start")
  inspect(started.active().overlay.length(), content="1")
  assert_true(started.active().overlay[0].reconciliation is Retained)
}

///|
test "only a causal gap-free snapshot may abandon a missing prior terminal" {
  let prior = { ..test_conversation(), run_durable_floor: Some(1) }
    .append_run_tail_notice(Assistant(is_danger=true), "old notice", Retained)
    .prepare_tail_notices_for_successor(2)
  let old_cut = prior
    .freeze_run_tail_notices_from_snapshot([], 1)
    .abandon_missing_prior_terminals(1, 0)
  assert_true(old_cut.overlay[0].anchor is PriorTerminalTail(..))
  let causal = old_cut
    .freeze_run_tail_notices_from_snapshot([], 2)
    .abandon_missing_prior_terminals(2, 0)
  assert_true(causal.overlay[0].anchor is AfterMessages(0))
}

///|
test "send waits while the durable transcript frontier is reloading" {
  let dispatch = test_dispatch()
  let conv = {
    ..running_conversation(),
    task: "do not send yet",
    sync: test_reloading([]),
  }
  let model = running_model().replace_conversation(conv)
  let (_, next) = update(dispatch, Send, model)
  inspect(next.active().task, content="do not send yet")
  inspect(next.active().input_ledger.length(), content="0")
}

///|
test "runs settled keeps exact steer ownership without notice growth" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["lost"]),
  )
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, once) = update_dev(dispatch, RunsSettled(live=[], frontier~), model)
  inspect(once.active().input_ledger.length(), content="1")
  assert_true(once.active().input_ledger[0].state is Unconfirmed)
  inspect(once.active().overlay.length(), content="1")
  assert_true(
    once.active().overlay[0].reconciliation is Submission("test-steer-0"),
  )
  let (_, twice) = update_dev(dispatch, RunsSettled(live=[], frontier~), once)
  inspect(twice.active().input_ledger.length(), content="1")
  inspect(twice.active().overlay.length(), content="1")
}

///|
test "a trailing applied receipt settles after an empty runs snapshot" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["late applied"]),
  )
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier~),
    model,
  )
  let (_, applied) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerApplied(content="late applied", submission_id=Some("test-steer-0")),
      session=None,
    ),
    settled,
  )
  inspect(applied.active().input_ledger.length(), content="0")
  inspect(applied.active().overlay.length(), content="0")
}

///|
test "a trailing dropped receipt restores input after an empty runs snapshot" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["late dropped"]),
  )
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier~),
    model,
  )
  let (_, dropped) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerDropped(content="late dropped", submission_id=Some("test-steer-0")),
      session=None,
    ),
    settled,
  )
  inspect(dropped.active().input_ledger.length(), content="0")
  inspect(dropped.active().task, content="late dropped")
  inspect(dropped.active().overlay.length(), content="1")
  assert_true(dropped.active().overlay[0].content.contains("late dropped"))
}

///|
test "a successor step cannot retire an older steer before its RPC rejection" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["late rejection"]),
  )
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier~),
    model,
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
      task=Some("foreign next run"),
      submission_id=None,
    ),
    settled,
  )
  let (_, stepped) = update_dev(
    dispatch,
    Engine(Some("r8"), AgentStep(Some(1)), session=None),
    started,
  )
  inspect(stepped.active().input_ledger.length(), content="1")
  let (_, rejected) = update_dev(
    dispatch,
    SteerRejected(
      session="desktop-test",
      submission_id="test-steer-0",
      text="late rejection",
      run_id="r7",
    ),
    stepped,
  )
  assert_true(rejected.active().run is Open(run_id="r8", ..))
  inspect(rejected.active().input_ledger.length(), content="0")
  inspect(rejected.active().task, content="late rejection")
}

///|
test "a runs snapshot cannot retire a steer submitted after its frontier" {
  let dispatch = test_dispatch()
  let model = running_model()
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, drafted) = update(dispatch, TaskChanged("post-snapshot steer"), model)
  let (_, steered) = update(dispatch, Send, drafted)
  guard steered.active().input_ledger is [pending] else {
    fail("expected one steer awaiting its exact receipt")
  }
  let submission_id = pending.submission_id
  assert_true(pending.state is Awaiting)
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier~),
    steered,
  )
  assert_true(settled.active().run is NoRun(ended=None))
  guard settled.active().input_ledger is [still_pending] else {
    fail("the older runs reply retired a newer steer")
  }
  assert_eq(still_pending.submission_id, submission_id)
  assert_true(still_pending.state is Awaiting)
  let (_, r2_started) = update_dev(
    dispatch,
    Started(
      run_id="r8",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("foreign next run"),
      submission_id=None,
    ),
    settled,
  )
  let (_, after_r2) = update_dev(
    dispatch,
    Finished(run_id="r8", status="finished", answer=None, durable_sequence=None),
    r2_started,
  )
  guard after_r2.active().input_ledger is [still_r1] else {
    fail("the successor finish consumed an older run's steer")
  }
  assert_eq(still_r1.submission_id, submission_id)
  assert_true(still_r1.state is Awaiting)
  inspect(after_r2.active().overlay.length(), content="0")
  // With no transcript, draft, overlay, or live run, exact ownership is the
  // only reason this conversation survives a switch.
  let other = {
    ..empty_conversation(@interop.ChannelId::Local, "desktop-other"),
    messages: [{ kind: User, content: "other conversation", ts: None }],
  }
  let (_, switched) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-other"),
    after_r2.replace_conversation(other),
  )
  guard switched.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(retained) else {
    fail("switching conversations pruned exact steer ownership")
  }
  assert_true(retained.has_begun())
  let (_, rejected) = update_dev(
    dispatch,
    SteerRejected(
      session="desktop-test",
      submission_id~,
      text="post-snapshot steer",
      run_id="r7",
    ),
    switched,
  )
  guard rejected.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(restored) else {
    fail("late rejection lost its conversation")
  }
  inspect(restored.input_ledger.length(), content="0")
  inspect(restored.task, content="post-snapshot steer")
}

///|
test "runs settlement releases after a causal cut and keeps exact receipt" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      watermark: 2,
      last_terminal_sequence: 2,
      run_durable_floor: Some(2),
      sync: test_reloading([]),
    },
    ["captured steer"],
  )
  let model = {
    ..running_model().replace_conversation(conv),
    transcript_request_generation: 1,
  }
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, snapshot_first) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[],
      watermark=3,
      event_boundaries=[(3, true, 0)],
      generation=1,
    ),
    model,
  )
  assert_true(snapshot_first.active().sync is Synced)
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier~),
    snapshot_first,
  )
  assert_true(settled.active().sync is Reloading(generation=2, ..))
  assert_true(settled.active().has_unresolved_run_tail_notice())
  let (_, reconciled) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[],
      watermark=3,
      event_boundaries=[(3, true, 0)],
      generation=2,
    ),
    settled,
  )
  assert_true(reconciled.active().sync is Synced)
  assert_true(reconciled.active().overlay[0].anchor is AfterMessages(0))
  assert_false(reconciled.active().has_unresolved_run_tail_notice())
  inspect(reconciled.active().input_ledger.length(), content="1")
  let (_, drafted) = update(dispatch, TaskChanged("next prompt"), reconciled)
  let (_, sent) = update(dispatch, Send, drafted)
  assert_true(sent.active().run is Starting(..))
  let (_, received) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerApplied(content="captured steer", submission_id=Some("test-steer-0")),
      session=None,
    ),
    sent,
  )
  assert_false(received.active().has_unresolved_run_tail_notice())
  inspect(received.active().overlay.length(), content="0")
  inspect(received.active().input_ledger.length(), content="1")
}

///|
test "a late normal Finished upgrades a runs-settled uncertain steer" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      watermark: 1,
      last_terminal_sequence: 1,
      run_durable_floor: Some(1),
    },
    ["captured steer"],
  )
  let model = running_model().replace_conversation(conv)
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier~),
    model,
  )
  assert_true(
    settled.active().overlay[0].anchor is SnapshotCut(snapshot_generation=1),
  )
  let finish : DeviceMsg = Finished(
    run_id="r7",
    status="finished",
    answer=None,
    durable_sequence=None,
  )
  let (_, finished) = update_dev(dispatch, finish, settled)
  assert_true(
    finished.active().overlay[0].anchor
    is PriorTerminalTail(floor=1, snapshot_generation=2),
  )
  let (_, duplicate) = update_dev(dispatch, finish, finished)
  assert_true(
    duplicate.active().overlay[0].anchor
    is PriorTerminalTail(floor=1, snapshot_generation=2),
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
    duplicate,
  )
  assert_true(old_cut.active().sync is Reloading(generation=2, ..))
  assert_true(old_cut.active().overlay[0].anchor is PriorTerminalTail(..))
  let (_, causal) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[{ kind: Assistant(is_danger=false), content: "answer", ts: None }],
      watermark=2,
      event_boundaries=[(1, true, 0), (2, true, 1)],
      generation=2,
    ),
    old_cut,
  )
  assert_true(causal.active().overlay[0].anchor is AfterMessages(1))
  assert_false(causal.active().has_unresolved_run_tail_notice())
  let (_, after_duplicate) = update_dev(dispatch, finish, causal)
  assert_true(after_duplicate.active().overlay[0].anchor is AfterMessages(1))
  assert_false(after_duplicate.active().has_unresolved_run_tail_notice())
}

///|
test "a late failed Finished preserves a runs-settled snapshot cut" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(running_conversation(), ["captured steer"])
  let model = running_model().replace_conversation(conv)
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier~),
    model,
  )
  let finish : DeviceMsg = Finished(
    run_id="r7",
    status="failed",
    answer=None,
    durable_sequence=None,
  )
  let (_, finished) = update_dev(dispatch, finish, settled)
  assert_true(
    finished.active().overlay[0].anchor is SnapshotCut(snapshot_generation=1),
  )
  assert_true(finished.active().has_unresolved_run_tail_notice())
  let (_, finalized) = update_dev(
    dispatch,
    DurableBoundary(run_id="r7", session="desktop-test", sequence=1),
    finished,
  )
  assert_true(finalized.active().overlay[0].anchor is DurableTail(1))
  let (_, duplicate) = update_dev(dispatch, finish, finalized)
  assert_true(duplicate.active().overlay[0].anchor is DurableTail(1))
  assert_true(duplicate.active().has_unresolved_run_tail_notice())
}

///|
test "runs settlement follows an older in-flight transcript cut" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    { ..running_conversation(), sync: test_reloading([]) },
    ["captured steer"],
  )
  let model = {
    ..running_model().replace_conversation(conv),
    transcript_request_generation: 1,
  }
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier~),
    model,
  )
  assert_true(
    settled.active().sync
    is Reloading(generation=1, reload_after_current=true, ..),
  )
  let (_, first_cut) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[],
      watermark=1,
      event_boundaries=[(1, true, 0)],
      generation=1,
    ),
    settled,
  )
  assert_true(first_cut.active().sync is Reloading(generation=2, ..))
}

///|
test "duplicate abnormal Finished keeps an initial prompt on one causal cut" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    running_conversation(),
    "prompt-id",
    "recover this prompt",
  ).bind_initial_submission_to_run("prompt-id", "r7")
  let finish : DeviceMsg = Finished(
    run_id="r7",
    status="failed",
    answer=None,
    durable_sequence=None,
  )
  let (_, once) = update_dev(
    dispatch,
    finish,
    running_model().replace_conversation(conv),
  )
  guard once.active().overlay is [first_notice] else {
    fail("the failed run should leave one recoverable prompt notice")
  }
  assert_true(first_notice.anchor is SnapshotCut(snapshot_generation=1))
  assert_true(once.active().sync is Reloading(generation=1, ..))
  let (_, twice) = update_dev(dispatch, finish, once)
  guard twice.active().overlay is [duplicate_notice] else {
    fail("duplicate Finished must not grow the prompt notice set")
  }
  assert_true(duplicate_notice.anchor is SnapshotCut(snapshot_generation=1))
  assert_true(twice.active().sync is Reloading(generation=1, ..))
  let (_, reconciled) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[],
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    twice,
  )
  assert_true(reconciled.active().sync is Synced)
  assert_true(reconciled.active().overlay[0].anchor is AfterMessages(0))
  assert_false(reconciled.active().has_unresolved_run_tail_notice())
  inspect(reconciled.active().input_ledger.length(), content="1")
  assert_true(reconciled.active().input_ledger[0].state is Unconfirmed)
}

///|
test "runs settlement causally freezes bound initial prompts from open and idle frontiers" {
  let dispatch = test_dispatch()
  let open_conv = with_initial_submission(
    running_conversation(),
    "open-prompt",
    "prompt from the open run",
  ).bind_initial_submission_to_run("open-prompt", "r7")
  let open_model = running_model().replace_conversation(open_conv)
  let (_, open_settled) = update_dev(
    dispatch,
    RunsSettled(
      live=[],
      frontier=open_model.run_snapshot_frontier(@interop.ChannelId::Local),
    ),
    open_model,
  )
  assert_true(open_settled.active().run is NoRun(ended=None))
  assert_true(open_settled.active().input_ledger[0].state is Unconfirmed)
  assert_true(
    open_settled.active().overlay[0].anchor
    is SnapshotCut(snapshot_generation=1),
  )
  assert_true(open_settled.active().sync is Reloading(generation=1, ..))
  let (_, open_frozen) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[{ kind: User, content: "open-run durable tail", ts: None }],
      watermark=1,
      event_boundaries=[(1, false, 1)],
      generation=1,
    ),
    open_settled,
  )
  assert_true(open_frozen.active().overlay[0].anchor is AfterMessages(1))
  assert_false(open_frozen.active().has_unresolved_run_tail_notice())
  inspect(open_frozen.active().input_ledger.length(), content="1")

  let idle_bound = with_initial_submission(
    { ..test_conversation(), run: NoRun(ended=None), last_run_id: Some("r7") },
    "idle-prompt",
    "prompt from the idle run",
  ).bind_initial_submission_to_run("idle-prompt", "r7")
  let (idle_conv, marked) = idle_bound.mark_submission_unconfirmed(
    "idle-prompt", "existing uncertain prompt notice", false,
  )
  assert_true(marked)
  let idle_model = test_model().replace_conversation(idle_conv)
  let (_, idle_settled) = update_dev(
    dispatch,
    RunsSettled(
      live=[],
      frontier=idle_model.run_snapshot_frontier(@interop.ChannelId::Local),
    ),
    idle_model,
  )
  assert_true(idle_settled.active().input_ledger[0].state is Unconfirmed)
  assert_true(
    idle_settled.active().overlay[0].anchor
    is SnapshotCut(snapshot_generation=1),
  )
  assert_true(idle_settled.active().sync is Reloading(generation=1, ..))
  let (_, idle_frozen) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[
        {
          kind: Assistant(is_danger=false),
          content: "idle-run durable tail",
          ts: None,
        },
      ],
      watermark=1,
      event_boundaries=[(1, false, 1)],
      generation=1,
    ),
    idle_settled,
  )
  assert_true(idle_frozen.active().overlay[0].anchor is AfterMessages(1))
  assert_false(idle_frozen.active().has_unresolved_run_tail_notice())
  inspect(idle_frozen.active().input_ledger.length(), content="1")
}

///|
test "an initial warning freezes between a snapshot and its buffered successor" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    running_conversation(),
    "prompt-id",
    "prompt awaiting proof",
  ).bind_initial_submission_to_run("prompt-id", "r7")
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="failed", answer=None, durable_sequence=None),
    running_model().replace_conversation(conv),
  )
  let (_, buffered) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.User({ content: "buffered W+1" }),
    ),
    finished,
  )
  guard buffered.active().sync is Reloading(buffered=commits, ..) else {
    fail("the post-cut commit should wait behind the snapshot")
  }
  inspect(commits.length(), content="1")
  let (_, reconciled) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[{ kind: User, content: "snapshot W", ts: None }],
      watermark=1,
      event_boundaries=[(1, false, 1)],
      generation=1,
    ),
    buffered,
  )
  assert_true(reconciled.active().sync is Synced)
  assert_true(reconciled.active().overlay[0].anchor is AfterMessages(1))
  inspect(reconciled.active().watermark, content="2")
  let visible = reconciled.active().visible_items()
  inspect(visible.length(), content="3")
  inspect(visible[0].content, content="snapshot W")
  assert_true(visible[1].content.contains("prompt awaiting proof"))
  inspect(visible[2].content, content="buffered W+1")
}

///|
test "foreign Started reanchors a reconnected initial before retiring its ownership" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    running_conversation(),
    "old-prompt",
    "old prompt",
  ).bind_initial_submission_to_run("old-prompt", "r7")
  let (_, bridged) = update_dev(
    dispatch,
    BridgeReady,
    running_model().replace_conversation(conv),
  )
  assert_true(bridged.active().input_ledger[0].state is Unconfirmed)
  assert_true(
    bridged.active().overlay[0].anchor is SnapshotCut(snapshot_generation=1),
  )
  assert_true(bridged.active().sync is Reloading(generation=1, ..))
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r8",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("foreign prompt"),
      submission_id=Some("foreign-prompt"),
    ),
    bridged,
  )
  inspect(started.active().input_ledger.length(), content="0")
  guard started.active().overlay is [retired_notice] else {
    fail("the old prompt warning should survive as a retained notice")
  }
  assert_true(retired_notice.reconciliation is Retained)
  assert_true(retired_notice.anchor is SnapshotCut(snapshot_generation=2))
  assert_true(
    started.active().sync
    is Reloading(generation=1, reload_after_current=true, ..),
  )
  let (_, old_cut) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[{ kind: User, content: "old durable prompt", ts: None }],
      watermark=1,
      event_boundaries=[(1, false, 1)],
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
      items=[{ kind: User, content: "old durable prompt", ts: None }],
      watermark=1,
      event_boundaries=[(1, false, 1)],
      generation=2,
    ),
    old_cut,
  )
  assert_true(causal.active().sync is Synced)
  assert_true(causal.active().overlay[0].anchor is AfterMessages(1))
  let visible = causal.active().visible_items()
  inspect(visible.length(), content="2")
  inspect(visible[0].content, content="old durable prompt")
  assert_true(visible[1].content.contains("old prompt"))
}

///|
test "an exact zero abnormal EOF releases a fresh prompt for another send" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="fresh-prompt") },
    "fresh-prompt",
    "prompt before setup failure",
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r-fresh",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("prompt before setup failure"),
      submission_id=Some("fresh-prompt"),
    ),
    test_model().replace_conversation(conv),
  )
  assert_true(started.active().sync is Reloading(generation=1, ..))
  let (_, failed) = update_dev(
    dispatch,
    Finished(
      run_id="r-fresh",
      status="failed",
      answer=None,
      durable_sequence=Some(0),
    ),
    started,
  )
  assert_true(failed.active().sync is Synced)
  assert_true(failed.active().run is NoRun(ended=Some(RunFinished(RunFailed))))
  inspect(failed.active().input_ledger.length(), content="0")
  inspect(failed.active().task, content="prompt before setup failure")
  assert_true(failed.active().overlay[0].anchor is AfterMessages(0))
  assert_true(failed.active().overlay[0].reconciliation is Retained)
  assert_true(
    failed.active().visible_items()[0].content.contains(
      "restored for resubmission",
    ),
  )
  assert_false(failed.active().has_unresolved_run_tail_notice())
  let (_, retried) = update(dispatch, Send, failed)
  assert_true(retried.active().run is Starting(..))
  inspect(retried.active().task, content="")
  inspect(retried.active().input_ledger.length(), content="1")
}

///|
test "late start responses cannot reopen an exact-zero recovery read" {
  let dispatch = test_dispatch()
  let started = fresh_started_model(
    "late-response-prompt", "r-late-response", "restore before the response",
  )
  let (_, recovered) = update_dev(
    dispatch,
    Finished(
      run_id="r-late-response",
      status="failed",
      answer=None,
      durable_sequence=Some(0),
    ),
    started,
  )
  assert_true(recovered.active().sync is Synced)
  inspect(recovered.active().input_ledger.length(), content="0")
  let generation = recovered.transcript_request_generation
  let (_, accepted) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="late-response-prompt",
      run_id="r-late-response",
      status="accepted",
      exit_code=0,
    ),
    recovered,
  )
  assert_true(accepted.active().sync is Synced)
  assert_eq(accepted.transcript_request_generation, generation)
  inspect(accepted.active().task, content="restore before the response")
  inspect(accepted.active().input_ledger.length(), content="0")
  let (_, failed) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="late-response-prompt",
      run_id="r-late-response",
      status="failed",
      exit_code=1,
    ),
    recovered,
  )
  assert_true(failed.active().sync is Synced)
  assert_eq(failed.transcript_request_generation, generation)
  inspect(failed.active().task, content="restore before the response")
  inspect(failed.active().input_ledger.length(), content="0")
}

///|
test "BridgeReady does not probe a record disproved by exact-zero EOF" {
  let dispatch = test_dispatch()
  let started = fresh_started_model(
    "reconnect-zero-prompt", "r-reconnect-zero", "restore across reconnect",
  )
  let (_, recovered) = update_dev(
    dispatch,
    Finished(
      run_id="r-reconnect-zero",
      status="failed",
      answer=None,
      durable_sequence=Some(0),
    ),
    started,
  )
  let generation = recovered.transcript_request_generation
  let (_, reconnected) = update_dev(dispatch, BridgeReady, recovered)
  assert_true(reconnected.active().sync is Synced)
  assert_eq(reconnected.transcript_request_generation, generation)
  inspect(reconnected.active().task, content="restore across reconnect")
  inspect(reconnected.active().input_ledger.length(), content="0")
  assert_true(reconnected.active().overlay[0].reconciliation is Retained)
}

///|
test "a late exact-zero durable boundary recovers from active and failed reloads" {
  let dispatch = test_dispatch()
  let reloading_started = fresh_started_model(
    "reloading-zero-prompt", "r-reloading-zero", "restore from reloading",
  )
  let (_, reloading) = update_dev(
    dispatch,
    Finished(
      run_id="r-reloading-zero",
      status="failed",
      answer=None,
      durable_sequence=None,
    ),
    reloading_started,
  )
  assert_true(reloading.active().sync is Reloading(..))
  let (_, recovered_reloading) = update_dev(
    dispatch,
    DurableBoundary(
      run_id="r-reloading-zero",
      session="desktop-test",
      sequence=0,
    ),
    reloading,
  )
  assert_true(recovered_reloading.active().sync is Synced)
  inspect(recovered_reloading.active().task, content="restore from reloading")
  inspect(recovered_reloading.active().input_ledger.length(), content="0")
  assert_true(
    recovered_reloading.active().overlay[0].reconciliation is Retained,
  )

  let failed_started = fresh_started_model(
    "failed-zero-prompt", "r-failed-zero", "restore from failed reload",
  )
  let (_, waiting) = update_dev(
    dispatch,
    Finished(
      run_id="r-failed-zero",
      status="failed",
      answer=None,
      durable_sequence=None,
    ),
    failed_started,
  )
  let failed_reload = waiting.replace_conversation({
    ..waiting.active(),
    sync: ReloadFailed(generation=1, buffered=[]),
  })
  let (_, recovered_failed) = update_dev(
    dispatch,
    DurableBoundary(run_id="r-failed-zero", session="desktop-test", sequence=0),
    failed_reload,
  )
  assert_true(recovered_failed.active().sync is Synced)
  inspect(recovered_failed.active().task, content="restore from failed reload")
  inspect(recovered_failed.active().input_ledger.length(), content="0")
  assert_true(recovered_failed.active().overlay[0].reconciliation is Retained)
}

///|
test "exact-zero recovery refuses buffered or nonzero durable frontiers" {
  let dispatch = test_dispatch()
  let buffered_started = fresh_started_model(
    "buffered-zero-prompt", "r-buffered-zero", "keep buffered ownership",
  )
  let (_, waiting) = update_dev(
    dispatch,
    Finished(
      run_id="r-buffered-zero",
      status="failed",
      answer=None,
      durable_sequence=None,
    ),
    buffered_started,
  )
  let (_, buffered) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "durable prompt arrived" }),
    ),
    waiting,
  )
  let (_, zero_with_buffer) = update_dev(
    dispatch,
    DurableBoundary(
      run_id="r-buffered-zero",
      session="desktop-test",
      sequence=0,
    ),
    buffered,
  )
  guard zero_with_buffer.active().sync is Reloading(buffered=commits, ..) else {
    fail("a buffered commit must keep transcript reconciliation active")
  }
  inspect(commits.length(), content="1")
  inspect(zero_with_buffer.active().task, content="")
  inspect(zero_with_buffer.active().input_ledger.length(), content="1")
  assert_true(
    zero_with_buffer.active().overlay[0].reconciliation
    is Submission("buffered-zero-prompt"),
  )

  let nonzero_started = fresh_started_model(
    "nonzero-prompt", "r-nonzero", "keep nonzero ownership",
  )
  let (_, nonzero) = update_dev(
    dispatch,
    Finished(
      run_id="r-nonzero",
      status="failed",
      answer=None,
      durable_sequence=Some(1),
    ),
    nonzero_started,
  )
  assert_true(nonzero.active().sync is Reloading(..))
  inspect(nonzero.active().task, content="")
  inspect(nonzero.active().input_ledger.length(), content="1")
  assert_true(nonzero.active().overlay[0].anchor is DurableTail(1))
  assert_true(
    nonzero.active().overlay[0].reconciliation is Submission("nonzero-prompt"),
  )
}
