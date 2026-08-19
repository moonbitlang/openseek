///|
test "recorded terminal outcomes follow the durable-log contracts" {
  guard recorded_terminal_outcome(Terminal(Finished("done")))
    is Some({ status: Finished, answer: Some("done"), error: None }) else {
    fail("expected a plain finish")
  }
  guard recorded_terminal_outcome(
      Terminal(Finished("[context ceiling] checkpointed")),
    )
    is Some({ status: ContextYield, .. }) else {
    fail("expected the answer prefix to spell a context yield")
  }
  guard recorded_terminal_outcome(Terminal(Failed("max steps exhausted")))
    is Some({ status: MaxStepsExhausted, .. }) else {
    fail("expected the exact message to spell a max-steps stop")
  }
  guard recorded_terminal_outcome(Terminal(Failed("boom")))
    is Some({ status: Failed, error: Some("boom"), .. }) else {
    fail("expected a plain failure")
  }
  guard recorded_terminal_outcome(Terminal(Interrupted("cancelled")))
    is Some({ status: Cancelled, error: Some("cancelled"), .. }) else {
    fail("expected an interruption to close as cancelled")
  }
  guard recorded_terminal_outcome(
      UnknownTerminal({ "kind": "terminal", "payload": { "kind": "novel" } }),
    )
    is Some({ status: Failed, answer: None, error: None }) else {
    fail("expected an unknown terminal to close as failed")
  }
  assert_true(
    recorded_terminal_outcome(
      Summary({ content: "s", from_sequence: 1, to_sequence: 2 }),
    )
    is None,
  )
}

///|
/// The follower is the run's single closer: an attributed durable Terminal
/// closes the open run immediately — real status, exact sequence, no grace
/// — and the engine stays alive for its next turn. Unattributable
/// terminals (a predecessor's, or one without a timestamp) close nothing.
#cfg(not(platform="windows"))
async test "a durable terminal closes its open run" {
  let dir = @fs.tmpdir(prefix="openseek-durable-close-")
  let root : @pathx.Absolute = @pathx.Path(dir + "/root").resolve()
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
      "s-close",
      writer,
      process,
      sink,
      phase=Running(
        run_id="r-close",
        cancel_requested=false,
        compact_queued=false,
      ),
      session_root=root,
    )
    let sessions : Map[String, SessionSlot] = Map([])
    let slot = slot_for(sessions, "s-close")
    slot.engine = Some(engine)
    manager.pump = Serving(sessions~)
    let follower = follower_state_fixture("s-close")
    let admitted = @async.now()
    engine.run_admitted_ms = admitted
    fn terminal_event(
      sequence : Int,
      ts : Int64,
      terminal : @protocol.SessionTerminal,
    ) -> @protocol.SessionEvent {
      { sequence, ts: Some(ts.to_double()), item: Terminal(terminal) }
    }

    // A predecessor's terminal (committed before this run was admitted)
    // closes nothing: a lagging scan replaying old history must not settle
    // the healthy successor. Neither does one without a timestamp.
    follower.close_run_from_terminal(
      sink,
      manager,
      terminal_event(40, admitted - 50, Finished("done")),
    )
    follower.close_run_from_terminal(sink, manager, {
      sequence: 41,
      ts: None,
      item: Terminal(Finished("done")),
    })
    assert_true(engine.phase is Running(..))
    assert_true(emitted.is_empty())

    // An attributed terminal closes immediately: real status, the record's
    // answer, the exact sequence — and the engine stays live for reuse.
    follower.close_run_from_terminal(
      sink,
      manager,
      terminal_event(42, admitted + 5, Finished("all done")),
    )
    assert_true(engine.phase is Idle(last_run=Some("r-close")))
    assert_false(engine.condemned)
    assert_true(slot.live() is Some(_))
    guard emitted is [Finished(finish)] else {
      fail("expected exactly one finished event")
    }
    assert_eq(finish.run_id, "r-close")
    assert_eq(finish.status, "finished")
    assert_eq(finish.answer, Some("all done"))
    assert_eq(finish.durable_sequence, Some(42))
    emitted.clear()

    // With the phase already closed, replaying the same commit is inert.
    follower.close_run_from_terminal(
      sink,
      manager,
      terminal_event(42, admitted + 5, Finished("all done")),
    )
    assert_true(emitted.is_empty())

    // A cancel is recorded as Interrupted, and closes with the same
    // Error+Finished pair the stream path used to publish.
    engine.run_admitted_ms = @async.now()
    engine.phase = Running(
      run_id="r-close-2",
      cancel_requested=true,
      compact_queued=false,
    )
    follower.close_run_from_terminal(
      sink,
      manager,
      terminal_event(44, engine.run_admitted_ms + 5, Interrupted("cancelled")),
    )
    guard emitted is [Error(error), Finished(cancel_finish)] else {
      fail("expected an error and a finished event")
    }
    assert_eq(error.message, Some("cancelled"))
    assert_eq(cancel_finish.status, "cancelled")
    assert_eq(cancel_finish.durable_sequence, Some(44))
    emitted.clear()

    // A close with a compaction queued behind the turn lands in Compacting,
    // exactly as the stream close did, so nothing slips in ahead of it.
    engine.run_admitted_ms = @async.now()
    engine.phase = Running(
      run_id="r-close-3",
      cancel_requested=false,
      compact_queued=true,
    )
    follower.close_run_from_terminal(
      sink,
      manager,
      terminal_event(46, engine.run_admitted_ms + 5, Finished("done")),
    )
    assert_true(engine.phase is Compacting(last_run=Some("r-close-3")))
  })
  @fs.rmdir(dir, recursive=true)
}

