///|
fn schedule_fixture(
  id : String,
  at : Int64,
  timing : @protocol.ScheduleTiming,
) -> @protocol.ScheduleEntry {
  {
    id,
    spec: {
      name: id,
      task: "inspect the project",
      workspace: Some("/workspace"),
      model: None,
      timing,
      timeout_minutes: 1,
    },
    enabled: true,
    run_requested: false,
    notice: None,
    next_at: Some(at),
  }
}

///|
async test "a scheduled run that left no session reports its exit code" {
  let folder = @fs.tmpdir(prefix="schedules-no-session-")
  defer @fs.rmdir(folder, recursive=true)
  let run : @protocol.ScheduleRun = {
    id: "r",
    schedule_id: "s",
    name: "s",
    // The run record holds a resource path (`/c:/…` on Windows), not a
    // native one.
    workspace: @pathx.Path(@fs.realpath(folder)).resolve().resource_path(),
    session: "scheduled-r",
    started_at: 1000,
    finished_at: None,
    status: Running,
    log_path: "/runtime/r.log",
  }
  assert_eq(
    scheduled_session_result(run, exit_code=3),
    Failed("CLI exited with code 3; see the run log"),
  )
}

///|
test "schedule recovery skips downtime without delaying a future deadline" {
  let future = schedule_fixture("future", 180000, Every(1))
  let missed = schedule_fixture("missed", 1000, Every(1))
  let once = schedule_fixture("once", 1000, Once(1000))
  let run : @protocol.ScheduleRun = {
    id: "r",
    schedule_id: "missed",
    name: "missed",
    workspace: "/workspace",
    session: "scheduled-r",
    started_at: 1000,
    finished_at: None,
    status: Running,
    log_path: "/runtime/r.log",
  }
  let state = recover_schedules(
    { entries: [future, missed, once], runs: [run], },
    120000,
  )
  assert_eq(state.entries[0].next_at, Some(180000))
  assert_eq(state.entries[1].next_at, Some(180000))
  assert_eq(state.entries[2].next_at, None)
  assert_false(state.entries[2].enabled)
  assert_true(state.runs[0].status is Interrupted)
  assert_eq(state.runs[0].finished_at, Some(120000))
}

///|
async test "schedule tick persists independent runs and caps concurrency without overlap" {
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="schedules-tick-"))
  defer @fs.rmdir(root.to_string(), recursive=true)
  let service = Schedules(new_engine_manager("unused"), Some(root))
  ignore(service.list())
  service.commit({
    entries: [
      for i in 0..<6 => schedule_fixture("p\{i}", 100000, Every(1))
    ],
    runs: [],
  })
  let launches = service.take_due(at=100000)
  assert_eq(launches.length(), 4)
  assert_eq(launches[0].1.session, "scheduled-" + launches[0].1.id)
  assert_true(launches[0].1.session != launches[1].1.session)
  assert_eq(service.take_due(at=160000).length(), 0)
  let state = service.list()
  assert_eq(state.runs.length(), 4)
  assert_true(state.entries.iter().all(entry => entry.next_at == Some(220000)))
  let disk = @fsx.read_text(root.join("schedules/schedules.json"))
  assert_true(disk.contains(launches[0].1.id))
  let restarted = Schedules(new_engine_manager("unused"), Some(root))
  let recovered = restarted.list()
  assert_eq(recovered.runs.length(), 4)
  assert_true(recovered.runs.iter().all(run => run.status is Interrupted))
  assert_eq(restarted.take_due().length(), 0)
}

