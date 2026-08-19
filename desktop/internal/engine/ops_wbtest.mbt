///|
#cfg(not(platform="windows"))
async test "one-shot session engine overrides ambient OPENSEEK_DIR" {
  let previous = @sys.get_env_var("OPENSEEK_DIR")
  @sys.set_env_var("OPENSEEK_DIR", "/missing/openseek-dir")
  let dir = @fs.tmpdir(prefix="openseek-session-env-")
  let engine = "\{dir}/engine.sh"
  @fs.write_file(
    engine,
    "#!/bin/sh\nprintf '%s' \"$OPENSEEK_DIR\"\n",
    create_mode=CreateOrTruncate,
  )
  let chmod = @process.run("chmod", ["+x", engine])
  assert_eq(chmod, 0)
  let manager = new_engine_manager(engine)
  let output = engine_stdout(manager, []) catch {
    error => {
      restore_openseek_dir(previous)
      @fs.rmdir(dir, recursive=true) catch {
        _ => ()
      }
      raise error
    }
  }
  restore_openseek_dir(previous)
  @fs.rmdir(dir, recursive=true)
  assert_eq(output, ".")
}

///|
#cfg(not(platform="windows"))
async test "start echoes the client submission id in Started" {
  let dir = @fs.tmpdir(prefix="openseek-start-submission-")
  let root : @pathx.Path = Path(dir)
  // A run is handed the global skills library under `HOME`. Own it, so this
  // test neither races one that moves `HOME` nor reads the developer's own.
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_home_env(previous_home)
  let previous_session_root = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous_session_root)
  let workspace = attach_run_workspace(root)
  let engine = root.join("bin/engine.sh")
  let seed = root.join("bin/toolchains/moonbit/macos-arm64")
  let runtime = root.join("runtime")
  prepare_fake_moonbit_seed(seed, version="0.10.0-test")
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then printf '%s' '{\"events\":[]}'; exit 0; fi\nwhile IFS= read -r line; do :; done\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let actor = new_engine_actor(engine.to_string(), runtime_dir=runtime)
  let manager = actor.manager()
  ignore(
    update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://example.invalid/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: None,
    }),
  )
  let emitted : Array[EngineEvent] = []
  // Starts are durable now, so each test owns a fresh conversation record
  // instead of sharing a fixed id across test processes.
  let session = "s-" + mint_run_id()
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) { () })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    ignore(
      start_run(sink, manager, {
        task: "hello",
        submission_id: Some("submission-start"),
        model: None,
        max_steps: None,
        session,
        workspace: Some(workspace),
      }),
    )
    let mut echoed : String? = None
    for event in emitted {
      if event is Started(payload) {
        echoed = payload.submission_id
      }
    }
    assert_eq(echoed, Some("submission-start"))
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
/// A goal is the one command with no lifecycle event behind it, so its reply
/// is only truthful if it waits for the writer. Both halves matter: the reply
/// must arrive when the command reaches stdin — otherwise the op hangs — and
/// must not arrive when it does not.
#cfg(not(platform="windows"))
async test "a goal is delivered only once its command is on the wire" {
  let dir = @fs.tmpdir(prefix="openseek-goal-ack-")
  let root : @pathx.Path = Path(dir)
  // A run is handed the global skills library under `HOME`. Own it, so this
  // test neither races one that moves `HOME` nor reads the developer's own.
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_home_env(previous_home)
  let previous_session_root = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous_session_root)
  let workspace = attach_run_workspace(root)
  let engine = root.join("bin/engine.sh")
  let seed = root.join("bin/toolchains/moonbit/macos-arm64")
  let runtime = root.join("runtime")
  let received = root.join("received")
  prepare_fake_moonbit_seed(seed, version="0.10.0-test")
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  // Echoes every command it reads back into a file, so the test can check the
  // goal really left the host rather than only that the op returned.
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then printf '%s' '{\"events\":[]}'; exit 0; fi\nwhile IFS= read -r line; do printf '%s\\n' \"$line\" >> '\{received}'; done\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let actor = new_engine_actor(engine.to_string(), runtime_dir=runtime)
  let manager = actor.manager()
  ignore(
    update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://example.invalid/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: None,
    }),
  )
  let session = "s-" + mint_run_id()
  let sink = EventSink(fn(_) { () })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) { () })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    let delivered = goal_run(manager, {
      session,
      text: Some("keep the build green"),
      auto: None,
      model: None,
      max_steps: None,
      workspace: Some(workspace),
    })
    assert_true(delivered.delivered)
    // The reply already means the bytes left this host, so the child has them
    // or is about to; only its append is asynchronous.
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while !@fsx.exists(received) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    assert_true(
      @fs.read_file(received.to_string())
      .text()
      .contains("keep the build green"),
    )
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
/// The other half: a command discarded before it could be written answers its
/// sender rather than leaving it waiting for an acknowledgement that can no
/// longer come. This is what a queued goal hits when an earlier write fails or
/// the child exits.
#cfg(not(platform="windows"))
async test "a discarded command answers its sender" {
  @async.with_task_group(group => {
    let (child_stdin, writer) = @process.write_to_process()
    let process = @process.spawn(
      group,
      "/bin/sh",
      ["-c", "sleep 30"],
      stdin=child_stdin,
      cancel_handler=@process.graceful_cancel(timeout=10),
      no_wait=true,
    )
    let engine = test_serve_engine(
      "s-discard",
      writer,
      process,
      EventSink(fn(_) { () }),
      phase=Idle(last_run=None),
    )
    let ack : @async.Queue[EngineError?] = Queue(kind=Blocking(1))
    assert_true(
      engine.submit("{}\n", failure_reason="failed to write the goal", ack~),
    )
    engine.discard_commands("the engine exited")
    guard ack.try_get() is Some(Some(EngineError(reason))) else {
      fail("expected the discarded command to answer its sender")
    }
    assert_eq(reason, "the engine exited")
    // Discarding also condemns the engine, in the same synchronous step.
    assert_true(engine.condemned)
    assert_false(engine.submit("{}\n", failure_reason="unreachable"))
    group.return_immediately(())
  })
}

