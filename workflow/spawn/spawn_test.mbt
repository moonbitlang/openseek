///|
/// Contract tests over SCRIPTED children: any process that speaks the
/// child contract exercises this package end to end — `sh` plays every
/// engine. The spawnability probe uses the low-level process API so only
/// a genuinely spawn-hostile sandbox can skip these.
async fn can_spawn_sh() -> Bool {
  let code = @process.run("sh", ["-c", "exit 0"]) catch { _ => return false }
  code == 0
}

///|
async fn run_script(script : String) -> @spawn.ContractResult {
  @spawn.contract_run(
    command="sh",
    args=["-c", script],
    input={ "query": "q" },
    kind="probe",
    id="test-1",
    wall_deadline_ms=10_000,
  )
}

///|
async test "events and the report line are drained and accounted" {
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let script =
    #|read line
    #|printf '{"timestamp":"t","level":"INFO","source":"s","event":"agent_step","step":1}\n'
    #|printf 'not json at all\n'
    #|printf '{"timestamp":"t","level":"INFO","source":"s","event":"usage","usage":{"prompt_tokens":90,"completion_tokens":10,"total_tokens":100,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":90}}\n'
    #|printf '{"timestamp":"t","level":"INFO","source":"s","event":"agent_step","step":2}\n'
    #|printf '{"subrun_report": {"answer": "forty-two"}}\n'
  let result = run_script(script)
  guard result.terminal is Captured else { fail("expected Captured") }
  assert_eq(result.report, Some(({ "answer": "forty-two" } : Json)))
  assert_eq(result.steps_used, 2)
  assert_eq(result.prompt_tokens, 90)
  assert_eq(result.completion_tokens, 10)
}

///|
async test "a clean exit without a report is NoReport" {
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let script =
    #|read line
    #|printf '{"timestamp":"t","level":"INFO","source":"s","event":"agent_step","step":1}\n'
  let result = run_script(script)
  guard result.terminal is NoReport else { fail("expected NoReport") }
  assert_eq(result.report, None)
}

///|
async test "an observed step exhaustion is MaxSteps" {
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let script =
    #|read line
    #|printf '{"timestamp":"t","level":"INFO","source":"s","event":"max_steps_exhausted"}\n'
  guard run_script(script).terminal is MaxSteps else {
    fail("expected MaxSteps")
  }
}

///|
async test "a reported turn failure classifies as Failed" {
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let script =
    #|read line
    #|printf '{"timestamp":"t","level":"ERROR","source":"s","event":"turn_failed","error":"the model refused"}\n'
  guard run_script(script).terminal is Failed(reason) else {
    fail("expected Failed")
  }
  assert_true(reason.contains("refused"))
}

///|
async test "a spawn failure folds into Failed, never a crash" {
  let result = @spawn.contract_run(
    command="/nonexistent/engine-not-here",
    args=[],
    input={ "query": "q" },
    kind="probe",
    id="test-2",
    wall_deadline_ms=2_000,
  )
  match result.terminal {
    Failed(_) => ()
    // Some sandboxes surface spawn refusal as an immediate empty exit.
    NoReport => ()
    _ => fail("expected the missing binary to degrade, not crash")
  }
}

///|
/// The point of the whole package: a FOREIGN engine — here, `sh` itself —
/// plugs into the workflow with no openseek anywhere, and gets journal
/// replay for free.
async test "a foreign contract engine gets workflows and replay for free" {
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  let dir = @fs.tmpdir(prefix="workflow-contract-journal-")
  let path = "\{dir}/journal.jsonl"
  let live =
    #|read line
    #|printf '{"timestamp":"t","level":"INFO","source":"s","event":"usage","usage":{"prompt_tokens":7,"completion_tokens":3,"total_tokens":10,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":7}}\n'
    #|printf '{"subrun_report": %s}\n' "$line"
  let wf1 = @workflow.Workflow(
    runner=@spawn.contract_runner(launch=_ => {
      command: "sh",
      args: ["-c", live],
      cwd: None,
      extra_env: None,
      deadline_ms: None,
    }),
    journal=@workflow.Journal::load(path),
  )
  // The report echoes the input line: the v1 request envelope carrying
  // the call's kind and exact input — self-contained, no argv needed.
  let first = wf1.agent("hello", kind="probe", hints="from a foreign engine")
  assert_eq(first, {
    "workflow_contract": 1,
    "id": "cr-1",
    "kind": "probe",
    "input": { "query": "hello", "hints": "from a foreign engine" },
  })
  assert_eq(wf1.tokens_spent(), 10)
  // Resume: served from the journal, no process spawned.
  let poisoned =
    #|read line
    #|printf '{"subrun_report": {"wrong": true}}\n'
  let wf2 = @workflow.Workflow(
    runner=@spawn.contract_runner(launch=_ => {
      command: "sh",
      args: ["-c", poisoned],
      cwd: None,
      extra_env: None,
      deadline_ms: None,
    }),
    journal=@workflow.Journal::load(path),
  )
  assert_eq(
    wf2.agent("hello", kind="probe", hints="from a foreign engine"),
    first,
  )
  assert_eq(wf2.calls_made(), 0)
  assert_eq(wf2.calls_replayed(), 1)
  @fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
}

///|
async test "malformed numeric events are ignored whole, never truncated" {
  guard can_spawn_sh() else {
    println("skipped: cannot spawn sh")
    return
  }
  // A fractional step, a fractional token count, and a usage object
  // missing its total: each ignored WHOLE — then one valid pair counts.
  let script =
    #|read line
    #|printf '{"event":"agent_step","step":2.9}\n'
    #|printf '{"event":"usage","usage":{"prompt_tokens":90.5,"completion_tokens":10,"total_tokens":100,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":90}}\n'
    #|printf '{"event":"usage","usage":{"prompt_tokens":50,"completion_tokens":5}}\n'
    #|printf '{"event":"agent_step","step":1}\n'
    #|printf '{"event":"usage","usage":{"prompt_tokens":7,"completion_tokens":3,"total_tokens":10,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":7}}\n'
    #|printf '{"subrun_report": {"ok": true}}\n'
  let result = run_script(script)
  guard result.terminal is Captured else { fail("expected Captured") }
  assert_eq(result.steps_used, 1)
  assert_eq(result.prompt_tokens, 7)
  assert_eq(result.completion_tokens, 3)
}
