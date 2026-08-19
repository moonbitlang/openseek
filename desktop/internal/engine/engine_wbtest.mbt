///|
/// A consumer that dies mid-stream must not leave its open run's phase
/// `Running` forever — that state is unreachable by every close path and
/// reads as a turn that never ends. The failure is forced through the same
/// retirement an observed engine death gets.
#cfg(not(platform="windows"))
async test "a failed consumer closes its open run and retires the slot" {
  let manager = new_engine_manager("/bin/sh")
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    let (child_stdin, writer) = @process.write_to_process()
    let process = @process.spawn(
      group,
      "/bin/sh",
      ["-c", "sleep 30"],
      stdin=child_stdin,
      no_wait=true,
    )
    let engine = test_serve_engine(
      "s-consumer-died",
      writer,
      process,
      sink,
      phase=Running(
        run_id="r-consumer-died",
        cancel_requested=false,
        compact_queued=false,
      ),
    )
    let sessions : Map[String, SessionSlot] = Map([])
    let slot = slot_for(sessions, "s-consumer-died")
    slot.engine = Some(engine)
    manager.pump = Serving(sessions~)
    let messages : @async.Queue[StreamMessage] = Queue(
      kind=Blocking(EngineStreamQueueSize),
    )
    // The pump's only suspension is this queue's read; failing it stands in
    // for any error escaping the consumer.
    messages.close(error=EngineError("boom"))
    let stderr_task = group.spawn(no_wait=true, () => "")
    engine.run(manager, messages, stderr_task)

    // `run` returning is retirement: the run was closed as a failure naming
    // the consumer, the child was killed, and the slot is clear.
    assert_true(slot.engine is None)
    assert_true(engine.condemned)
    assert_true(engine.phase is Idle(..))
    let mut cause = ""
    let mut status = ""
    for event in emitted {
      match event {
        Error(payload) if payload.run_id == Some("r-consumer-died") =>
          cause = payload.message.unwrap_or("")
        Finished(payload) if payload.run_id == "r-consumer-died" =>
          status = payload.status
        _ => ()
      }
    }
    assert_true(cause.contains("the engine's event consumer failed"))
    assert_eq(status, "failed")
  })
}

///|
/// A failed stdin write condemns the handle and answers its senders, but
/// settles no lifecycle itself: the one EOF retirement stays the only
/// closer for engine death and reports the stashed cause.
#cfg(not(platform="windows"))
async test "a failed command leaves settlement to the EOF retirement" {
  let manager = new_engine_manager("/bin/sh")
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    let (child_stdin, writer) = @process.write_to_process()
    // A child that is already gone, so the first write hits a closed pipe.
    let process = @process.spawn(
      group,
      "/bin/sh",
      ["-c", "exit 0"],
      stdin=child_stdin,
      no_wait=true,
    )
    let engine = test_serve_engine(
      "s-write-failed",
      writer,
      process,
      sink,
      phase=Running(
        run_id="r-write-failed",
        cancel_requested=false,
        compact_queued=false,
      ),
    )
    let sessions : Map[String, SessionSlot] = Map([])
    let slot = slot_for(sessions, "s-write-failed")
    slot.engine = Some(engine)
    manager.pump = Serving(sessions~)
    engine.wait_process()
    let ack : @async.Queue[EngineError?] = Queue(kind=Blocking(1))
    assert_true(
      engine.submit("{}\n", failure_reason="failed to write the goal", ack~),
    )
    engine.write_commands()

    // The sender learned the exact failure, the handle is condemned with
    // the cause stashed — and nothing was settled: the phase still belongs
    // to the EOF retirement.
    guard ack.try_get() is Some(Some(EngineError(reason))) else {
      fail("expected the failed write to answer its sender")
    }
    assert_true(reason.has_prefix("failed to write the goal"))
    assert_true(engine.condemned)
    assert_true(engine.pending_failure is Some(_))
    assert_true(engine.phase is Running(..))
    assert_true(emitted.is_empty())

    // EOF retirement settles exactly once, naming the stashed cause.
    let messages : @async.Queue[StreamMessage] = Queue(
      kind=Blocking(EngineStreamQueueSize),
    )
    messages.put(StreamExited(0))
    let stderr_task = group.spawn(no_wait=true, () => "")
    engine.run(manager, messages, stderr_task)
    assert_true(slot.engine is None)
    assert_true(engine.phase is Idle(..))
    let mut finishes = 0
    let mut cause = ""
    for event in emitted {
      match event {
        Error(payload) if payload.run_id == Some("r-write-failed") =>
          cause = payload.message.unwrap_or("")
        Finished(payload) if payload.run_id == "r-write-failed" => {
          assert_eq(payload.status, "failed")
          finishes += 1
        }
        _ => ()
      }
    }
    assert_eq(finishes, 1)
    assert_true(cause.has_prefix("failed to write the goal"))
    group.return_immediately(())
  })
}