///|
/// A child that dies mid-turn but committed its Terminal first is settled
/// by the retirement's final durable scan with the record's real outcome;
/// the synthetic Failed is reserved for a death that left no Terminal.
#cfg(not(platform="windows"))
async test "EOF retirement closes a committed turn with its real outcome" {
  let dir = @fs.tmpdir(prefix="openseek-eof-durable-close-")
  let root : @pathx.Absolute = @pathx.Path(dir + "/root").resolve()
  let count = dir + "/count"
  let engine_sh = dir + "/engine.sh"
  // `sessions show` runs once for the follower's baseline (before the turn:
  // no events) and again for the final scan (the record now holds the
  // turn's Terminal).
  @fs.write_file(
    engine_sh,
    "#!/bin/sh\n" +
    "n=0\n" +
    "if [ -f '\{count}' ]; then n=$(cat '\{count}'); fi\n" +
    "n=$((n + 1))\n" +
    "printf '%s' \"$n\" > '\{count}'\n" +
    "if [ \"$n\" -eq 1 ]; then printf '%s' '{\"events\":[]}'; exit 0; fi\n" +
    "printf '%s' '{\"events\":[{\"sequence\":7,\"ts\":1723900000000.0,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"interrupted\",\"message\":\"cancelled\"}}}]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine_sh]), 0)
  let manager = new_engine_manager(engine_sh)
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine_sh, "s-eof-close", root),
      ),
    )
    guard manager.followers.get("s-eof-close") is Some(follower) else {
      fail("expected follower")
    }
    let (child_stdin, writer) = @process.write_to_process()
    let process = @process.spawn(
      group,
      "/bin/sh",
      ["-c", "sleep 30"],
      stdin=child_stdin,
      no_wait=true,
    )
    let engine = test_serve_engine(
      "s-eof-close",
      writer,
      process,
      sink,
      phase=Running(
        run_id="r-eof",
        cancel_requested=false,
        compact_queued=false,
      ),
      session_root=root,
      follower~,
    )
    let sessions : Map[String, SessionSlot] = Map([])
    let slot = slot_for(sessions, "s-eof-close")
    slot.engine = Some(engine)
    manager.pump = Serving(sessions~)
    let messages : @async.Queue[StreamMessage] = Queue(
      kind=Blocking(EngineStreamQueueSize),
    )
    messages.put(StreamExited(0))
    let stderr_task = group.spawn(no_wait=true, () => "")
    engine.run(manager, messages, stderr_task)

    // The final scan found the Terminal: the run settled with the record's
    // own outcome and sequence, and no synthetic failure was fabricated.
    assert_true(engine.phase is Idle(last_run=Some("r-eof")))
    assert_true(slot.engine is None)
    let mut cancelled = 0
    for event in emitted {
      if event is Finished(payload) {
        assert_eq(payload.run_id, "r-eof")
        assert_eq(payload.status, "cancelled")
        assert_eq(payload.durable_sequence, Some(7))
        cancelled += 1
      }
    }
    assert_eq(cancelled, 1)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
