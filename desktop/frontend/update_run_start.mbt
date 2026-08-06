// Run start ownership and response transitions.

///|
test "runs resync names exact Starting Open and Idle owners" {
  let starting = {
    ..empty_conversation(@interop.ChannelId::Local, "starting-session"),
    run: Starting(submission_id="submission-starting"),
  }
  let open = {
    ..empty_conversation(@interop.ChannelId::Local, "open-session"),
    run: Open(run_id="run-open", stage=Opened),
  }
  let idle = {
    ..empty_conversation(@interop.ChannelId::Local, "idle-session"),
    last_run_id: Some("run-idle"),
  }
  let empty = empty_conversation(@interop.ChannelId::Local, "never-started")
  let model = test_model()
    .replace_conversation(starting)
    .replace_conversation(open)
    .replace_conversation(idle)
    .replace_conversation(empty)
  let json = runs_payload(
    model.run_snapshot_frontier(@interop.ChannelId::Local),
  ).to_json()
  guard json is { "known": Array(known), .. } else {
    fail("runs payload omitted known selectors")
  }
  inspect(known.length(), content="3")
  assert_true(
    known.contains({
      "session": "starting-session",
      "submission_id": "submission-starting",
    }),
  )
  assert_true(
    known.contains({ "session": "open-session", "run_id": "run-open" }),
  )
  assert_true(
    known.contains({ "session": "idle-session", "run_id": "run-idle" }),
  )
}

///|
fn with_pending_steers(
  conv : Conversation,
  texts : Array[String],
  run_id? : String = "r7",
) -> Conversation {
  let mut next = conv
  for index, text in texts {
    next = next.enqueue_input(
      SteerInput,
      "test-steer-" + index.to_string(),
      Some(run_id),
      text,
      text,
      [],
    )
  }
  next
}

///|
fn with_initial_submission(
  conv : Conversation,
  id : String,
  text : String,
) -> Conversation {
  conv.enqueue_input(InitialPrompt, id, None, text, text, [])
}

///|
/// Drive one new-chat prompt through its id-bearing Started boundary. The
/// resulting causal transcript read is deliberately left in flight.
fn fresh_started_model(
  submission_id : String,
  run_id : String,
  prompt : String,
) -> Model {
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id~) },
    submission_id,
    prompt,
  )
  let (_, started) = update_dev(
    test_dispatch(),
    Started(
      run_id~,
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some(prompt),
      submission_id=Some(submission_id),
    ),
    test_model().replace_conversation(conv),
  )
  started
}

///|
/// Run A has finished but its exact start response is still in flight; run B
/// has already been sent and announced on the same conversation.
fn second_run_started_before_first_response() -> (Model, String)? {
  let dispatch = test_dispatch()
  let first = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="first-start") },
    "first-start",
    "first prompt",
  )
  let (_, first_started) = update_dev(
    dispatch,
    Started(
      run_id="r-first",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("first prompt"),
      submission_id=Some("first-start"),
    ),
    test_model().replace_conversation(first),
  )
  let (_, first_finished) = update_dev(
    dispatch,
    Finished(
      run_id="r-first",
      status="finished",
      answer=None,
      durable_sequence=None,
    ),
    first_started,
  )
  let (_, reconciled) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[],
      watermark=1,
      event_boundaries=[(1, true, 0)],
      generation=1,
    ),
    first_finished,
  )
  let (_, post_finish) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[],
      watermark=1,
      event_boundaries=[(1, true, 0)],
      generation=2,
    ),
    reconciled,
  )
  let (_, drafted) = update(dispatch, TaskChanged("second prompt"), post_finish)
  let (_, sending) = update(dispatch, Send, drafted)
  guard sending.active().run is Starting(submission_id=second_submission) else {
    return None
  }
  let (_, second_started) = update_dev(
    dispatch,
    Started(
      run_id="r-second",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("second prompt"),
      submission_id=Some(second_submission),
    ),
    sending,
  )
  Some((second_started, second_submission))
}

///|
/// Run A ended with one steer receipt still in flight, then run B started.
fn second_run_started_before_first_steer_receipt() -> Model? {
  let dispatch = test_dispatch()
  let first = with_pending_steers(running_conversation(), ["late steer"])
  let (_, first_finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=None, durable_sequence=None),
    running_model().replace_conversation(first),
  )
  // A second local run is admitted only after the prior durable terminal has
  // reconciled. The old steer receipt may still trail that boundary.
  let (_, reconciled) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[],
      watermark=1,
      event_boundaries=[(1, true, 0)],
      generation=1,
    ),
    first_finished,
  )
  let (_, drafted) = update(dispatch, TaskChanged("second prompt"), reconciled)
  let (_, sending) = update(dispatch, Send, drafted)
  guard sending.active().run is Starting(submission_id=second_submission) else {
    return None
  }
  let (_, second_started) = update_dev(
    dispatch,
    Started(
      run_id="r8",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("second prompt"),
      submission_id=Some(second_submission),
    ),
    sending,
  )
  Some(second_started)
}