///|
async test "schedule Run now preserves a paused plan and its future interval" {
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="schedules-manual-"))
  defer @fs.rmdir(root.to_string(), recursive=true)
  let service = Schedules(new_engine_manager("unused"), Some(root))
  ignore(service.list())
  let entry = schedule_fixture("p", 500000, Every(10))
  service.commit({ entries: [entry], runs: [], })
  ignore(service.action({ id: "p", action: "run", }))
  assert_eq(service.take_due(at=100000).length(), 1)
  assert_eq(service.list().entries[0].next_at, Some(500000))
  // Stop before process spawn must be retained for the worker.
  let state = service.action({ id: "p", action: "stop", })
  assert_true(service.stopped.contains(state.runs[0].id))
  service.commit({
    entries: [{ ..entry, enabled: false, next_at: None, }],
    runs: [],
  })
  ignore(service.action({ id: "p", action: "run", }))
  assert_eq(service.take_due(at=100000).length(), 1)
  assert_false(service.list().entries[0].enabled)
  assert_eq(service.list().entries[0].next_at, None)
}

///|
async test "schedule sleep gap skips old ticks and corrupt persistence is never erased" {
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="schedules-recovery-"))
  defer @fs.rmdir(root.to_string(), recursive=true)
  let service = Schedules(new_engine_manager("unused"), Some(root))
  ignore(service.list())
  service.commit({
    entries: [schedule_fixture("old", 1000, Every(1))],
    runs: [],
  })
  assert_eq(service.take_due(at=200000).length(), 0)
  assert_eq(service.list().entries[0].next_at, Some(260000))
  let path = root.join("schedules/schedules.json")
  @fs.write_file(path.to_string(), "broken", create_mode=CreateOrTruncate)
  let other = Schedules(new_engine_manager("unused"), Some(root))
  let failed = try {
    ignore(other.list())
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_eq(@fsx.read_text(path), "broken")
}

///|
#cfg(not(platform="windows"))
async test "scheduled CLI writes bounded-memory logs and settles an independent run" {
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="schedules-cli-"))
  defer @fs.rmdir(root.to_string(), recursive=true)
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_home_env(previous_home)
  let workspace = attach_run_workspace(root)
  let engine = root.join("bin/engine.sh")
  let repository = root.join("repository")
  assert_eq(@process.run("git", ["init", "--quiet", repository.to_string()]), 0)
  assert_eq(
    @process.run("git", [
      "-C",
      repository.to_string(),
      "-c",
      "user.name=Test",
      "-c",
      "user.email=test@example.test",
      "commit",
      "--quiet",
      "--allow-empty",
      "-m",
      "fixture",
    ]),
    0,
  )
  let checkout = root.join("checkout")
  assert_eq(
    @process.run("git", [
      "-C",
      repository.to_string(),
      "worktree",
      "add",
      "--quiet",
      "--detach",
      checkout.to_string(),
    ]),
    0,
  )
  let runtime = checkout.join("runtime")
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
    "#!/bin/sh\nprintf '%s\\n' \"$@\"\nprintf 'stderr marker\\n' >&2\nexit 0\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let manager = new_engine_manager(engine.to_string(), runtime_dir=runtime)
  configure_custom_provider(manager)
  let service = Schedules(manager, Some(runtime))
  ignore(service.list())
  let entry = schedule_fixture("cli", 100000, Once(100000))
  let entry = {
    ..entry,
    spec: {
      ..entry.spec,
      workspace: Some(workspace),
      task: "--literal prompt\nsecond line",
    },
  }
  service.commit({ entries: [entry], runs: [], })
  let launches = service.take_due(at=100000)
  assert_eq(launches.length(), 1)
  let session_store = @store.SessionStore(workspace + "/.openseek")
  session_store.create(
    @agent_session.Session(
      SessionId(launches[0].1.session),
      system_prompt="test",
    ).append(Terminal(Finished("done"))),
  )
  service.execute(launches[0].0, launches[0].1)
  let run = service.list().runs[0]
  assert_true(run.status is Succeeded)
  assert_true(run.finished_at is Some(_))
  let log = @fsx.read_text(Path(run.log_path))
  assert_true(log.contains("run\n--session=scheduled-"))
  assert_true(log.contains("--approval=never\n"))
  assert_true(log.contains("--literal prompt\nsecond line"))
  assert_true(log.contains("stderr marker"))

  let automatic = service.save({
      id: None,
      spec: {
        ..entry.spec,
        name: "Automatic",
        workspace: None,
        timing: Every(30),
      },
      run_now: true,
    }).entries[1]
  assert_true(automatic.run_requested)
  let first = service.take_due()[0]
  assert_eq(service.list().entries[1].next_at, automatic.next_at)
  let folder = @pathx.Absolute::from_uri_path(first.1.workspace).unwrap()
  assert_false(@fsx.is_dir(folder.to_path()))
  assert_false(folder.to_string().has_prefix(checkout.to_string()))
  assert_true(@gitx.is_linked_worktree(runtime.resolve()))
  let directory_notifications : Array[Array[String]] = []
  service.execute(first.0, first.1, on_workspaces=paths => {
    directory_notifications.push(paths)
  })
  assert_eq(directory_notifications.length(), 1)
  assert_true(
    directory_notifications[0].contains(
      @pathx.Path(@fs.realpath(folder.to_string())).resolve().resource_path(),
    ),
  )
  assert_true(@fsx.is_dir(folder.to_path()))
  assert_false(@gitx.is_linked_worktree(folder))
  assert_true(@workspaces.registered_dir(folder) is Some(_))
  assert_true(@fsx.read_text(Path(first.1.log_path)).contains("stderr marker"))
  @fsx.write_text(folder.to_path().join("progress.txt"), "keep this progress")
  ignore(service.action({ id: automatic.id, action: "run", }))
  let second = service.take_due()[0]
  assert_eq(second.1.workspace, first.1.workspace)
  assert_true(second.1.session != first.1.session)
  service.execute(second.0, second.1)
  assert_eq(
    @fsx.read_text(folder.to_path().join("progress.txt")),
    "keep this progress",
  )
}