test "commits_after filters typed events by watermark in file order" {
  let session : @protocol.SessionDocument = {
    version: None,
    id: Some("s"),
    system_prompt: None,
    events: Some([
      { sequence: 1, ts: None, item: User({ content: "one" }) },
      { sequence: 2, ts: None, item: User({ content: "two" }) },
      { sequence: 3, ts: None, item: User({ content: "three" }) },
    ]),
  }
  let fresh = commits_after(session, 1)
  inspect(fresh.length(), content="2")
  inspect(fresh[0].sequence, content="2")
  inspect(fresh[1].sequence, content="3")
  inspect(commits_after(session, 3).length(), content="0")
}

///|
test "commits_after tolerates a session without events" {
  let session : @protocol.SessionDocument = {
    version: None,
    id: Some("s"),
    system_prompt: None,
    events: None,
  }
  inspect(commits_after(session, 0).length(), content="0")
}

///|
test "session_max_sequence is the snapshot's watermark" {
  let session : @protocol.SessionDocument = {
    version: None,
    id: Some("s"),
    system_prompt: None,
    events: Some([
      { sequence: 5, ts: None, item: User({ content: "five" }) },
      { sequence: 9, ts: None, item: User({ content: "nine" }) },
      { sequence: 7, ts: None, item: User({ content: "seven" }) },
    ]),
  }
  inspect(session_max_sequence(session), content="9")
  inspect(session_max_sequence({ ..session, events: Some([]) }), content="0")
}

///|
test "session_store_file follows the store layout" {
  let path = session_store_file(
    @pathx.Path("/tmp/store-root").resolve(),
    "desktop-abc",
  )
  assert_true(
    path.has_suffix("sessions/desktop-abc/openseek_session-desktop-abc.jsonl"),
  )
}

