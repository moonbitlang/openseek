///|
/// Parent-runner tests against SCRIPTED children: any process that speaks
/// the contract (JSONL events on stdout, a final `subrun_report` line,
/// stdin EOF as cancel) exercises spawn/drain/deadline/teardown without a
/// model or a built binary — the same hermetic trick the MCP stdio tests
/// use. Skips cleanly where the sandbox forbids spawning `sh`.
fn parse_answer(json : Json) -> Result[String, String] {
  match json {
    { "answer": String(answer), .. } => Ok(answer)
    _ => Err("answer must be a string")
  }
}

///|
async fn run_script(
  script : String,
  wall_deadline_ms? : Int = 10_000,
  emit_event? : (@protocol.Event) -> Unit,
) -> @agent_subrun.SubrunResult[String] {
  @agent_subrun.run_subrun(
    command="sh",
    args=["-c", script],
    input={ "query": "q" },
    parse_report=parse_answer,
    wall_deadline_ms~,
    kind="test-kind",
    label="scripted child",
    emit_event?,
  )
}

///|
/// One-time spawnability probe: a trivial child that must succeed wherever
/// `sh` can spawn at all. Tests guard on THIS and then assert hard — a
/// skip-on-Failed guard inside a real test would silently hide a regression
/// that wrongly folds stream errors into Failed (review finding).
async fn can_spawn_sh() -> Bool {
  let script =
    #|read line
    #|printf '{"subrun_report": {"answer": "probe"}}\n'
  // The probe must never throw: under fork pressure (EAGAIN) or a
  // spawn-hostile sandbox it reports false and the test skips.
  let result = run_script(script) catch { _ => return false }
  result.value() is Some("probe")
}

///|
/// A child that could not even spawn is a Failed terminal, not a crash.
async test "a spawn failure folds into Failed" {
  let events : Array[@protocol.Event] = []
  let result = @agent_subrun.run_subrun(
    command="/nonexistent/openseek-not-here",
    args=[],
    input={ "query": "q" },
    parse_report=parse_answer,
    wall_deadline_ms=2_000,
    kind="test-kind",
    label="spawn failure",
    emit_event=bracket_collector(events),
  )
  guard events is [SubrunStarted(..), SubrunFinished(status=bracket_status, ..)] else {
    fail("expected one bracket pair, got \{Repr(events)}")
  }
  guard result.terminal() is Failed(reason) else {
    // Some sandboxes surface spawn refusal as an immediate empty exit:
    // accept NoReport there but never a hang or crash.
    assert_true(result.terminal() is NoReport)
    assert_eq(bracket_status, "no_report")
    return
  }
  assert_true(reason.contains("spawn") || reason.contains("subrun"))
  assert_eq(bracket_status, "failed")
}

///|
async test "events and the report line are drained and accounted" {
  let script =
    #|read line
    #|printf '{"event":"agent_step","step":1}\n'
    #|printf 'not json at all\n'
    #|printf '{"event":"usage","usage":{"prompt_tokens":90,"completion_tokens":10,"total_tokens":100,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":90}}\n'
    #|printf '{"event":"agent_step","step":2}\n'
    #|printf '{"event":"usage","usage":{"prompt_tokens":95,"completion_tokens":5,"total_tokens":100,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":95}}\n'
    #|printf '{"subrun_report": {"answer": "forty-two"}}\n'
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let result = run_script(script)
  assert_true(result.value() is Some("forty-two"))
  debug_inspect(result.terminal(), content="Captured")
  assert_eq(result.steps_used(), 2)
  assert_eq(result.prompt_tokens(), 185)
  assert_eq(result.completion_tokens(), 15)
}

///|
async test "a clean exit without a report is NoReport" {
  let script =
    #|read line
    #|printf '{"event":"agent_step","step":1}\n'
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let events : Array[@protocol.Event] = []
  let result = run_script(script, emit_event=bracket_collector(events))
  assert_true(result.value() is None)
  debug_inspect(result.terminal(), content="NoReport")
  guard events is [SubrunStarted(..), SubrunFinished(status="no_report", ..)] else {
    fail("expected a no_report pair, got \{Repr(events)}")
  }
}

///|
async test "an observed step exhaustion without a report is MaxSteps" {
  let script =
    #|read line
    #|printf '{"event":"max_steps_exhausted"}\n'
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let events : Array[@protocol.Event] = []
  let result = run_script(script, emit_event=bracket_collector(events))
  debug_inspect(result.terminal(), content="MaxSteps")
  guard events is [SubrunStarted(..), SubrunFinished(status="max_steps", ..)] else {
    fail("expected a max_steps pair, got \{Repr(events)}")
  }
}