///|
#cfg(not(platform="windows"))
async test "scheduled run Stop and timeout reap CLI processes" {
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="schedules-cancel-"))
  defer @fs.rmdir(root.to_string(), recursive=true)
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_home_env(previous_home)
  let workspace = attach_run_workspace(root)
  let engine = root.join("bin/engine.sh")
  let runtime = root.join("runtime")
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
    "#!/bin/sh\nexec sleep 30\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let manager = new_engine_manager(engine.to_string(), runtime_dir=runtime)
  configure_custom_provider(manager)
  let service = Schedules(manager, Some(runtime))
  ignore(service.list())
  let entry = schedule_fixture("cancel", 100000, Every(1))
  let entry = { ..entry, spec: { ..entry.spec, workspace: Some(workspace), }, }
  service.commit({ entries: [entry], runs: [], })
  let launches = service.take_due(at=100000)
  let events : Array[EngineEvent] = []
  let unleased_commit = Ref(false)
  let sink = EventSink(event => {
    events.push(event)
    if event is SessionCommit(_) {
      try {
        let lease = manager.begin_record_op(launches[0].1.session)
        manager.end_record_op(launches[0].1.session, lease)
        unleased_commit.val = true
      } catch {
        _ => ()
      }
    }
  })
  @async.with_task_group(group => {
    let worker = group.spawn(() => {
      service.execute(launches[0].0, launches[0].1, sink~)
    })
    @async.with_timeout(5000, () => {
      while !service.processes.contains(launches[0].1.id) {
        @async.sleep(10)
      }
    })
    let run = launches[0].1
    let store = @store.SessionStore(workspace + "/.openseek")
    store.create(
      @agent_session.Session(SessionId(run.session), system_prompt="test").append(
        Terminal(Finished("tail proof")),
      ),
    )
    @async.with_timeout(5000, () => {
      while !events.any(event => event is SessionCommit(_)) {
        @async.sleep(10)
      }
    })
    let loaded = load_session(manager, {
      session: run.session,
      workspace: Some(workspace),
    })
    assert_true(loaded.watermark is Some(n) && n > 0)
    let blocked = try {
      let lease = manager.begin_record_op(run.session)
      manager.end_record_op(run.session, lease)
      false
    } catch {
      _ => true
    }
    assert_true(blocked)
    let commits_before_stop = events.length()
    ignore(
      store.append(
        store.load(SessionId(run.session)),
        Terminal(Finished("last commit before stop")),
      ),
    )
    ignore(service.action({ id: entry.id, action: "stop", }))
    @async.with_timeout(5000, () => worker.wait())
    assert_true(events.length() > commits_before_stop)
    assert_false(unleased_commit.val)
    assert_false(manager.followers.contains(run.session))
  })
  assert_true(service.list().runs[0].status is Stopped)
  assert_true(service.processes.is_empty())
  let timed = service.take_due(at=160000)
  assert_eq(timed.length(), 1)
  service.execute(timed[0].0, timed[0].1, timeout_ms=500)
  assert_true(service.list().runs[1].status is TimedOut)
  assert_true(service.processes.is_empty())

  // Simulate a CLI unwinding a tool's cleanup beyond the old one-second
  // outer deadline. Its cleanup must complete before the slot is released.
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\ntrap 'sleep 2; echo cleanup-finished; exit 0' TERM\necho ready\nwhile :; do sleep 0.1; done\n",
    create_mode=CreateOrTruncate,
  )
  let cleanup = service.take_due(at=220000)[0]
  @async.with_task_group(group => {
    let worker = group.spawn(() => service.execute(cleanup.0, cleanup.1))
    @async.with_timeout(5000, () => {
      while !@fsx.read_text_if_exists(Path(cleanup.1.log_path)).map_or(false, text => {
              text.contains("ready")
            }) {
        @async.sleep(10)
      }
    })
    ignore(service.action({ id: entry.id, action: "stop", }))
    @async.with_timeout(5000, () => worker.wait())
  })
  assert_true(service.list().runs[2].status is Stopped)
  assert_true(
    @fsx.read_text(Path(cleanup.1.log_path)).contains("cleanup-finished"),
  )
}