///|
test "session loaded swaps the active conversation onto the stored session" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    usage_tokens: 42,
    watcher_status: "running",
    streaming_response: "leftover",
    messages: [{ kind: User, content: "old chat", ts: None }],
  })
  let (_, loading) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-stored"),
    model,
  )
  let items : Array[@transcript.TranscriptItem] = [
    { kind: User, content: "stored question", ts: None },
    { kind: Assistant(is_danger=false), content: "stored answer", ts: None },
  ]
  let (_, once) = update_dev(
    dispatch,
    SessionLoaded(
      session="desktop-stored",
      items~,
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    loading,
  )
  let (_, twice) = update_dev(
    dispatch,
    SessionLoaded(
      session="desktop-stored",
      items~,
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    loading,
  )
  inspect(once.active_session, content="desktop-stored")
  inspect(once.active().messages.length(), content="2")
  inspect(once.active().messages[0].content, content="stored question")
  inspect(once.active().streaming_response, content="")
  inspect(once.active().usage_tokens, content="0")
  inspect(once.active().watcher_status, content="")
  assert_true(once.active().cwd is None)
  assert_true(once.display_status() is Ready)
  inspect(twice.active().messages.length(), content="2")
}

///|
test "session loaded adopts the store transcript and keeps live run state" {
  let dispatch = test_dispatch()
  let model = running_model()
  let items : Array[@transcript.TranscriptItem] = [
    { kind: User, content: "stored", ts: None },
  ]
  // The active conversation runs; loading some other stored session is fine.
  let (_, loading_other) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-stored"),
    model,
  )
  let (_, other) = update_dev(
    dispatch,
    SessionLoaded(
      session="desktop-stored",
      items~,
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    loading_other,
  )
  inspect(other.active_session, content="desktop-stored")
  guard other.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(live) else {
    fail("expected the running conversation to survive")
  }
  inspect(live.is_running(), content="true")
  // A load reply for the running conversation itself adopts the store's
  // transcript — the source of truth for completed items — while the live
  // run state (phase, streaming buffers) rides across untouched.
  let streaming = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "mid-step",
  })
  let loading_same = {
    ..streaming.replace_conversation({
      ..streaming.active(),
      sync: test_reloading([]),
    }),
    loading_conversation: Some({ channel: Local, session: "desktop-test" }),
  }
  let (_, same) = update_dev(
    dispatch,
    SessionLoaded(
      session="desktop-test",
      items~,
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    loading_same,
  )
  inspect(same.active().messages.length(), content="1")
  inspect(same.active().messages[0].content, content="stored")
  inspect(same.active().is_running(), content="true")
  inspect(same.active().streaming_response, content="mid-step")
}

///|
test "started routes by session and records the host's workspace" {
  let dispatch = test_dispatch()
  let cwd = @interop.ChannelId::Local.test_resource(
    "/home/u/Documents/OpenSeek/desktop-test",
  )
  let (_, next) = update_dev(
    dispatch,
    Started(
      run_id="r7",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=Some(cwd),
      session_root=None,
      task=None,
      submission_id=None,
    ),
    test_model(),
  )
  assert_eq(next.active().cwd, Some(cwd))
  inspect(next.active().is_running(), content="true")
  guard next.active().run is Open(run_id="r7", ..) else {
    fail("expected the run id to be recorded")
  }
  // A run this client did not send: the store gained its prompt, so the
  // on-screen conversation re-reads it in the background, buffering commits
  // until the snapshot lands. The user-load marker stays free.
  assert_true(next.active().sync is Reloading(..))
  assert_true(next.loading_conversation is None)
}

///|
test "started decoder preserves optional placement and submission id" {
  guard started_msg(@interop.ChannelId::Local, {
      run_id: "r7",
      task: None,
      submission_id: Some("submission-7"),
      engine: None,
      model: Some("deepseek-v4-pro"),
      max_steps: Some(1000),
      cwd: None,
      session: Some("desktop-test"),
      session_root: Some("/work/core/.openseek"),
    })
    is Some(Started(session_root~, submission_id~, ..)) else {
    fail("placement or submission id was lost while decoding Started")
  }
  assert_true(
    session_root is Some(resource) && resource.path == "/work/core/.openseek",
  )
  assert_eq(submission_id, Some("submission-7"))
}

