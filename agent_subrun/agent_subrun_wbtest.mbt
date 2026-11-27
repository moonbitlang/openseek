// Whitebox tests for the runner's own accounting: `steps_used`, `subrun_id`
// and `unaccounted` are private to this package — the runner's tests are
// their only consumer, so they are not API. A whitebox test package cannot
// share helpers with `runner_test.mbt` (a blackbox package), so the
// scripted-child harness is repeated here.

///|
/// See `child_preamble` in `runner_test.mbt`: the scripted child reads the
/// request, keeps the result path (`$1`, from `{result_file}`) as `$RESULT`
/// and the request id as `$id`, and `result FIELDS` writes a result
/// answering it.
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
  child_session? : ChildSession,
  emit_event? : (@protocol.Event) -> Unit,
) -> SubrunResult[String] {
  run_subrun(
    command="sh",
    args=["-c", child_preamble + script, "sh", @spawn.ResultFilePlaceholder],
    input={ "query": "q" },
    parse_report=parse_answer,
    wall_deadline_ms=10_000,
    kind="test-kind",
    label="scripted child",
    child_session?,
    emit_event?,
  )
}

///|
/// See `can_spawn_sh` in `runner_test.mbt`: the one-time spawnability probe,
/// which reports false rather than raising under fork pressure or in a
/// spawn-hostile sandbox.
async fn can_spawn_sh() -> Bool {
  let script =
    #|result '"status":"completed","output":{"answer":"probe"}'
  let result = run_script(script) catch { _ => return false }
  result.value() is Some("probe")
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
/// The id of the child a sub-run launched; every launch has one. The result
/// records the same id its brackets carried.
fn[T] launched_id(result : SubrunResult[T]) -> String raise {
  guard result.subrun_id is Some(id) else {
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
  assert_eq(result.steps_used, 2)
  assert_eq(result.prompt_tokens(), 185)
  assert_eq(result.completion_tokens(), 15)
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
  assert_eq(result.unaccounted, Some("the child left no result"))
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
  defer @fs.remove(root, recursive=true)
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
  defer @fs.remove(root, recursive=true)
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
/// A claim that cannot be made launches nothing: a Failed result with no
/// child id and no brackets, which the gate degrades to its notice.
async test "a failed claim is Failed and launches nothing" {
  let root = @fs.tmpdir(prefix="openseek-subrun-noclaim-")
  defer @fs.remove(root, recursive=true)
  // A file where the sessions directory should be makes every claim fail.
  @fs.write_text("\{root}/sessions", "", create_mode=CreateNew)
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
  assert_true(result.subrun_id is None)
  assert_true(events is [])
  assert_false(@fs.exists("launched"))
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
