// The idle reaper, exercised without waiting for its clock: `reap_idle_engines`
// takes "now" and the deadline as arguments, so each test states the instant
// it is asking about. The engines are real child processes — a shell that
// speaks just enough of the serve protocol — wired the way the pump wires
// one, so stopping one goes through the real stdin-EOF close and retirement.

///|
/// The deadline these tests reap against. Its size is irrelevant: every test
/// names its own clock.
#cfg(not(platform="windows"))
const TestIdleMs : Int64 = 1000L

///|
/// A serve stand-in. It answers a jobs snapshot request with `$1` (after
/// `$2` seconds), answers any other command with `$3`, and exits when its
/// stdin closes — the engine's documented shutdown.
#cfg(not(platform="windows"))
const FakeIdleEngineSh : String =
  #|snapshot=$1
  #|delay=$2
  #|other=$3
  #|while IFS= read -r line; do
  #|  case "$line" in
  #|    *jobs_snapshot*)
  #|      id=$(printf '%s\n' "$line" | sed 's/.*"request_id": *"\([^"]*\)".*/\1/')
  #|      sleep "$delay"
  #|      printf '%s\n' "$snapshot" | sed "s/__RID__/$id/"
  #|      ;;
  #|    *) printf '%s\n' "$other" ;;
  #|  esac
  #|done
  #|

///|
/// Spawn a stand-in engine into `sessions` and wire it as
/// `start_serve_engine` does: a writer task owning stdin, and the consumer
/// task whose completion is retirement. `jobs` is what it reports when asked;
/// `last_activity_ms` defaults to the epoch, i.e. idle since forever.
#cfg(not(platform="windows"))
async fn[G] start_fake_idle_engine(
  group : @async.TaskGroup[G],
  manager : EngineManager,
  sessions : Map[String, SessionSlot],
  session : String,
  sink~ : EventSink = EventSink(_ => ()),
  jobs~ : Array[@wire.JobRecord] = [],
  snapshot_delay~ : String = "0",
  phase~ : EnginePhase = Idle(last_run=None),
  last_activity_ms~ : Int64 = 0,
) -> ServeEngine {
  let (child_stdin, writer) = @process.write_to_process()
  let (reader, child_stdout) = @process.read_from_process()
  let snapshot : @wire.Event = JobsSnapshot(request_id="__RID__", jobs~)
  let other : @wire.Event = BackgroundNotice(content="a job finished")
  let process = @process.spawn(
    group,
    "/bin/sh",
    [
      "-c",
      FakeIdleEngineSh,
      "sh",
      snapshot.to_json().stringify(),
      snapshot_delay,
      other.to_json().stringify(),
    ],
    stdin=child_stdin,
    stdout=child_stdout,
    no_wait=true,
  )
  let engine = test_serve_engine(
    session,
    writer,
    process,
    sink,
    phase~,
    last_activity_ms~,
  )
  group.spawn_bg(no_wait=true, allow_failure=true, () => engine.write_commands())
  slot_for(sessions, session).engine = Some(engine)
  let stderr_task = group.spawn(no_wait=true, () => "")
  engine.consumer = Some(
    group.spawn(no_wait=true, allow_failure=true, () => {
      engine.run(manager, reader, stderr_task)
    }),
  )
  engine
}