///|
async test "schedule setup failure creates a readable diagnostic log" {
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="schedule-setup-"))
  defer @fs.rmdir(root.to_string(), recursive=true)
  let service = Schedules(new_engine_manager("unused"), Some(root))
  ignore(service.list())
  let entry = schedule_fixture("setup", 100000, Once(100000))
  service.commit({ entries: [entry], runs: [], })
  let (entry, run) = service.take_due(at=100000)[0]
  service.execute(entry, run)
  assert_true(service.list().runs[0].status is Failed(_))
  assert_true(@fsx.read_text(Path(run.log_path)).contains("Failed:"))
}

///|
test "scheduled run status reads the turn outcome whatever the exit code" {
  assert_eq(schedule_run_status(Some(Finished("done")), exit_code=0), Succeeded)
  // The CLI exits 1 for an incomplete turn; the reason comes from the session.
  assert_eq(
    schedule_run_status(Some(MaxStepsExhausted), exit_code=1),
    Failed("max steps exhausted"),
  )
  assert_eq(
    schedule_run_status(Some(Aborted("gave up")), exit_code=1),
    Failed("gave up"),
  )
  assert_eq(
    schedule_run_status(Some(Interrupted("cancelled")), exit_code=1),
    Interrupted,
  )
  assert_true(
    schedule_run_status(Some(ContextYield("[context ceiling] x")), exit_code=1)
    is Failed(_),
  )
  // No terminal: only the exit code is left to report.
  assert_eq(
    schedule_run_status(None, exit_code=3),
    Failed("CLI exited with code 3; see the run log"),
  )
  assert_eq(
    schedule_run_status(None, exit_code=0),
    Failed("CLI exited without a completed session; see the run log"),
  )
}