///|
#cfg(not(platform="windows"))
async test "failed final scan keeps the follower active and propagates" {
  let dir = @fs.tmpdir(prefix="openseek-follower-stop-")
  let engine = dir + "/engine.sh"
  let root : @pathx.Absolute = @pathx.Path(dir + "/root").resolve()
  let record : @pathx.Path = Path(session_store_file(root, "s-fail"))
  @fsx.ensure_dir(record.dirname())
  @fs.write_file(record.to_string(), "record", create_mode=CreateOrTruncate)
  @fs.write_file(
    engine,
    "#!/bin/sh\nprintf '%s' 'show failed' >&2\nexit 7\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let sink = EventSink(fn(_) { () })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine, "s-fail", root),
      ),
    )
    guard manager.followers.get("s-fail") is Some(follower) else {
      fail("expected follower")
    }
    let detail = try {
      stop_follower(manager, "s-fail", writer_exited=true)
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
    assert_true(detail.contains("show failed"))
    assert_true(
      manager.followers.get("s-fail") is Some(current) &&
      physical_equal(current, follower),
    )
    assert_false(follower.stopping)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "zero-watermark durable boundary survives a failed final scan" {
  let dir = @fs.tmpdir(prefix="openseek-follower-durable-zero-")
  let engine = dir + "/engine.sh"
  let calls = dir + "/calls"
  let session = "s-durable-zero"
  let root : @pathx.Absolute = @pathx.Path(dir + "/root").resolve()
  let record : @pathx.Path = Path(session_store_file(root, session))
  @fsx.ensure_dir(record.dirname())
  @fs.write_file(record.to_string(), "record", create_mode=CreateOrTruncate)
  let script =
    $|#!/bin/sh
    $|calls='\{calls}'
    $|count=0
    $|if [ -f "$calls" ]; then count=$(cat "$calls"); fi
    $|count=$((count + 1))
    $|printf '%s' "$count" > "$calls"
    $|case "$count" in
    $|  1) printf '%s' '{"events":[]}' ;;
    $|  2) printf '%s' 'transient show failure' >&2; exit 7 ;;
    $|  *) printf '%s' '{"events":[]}' ;;
    $|esac
    $|
  @fs.write_file(engine, script, create_mode=CreateOrTruncate)
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine, session, root),
      ),
    )
    guard manager.followers.get(session) is Some(follower) else {
      fail("expected follower")
    }
    follower.expect_durable_finish("r-durable-zero")
    follower.expect_durable_finish("r-durable-zero")
    let detail = try {
      stop_follower(manager, session, writer_exited=true)
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
    assert_true(detail.contains("transient show failure"))
    assert_true(
      follower.durable_finishes
      is [{ run_id: "r-durable-zero", published: false }],
    )
    assert_false(emitted.iter().any(event => event is DurableBoundary(_)))

    let retry_a = group.spawn(() => {
      stop_follower(manager, session, writer_exited=true)
    })
    let retry_b = group.spawn(() => {
      stop_follower(manager, session, writer_exited=true)
    })
    retry_a.wait()
    retry_b.wait()
    stop_follower(manager, session, writer_exited=true)
    let boundaries : Array[Int] = []
    for event in emitted {
      if event is DurableBoundary(payload) && payload.run_id == "r-durable-zero" {
        boundaries.push(payload.sequence)
      }
    }
    assert_eq(boundaries, [0])
    assert_true(follower.durable_finishes[0].published)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "absent first record publishes one exact-zero durable boundary" {
  let dir = @fs.tmpdir(prefix="openseek-follower-durable-absent-")
  let engine = dir + "/engine.sh"
  let session = "s-durable-absent"
  let root : @pathx.Absolute = @pathx.Path(dir + "/root").resolve()
  @fs.write_file(
    engine,
    "#!/bin/sh\nprintf '%s' 'show failed' >&2\nexit 7\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine, session, root),
      ),
    )
    guard manager.followers.get(session) is Some(follower) else {
      fail("expected follower")
    }
    follower.expect_durable_finish("r-durable-absent")
    stop_follower(manager, session, writer_exited=true)
    stop_follower(manager, session, writer_exited=true)

    let boundaries : Array[Int] = []
    for event in emitted {
      if event is DurableBoundary(payload) &&
        payload.run_id == "r-durable-absent" {
        boundaries.push(payload.sequence)
      }
    }
    assert_eq(boundaries, [0])
    assert_true(follower.retired)
    assert_true(manager.followers.get(session) is None)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "nonzero durable boundary survives a failed final scan" {
  let dir = @fs.tmpdir(prefix="openseek-follower-durable-tail-")
  let engine = dir + "/engine.sh"
  let calls = dir + "/calls"
  let session = "s-durable-tail"
  let root : @pathx.Absolute = @pathx.Path(dir + "/root").resolve()
  let record : @pathx.Path = Path(session_store_file(root, session))
  @fsx.ensure_dir(record.dirname())
  @fs.write_file(record.to_string(), "record", create_mode=CreateOrTruncate)
  let script =
    $|#!/bin/sh
    $|calls='\{calls}'
    $|count=0
    $|if [ -f "$calls" ]; then count=$(cat "$calls"); fi
    $|count=$((count + 1))
    $|printf '%s' "$count" > "$calls"
    $|case "$count" in
    $|  1) printf '%s' '{"events":[]}' ;;
    $|  2) printf '%s' 'transient show failure' >&2; exit 7 ;;
    $|  *) printf '%s' '{"events":[{"sequence":1,"ts":0,"item":{"kind":"user","payload":{"content":"done"}}}]}' ;;
    $|esac
    $|
  @fs.write_file(engine, script, create_mode=CreateOrTruncate)
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine, session, root),
      ),
    )
    guard manager.followers.get(session) is Some(follower) else {
      fail("expected follower")
    }
    follower.expect_durable_finish("r-durable-tail")
    stop_follower(manager, session, writer_exited=true) catch {
      EngineError(detail) =>
        assert_true(detail.contains("transient show failure"))
      error if @async.is_being_cancelled() => raise error
      error => raise error
    }

    stop_follower(manager, session, writer_exited=true)
    let relevant : Array[EngineEvent] = []
    for event in emitted {
      match event {
        SessionCommit(payload) if payload.session == session =>
          relevant.push(event)
        DurableBoundary(payload) if payload.run_id == "r-durable-tail" =>
          relevant.push(event)
        _ => ()
      }
    }
    guard relevant
      is [
        SessionCommit({ sequence: 1, session_root, .. }),
        DurableBoundary({ sequence: 1, .. }),
      ] else {
      fail("expected one rooted commit and one durable boundary")
    }
    assert_eq(session_root, root.resource_path())
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "abrupt EOF retains a failed final drain for later boundary retry" {
  let dir = @fs.tmpdir(prefix="openseek-follower-abrupt-eof-")
  let engine_path = dir + "/engine.sh"
  let calls = dir + "/calls"
  let session = "s-abrupt-eof"
  let root : @pathx.Absolute = @pathx.Path(dir + "/root").resolve()
  let record : @pathx.Path = Path(session_store_file(root, session))
  @fsx.ensure_dir(record.dirname())
  @fs.write_file(record.to_string(), "record", create_mode=CreateOrTruncate)
  let script =
    $|#!/bin/sh
    $|calls='\{calls}'
    $|count=0
    $|if [ -f "$calls" ]; then count=$(cat "$calls"); fi
    $|count=$((count + 1))
    $|printf '%s' "$count" > "$calls"
    $|case "$count" in
    $|  1) printf '%s' '{"events":[]}' ;;
    $|  2) printf '%s' 'transient show failure' >&2; exit 7 ;;
    $|  *) printf '%s' '{"events":[]}' ;;
    $|esac
    $|
  @fs.write_file(engine_path, script, create_mode=CreateOrTruncate)
  assert_eq(@process.run("chmod", ["+x", engine_path]), 0)
  let manager = new_engine_manager(engine_path)
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine_path, session, root),
      ),
    )
    guard manager.followers.get(session) is Some(follower) else {
      fail("expected follower")
    }
    let (child_stdin, writer) = @process.write_to_process()
    let process = @process.spawn(
      group,
      "/bin/sh",
      ["-c", "exit 7"],
      stdin=child_stdin,
      no_wait=true,
    )
    let engine = test_serve_engine(
      session,
      writer,
      process,
      sink,
      phase=Running(
        run_id="r-abrupt-eof",
        cancel_requested=false,
        compact_queued=false,
      ),
      session_root=root,
      follower~,
    )
    let sessions : Map[String, SessionSlot] = Map([])
    let slot = slot_for(sessions, session)
    slot.engine = Some(engine)
    manager.pump = Serving(sessions~)
    let messages : @async.Queue[StreamMessage] = Queue(
      kind=Blocking(EngineStreamQueueSize),
    )
    messages.put(StreamExited(7))
    let stderr_task = group.spawn(no_wait=true, () => "")
    engine.run(manager, messages, stderr_task)

    // `run` returning is retirement: the slot is clear and every lifecycle
    // event this engine owed has been published.
    assert_true(slot.engine is None)
    assert_true(
      follower.durable_finishes
      is [{ run_id: "r-abrupt-eof", published: false }],
    )
    let mut finished_index = -1
    let mut early_boundaries = 0
    for index, event in emitted {
      match event {
        Finished(payload) if payload.run_id == "r-abrupt-eof" => {
          assert_true(payload.durable_sequence is None)
          finished_index = index
        }
        DurableBoundary(payload) if payload.run_id == "r-abrupt-eof" =>
          early_boundaries = early_boundaries + 1
        _ => ()
      }
    }
    assert_true(finished_index >= 0)
    assert_eq(early_boundaries, 0)

    stop_follower(manager, session, writer_exited=true)
    let mut boundary_index = -1
    let mut boundary_count = 0
    for index, event in emitted {
      if event is DurableBoundary(payload) && payload.run_id == "r-abrupt-eof" {
        assert_eq(payload.sequence, 0)
        boundary_index = index
        boundary_count = boundary_count + 1
      }
    }
    assert_eq(boundary_count, 1)
    assert_true(boundary_index > finished_index)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "workspace detach drains an orphaned pending follower before commit" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let dir = @fs.tmpdir(prefix="openseek-detach-orphan-follower-")
  let global_root : @pathx.Absolute = @pathx.Path(dir + "/global").resolve()
  let workspace : @pathx.Absolute = @pathx.Path(dir + "/workspace").resolve()
  let root = @workspaces.store_root(workspace)
  let engine_path = dir + "/engine.sh"
  let calls = dir + "/calls"
  let session = "s-detach-orphan"
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", global_root.to_string())
  defer restore_session_root_env(previous)
  @fsx.ensure_dir(workspace.to_path())
  ignore(attach_workspace(workspace.to_string(), fn(_) { () }))
  let record : @pathx.Path = Path(session_store_file(root, session))
  @fsx.ensure_dir(record.dirname())
  @fs.write_file(record.to_string(), "record", create_mode=CreateOrTruncate)
  let script =
    $|#!/bin/sh
    $|calls='\{calls}'
    $|count=0
    $|if [ -f "$calls" ]; then count=$(cat "$calls"); fi
    $|count=$((count + 1))
    $|printf '%s' "$count" > "$calls"
    $|case "$count" in
    $|  1) printf '%s' '{"events":[]}' ;;
    $|  2) printf '%s' 'transient show failure' >&2; exit 7 ;;
    $|  *) printf '%s' '{"events":[]}' ;;
    $|esac
    $|
  @fs.write_file(engine_path, script, create_mode=CreateOrTruncate)
  assert_eq(@process.run("chmod", ["+x", engine_path]), 0)
  let manager = new_engine_manager(engine_path)
  let sessions : Map[String, SessionSlot] = Map([])
  manager.pump = Serving(sessions~)
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine_path, session, root),
      ),
    )
    guard manager.followers.get(session) is Some(follower) else {
      fail("expected follower")
    }
    follower.expect_durable_finish("r-detach-orphan")
    stop_follower(manager, session, writer_exited=true) catch {
      EngineError(detail) =>
        assert_true(detail.contains("transient show failure"))
      error if @async.is_being_cancelled() => raise error
      error => raise error
    }
    assert_false(follower.retired)

    let committed_after_boundary : Ref[Bool] = Ref(false)
    let detached = detach_workspace(manager, workspace.to_string(), fn(_) {
      committed_after_boundary.val = emitted
        .iter()
        .any(event => {
          event
          is DurableBoundary({ run_id: "r-detach-orphan", sequence: 0, .. })
        })
    })
    assert_true(committed_after_boundary.val)
    assert_true(detached is Workspaces([]))
    assert_true(follower.retired)
    assert_true(manager.followers.get(session) is None)
    let boundaries : Array[Int] = []
    for event in emitted {
      if event is DurableBoundary(payload) &&
        payload.run_id == "r-detach-orphan" {
        boundaries.push(payload.sequence)
      }
    }
    assert_eq(boundaries, [0])
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "workspace detach refuses an idle engine whose follower cannot drain" {
  let dir = @fs.tmpdir(prefix="openseek-detach-follower-stop-")
  let workspace : @pathx.Absolute = @pathx.Path(dir + "/workspace").resolve()
  let root = @workspaces.store_root(workspace)
  let engine_path = dir + "/engine.sh"
  let session = "s-detach-fail"
  let record : @pathx.Path = Path(session_store_file(root, session))
  @fsx.ensure_dir(record.dirname())
  @fs.write_file(record.to_string(), "record", create_mode=CreateOrTruncate)
  @fs.write_file(
    engine_path,
    "#!/bin/sh\nprintf '%s' 'show failed' >&2\nexit 7\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine_path]), 0)
  let manager = new_engine_manager(engine_path)
  let sink = EventSink(fn(_) { () })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine_path, session, root),
      ),
    )
    guard manager.followers.get(session) is Some(follower) else {
      fail("expected follower")
    }
    let (child_stdin, writer) = @process.write_to_process()
    // The real EOF consumer reaches this state after its first failed final
    // scan: the child is gone and the consumer with it, but the follower is
    // still live. Detach must retry it and propagate the failure again — so
    // the fixture's child exits on its own and its close barrier is the
    // process task, exactly as it would be in production.
    let process = @process.spawn(
      group,
      "/bin/sh",
      ["-c", "exit 0"],
      stdin=child_stdin,
      no_wait=true,
    )
    let engine = test_serve_engine(
      session,
      writer,
      process,
      sink,
      phase=Idle(last_run=Some("r-detach-fail")),
      session_root=root,
      follower~,
      condemned=true,
    )
    let sessions : Map[String, SessionSlot] = Map([])
    let slot = slot_for(sessions, session)
    slot.engine = Some(engine)
    manager.pump = Serving(sessions~)
    let detail = try {
      manager.close_engines_for_workspace(workspace)
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
    assert_true(detail.contains("show failed"))
    assert_true(
      manager.followers.get(session) is Some(current) &&
      physical_equal(current, follower),
    )
    assert_false(follower.stopping)
    discard_follower_startup(manager, follower)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "record stat failure is not mistaken for an empty final drain" {
  let dir = @fs.tmpdir(prefix="openseek-follower-stat-")
  let engine = dir + "/engine.sh"
  let root : @pathx.Absolute = @pathx.Path(dir + "/not-a-directory").resolve()
  // Looking up the pinned record beneath a regular file deterministically
  // raises ENOTDIR. That verification failure must complete Stop as failed
  // and leave the actor installed, never masquerade as ENOENT.
  @fs.write_file(root.to_string(), "file", create_mode=CreateOrTruncate)
  @fs.write_file(
    engine,
    "#!/bin/sh\nprintf '%s' 'show failed' >&2\nexit 7\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let sink = EventSink(fn(_) { () })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine, "s-stat", root),
      ),
    )
    guard manager.followers.get("s-stat") is Some(follower) else {
      fail("expected follower")
    }
    let detail = try {
      stop_follower(manager, "s-stat", writer_exited=true)
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
    assert_true(detail.contains("show failed"))
    assert_true(detail.contains("failed to verify session record"))
    assert_true(
      manager.followers.get("s-stat") is Some(current) &&
      physical_equal(current, follower),
    )
    assert_false(follower.stopping)
    discard_follower_startup(manager, follower)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "root change retires the old follower before installing another" {
  let dir = @fs.tmpdir(prefix="openseek-follower-root-")
  let engine = dir + "/engine.sh"
  @fs.write_file(
    engine,
    "#!/bin/sh\nprintf '%s' '{\"events\":[]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let sink = EventSink(fn(_) { () })
  let root_a : @pathx.Absolute = @pathx.Path(dir + "/a").resolve()
  let root_b : @pathx.Absolute = @pathx.Path(dir + "/b").resolve()
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine, "s-root", root_a),
      ),
    )
    guard manager.followers.get("s-root") is Some(first) else {
      fail("expected first follower")
    }
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine, "s-root", root_b),
      ),
    )
    guard manager.followers.get("s-root") is Some(second) else {
      fail("expected replacement follower")
    }
    assert_false(physical_equal(first, second))
    assert_eq(second.root.to_string(), root_b.to_string())
    discard_follower_startup(manager, second)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "one Load control message answers a bounded request batch" {
  let dir = @fs.tmpdir(prefix="openseek-follower-load-")
  let engine = dir + "/engine.sh"
  let count = dir + "/count"
  @fs.write_file(
    engine,
    "#!/bin/sh\nn=0\nif [ -f '\{count}' ]; then n=$(cat '\{count}'); fi\nn=$((n + 1))\nprintf '%s' \"$n\" > '\{count}'\nprintf '%s' '{\"events\":[]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let sink = EventSink(fn(_) { () })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(
          engine,
          "s-load",
          @pathx.Path(dir + "/root").resolve(),
        ),
      ),
    )
    guard manager.followers.get("s-load") is Some(follower) else {
      fail("expected follower")
    }
    let replies : Array[@async.Queue[FollowerLoadReply]] = []
    for _ in 0..<8 {
      let reply : @async.Queue[FollowerLoadReply] = Queue(kind=Blocking(1))
      replies.push(reply)
      follower.load_requests.put({ reply, active: true })
    }
    follower.load_pending = true
    assert_true(follower.inbox.try_put(Load))
    for reply in replies {
      assert_true(reply.get() is LoadOk(_))
    }
    assert_eq(@fs.read_file(count).text(), "2")
    discard_follower_startup(manager, follower)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