///|
test "terminal failures are normalized by the host" {
  assert_false(host_reports_terminal_error(AgentStep))
  assert_false(host_reports_terminal_error(AgentFinished("done")))
  assert_false(
    host_reports_terminal_error(ContextYield("[context ceiling] checkpointed")),
  )
  assert_true(host_reports_terminal_error(AgentAborted("interrupted")))
  assert_true(host_reports_terminal_error(MaxStepsExhausted))
  assert_true(host_reports_terminal_error(AgentError("boom")))
}

///|
test "unproven terminal logs require an EOF durable scan" {
  assert_true(
    DecodedStreamEvent::from_wire({ "event": "agent_setup_failed" }).needs_durable_scan,
  )
  assert_true(
    DecodedStreamEvent::from_wire({ "event": "turn_failed" }).needs_durable_scan,
  )
  assert_true(
    DecodedStreamEvent::from_wire({ "event": "agent_aborted" }).needs_durable_scan,
  )
  assert_false(
    DecodedStreamEvent::from_wire({ "event": "agent_finished" }).needs_durable_scan,
  )
  assert_false(
    DecodedStreamEvent::from_wire({ "event": "max_steps_exhausted" }).needs_durable_scan,
  )
}

///|
test "context yield has a distinct non-success wire status" {
  let status : RunStatus = ContextYield
  assert_eq(status.wire(), "context_yield")
}

///|
test "run ids carry 128 bits of cross-host entropy" {
  let id = mint_run_id()
  assert_true(id.has_prefix("r"))
  assert_eq(id.length(), 33)
}

///|
test "terminal closure preserves a queued compaction" {
  assert_true(
    Running(run_id="r-1", cancel_requested=false, compact_queued=false).after_run_close()
    is Idle(last_run=Some("r-1")),
  )
  assert_true(
    Running(run_id="r-1", cancel_requested=false, compact_queued=true).after_run_close()
    is Compacting(last_run=Some("r-1")),
  )
}

///|
test "trailing steer settle events keep the terminal run id" {
  let tracker = SteerRunTracker::new()
  tracker.begin_run()
  ignore(tracker.record_sent("old steer", Some("submission-old")))
  tracker.record_terminal("r41")
  tracker.begin_run()
  ignore(tracker.record_sent("fresh steer", Some("submission-fresh")))
  let old_drop : @event.AgentEvent? = Some(SteerDropped("old steer"))
  let fresh_apply : @event.AgentEvent? = Some(SteerApplied("fresh steer"))
  assert_eq(
    tracker.route_event(old_drop, false, Some("r42")),
    (Some("r41"), Some("submission-old")),
  )
  assert_eq(
    tracker.route_event(fresh_apply, true, Some("r42")),
    (Some("r42"), Some("submission-fresh")),
  )
}

///|
test "equal steer text receipts retain writer-order submission ids" {
  let tracker = SteerRunTracker::new()
  tracker.begin_run()
  ignore(tracker.record_sent("same", Some("submission-a")))
  ignore(tracker.record_sent("same", Some("submission-b")))
  let receipt : @event.AgentEvent? = Some(SteerApplied("same"))
  let (first_run, first_submission) = tracker.route_event(
    receipt,
    true,
    Some("r9"),
  )
  assert_eq(first_run, Some("r9"))
  let first_event : @protocol.AgentStreamEvent = {
    event: (SteerApplied(kind="prompt", content="same") : @wire.Event),
    submission_id: first_submission,
  }
  guard first_event.to_json() is Object(first_fields) &&
    first_fields.get("submission_id") is Some(String(first_id)) else {
    fail("first receipt did not carry a submission id")
  }
  assert_eq(first_id, "submission-a")
  let (second_run, second_submission) = tracker.route_event(
    receipt,
    true,
    Some("r9"),
  )
  assert_eq(second_run, Some("r9"))
  let second_event : @protocol.AgentStreamEvent = {
    event: (SteerApplied(kind="prompt", content="same") : @wire.Event),
    submission_id: second_submission,
  }
  guard second_event.to_json() is Object(second_fields) &&
    second_fields.get("submission_id") is Some(String(second_id)) else {
    fail("second receipt did not carry a submission id")
  }
  assert_eq(second_id, "submission-b")
}