///|
test "host path decoders reject relative placement and diagnostic paths" {
  let payload : @protocol.StartedPayload = {
    run_id: "r7",
    task: None,
    submission_id: None,
    engine: None,
    model: Some("deepseek-v4-pro"),
    max_steps: Some(1000),
    cwd: Some("relative/workspace"),
    session: Some("desktop-test"),
    session_root: None,
  }
  assert_true(started_msg(@interop.ChannelId::Local, payload) is None)
  assert_true(
    RecoveredRun::from_started(@interop.ChannelId::Local, payload) is None,
  )
  assert_true(
    diagnostics_msg(@interop.ChannelId::Local, {
      path: "relative/file.mbt",
      diagnostics: [],
    })
    is None,
  )
}

///|
test "started for an unknown session materializes its conversation" {
  let dispatch = test_dispatch()
  let (_, next) = update_dev(
    dispatch,
    Started(
      run_id="r7",
      session="desktop-ghost",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("fix the flaky test"),
      submission_id=None,
    ),
    test_model(),
  )
  // Another client's run is now trackable here: cancellable, steerable,
  // and its events route to a real conversation.
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-ghost")
    is Some(ghost) else {
    fail("expected the foreign run's conversation to materialize")
  }
  inspect(ghost.is_running(), content="true")
  guard ghost.run is Open(run_id="r7", ..) else {
    fail("expected the run id to be recorded")
  }
  // No bubble is synthesized from the pushed task — the durable transcript's
  // only sources are snapshots and commits, and the prompt's own commit (or
  // the read when this conversation is opened) brings it.
  inspect(ghost.messages.length(), content="0")
  inspect(ghost.overlay.length(), content="0")
  // Focus stays where the user is.
  inspect(next.active_session, content="desktop-test")
  inspect(next.active().is_running(), content="false")
}

///|
test "a distinct started id replaces a stale open run as foreign" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      run: Open(run_id="r-old", stage=AtStep(Some(3))),
      streaming_response: "old answer fragment",
    },
    ["old steer"],
    run_id="r-old",
  )
  let model = running_model().replace_conversation(conv)
  let (_, next) = update_dev(
    dispatch,
    Started(
      run_id="r-new",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("new foreign prompt"),
      submission_id=None,
    ),
    model,
  )
  guard next.active().run is Open(run_id="r-new", stage=Opened) else {
    fail("expected the new run to replace the stale id")
  }
  inspect(next.active().streaming_response, content="")
  inspect(next.active().pending_steers().length(), content="0")
  inspect(next.active().overlay.length(), content="1")
  assert_true(next.active().overlay[0].content.contains("old steer"))
  guard next.active().sync is Reloading(generation=1, attempt=1, ..) else {
    fail("a foreign replacement did not refresh the transcript")
  }
}

///|
test "a repeated started id is idempotent" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      run: Open(run_id="r7", stage=AtStep(Some(4))),
      streaming_response: "current fragment",
    },
    ["current steer"],
  )
  let model = running_model().replace_conversation(conv)
  let (_, next) = update_dev(
    dispatch,
    Started(
      run_id="r7",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=None,
      submission_id=None,
    ),
    model,
  )
  guard next.active().run is Open(run_id="r7", stage=AtStep(Some(4))) else {
    fail("a repeated start reset the live run stage")
  }
  inspect(next.active().streaming_response, content="current fragment")
  inspect(next.active().pending_steers().length(), content="1")
  inspect(next.active().pending_steers()[0], content="current steer")
  inspect(next.transcript_request_generation, content="0")
  assert_true(next.active().sync is Synced)
}