///|
#cfg(not(platform="windows"))
async test "setup failure retires the writer before an immediate next start" {
  let dir = @fs.tmpdir(prefix="openseek-setup-failed-seam-")
  let root : @pathx.Path = Path(dir)
  // A run is handed the global skills library under `HOME`. Own it, so this
  // test neither races one that moves `HOME` nor reads the developer's own.
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_home_env(previous_home)
  let previous_session_root = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous_session_root)
  let workspace = attach_run_workspace(root)
  let engine = root.join("bin/engine.sh")
  let seed = root.join("bin/toolchains/moonbit/macos-arm64")
  let runtime = root.join("runtime")
  let count = root.join("count")
  let old_done = root.join("old-done")
  let overlapped = root.join("overlapped")
  prepare_fake_moonbit_seed(seed, version="0.10.0-test")
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then printf '%s' '{\"events\":[]}'; exit 0; fi\nn=0\nif [ -f '\{count}' ]; then n=$(cat '\{count}'); fi\nn=$((n + 1))\nprintf '%s' \"$n\" > '\{count}'\nif [ \"$n\" -eq 1 ]; then\n  IFS= read -r line || exit 0\n  printf '%s\\n' '{\"event\":\"agent_setup_failed\",\"error\":\"boom\"}'\n  sleep 1\n  printf '%s\\n' '{\"event\":\"turn_failed\",\"error\":\"append failed\"}'\n  printf '' > '\{old_done}'\n  exit 0\nfi\nif [ ! -f '\{old_done}' ]; then printf '' > '\{overlapped}'; fi\nwhile IFS= read -r line; do\n  printf '%s\\n' '{\"event\":\"agent_finished\",\"answer\":\"ok\"}'\ndone\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let actor = new_engine_actor(engine.to_string(), runtime_dir=runtime)
  let manager = actor.manager()
  ignore(
    update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://example.invalid/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: None,
    }),
  )
  let emitted : Array[EngineEvent] = []
  let session = "s-" + mint_run_id()
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) { () })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    let first = start_run(sink, manager, {
      task: "first",
      submission_id: None,
      model: None,
      max_steps: None,
      session,
      workspace: Some(workspace),
    })
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while !has_finished_run(emitted, first.run_id) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    // No durable Terminal was ever committed, so the run settles at EOF
    // retirement — which publishes Finished and clears the slot in one
    // synchronous block. Once Finished is observable, the dead writer has
    // already left its slot.
    if manager.serving().get(session) is Some(slot) {
      assert_true(slot.engine is None)
    }
    let cancelled = cancel_run(manager, { run_id: Some(first.run_id) })
    assert_false(cancelled.cancelled)
    let second = start_run(sink, manager, {
      task: "second",
      submission_id: None,
      model: None,
      max_steps: None,
      session,
      workspace: Some(workspace),
    })
    assert_eq(second.status, "accepted")
    assert_true(@fsx.exists(old_done))
    assert_false(@fsx.exists(overlapped))
    assert_true(
      @async.with_timeout_opt(1000, () => {
        while @fs.read_file(count.to_string()).text() != "2" {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    assert_eq(@fs.read_file(count.to_string()).text(), "2")
    let mut first_finishes = 0
    for event in emitted {
      if event is Finished(payload) && payload.run_id == first.run_id {
        first_finishes = first_finishes + 1
      }
    }
    assert_eq(first_finishes, 1)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
/// The prompt is far larger than the pipe buffer and the child never reads,
/// so the write is still in flight when the child dies. Submission itself
/// never waits for it — that is what removed the cancel-after-public window
/// this test used to cover — and the run is still settled exactly once,
/// whether the writer's failure or the consumer's EOF gets there first.
#cfg(not(platform="windows"))
async test "a prompt bigger than the pipe still settles exactly once" {
  let dir = @fs.tmpdir(prefix="openseek-backpressured-command-")
  let root : @pathx.Path = Path(dir)
  // A run is handed the global skills library under `HOME`. Own it, so this
  // test neither races one that moves `HOME` nor reads the developer's own.
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_home_env(previous_home)
  let previous_session_root = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous_session_root)
  let workspace = attach_run_workspace(root)
  let engine = root.join("bin/engine.sh")
  let seed = root.join("bin/toolchains/moonbit/macos-arm64")
  let runtime = root.join("runtime")
  prepare_fake_moonbit_seed(seed, version="0.10.0-test")
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  // Deliberately never read stdin, then die with the prompt still half
  // written: the JSONL frame on the wire is partial, so the handle must
  // become unusable and the run must be reported as failed.
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then printf '%s' '{\"events\":[]}'; exit 0; fi\nsleep 1\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let actor = new_engine_actor(engine.to_string(), runtime_dir=runtime)
  let manager = actor.manager()
  ignore(
    update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://example.invalid/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: None,
    }),
  )
  let emitted : Array[EngineEvent] = []
  let session = "s-" + mint_run_id()
  let started : Ref[String?] = Ref(None)
  let sink = EventSink(fn(event) {
    if event is Started(payload) {
      started.val = Some(payload.run_id)
    }
    emitted.push(event)
  })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) { () })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    // Returns without waiting for the 4MB to reach the child.
    let reply = start_run(sink, manager, {
      task: "x".repeat(4_000_000),
      submission_id: None,
      model: None,
      max_steps: None,
      session,
      workspace: Some(workspace),
    })
    assert_eq(reply.status, "accepted")
    assert_eq(started.val, Some(reply.run_id))
    let run_id = reply.run_id
    assert_true(
      @async.with_timeout_opt(10_000, () => {
        while !has_finished_run(emitted, run_id) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    // Both the writer's failed write and the consumer's EOF want to settle
    // this run; they share the engine's phase, so only one of them does.
    let mut finishes = 0
    for event in emitted {
      if event is Finished(payload) && payload.run_id == run_id {
        finishes = finishes + 1
      }
    }
    assert_eq(finishes, 1)
    assert_true(open_run_engine(manager, run_id~) is None)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "named session retries after its first prompt creates no record" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let dir = @fs.tmpdir(prefix="openseek-first-prompt-retry-")
  let root : @pathx.Path = Path(dir)
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_home_env(previous_home)
  let engine = root.join("bin/engine.sh")
  let seed = root.join("bin/toolchains/moonbit/macos-arm64")
  let runtime = root.join("runtime")
  let previous_session_root = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous_session_root)
  let workspace = attach_run_workspace(root)
  // The conversation's record lives in its workspace's in-project store.
  let store = root.join("ws/.openseek")
  let count = root.join("serve-count")
  let first_ready = root.join("first-ready")
  let settled = root.join("settled")
  let session = "s-" + mint_run_id()
  prepare_fake_moonbit_seed(seed, version="0.10.0-test")
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  // `sessions show` reports the missing first-turn record. The first serve
  // process creates only the session directory, never reads stdin, and dies
  // with the large prompt's JSONL frame still partial. The successor commits
  // a durable Terminal before echoing `agent_finished` — the real engine's
  // append-then-emit order — so the follower's scan settles its run.
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then\n  if [ -f '\{settled}' ]; then\n    printf '%s' '{\"events\":[{\"sequence\":1,\"ts\":4000000000000.0,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"finished\",\"message\":\"ok\"}}}]}'\n    exit 0\n  fi\n  printf '%s\\n' 'session record does not exist' >&2\n  exit 7\nfi\nn=0\nif [ -f '\{count}' ]; then n=$(cat '\{count}'); fi\nn=$((n + 1))\nprintf '%s' \"$n\" > '\{count}'\nif [ \"$n\" -eq 1 ]; then\n  mkdir -p '\{store}/sessions/\{session}'\n  printf '' > '\{first_ready}'\n  exec sleep 1\nfi\nwhile IFS= read -r line; do\n  printf '' > '\{settled}'\n  printf '%s\\n' '{\"event\":\"agent_finished\",\"answer\":\"ok\"}'\ndone\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let actor = new_engine_actor(engine.to_string(), runtime_dir=runtime)
  let manager = actor.manager()
  ignore(
    update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://example.invalid/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: None,
    }),
  )
  let emitted : Array[EngineEvent] = []
  let started : Ref[String?] = Ref(None)
  let sink = EventSink(fn(event) {
    if event is Started(payload) {
      started.val = Some(payload.run_id)
    }
    emitted.push(event)
  })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) { () })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    let first = start_run(sink, manager, {
      task: "x".repeat(4_000_000),
      submission_id: None,
      model: None,
      max_steps: None,
      session,
      workspace: Some(workspace),
    })
    assert_eq(first.status, "accepted")
    assert_eq(started.val, Some(first.run_id))
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while !@fsx.exists(first_ready) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    assert_true(@fsx.is_dir(store.join("sessions").join(session)))
    assert_false(
      @fsx.exists(Path(session_store_file(store.resolve(), session))),
    )
    let first_run_id = first.run_id
    assert_true(
      @async.with_timeout_opt(10_000, () => {
        while !has_finished_run(emitted, first_run_id) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    assert_true(
      @async.with_timeout_opt(10_000, () => {
        while manager.followers.get(session) is Some(_) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )

    let second = start_run(sink, manager, {
      task: "retry",
      submission_id: None,
      model: None,
      max_steps: None,
      session,
      workspace: Some(workspace),
    })
    assert_eq(second.status, "accepted")
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while !has_finished_run(emitted, second.run_id) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    assert_eq(@fs.read_file(count.to_string()).text(), "2")
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "timed out sessions show is killed and the next read can run" {
  let dir = @fs.tmpdir(prefix="openseek-session-timeout-")
  let engine = dir + "/engine.sh"
  let fast = dir + "/fast"
  @fs.write_file(
    engine,
    "#!/bin/sh\nif [ ! -f '\{fast}' ]; then while :; do :; done; fi\nprintf '%s' '{\"events\":[]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let root : @pathx.Absolute = @pathx.Path(dir + "/root").resolve()
  let detail = try {
    ignore(session_show_stdout(manager, "s-timeout", root, timeout_ms=50))
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(detail.contains("timed out"))
  @fs.write_file(fast, "", create_mode=CreateOrTruncate)
  assert_eq(
    session_show_stdout(manager, "s-timeout", root, timeout_ms=1000),
    "{\"events\":[]}",
  )
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "session load preserves a future item without hiding known events" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let dir = @fs.tmpdir(prefix="openseek-load-future-item-")
  let engine = dir + "/engine.sh"
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", dir + "/global")
  defer restore_session_root_env(previous)
  // A hint-less load resolves the store from where the record actually
  // lives, so the record goes in an attached workspace's own store.
  ignore(attach_run_workspace(Path(dir)))
  @fsx.ensure_dir(Path(dir + "/ws/.openseek/sessions/s-future"))
  @fs.write_file(
    engine,
    "#!/bin/sh\nprintf '%s' '{\"events\":[{\"sequence\":1,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"question\"}}},{\"sequence\":2,\"item\":{\"kind\":\"future_item\",\"payload\":{\"value\":42}}},{\"sequence\":3,\"item\":{\"kind\":\"assistant\",\"payload\":{\"content\":\"answer\"}}}]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let reply = load_session(new_engine_manager(engine), {
    session: "s-future",
    workspace: None,
  })
  guard reply.session.events is Some(events) else {
    fail("expected session events")
  }
  assert_eq(events.length(), 3)
  assert_true(events[1].item is Unknown(_))
  assert_eq(reply.watermark, Some(3))
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "archived session load reads without restoring the record" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let dir = @fs.tmpdir(prefix="openseek-load-archived-")
  let engine = dir + "/engine.sh"
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", dir + "/global")
  defer restore_session_root_env(previous)
  // A hint-less load resolves the store from where the record actually
  // lives, so the record goes in an attached workspace's own store.
  ignore(attach_run_workspace(Path(dir)))
  let store = dir + "/ws/.openseek"
  @fsx.ensure_dir(Path(store + "/archived/sessions/s-archived"))
  @fs.write_file(
    engine,
    "#!/bin/sh\nprintf '%s' '{\"events\":[{\"sequence\":1,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"question\"}}},{\"sequence\":2,\"item\":{\"kind\":\"assistant\",\"payload\":{\"content\":\"answer\"}}}]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let reply = load_archived_session(manager, {
    session: "s-archived",
    workspace: None,
  })
  guard reply.session.events is Some(events) else {
    fail("expected archived session events")
  }
  assert_eq(events.length(), 2)
  assert_eq(reply.watermark, Some(2))
  assert_true(@fsx.is_dir(Path(store + "/archived/sessions/s-archived")))
  assert_false(@fsx.exists(Path(store + "/sessions/s-archived")))
  assert_true(manager.record_guards.is_empty())
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "load rejects a detached workspace hint instead of probing global" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let dir = @fs.tmpdir(prefix="openseek-load-detached-")
  let marker = dir + "/engine-ran"
  let engine = dir + "/engine.sh"
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", dir)
  defer restore_session_root_env(previous)
  @fsx.ensure_dir(Path(dir + "/sessions/s-detached"))
  @fs.write_file(
    engine,
    "#!/bin/sh\nprintf '' > '\{marker}'\nprintf '%s' '{\"events\":[]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let detail = try {
    ignore(
      load_session(manager, {
        session: "s-detached",
        workspace: Some(dir + "/detached-workspace"),
      }),
    )
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(detail.contains("not a registered workspace"))
  assert_false(@fsx.exists(Path(marker)))
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "workspace detach refuses a running conversation without hiding it" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  // The registry canonicalizes workspace paths, so build the fixture from
  // the tmpdir's physical spelling (`/tmp` is a symlink on macOS).
  let root : @pathx.Path = Path(
    @fs.realpath(@fs.tmpdir(prefix="openseek-detach-running-")),
  )
  let global_store = root.join("global")
  let workspace = root.join("workspace")
  let engine = root.join("bin/engine.sh")
  let runtime = root.join("runtime")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", global_store.to_string())
  defer restore_session_root_env(previous)
  @fsx.ensure_dir(workspace)
  prepare_fake_moonbit_seed(
    root.join("bin/toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then printf '%s' '{\"events\":[]}' ; exit 0; fi\nwhile IFS= read -r line; do sleep 30; done\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let actor = new_engine_actor(engine.to_string(), runtime_dir=runtime)
  let manager = actor.manager()
  ignore(
    update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://example.invalid/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: None,
    }),
  )
  let sink = EventSink(fn(_) { () })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) { () })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    ignore(attach_workspace(workspace.to_string(), fn(_) { () }))
    let reply = start_run(sink, manager, {
      task: "keep running",
      submission_id: None,
      model: None,
      max_steps: None,
      session: "s-detach-running",
      workspace: Some(workspace.to_string()),
    })
    assert_eq(reply.status, "accepted")
    let committed : Ref[Bool] = Ref(false)
    let detail = try {
      ignore(
        detach_workspace(manager, workspace.to_string(), fn(_) {
          committed.val = true
        }),
      )
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
    assert_true(detail.contains("still running"))
    assert_false(committed.val)
    guard workspace.to_absolute() is Some(workspace_path) else {
      fail("expected an absolute workspace fixture")
    }
    assert_true(@workspaces.registered().contains(workspace_path))
    group.return_immediately(())
  })
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "workspace detach drains an idle writer and its follower first" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  // The registry canonicalizes workspace paths, so build the fixture from
  // the tmpdir's physical spelling (`/tmp` is a symlink on macOS).
  let root : @pathx.Path = Path(
    @fs.realpath(@fs.tmpdir(prefix="openseek-detach-idle-")),
  )
  let global_store = root.join("global")
  let workspace = root.join("workspace")
  let engine = root.join("bin/engine.sh")
  let runtime = root.join("runtime")
  let exited = root.join("writer-exited")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", global_store.to_string())
  defer restore_session_root_env(previous)
  @fsx.ensure_dir(workspace)
  prepare_fake_moonbit_seed(
    root.join("bin/toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  // The serve branch commits a durable Terminal (the `settled` marker)
  // before echoing `agent_finished` — the real engine's append-then-emit
  // order — so the follower's scan settles the run and detach finds the
  // writer idle.
  let settled = root.join("settled")
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then\n  if [ -f '\{settled}' ]; then\n    printf '%s' '{\"events\":[{\"sequence\":1,\"ts\":4000000000000.0,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"finished\",\"message\":\"ok\"}}}]}'\n  else\n    printf '%s' '{\"events\":[]}'\n  fi\n  exit 0\nfi\nwhile IFS= read -r line; do printf '' > '\{settled}'; printf '%s\\n' '{\"event\":\"agent_finished\",\"answer\":\"ok\"}'; done\nprintf '' > '\{exited}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let actor = new_engine_actor(engine.to_string(), runtime_dir=runtime)
  let manager = actor.manager()
  ignore(
    update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://example.invalid/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: None,
    }),
  )
  let events : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { events.push(event) })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) { () })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    ignore(attach_workspace(workspace.to_string(), fn(_) { () }))
    let reply = start_run(sink, manager, {
      task: "finish",
      submission_id: None,
      model: None,
      max_steps: None,
      session: "s-detach-idle",
      workspace: Some(workspace.to_string()),
    })
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while !has_finished_run(events, reply.run_id) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    let committed : Ref[Bool] = Ref(false)
    let detached = detach_workspace(manager, workspace.to_string(), fn(_) {
      committed.val = true
    })
    assert_true(committed.val)
    assert_true(detached is Workspaces([]))
    assert_true(@fsx.exists(exited))
    assert_true(manager.followers.get("s-detach-idle") is None)
    guard manager.pump is Serving(sessions~) else {
      fail("engine pump stopped during detach")
    }
    assert_true(sessions.get("s-detach-idle") is None)
    group.return_immediately(())
  })
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
/// Both refusals land before the op can touch an engine, so no fake one is
/// needed — reaching a live engine is precisely what they must prevent.
async test "a goal request is refused before it can reach the wrong engine" {
  let manager = new_engine_manager("/nonexistent/engine")
  async fn refusal(payload : @protocol.GoalPayload) -> String {
    try {
      ignore(goal_run(manager, payload))
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
  }

  // Arming is not wired end to end, and this endpoint serves the relay: a
  // remote client must not be able to ask for what the app's own page no
  // longer offers.
  assert_true(
    refusal({
      session: "s-armed",
      text: Some("ship it"),
      auto: Some(true),
      model: None,
      max_steps: None,
      workspace: None,
    }).contains("autonomous goal continuation is not supported yet"),
  )
  // Manual, named: past the refusal and on to the engine, which is where a
  // nonexistent binary makes itself known.
  assert_false(
    refusal({
      session: "s-named",
      text: Some("ship it"),
      auto: None,
      model: None,
      max_steps: None,
      workspace: None,
    }).contains("not supported yet"),
  )
}