test "startup rollback closes waiters and preserves a successor identity" {
  let manager = new_engine_manager("unused")
  let abandoned = follower_state_fixture("s-startup")
  let reply : @async.Queue[FollowerLoadReply] = Queue(kind=Blocking(1))
  let request : FollowerLoadRequest = { reply, active: true }
  assert_true(abandoned.load_requests.try_put(request))
  manager.followers["s-startup"] = abandoned
  discard_follower_startup(manager, abandoned)
  assert_true(manager.followers.get("s-startup") is None)
  assert_false(request.active)
  assert_true(reply.try_get() is Some(LoadStopped))
  assert_false(abandoned.inbox.try_put(Kick) catch { _ => false })

  let stale = follower_state_fixture("s-startup")
  let successor = follower_state_fixture("s-startup")
  manager.followers["s-startup"] = successor
  discard_follower_startup(manager, stale)
  assert_true(
    manager.followers.get("s-startup") is Some(current) &&
    physical_equal(current, successor),
  )
  assert_true(successor.inbox.try_put(Kick))
}

///|
test "pump reset completes every queued follower load" {
  let manager = new_engine_manager("unused")
  let follower = follower_state_fixture("s-reset")
  let reply : @async.Queue[FollowerLoadReply] = Queue(kind=Blocking(1))
  let request : FollowerLoadRequest = { reply, active: true }
  assert_true(follower.load_requests.try_put(request))
  manager.followers["s-reset"] = follower
  manager.pump = Serving(sessions=Map([]))
  reset_engine_generation(manager, Ref(None))
  assert_true(manager.pump is Stopped)
  assert_true(manager.followers.get("s-reset") is None)
  assert_false(request.active)
  assert_true(reply.try_get() is Some(LoadStopped))
}