///|
async test "a garbled report is Failed, never rendered" {
  let script =
    #|read line
    #|printf '{"subrun_report": {"answer": 42}}\n'
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let result = run_script(script)
  assert_true(result.value() is None)
  guard result.terminal() is Failed(reason) else { fail("expected Failed") }
  assert_true(reason.contains("report rejected"))
}

///|
/// The deadline closes stdin (graceful cancel); a child that answers the
/// EOF with its report inside the grace window still counts as Captured.
async test "a report arriving in the cancel grace window still captures" {
  let script =
    #|read line
    #|read _ignored
    #|printf '{"subrun_report": {"answer": "flushed on eof"}}\n'
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let result = run_script(script, wall_deadline_ms=300)
  assert_true(result.value() is Some("flushed on eof"))
  debug_inspect(result.terminal(), content="Captured")
}

///|
/// A child that ignores the graceful cancel is terminated after the grace
/// and reported TimedOut.
async test "a stalling child times out after deadline and grace" {
  let script =
    #|read line
    #|sleep 60
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let result = run_script(script, wall_deadline_ms=300)
  assert_true(result.value() is None)
  debug_inspect(result.terminal(), content="TimedOut")
}

///|
/// External cancellation must RE-RAISE out of run_subrun, never fold into a
/// terminal. Pinned by awaiting the cancelled task directly: a runner that
/// swallowed the cancellation would complete with a SubrunResult and fail
/// this test. (An outer with_timeout_opt cannot pin this — it returns None
/// whether or not the body re-raised; review finding.)
async test "external cancellation re-raises out of the runner" {
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let script =
    #|read line
    #|sleep 60
  @async.with_task_group() <| group => {
    let task = group.spawn(() => run_script(script, wall_deadline_ms=30_000))
    @async.sleep(300)
    task.cancel()
    let mut reraised = false
    let outcome : @agent_subrun.SubrunResult[String]? = Some(task.wait()) catch {
      error => {
        reraised = @async.is_cancellation_error(error) ||
          @async.is_being_cancelled()
        None
      }
    }
    assert_true(reraised)
    assert_true(outcome is None)
  }
}

///|
/// The input pipe must stay OPEN after the write — stdin EOF is the cancel
/// signal, so a runner that closes it early cancels every child at startup.
/// Pinned via exit-status classification: this child exits 7 the moment its
/// stdin closes. Held open, that happens only when the DEADLINE closes it,
/// inside the grace window -> TimedOut. Closed early, the child exits 7
/// before the deadline -> the normal path reads exit status -> Failed.
async test "the input pipe stays open until the deadline" {
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let script =
    #|read line
    #|read second || exit 7
    #|exit 7
  let result = run_script(script, wall_deadline_ms=500)
  assert_true(result.value() is None)
  debug_inspect(result.terminal(), content="TimedOut")
}

///|
/// A crash-class child — nonzero exit, no failure event, no report — is
/// classified Failed via its exit status, never NoReport.
async test "a nonzero exit without a report is Failed by exit status" {
  let script =
    #|read line
    #|exit 3
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let result = run_script(script)
  guard result.terminal() is Failed(reason) else { fail("expected Failed") }
  assert_true(reason.contains("exited 3"))
}

///|
/// Collect the subrun bracket events one run emits, in order.
fn bracket_collector(
  into : Array[@protocol.Event],
) -> (@protocol.Event) -> Unit {
  event => {
    match event {
      SubrunStarted(..) | SubrunFinished(..) => into.push(event)
      _ => ()
    }
  }
}

///|
async test "a run emits a matched started/finished bracket pair" {
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let script =
    #|read line
    #|printf '{"event":"agent_step","step":2}\n'
    #|printf '{"event":"usage","usage":{"prompt_tokens":90,"completion_tokens":10,"total_tokens":100,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":90}}\n'
    #|printf '{"subrun_report": {"answer": "forty-two"}}\n'
  let events : Array[@protocol.Event] = []
  let result = run_script(script, emit_event=bracket_collector(events))
  debug_inspect(result.terminal(), content="Captured")
  guard events
    is [
      SubrunStarted(id=started_id, kind="test-kind", label="scripted child"),
      SubrunFinished(
        id=finished_id,
        status="captured",
        steps=2,
        prompt_tokens=90,
        completion_tokens=10
      ),
    ] else {
    fail("expected exactly one started/finished pair, got \{Repr(events)}")
  }
  assert_eq(started_id, finished_id)
}

///|
async test "a timed-out run still closes its bracket" {
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let script =
    #|read line
    #|sleep 60
  let events : Array[@protocol.Event] = []
  let result = run_script(
    script,
    wall_deadline_ms=300,
    emit_event=bracket_collector(events),
  )
  debug_inspect(result.terminal(), content="TimedOut")
  guard events is [SubrunStarted(..), SubrunFinished(status="timed_out", ..)] else {
    fail("expected a timed_out pair, got \{Repr(events)}")
  }
}