///|
/// The deadline is per engine and inclusive: the one that reached it is
/// stopped through a clean close — reaped child, cleared slot, nothing said
/// to the conversation — and the one a millisecond short is untouched.
#cfg(not(platform="windows"))
async test "an engine idle for the whole deadline is stopped, a younger one is not" {
  let manager = new_engine_manager("/bin/sh")
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(event => emitted.push(event))
  @async.with_task_group(group => {
    let sessions : Map[String, SessionSlot] = Map([])
    manager.pump = Serving(sessions~)
    let old = start_fake_idle_engine(
      group,
      manager,
      sessions,
      "s-old",
      sink~,
      last_activity_ms=0,
    )
    let young = start_fake_idle_engine(
      group,
      manager,
      sessions,
      "s-young",
      sink~,
      last_activity_ms=1,
    )
    let reaped = manager.reap_idle_engines(now=TestIdleMs, idle_ms=TestIdleMs)
    assert_eq(reaped, ["s-old"])
    assert_true(old.condemned)
    assert_eq(old.process.wait(), 0)
    assert_true(sessions.get("s-old") is None)
    assert_true(
      sessions.get("s-young") is Some(slot) &&
      slot.live() is Some(live) &&
      physical_equal(live, young),
    )
    // An idle stop is not an event in the conversation's life.
    assert_true(emitted.is_empty())
  })
}

///|
/// Jobs are children of the serve process, and a finished one wakes its idle
/// engine. However old the engine's stamp, a job still in flight keeps it —
/// and asking about jobs must not itself count as activity, or every look
/// would push the deadline out for good.
///
/// So does a job that only just finished. Its state is terminal as soon as
/// the process exits, before the engine has published the record or queued
/// the completion notice, so "every job is terminal" is not yet "nothing more
/// is coming". A finish has to be a full deadline old, like any activity.
#cfg(not(platform="windows"))
async test "a job running, just finished or undated keeps its engine" {
  let manager = new_engine_manager("/bin/sh")
  @async.with_task_group(group => {
    let sessions : Map[String, SessionSlot] = Map([])
    manager.pump = Serving(sessions~)
    let settled : @wire.JobRecord = {
      ..job_record_fixture(),
      state: Exited(0),
      finished_at_ms: Some(0),
    }
    let running = start_fake_idle_engine(
      group,
      manager,
      sessions,
      "s-running-job",
      jobs=[settled, { ..job_record_fixture(), state: Running, id: "bg-2", }],
    )
    let fresh = start_fake_idle_engine(
      group,
      manager,
      sessions,
      "s-fresh-finish",
      jobs=[settled, { ..settled, id: "bg-2", finished_at_ms: Some(1), }],
    )
    let undated = start_fake_idle_engine(
      group,
      manager,
      sessions,
      "s-undated-finish",
      jobs=[{ ..settled, finished_at_ms: None, }],
    )
    ignore(
      start_fake_idle_engine(group, manager, sessions, "s-settled", jobs=[
        settled,
      ]),
    )
    let reaped = manager.reap_idle_engines(now=TestIdleMs, idle_ms=TestIdleMs)
    assert_eq(reaped, ["s-settled"])
    assert_false(running.condemned)
    assert_false(fresh.condemned)
    assert_false(undated.condemned)
    assert_eq(running.last_activity_ms, 0)
    // Still eligible on the next look, and still kept for the same reason;
    // one millisecond later the fresh finish is a deadline old.
    assert_eq(manager.reap_idle_engines(now=TestIdleMs, idle_ms=TestIdleMs), [])
    assert_eq(
      manager.reap_idle_engines(now=TestIdleMs + 1, idle_ms=TestIdleMs),
      ["s-fresh-finish"],
    )
  })
}

///|
/// Everything that says "this conversation is in use" without being a stamp:
/// an open turn, a compaction, an op that has claimed the slot, a follow-up
/// queued behind the turn.
#cfg(not(platform="windows"))
async test "a busy, compacting, claimed or queued engine is never stopped" {
  let manager = new_engine_manager("/bin/sh")
  @async.with_task_group(group => {
    let sessions : Map[String, SessionSlot] = Map([])
    manager.pump = Serving(sessions~)
    ignore(
      start_fake_idle_engine(
        group,
        manager,
        sessions,
        "s-running",
        phase=Running(run_id="r-1", compact_queued=false),
      ),
    )
    ignore(
      start_fake_idle_engine(
        group,
        manager,
        sessions,
        "s-compacting",
        phase=Compacting(last_run=None),
      ),
    )
    ignore(start_fake_idle_engine(group, manager, sessions, "s-claimed"))
    let claim = slot_for(sessions, "s-claimed").claim(
      sessions,
      "s-claimed",
      StartPending,
    )
    let queued = start_fake_idle_engine(group, manager, sessions, "s-queued")
    queued.queued_runs.push({
      id: "q-1",
      run_id: "r-2",
      content: Content([Text("next")]),
    })
    assert_eq(manager.reap_idle_engines(now=TestIdleMs, idle_ms=TestIdleMs), [])
    assert_eq(sessions.length(), 4)
    // The claim was the only thing holding that engine.
    claim.release(manager)
    assert_eq(manager.reap_idle_engines(now=TestIdleMs, idle_ms=TestIdleMs), [
      "s-claimed",
    ])
  })
}