///|
test "legacy steer receipt does not gain a submission field" {
  let tracker = SteerRunTracker::new()
  tracker.begin_run()
  ignore(tracker.record_sent("legacy", None))
  let decoded : @event.AgentEvent? = Some(SteerApplied("legacy"))
  let (_, submission_id) = tracker.route_event(decoded, true, Some("r11"))
  let event : @protocol.AgentStreamEvent = {
    event: (SteerApplied(kind="prompt", content="legacy") : @wire.Event),
    submission_id,
  }
  guard event.to_json() is Object(fields) else {
    fail("expected receipt object")
  }
  assert_true(fields.get("submission_id") is None)
}

///|
test "submission ids are non-blank and bounded by UTF-8 bytes" {
  assert_true(normalize_submission_id(None) is None)
  assert_true(normalize_submission_id(Some(" \t\n")) is None)
  assert_eq(
    normalize_submission_id(Some("x".repeat(128))),
    Some("x".repeat(128)),
  )
  assert_true(normalize_submission_id(Some("x".repeat(129))) is None)
  // U+754C occupies three UTF-8 bytes: count wire bytes, not UTF-16 units.
  assert_eq(
    normalize_submission_id(Some("界".repeat(42))),
    Some("界".repeat(42)),
  )
  assert_true(normalize_submission_id(Some("界".repeat(43))) is None)
  // Accepted ids stay opaque rather than being trimmed before the echo.
  assert_eq(normalize_submission_id(Some(" id ")), Some(" id "))
}

///|
test "started payload omits a missing submission id" {
  let payload : StartedPayload = {
    run_id: "r1",
    submission_id: None,
    engine: Some("openseek"),
    model: Some("model"),
    max_steps: Some(10),
    session: "s-started",
    session_root: None,
  }
  guard payload.to_json() is Object(fields) else {
    fail("expected started payload object")
  }
  assert_true(fields.get("submission_id") is None)
}

///|
test "new turn events clear stale settling state" {
  let tracker = SteerRunTracker::new()
  tracker.begin_run()
  ignore(tracker.record_sent("old steer", Some("submission-old")))
  tracker.record_terminal("r7")
  assert_eq(
    tracker.route_event(Some(AgentStep), false, Some("r8")),
    (Some("r8"), None),
  )
  let old_drop : @event.AgentEvent? = Some(SteerDropped("old steer"))
  assert_eq(
    tracker.route_event(old_drop, false, Some("r8")),
    (Some("r8"), None),
  )
}

///|
test "background events do not clear trailing steer receipts" {
  let tracker = SteerRunTracker::new()
  tracker.begin_run()
  ignore(tracker.record_sent("first", Some("submission-first")))
  ignore(tracker.record_sent("second", Some("submission-second")))
  tracker.record_terminal("r-old")
  tracker.begin_run()
  assert_eq(
    tracker.route_event(None, false, Some("r-new")),
    (Some("r-new"), None),
  )
  assert_eq(
    tracker.route_event(Some(SteerApplied("first")), true, Some("r-new")),
    (Some("r-old"), Some("submission-first")),
  )
  assert_eq(
    tracker.route_event(Some(SteerDropped("second")), false, Some("r-new")),
    (Some("r-old"), Some("submission-second")),
  )
}

///|
test "only prompt steer_applied consumes a desktop steer" {
  let tracker = SteerRunTracker::new()
  tracker.begin_run()
  ignore(tracker.record_sent("same", Some("submission-prompt")))
  let decoded : @event.AgentEvent? = Some(SteerApplied("same"))
  for _ in ["command", "notice"] {
    assert_eq(
      tracker.route_event(decoded, false, Some("r1")),
      (Some("r1"), None),
    )
  }
  assert_eq(
    tracker.route_event(decoded, true, Some("r1")),
    (Some("r1"), Some("submission-prompt")),
  )
}

///|
async test "timed out command-lock waiter is removed" {
  let lock : @async.Mutex = Mutex()
  lock.acquire()
  assert_true(@async.with_timeout_opt(10, () => lock.acquire()) is None)
  lock.release()
  // The timed-out waiter must not consume the later release; close_and_wait's
  // cancellation fallback depends on the mutex queue removing it cleanly.
  assert_true(@async.with_timeout_opt(100, () => lock.acquire()) is Some(_))
  lock.release()
}