///|
async test "identity-scoped stop never retires a successor" {
  let manager = new_engine_manager("unused")
  let departed = follower_state_fixture("s-exit")
  let successor = follower_state_fixture("s-exit")
  manager.followers["s-exit"] = successor
  stop_follower_instance(manager, departed, writer_exited=false)
  assert_true(
    manager.followers.get("s-exit") is Some(current) &&
    physical_equal(current, successor),
  )
  assert_false(successor.stopping)
  assert_true(successor.inbox.try_get() is None)
}

///|
#cfg(not(platform="windows"))
async test "cancelling follower baseline removes its startup identity" {
  let dir = @fs.tmpdir(prefix="openseek-follower-cancel-")
  let engine = dir + "/engine.sh"
  @fs.write_file(
    engine,
    "#!/bin/sh\nsleep 30\nprintf '%s' '{\"events\":[]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let sink = EventSink(fn(_) { () })
  @async.with_task_group(group => {
    let startup = group.spawn(() => {
      ignore(
        ensure_follower(
          sink~,
          group~,
          manager~,
          config=follower_test_config(
            engine,
            "s-cancel",
            @pathx.Path(dir + "/root").resolve(),
          ),
        ),
      )
    })
    while manager.followers.get("s-cancel") is None {
      @async.pause()
    }
    startup.cancel()
    let cancelled = try {
      startup.wait()
      false
    } catch {
      error if @async.is_cancellation_error(error) => true
      _ => false
    }
    assert_true(cancelled)
    assert_true(manager.followers.get("s-cancel") is None)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "load request is queued before its collapsed control message" {
  let follower = follower_state_fixture("s-order")
  @async.with_task_group(group => {
    let caller = group.spawn(() => request_follower_load(follower))
    assert_true(follower.inbox.get() is Load)
    let request = follower.load_requests.get()
    assert_true(request.active)
    request.active = false
    request.reply.put(
      LoadOk({ version: None, id: None, system_prompt: None, events: Some([]) }),
    )
    assert_true(caller.wait() is LoadOk(_))
  })
}

///|
async test "backpressured load schedules the next control generation" {
  let follower = follower_state_fixture("s-backpressure")
  let placeholder : @async.Queue[FollowerLoadReply] = Queue(kind=Blocking(1))
  follower.load_requests.put({ reply: placeholder, active: false })
  follower.load_pending = true
  @async.with_task_group(group => {
    let caller = group.spawn(() => request_follower_load(follower))
    @async.pause()
    // Freeing the sole request slot accepts and wakes the blocked caller.
    // Model the previous Load generation finishing before that caller runs.
    ignore(follower.load_requests.get())
    follower.load_pending = false
    assert_true(follower.inbox.get() is Load)
    let request = follower.load_requests.get()
    assert_true(request.active)
    request.active = false
    request.reply.put(
      LoadOk({ version: None, id: None, system_prompt: None, events: Some([]) }),
    )
    assert_true(caller.wait() is LoadOk(_))
  })
}

///|
async test "stop requires its generation proof when follower identity vanishes" {
  let manager = new_engine_manager("unused")
  let follower = follower_state_fixture("s-stop-proof")
  manager.followers["s-stop-proof"] = follower
  @async.with_task_group(group => {
    let caller = group.spawn(() => {
      try {
        stop_follower(manager, "s-stop-proof", writer_exited=false)
        "no error"
      } catch {
        EngineError(detail) => detail
        error if @async.is_being_cancelled() => raise error
        error => "\{error}"
      }
    })
    guard follower.inbox.get() is Stop(generation~, ..) else {
      fail("expected Stop")
    }
    manager.followers.remove("s-stop-proof")
    let detail = caller.wait()
    assert_true(detail.contains("without completing"))

    let completed = follower_state_fixture("s-stop-complete")
    manager.followers["s-stop-complete"] = completed
    let successful = group.spawn(() => {
      stop_follower(manager, "s-stop-complete", writer_exited=false)
      true
    })
    guard completed.inbox.get() is Stop(generation=completed_generation, ..) else {
      fail("expected second Stop")
    }
    completed.completed_stop_generation = completed_generation
    completed.completed_stop_error = None
    manager.followers.remove("s-stop-complete")
    assert_true(successful.wait())
    ignore(generation)
  })
}