///|
/// Cancellation must still close the bracket — emitted BEFORE the re-raise,
/// so a reader never shows the sub-run as running forever.
async test "external cancellation closes the bracket before re-raising" {
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let script =
    #|read line
    #|sleep 60
  let events : Array[@protocol.Event] = []
  @async.with_task_group() <| group => {
    let task = group.spawn(() => {
      run_script(
        script,
        wall_deadline_ms=30_000,
        emit_event=bracket_collector(events),
      )
    })
    @async.sleep(300)
    task.cancel()
    let _ = Some(task.wait()) catch { _ => None }
  }
  guard events is [SubrunStarted(..), SubrunFinished(status="cancelled", ..)] else {
    fail("expected a cancelled pair, got \{Repr(events)}")
  }
}

///|
async test "sub-run ids are unique across runs" {
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let script =
    #|read line
    #|printf '{"subrun_report": {"answer": "ok"}}\n'
  let events : Array[@protocol.Event] = []
  let _ = run_script(script, emit_event=bracket_collector(events))
  let _ = run_script(script, emit_event=bracket_collector(events))
  guard events
    is [
      SubrunStarted(id=first, ..),
      SubrunFinished(id=first_done, ..),
      SubrunStarted(id=second, ..),
      SubrunFinished(id=second_done, ..),
    ] else {
    fail("expected two pairs, got \{Repr(events)}")
  }
  assert_true(first != second)
  assert_eq(first, first_done)
  assert_eq(second, second_done)
}

///|
async test "an observed context yield closes with its status" {
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let script =
    #|read line
    #|printf '{"event":"context_yield","to_sequence":9,"answer":"partial"}\n'
  let events : Array[@protocol.Event] = []
  let result = run_script(script, emit_event=bracket_collector(events))
  debug_inspect(result.terminal(), content="ContextYield")
  guard events
    is [SubrunStarted(..), SubrunFinished(status="context_yield", ..)] else {
    fail("expected a context_yield pair, got \{Repr(events)}")
  }
}

///|
/// With a `ChildSession` the runner appends the child's durable-session
/// argv AFTER allocating the sub-run id: the scripted child's positional
/// view of its own argv pins both flag names and the `<parent>-<id>`
/// derivation, and the result carries the same id.
async test "child_session appends session argv derived from the sub-run id" {
  let script =
    #|read line
    #|printf '{"subrun_report": {"answer": "%s %s %s %s"}}\n' "$0" "$1" "$2" "$3"
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let result = @agent_subrun.run_subrun(
    command="sh",
    args=["-c", script],
    input={ "query": "q" },
    parse_report=parse_answer,
    wall_deadline_ms=10_000,
    kind="test-kind",
    label="argv probe",
    child_session=ChildSession(root="/tmp/subrun-root", parent="parent-id"),
  )
  guard result.value() is Some(argv) else {
    fail("expected a captured report, got \{Repr(result.terminal())}")
  }
  assert_eq(
    argv,
    "--session parent-id-\{result.subrun_id()} --session-root /tmp/subrun-root",
  )
}

///|
/// The ChildSession ordinal floor bumps the process counter monotonically:
/// a resumed parent that scanned 49_999 persisted children never hands out
/// a session id an earlier process already used. (The floor is absurdly
/// high so no other test's allocations can reach it first.)
async test "child_session's ordinal floor skips persisted ids" {
  let script =
    #|read line
    #|printf '{"subrun_report": {"answer": "%s"}}\n' "$1"
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let result = @agent_subrun.run_subrun(
    command="sh",
    args=["-c", script],
    input={ "query": "q" },
    parse_report=parse_answer,
    wall_deadline_ms=10_000,
    kind="test-kind",
    label="ordinal floor",
    child_session=ChildSession(
      root="/tmp/subrun-root",
      parent="resumed",
      first_free=50_000,
    ),
  )
  guard result.value() is Some(session_arg) else {
    fail("expected a captured report, got \{Repr(result.terminal())}")
  }
  // $1 is the --session value: parent + the allocated id, at or past the floor.
  assert_eq(session_arg, "resumed-\{result.subrun_id()}")
  guard result.subrun_id().strip_prefix("sr-") is Some(digits) else {
    fail("unexpected subrun id \{result.subrun_id()}")
  }
  let mut ordinal = 0
  for c in digits {
    ordinal = ordinal * 10 + (c.to_int() - '0'.to_int())
  }
  assert_true(ordinal >= 50_000)
}