///|
async test "native engine env has one authoritative bundled moon path" {
  let ambient_path = @sys.get_env_var("PATH")
  let root = @pathx.Path(@fs.tmpdir(prefix="openseek-engine-env-"))
  // The macOS bundle's real shape (`package/macos/main.mbt`): the engine is
  // staged in the Proton package input's `bin/`, with the toolchain seed
  // beside that directory rather than inside it.
  let input = root.join("Contents/Resources/target/proton-package-input")
  let engine = input.join("bin/openseek")
  let seed = input.join("toolchains/moonbit/macos-arm64")
  let runtime = root.join("runtime")
  let moon_home = runtime.join("toolchains/moonbit/macos-arm64")
  prepare_fake_moonbit_seed(seed, version="0.10.0-test") catch {
    error => {
      @fs.rmdir(root.to_string(), recursive=true) catch {
        _ => ()
      }
      raise error
    }
  }
  prepare_fake_bundled_moonbit_home(moon_home, version="0.10.0-test") catch {
    error => {
      @fs.rmdir(root.to_string(), recursive=true) catch {
        _ => ()
      }
      raise error
    }
  }
  let config : RunConfig = {
    task: "t",
    api_key: "k",
    api_url: None,
    model: "m",
    max_steps: 1,
    engine: engine.to_string(),
    cwd: None,
    session: "s-env",
    session_root: None,
  }
  let env = engine_process_env(config, Some(runtime)) catch {
    error => {
      @fs.rmdir(root.to_string(), recursive=true) catch {
        _ => ()
      }
      raise error
    }
  }
  @fs.rmdir(root.to_string(), recursive=true)
  assert_eq(env["OPENSEEK_SESSION"], "s-env")
  assert_true(env.get("OPENSEEK_SESSION_ROOT") is None)
  let moon_bin = moon_home.join("bin").to_string()
  let expected_path = if ambient_path is Some(path) && !path.is_empty() {
    "\{moon_bin}\{@env.path_sep}\{path}"
  } else {
    moon_bin
  }
  assert_eq(env["PATH"], expected_path)
}

