///|
/// Parent-runner tests against SCRIPTED children: any process that speaks
/// transport 2 of the workflow child contract (one request line on stdin,
/// stdin EOF as cancel, one result file) exercises spawn/deadline/teardown
/// without a model or a built binary — the same hermetic trick the MCP
/// stdio tests use. Skips cleanly where the sandbox forbids spawning `sh`.
///
/// Every scripted child starts with `child_preamble`: it reads the request,
/// keeps the result path (`$1`, from `{result_file}`) as `$RESULT` and the
/// request id as `$id`, and `result FIELDS` writes a result answering it.
let child_preamble : String =
  #|read line
  #|RESULT=$1
  #|id=$(printf '%s' "$line" | sed -e 's/.*"request_id":"\([^"]*\)".*/\1/')
  #|result() { printf '{"version":1,"request_id":"%s",%s}' "$id" "$1" > "$RESULT"; }
  #|

///|
fn parse_answer(json : Json) -> Result[String, String] {
  match json {
    { "answer": String(answer), .. } => Ok(answer)
    _ => Err("answer must be a string")
  }
}

///|
async fn run_script(
  script : String,
  wall_deadline_ms~ : Int32 = 10_000,
  child_session? : @agent_subrun.ChildSession,
  emit_event? : (@protocol.Event) -> Unit,
) -> @agent_subrun.SubrunResult[String] {
  @agent_subrun.run_subrun(
    command="sh",
    args=["-c", child_preamble + script, "sh", @spawn.ResultFilePlaceholder],
    input={ "query": "q" },
    parse_report=parse_answer,
    wall_deadline_ms~,
    kind="test-kind",
    label="scripted child",
    child_session?,
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
    #|result '"status":"completed","output":{"answer":"probe"}'
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
    args=[@spawn.ResultFilePlaceholder],
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
    fail("expected Failed, got \{Repr(result.terminal())}")
  }
  // Some sandboxes surface spawn refusal as an immediate failed exit.
  assert_true(reason.contains("spawn") || reason.contains("exited"))
  assert_eq(bracket_status, "failed")
}