///|
test "a start failure cannot close a run opened by a winning push" {
  let dispatch = test_dispatch()
  let starting_conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="mine") },
    "mine",
    "my competing prompt",
  )
  let starting = test_model().replace_conversation(starting_conv)
  let (_, opened) = update_dev(
    dispatch,
    Started(
      run_id="r-foreign",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("the other client's prompt"),
      submission_id=Some("theirs"),
    ),
    starting,
  )
  let opened = opened.replace_conversation(
    with_pending_steers(
      { ..opened.active(), streaming_response: "foreign fragment" },
      ["steer for foreign run"],
      run_id="r-foreign",
    ),
  )
  let (_, failed) = update_dev(
    dispatch,
    StartRejected(
      session="desktop-test",
      submission_id="mine",
      message="start was rejected",
    ),
    opened,
  )
  guard failed.active().run is Open(run_id="r-foreign", stage=Opened) else {
    fail("the local failure closed the already-open run")
  }
  inspect(failed.active().streaming_response, content="foreign fragment")
  inspect(failed.active().pending_steers().length(), content="1")
  inspect(failed.active().pending_steers()[0], content="steer for foreign run")
  inspect(failed.active().task, content="my competing prompt")
  inspect(failed.active().overlay.length(), content="1")
  inspect(failed.active().overlay[0].content, content="start was rejected")
  guard failed.active().sync is Reloading(generation=1, ..) else {
    fail("the raced start failure did not catch up the transcript")
  }
}

///|
test "a start failure closes only a still-starting run" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    {
      ..test_conversation(),
      run: Starting(submission_id="prompt-id"),
      streaming_response: "partial",
    },
    "prompt-id",
    "prompt",
  )
  let model = test_model().replace_conversation(conv)
  let (_, failed) = update_dev(
    dispatch,
    StartRejected(
      session="desktop-test",
      submission_id="prompt-id",
      message="start failed",
    ),
    model,
  )
  assert_true(failed.active().run is NoRun(ended=Some(RunFailed)))
  inspect(failed.active().streaming_response, content="")
  inspect(failed.active().overlay.length(), content="1")
  inspect(failed.active().task, content="prompt")
  inspect(failed.transcript_request_generation, content="0")
}

///|
test "canonical User text never claims an unconfirmed start" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    test_conversation(),
    "prompt-id",
    "accepted prompt",
  )
  let model = test_model().replace_conversation({
    ..conv,
    run: Starting(submission_id="prompt-id"),
  })
  let (_, failed) = update_dev(
    dispatch,
    StartUndelivered(
      session="desktop-test",
      submission_id="prompt-id",
      message="response transport closed",
    ),
    model,
  )
  assert_true(failed.active().run is NoRun(ended=Some(RunFailed)))
  inspect(failed.active().overlay.length(), content="1")
  inspect(failed.active().input_ledger.length(), content="1")
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "accepted prompt" }),
    ),
    failed,
  )
  assert_true(committed.active().run is NoRun(ended=Some(RunFailed)))
  inspect(committed.active().overlay.length(), content="1")
  inspect(committed.active().input_ledger.length(), content="1")
  inspect(committed.active().messages.length(), content="1")
}

///|
test "a matching Started establishes the run without consuming its prompt" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="prompt-id") },
    "prompt-id",
    "accepted prompt",
  )
  let (_, failed) = update_dev(
    dispatch,
    StartUndelivered(
      session="desktop-test",
      submission_id="prompt-id",
      message="connection lost",
    ),
    test_model().replace_conversation(conv),
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r-recovered",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("accepted prompt"),
      submission_id=Some("prompt-id"),
    ),
    failed,
  )
  assert_true(started.active().run is Open(run_id="r-recovered", ..))
  inspect(started.active().overlay.length(), content="1")
  assert_true(started.active().overlay[0].content.contains("accepted prompt"))
  inspect(started.active().input_ledger.length(), content="1")
  inspect(started.active().input_ledger[0].submission_id, content="prompt-id")
  assert_true(started.active().input_ledger[0].state is Unconfirmed)
}

///|
test "an accepted start response opens the run without Started" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="prompt-id") },
    "prompt-id",
    "prompt",
  )
  let (_, responded) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="prompt-id",
      run_id="r-response",
      status="accepted",
      exit_code=0,
    ),
    test_model().replace_conversation(conv),
  )
  assert_true(responded.active().run is Open(run_id="r-response", ..))
  assert_true(responded.active().last_run_id is Some("r-response"))
  inspect(responded.active().input_ledger.length(), content="1")
  assert_true(responded.active().input_ledger[0].run_id is Some("r-response"))
  assert_true(responded.active().sync is Reloading(generation=1, ..))
  assert_true(responded.active().run_durable_floor is None)
  assert_true(responded.active().run_floor_generation is Some(1))
  let (_, drafted) = update(dispatch, TaskChanged("too early"), responded)
  let (_, gated) = update(dispatch, Send, drafted)
  inspect(gated.active().input_ledger.length(), content="1")
  inspect(gated.active().task, content="too early")
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r-response",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("prompt"),
      submission_id=Some("prompt-id"),
    ),
    gated,
  )
  // The delayed Started is idempotent with the response-first recovery: it
  // neither drops nor queues a second generation.
  assert_true(started.active().sync is Reloading(generation=1, ..))
  assert_true(started.active().run_floor_generation is Some(1))
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[
        { kind: User, content: "external prompt", ts: None },
        {
          kind: Assistant(is_danger=false),
          content: "external answer",
          ts: None,
        },
        { kind: User, content: "prompt", ts: None },
      ],
      watermark=4,
      event_boundaries=[
        (1, false, 1),
        (2, false, 2),
        (3, true, 2),
        (4, false, 3),
      ],
      generation=1,
    ),
    started,
  )
  assert_true(loaded.active().sync is Synced)
  assert_true(loaded.active().run_durable_floor is Some(3))
  assert_true(loaded.active().run_floor_generation is None)
  inspect(loaded.active().input_ledger.length(), content="1")
}