///|
/// The stamp moves on both directions of the pipe: a command handed to the
/// writer, and an event the engine sends on its own account — the path a
/// background job's completion notice takes between turns.
#cfg(not(platform="windows"))
async test "a command to the engine and an event from it both reset its clock" {
  let manager = new_engine_manager("/bin/sh")
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(event => emitted.push(event))
  @async.with_task_group(group => {
    let sessions : Map[String, SessionSlot] = Map([])
    manager.pump = Serving(sessions~)
    let engine = start_fake_idle_engine(
      group,
      manager,
      sessions,
      "s-touched",
      sink~,
    )
    let before = engine_clock_ms()
    assert_true(engine.submit(GoalClear, failure_reason="test"))
    assert_true(engine.last_activity_ms >= before)
    // Forget the submission, so only the engine's answer can move the stamp.
    engine.last_activity_ms = 0
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while emitted.is_empty() {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    assert_true(engine.last_activity_ms >= before)
    assert_eq(
      manager.reap_idle_engines(
        now=engine_clock_ms(),
        idle_ms=EngineIdleTimeoutMs,
      ),
      [],
    )
    assert_false(engine.condemned)
  })
}

///|
/// Asking the engine about its jobs suspends the reaper, and the conversation
/// does not wait for it. A prompt accepted in that window opens a turn — one
/// synchronous step in `start_run` — and the reaper must see it when it looks
/// again rather than close the engine under the turn.
#cfg(not(platform="windows"))
async test "a prompt accepted while the reaper asks about jobs keeps its engine" {
  let manager = new_engine_manager("/bin/sh")
  @async.with_task_group(group => {
    let sessions : Map[String, SessionSlot] = Map([])
    manager.pump = Serving(sessions~)
    let engine = start_fake_idle_engine(
      group,
      manager,
      sessions,
      "s-raced",
      snapshot_delay="0.3",
    )
    let reaper = group.spawn(() => {
      manager.reap_idle_engines(now=TestIdleMs, idle_ms=TestIdleMs)
    })
    // The probe is in flight exactly while its reply queue is registered.
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while engine.job_requests.is_empty() {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    engine.phase = Running(run_id="r-raced", compact_queued=false)
    assert_eq(reaper.wait(), [])
    assert_false(engine.condemned)
    assert_true(sessions.get("s-raced") is Some(slot) && slot.live() is Some(_))
  })
}

///|
/// The same window, for activity that opens no turn: a goal command leaves the
/// engine `Idle` and claims nothing by the time the reaper looks again, so the
/// moved stamp is the only evidence that the engine was just used.
#cfg(not(platform="windows"))
async test "a command sent while the reaper asks about jobs keeps its engine" {
  let manager = new_engine_manager("/bin/sh")
  @async.with_task_group(group => {
    let sessions : Map[String, SessionSlot] = Map([])
    manager.pump = Serving(sessions~)
    let engine = start_fake_idle_engine(
      group,
      manager,
      sessions,
      "s-goal",
      snapshot_delay="0.3",
    )
    // A clock far enough ahead that the freshly stamped engine still reads
    // as past the deadline: only the changed stamp can save it.
    let now = engine_clock_ms() + 2L * TestIdleMs
    let reaper = group.spawn(() => {
      manager.reap_idle_engines(now~, idle_ms=TestIdleMs)
    })
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while engine.job_requests.is_empty() {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    assert_true(engine.submit(GoalClear, failure_reason="test"))
    assert_eq(reaper.wait(), [])
    assert_false(engine.condemned)
  })
}

///|
/// The whole point, end to end through the real pump and follower: a
/// conversation whose engine was stopped for idleness loses nothing. Its next
/// prompt spawns a fresh process on the same durable record, and the record's
/// commits reach clients exactly once each, in order — the stopped engine's
/// tail is not replayed and the new engine's first commit is not skipped.
#cfg(not(platform="windows"))
async test "a conversation resumes on a fresh engine after an idle stop" {
  let dir = @fs.tmpdir(prefix="openseek-idle-reap-")
  defer @fs.rmdir(dir, recursive=true)
  let root : @pathx.Path = Path(dir)
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
  let snapshot : @wire.Event = JobsSnapshot(request_id="__RID__", jobs=[])
  // A prompt commits one durable Terminal and reports the turn finished; a
  // jobs snapshot request is answered with no jobs; stdin EOF ends the loop.
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then printf '%s' '{\"events\":[]}'; exit 0; fi\nwhile IFS= read -r line; do\n  case \"$line\" in\n    *jobs_snapshot*)\n      id=$(printf '%s\\n' \"$line\" | sed 's/.*\"request_id\": *\"\\([^\"]*\\)\".*/\\1/')\n      printf '%s\\n' '\{snapshot.to_json().stringify()}' | sed \"s/__RID__/$id/\"\n      ;;\n    *)\n\{commit_terminal_sh()}      printf '%s\\n' '{\"event\":\"agent_finished\",\"answer\":\"ok\"}'\n      ;;\n  esac\ndone\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let actor = new_engine_actor(engine.to_string(), runtime_dir=runtime)
  let manager = actor.manager()
  configure_custom_provider(manager)
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(event => emitted.push(event))
  let session = "s-" + mint_run_id()
  async fn run_to_finish() -> Unit {
    let reply = start_run(
      sink,
      manager,
      test_start_payload("go", session~, workspace~),
    )
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while !has_finished_run(emitted, reply.run_id) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
  }

  fn committed() -> Array[Int32] {
    let sequences : Array[Int32] = []
    for event in emitted {
      if event is SessionCommit(payload) && payload.session == session {
        sequences.push(payload.sequence)
      }
    }
    sequences
  }

  @async.with_task_group(group => {
    serve_until_pumping(actor, manager, sink, group~)
    run_to_finish()
    guard manager.serving().get(session) is Some(slot) &&
      slot.live() is Some(first) else {
      fail("the first prompt left no live engine")
    }
    assert_eq(committed(), [1])
    // Just used: nowhere near the deadline.
    assert_eq(
      manager.reap_idle_engines(
        now=engine_clock_ms(),
        idle_ms=EngineIdleTimeoutMs,
      ),
      [],
    )
    // The same engine, as the clock reads once the deadline has passed.
    let said = emitted.length()
    assert_eq(
      manager.reap_idle_engines(
        now=engine_clock_ms() + EngineIdleTimeoutMs,
        idle_ms=EngineIdleTimeoutMs,
      ),
      [session],
    )
    assert_eq(first.process.wait(), 0)
    assert_true(manager.serving().get(session) is None)
    assert_true(manager.followers.get(session) is None)
    assert_eq(emitted.length(), said)
    // The next prompt needs no help from the client: it spawns its own engine.
    run_to_finish()
    guard manager.serving().get(session) is Some(slot) &&
      slot.live() is Some(second) else {
      fail("the second prompt left no live engine")
    }
    assert_false(physical_equal(first, second))
    assert_not_eq(first.process.pid, second.process.pid)
    assert_eq(committed(), [1, 2])
    group.return_immediately(())
  })
}