///|
#cfg(not(platform="windows"))
async test "engine startup rolls back follower on pre-spawn failure" {
  let dir = @fs.tmpdir(prefix="openseek-engine-startup-")
  let baseline_engine = dir + "/baseline.sh"
  @fs.write_file(
    baseline_engine,
    "#!/bin/sh\nprintf '%s' '{\"events\":[]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", baseline_engine]), 0)
  let manager = new_engine_manager(baseline_engine)
  let sink = EventSink(fn(_) { () })
  let slot : SessionSlot = { pending: None, engine: None }
  let config : RunConfig = {
    task: "test",
    api_key: "test",
    api_url: None,
    model: "test",
    max_steps: 1,
    engine: dir + "/missing/openseek",
    cwd: None,
    session: "s-startup-failure",
    session_root: Some(@pathx.Path(dir + "/root").resolve()),
  }
  @async.with_task_group(group => {
    let failed = try {
      start_serve_engine(sink~, group~, manager~, slot~, config~)
      false
    } catch {
      error if @async.is_being_cancelled() => raise error
      _ => true
    }
    assert_true(failed)
    assert_true(manager.followers.get("s-startup-failure") is None)
    assert_true(slot.engine is None)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
/// The slot claim is what closes the compact-preempts-starting-prompt race:
/// whichever op (start, compact, archive) validated first holds the slot
/// through its command hitting the wire, and every later claimant is refused
/// with the holder's message — releasing reopens the slot.
test "a claimed session slot refuses every other op until released" {
  let manager = new_engine_manager("unused")
  let sessions : Map[String, SessionSlot] = Map([])
  manager.pump = Serving(sessions~)
  let slot = slot_for(sessions, "s")
  let start_claim = slot.claim(sessions, "s", StartPending)
  let refused = try slot.claim(sessions, "s", CompactPending) catch {
    EngineError(message) => message
  } noraise {
    _ => ""
  }
  assert_true(refused.contains("already starting"))
  start_claim.release(manager)
  let compact_claim = slot.claim(sessions, "s", CompactPending)
  let refused = try slot.claim(sessions, "s", ArchivePending) catch {
    EngineError(message) => message
  } noraise {
    _ => ""
  }
  assert_true(refused.contains("compaction is already being requested"))
  compact_claim.release(manager)
}

///|
test "loads coexist with start and compact but not archive" {
  let manager = new_engine_manager("unused")
  let read_guard = manager.begin_record_read("s")
  let op_guard = manager.begin_record_op("s")
  let second_op = try manager.begin_record_op("s") catch {
    EngineError(message) => message
  } noraise {
    _ => ""
  }
  assert_true(second_op.contains("already preparing"))
  manager.end_record_op("s", op_guard)
  manager.end_record_read("s", read_guard)
  let move_guard = manager.claim_record_move("s")
  let refused = try manager.begin_record_read("s") catch {
    EngineError(message) => message
  } noraise {
    _ => ""
  }
  assert_true(refused.contains("moving between live and archived"))
  manager.release_record_move("s", move_guard)
}

///|
test "a slot claim cannot cross an engine pump generation" {
  let manager = new_engine_manager("unused")
  let departed : Map[String, SessionSlot] = Map([])
  manager.pump = Serving(sessions=departed)
  let claim = slot_for(departed, "s").claim(departed, "s", StartPending)
  let successor : Map[String, SessionSlot] = Map([])
  manager.pump = Serving(sessions=successor)
  assert_false(claim.is_current(manager))
  let refused = try claim.require_current(manager) catch {
    EngineError(message) => message
  } noraise {
    _ => ""
  }
  assert_true(refused.contains("restarted"))
  claim.release(manager)
  assert_true(successor.get("s") is None)
}

///|
async test "record move waits for readers across pump replacement" {
  let manager = new_engine_manager("unused")
  let reader = manager.begin_record_read("s")
  let moving = manager.claim_record_move("s")
  manager.pump = Serving(sessions=Map([]))
  @async.with_task_group(group => {
    let waiter = group.spawn(() => moving.wait_until_idle())
    @async.pause()
    assert_true(waiter.try_wait() is None)
    manager.pump = Serving(sessions=Map([]))
    manager.end_record_read("s", reader)
    waiter.wait()
  })
  manager.release_record_move("s", moving)
}

///|
async test "pump reset acks active and queued spawn requests" {
  let manager = new_engine_manager("unused")
  let sessions : Map[String, SessionSlot] = Map([])
  manager.pump = Serving(sessions~)
  let active_claim = slot_for(sessions, "active").claim(
    sessions,
    "active",
    StartPending,
  )
  let queued_claim = slot_for(sessions, "queued").claim(
    sessions,
    "queued",
    StartPending,
  )
  let active_ack : @async.Queue[EngineError?] = Queue(kind=Blocking(1))
  let queued_ack : @async.Queue[EngineError?] = Queue(kind=Blocking(1))
  manager.commands.put(
    SpawnEngine(queued_claim, pump_test_config("queued"), queued_ack),
  )
  let active = Ref(Some(active_ack))
  reset_engine_generation(manager, active)
  assert_true(manager.pump is Stopped)
  assert_true(active_ack.try_get() is Some(Some(EngineError(_))))
  assert_true(queued_ack.try_get() is Some(Some(EngineError(_))))
  assert_true(manager.commands.try_get() is None)
  // Ack completion, not reset itself, lets each requester release its claim.
  assert_true(active_claim.is_current(manager) == false)
  assert_true(queued_claim.active)
  active_claim.release(manager)
  queued_claim.release(manager)
}

///|
async test "cancelled spawn requester holds its claim until pump ack" {
  let manager = new_engine_manager("unused")
  let sessions : Map[String, SessionSlot] = Map([])
  manager.pump = Serving(sessions~)
  let claim = slot_for(sessions, "s").claim(sessions, "s", StartPending)
  @async.with_task_group(group => {
    let requester = group.spawn(() => {
      defer claim.release(manager)
      request_spawn(manager, claim, pump_test_config("s"))
    })
    let SpawnEngine(queued, _, ack) = manager.commands.get()
    assert_true(physical_equal(queued, claim))
    requester.cancel()
    @async.pause()
    assert_true(claim.is_current(manager))
    assert_true(ack.try_get() is None)
    ack.put(None)
    let cancelled = try {
      requester.wait()
      false
    } catch {
      error if @async.is_cancellation_error(error) => true
      _ => false
    }
    assert_true(cancelled)
    assert_false(claim.active)
  })
}