///|
test "accepted start remains recoverable when the engine fails before User append" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="prompt-id") },
    "prompt-id",
    "must not disappear",
  )
  let (_, accepted) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="prompt-id",
      run_id="r-failed",
      status="accepted",
      exit_code=0,
    ),
    test_model().replace_conversation(conv),
  )
  let (_, failed) = update_dev(
    dispatch,
    Finished(
      run_id="r-failed",
      status="failed",
      answer=None,
      durable_sequence=None,
    ),
    accepted,
  )
  inspect(failed.active().input_ledger.length(), content="1")
  assert_true(failed.active().input_ledger[0].state is Unconfirmed)
  assert_true(failed.active().overlay[0].content.contains("must not disappear"))
  let (_, external_snapshot) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[{ kind: User, content: "external writer only", ts: None }],
      watermark=1,
      event_boundaries=[(1, false, 1)],
      generation=1,
    ),
    failed,
  )
  // Unrelated durable text is not ownership proof for this exact prompt.
  inspect(external_snapshot.active().input_ledger.length(), content="1")
  assert_true(
    external_snapshot.active().overlay[0].content.contains("must not disappear"),
  )
}

///|
test "an old-host Started without an id is settled by the exact start response" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="prompt-id") },
    "prompt-id",
    "prompt",
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r-old-host",
      session="desktop-test",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("prompt"),
      submission_id=None,
    ),
    test_model().replace_conversation(conv),
  )
  assert_true(started.active().run is Open(run_id="r-old-host", ..))
  inspect(started.active().input_ledger.length(), content="1")
  inspect(started.active().overlay.length(), content="1")
  let (_, responded) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="prompt-id",
      run_id="r-old-host",
      status="accepted",
      exit_code=0,
    ),
    started,
  )
  assert_true(responded.active().run is Open(run_id="r-old-host", ..))
  inspect(responded.active().input_ledger.length(), content="1")
  assert_true(responded.active().input_ledger[0].run_id is Some("r-old-host"))
  inspect(responded.active().overlay.length(), content="1")
}

///|
test "a late accepted response settles run A without replacing open run B" {
  let dispatch = test_dispatch()
  guard second_run_started_before_first_response() is Some(result) else {
    fail("expected the second prompt to be starting")
  }
  let (second_started, second_submission) = result
  let (_, responded) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="first-start",
      run_id="r-first",
      status="accepted",
      exit_code=0,
    ),
    second_started,
  )
  assert_true(responded.active().run is Open(run_id="r-second", ..))
  assert_true(responded.active().last_run_id is Some("r-second"))
  inspect(responded.active().input_ledger.length(), content="1")
  inspect(
    responded.active().input_ledger[0].submission_id,
    content=second_submission,
  )
  assert_true(responded.active().input_ledger[0].state is Awaiting)
}

///|
test "a late failed response for durable run A cannot disturb open run B" {
  let dispatch = test_dispatch()
  guard second_run_started_before_first_response() is Some(result) else {
    fail("expected the second prompt to be starting")
  }
  let (second_started, second_submission) = result
  let (_, responded) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="first-start",
      run_id="r-first",
      status="failed",
      exit_code=1,
    ),
    second_started,
  )
  assert_true(responded.active().run is Open(run_id="r-second", ..))
  assert_true(responded.active().last_run_id is Some("r-second"))
  inspect(responded.active().input_ledger.length(), content="1")
  inspect(
    responded.active().input_ledger[0].submission_id,
    content=second_submission,
  )
  assert_true(responded.active().input_ledger[0].state is Awaiting)
  inspect(responded.active().overlay.length(), content="0")
}