///|
async test "the result file is the report and the account; stdout is not read" {
  // Under the old stdout contract the first two lines would have counted.
  let script =
    #|printf '{"subrun_report": {"answer": "forged"}}\n'
    #|printf '{"event":"usage","usage":{"prompt_tokens":999,"completion_tokens":1,"total_tokens":1000,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":999}}\n'
    #|result '"status":"completed","output":{"answer":"forty-two"},"usage":{"prompt_tokens":185,"completion_tokens":15,"total_tokens":200,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":185},"steps":2'
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
async test "a result without a report is NoReport" {
  let script =
    #|result '"status":"no_report"'
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
async test "step exhaustion without a report is MaxSteps" {
  let script =
    #|result '"status":"max_steps_exhausted"'
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
    #|result '"status":"completed","output":{"answer":42}'
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
    #|read _ignored
    #|result '"status":"completed","output":{"answer":"flushed on eof"}'
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let result = run_script(script, wall_deadline_ms=300)
  assert_true(result.value() is Some("flushed on eof"))
  debug_inspect(result.terminal(), content="Captured")
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
    #|read second || exit 7
    #|exit 7
  let result = run_script(script, wall_deadline_ms=500)
  assert_true(result.value() is None)
  debug_inspect(result.terminal(), content="TimedOut")
}

///|
/// A crash-class child — nonzero exit, no result — is classified Failed via
/// its exit status, never success.
async test "a nonzero exit without a result is Failed by exit status" {
  let script =
    #|exit 3
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let result = run_script(script)
  guard result.terminal() is Failed(reason) else { fail("expected Failed") }
  assert_true(reason.contains("exited 3"))
  // The child may have spent anything before it died.
  assert_eq(result.unaccounted(), Some("the child left no result"))
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
    #|result '"status":"completed","output":{"answer":"forty-two"},"usage":{"prompt_tokens":90,"completion_tokens":10,"total_tokens":100,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":90},"steps":2'
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
        completion_tokens=10,
        unaccounted=None
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
    #|sleep 60
  let events : Array[@protocol.Event] = []
  let result = run_script(
    script,
    wall_deadline_ms=300,
    emit_event=bracket_collector(events),
  )
  assert_true(result.value() is None)
  debug_inspect(result.terminal(), content="TimedOut")
  guard events is [SubrunStarted(..), SubrunFinished(status="timed_out", ..)] else {
    fail("expected a timed_out pair, got \{Repr(events)}")
  }
}

///|
/// External cancellation must RE-RAISE out of run_subrun, never fold into a
/// terminal. Pinned by awaiting the cancelled task directly: a runner that
/// swallowed the cancellation would complete with a SubrunResult and fail
/// this test. (An outer with_timeout_opt cannot pin this — it returns None
/// whether or not the body re-raised; review finding.)
///
/// Cancellation must still close the bracket — emitted BEFORE the re-raise,
/// so a reader never shows the sub-run as running forever.
async test "external cancellation closes the bracket before re-raising" {
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let script =
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
    let mut reraised = false
    let outcome : @agent_subrun.SubrunResult[String]? = Some(task.wait()) catch {
      error => {
        reraised = error is @async.WaitedTaskAlreadyCancelled
        None
      }
    }
    assert_true(reraised)
    assert_true(outcome is None)
  }
  // A result-file child's spend is known only from its result: a cancelled
  // one's is unknown, never zero.
  guard events
    is [
      SubrunStarted(..),
      SubrunFinished(status="cancelled", unaccounted=Some(_), ..),
    ] else {
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
    #|result '"status":"completed","output":{"answer":"ok"}'
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
async test "a context yield closes with its status" {
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let script =
    #|result '"status":"context_yield","reason":"partial"'
  let events : Array[@protocol.Event] = []
  let result = run_script(script, emit_event=bracket_collector(events))
  debug_inspect(result.terminal(), content="ContextYield")
  guard events
    is [SubrunStarted(..), SubrunFinished(status="context_yield", ..)] else {
    fail("expected a context_yield pair, got \{Repr(events)}")
  }
}

///|
/// With a `ChildSession` the runner claims the child's session and appends
/// its argv AFTER allocating the sub-run id: the scripted child's positional
/// view of its own argv pins the flag names, the `<parent>-<id>`
/// derivation and the claim token, and the result carries the same id.
async test "child_session claims the session and appends its argv" {
  let script =
    #|result "\"status\":\"completed\",\"output\":{\"answer\":\"$2 $3 $4 $5 $6 $7\"}"
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let root = @fs.tmpdir(prefix="openseek-subrun-claim-")
  defer @fs.rmdir(root, recursive=true)
  let result = run_script(
    script,
    child_session=ChildSession(root~, parent="parent-id"),
  )
  guard result.value() is Some(argv) else {
    fail("expected a captured report, got \{Repr(result.terminal())}")
  }
  let session = "parent-id-\{launched_id(result)}"
  guard argv.split(" ").collect() is [.. prefix, token] else {
    fail("unexpected argv \{argv}")
  }
  assert_eq(prefix.map(part => part.to_owned()), [
    "--session", session, "--session-root", root, "--claim",
  ])
  // The scripted child does not accept its claim, so the claim is still
  // there, for the token the child was given.
  assert_eq(token.length(), 32)
  @store.SessionStore(root).accept_claim(SessionId(session), token.to_owned())
}

///|
/// The ChildSession ordinal floor bumps the process counter monotonically:
/// a resumed parent that scanned 49_999 persisted children never hands out
/// a session id an earlier process already used. (The floor is absurdly
/// high so no other test's allocations can reach it first.)
async test "child_session's ordinal floor skips persisted ids" {
  let script =
    #|result "\"status\":\"completed\",\"output\":{\"answer\":\"$3\"}"
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let root = @fs.tmpdir(prefix="openseek-subrun-floor-")
  defer @fs.rmdir(root, recursive=true)
  let result = run_script(
    script,
    child_session=ChildSession(root~, parent="resumed", first_free=50_000),
  )
  guard result.value() is Some(session_arg) else {
    fail("expected a captured report, got \{Repr(result.terminal())}")
  }
  // $3 is the --session value: parent + the allocated id, at or past the floor.
  assert_eq(session_arg, "resumed-\{launched_id(result)}")
  assert_true(ordinal_of(launched_id(result)) >= 50_000)
}

///|
/// The id of the child a sub-run launched; every launch has one.
fn[T] launched_id(result : @agent_subrun.SubrunResult[T]) -> String raise {
  guard result.subrun_id() is Some(id) else {
    fail("expected a launched child, got \{Repr(result.terminal())}")
  }
  id
}

///|
fn ordinal_of(subrun_id : String) -> Int32 raise {
  guard subrun_id.strip_prefix("sr-") is Some(digits) else {
    fail("unexpected subrun id \{subrun_id}")
  }
  let mut ordinal = 0
  for c in digits {
    ordinal = ordinal * 10 + (c.to_int() - '0'.to_int())
  }
  ordinal
}

///|
/// A child session another process already took is stepped over, never
/// shared. (The floor is far above every other test's allocations.)
async test "a claim steps over a session that already exists" {
  let root = @fs.tmpdir(prefix="openseek-subrun-taken-")
  defer @fs.rmdir(root, recursive=true)
  for ordinal in [70_000, 70_001] {
    @fs.mkdir("\{root}/sessions/taken-sr-\{ordinal}", recursive=true)
  }
  let claimed = @agent_subrun.ChildSession(
    root~,
    parent="taken",
    first_free=70_000,
  ).claim()
  assert_true(ordinal_of(claimed.subrun_id) >= 70_002)
  assert_eq(claimed.session, "taken-\{claimed.subrun_id}")
  assert_true(@fs.exists("\{root}/sessions/\{claimed.session}/claim.json"))
}

///|
/// A claim that cannot be made launches nothing: a Failed result with no
/// child id and no brackets, which the gate degrades to its notice.
async test "a failed claim is Failed and launches nothing" {
  let root = @fs.tmpdir(prefix="openseek-subrun-noclaim-")
  defer @fs.rmdir(root, recursive=true)
  // A file where the sessions directory should be makes every claim fail.
  @fs.write_file("\{root}/sessions", "", create_mode=CreateNew)
  let events : Array[@protocol.Event] = []
  let result = run_script(
    "touch launched",
    child_session=ChildSession(root~, parent="blocked"),
    emit_event=bracket_collector(events),
  )
  guard result.terminal() is Failed(reason) else {
    fail("expected Failed, got \{Repr(result.terminal())}")
  }
  assert_true(reason.has_prefix("could not claim a child session"))
  assert_true(result.subrun_id() is None)
  assert_true(events is [])
  assert_false(@fs.exists("launched"))
}

///|
/// A sibling engine that launched many children since this session's floor
/// was read does not exhaust the claim: the floor is refreshed past them.
async test "a claim refreshes a stale floor past a sibling's children" {
  let root = @fs.tmpdir(prefix="openseek-subrun-stale-")
  defer @fs.rmdir(root, recursive=true)
  for ordinal in 80_000..<80_100 {
    @fs.mkdir("\{root}/sessions/busy-sr-\{ordinal}", recursive=true)
  }
  let claimed = @agent_subrun.ChildSession(
    root~,
    parent="busy",
    first_free=80_000,
  ).claim()
  assert_true(ordinal_of(claimed.subrun_id) >= 80_100)
}

///|
/// Without a `ChildSession` the child is told to keep its transcript in
/// memory, and the request it reads names the kind and the sub-run id.
async test "a child without a session is launched with --no-session" {
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let script =
    #|kind=$(printf '%s' "$line" | sed -e 's/.*"kind":"\([^"]*\)".*/\1/')
    #|result "\"status\":\"completed\",\"output\":{\"answer\":\"$2 $kind $id\"}"
  let result = run_script(script)
  guard result.value() is Some(answer) else {
    fail("expected a captured report, got \{Repr(result.terminal())}")
  }
  assert_eq(answer, "--no-session test-kind \{launched_id(result)}")
}
