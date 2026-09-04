///|
/// End-to-end tests over SCRIPTED children: any process that speaks the
/// subrun contract (JSONL events on stdout, a final `subrun_report` line,
/// stdin EOF as cancel) exercises the whole workflow → runner → child
/// path without a model or a built binary. The spawnability probe uses
/// the LOW-LEVEL process API, so it can only skip on a genuinely
/// spawn-hostile sandbox — an adapter regression cannot masquerade as a
/// skip.
fn scripted_subrun(script : String) -> @workflow.Runner {
  @agent_workflow.subrun_runner(exe="unused", deadline_ms=10_000, map_launch=(
    spec,
    _,
  ) => { ..spec, command: "sh", args: ["-c", script], })
}

///|
async fn can_spawn_sh_here() -> Bool {
  let code = @process.run("sh", ["-c", "exit 0"]) catch { _ => return false }
  code == 0
}

///|
async test "a scripted child's report and cost flow into the workflow" {
  guard can_spawn_sh_here() else {
    println("skipped: cannot spawn sh")
    return
  }
  let script =
    #|read line
    #|printf '{"timestamp":"t","level":"INFO","source":"s","event":"agent_step","step":1}\n'
    #|printf '{"timestamp":"t","level":"INFO","source":"s","event":"usage","usage":{"prompt_tokens":90,"completion_tokens":10,"total_tokens":100,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":90}}\n'
    #|printf '{"subrun_report": {"answer": "forty-two"}}\n'
  let journal = @workflow.Journal::in_memory()
  let wf = @workflow.Workflow(runner=scripted_subrun(script), journal~)
  assert_eq(wf.agent("q", kind="explore"), { "answer": "forty-two" })
  assert_eq(wf.tokens_spent(), 100)
  assert_eq(wf.calls_made(), 1)
  // The journalled attempt carries the exact accounting, not just totals.
  guard journal.recorded()
    is [
      {
        outcome: Finished(
          attempt={
            steps_used: 1,
            prompt_tokens: 90,
            completion_tokens: 10,
            ..
          },
          ..
        ),
        ..
      },
    ] else {
    fail("expected the attempt's full accounting in the journal")
  }
}

///|
async test "the call's input IS the child's input line" {
  guard can_spawn_sh_here() else {
    println("skipped: cannot spawn sh")
    return
  }
  // The child echoes its stdin line back as the report: the v1 request
  // envelope, carrying the kind and EXACTLY the input the journal uses
  // as the replay identity.
  let script =
    #|read line
    #|printf '{"subrun_report": %s}\n' "$line"
  let wf = @workflow.Workflow(runner=scripted_subrun(script))
  guard wf.agent("hello", kind="explore", hints="look here")
    is {
      "workflow_contract": 1,
      "kind": "explore",
      "input": { "query": "hello", "hints": "look here", .. },
      ..
    } else {
    fail("expected the v1 request envelope around the exact input")
  }
}

///|
async test "the seam sees the canonical argv it may transform" {
  guard can_spawn_sh_here() else {
    println("skipped: cannot spawn sh")
    return
  }
  let ok =
    #|read line
    #|printf '{"subrun_report": {"ok": true}}\n'
  let seen : Ref[@spawn.LaunchSpec?] = { val: None, }
  let runner = @agent_workflow.subrun_runner(
    exe="/usr/local/bin/openseek",
    model="deepseek-reasoner",
    api_url="http://localhost:9",
    map_launch=(canonical, _) => {
      seen.val = Some(canonical)
      { ..canonical, command: "sh", args: ["-c", ok], }
    },
  )
  let wf = @workflow.Workflow(runner~)
  let _ = wf.agent("q", kind="explore", max_steps=42)
  guard seen.val is Some(spec) else {
    fail("the seam never saw the canonical launch spec")
  }
  assert_eq(spec.command, "/usr/local/bin/openseek")
  assert_eq(spec.args, [
    "subrun", "explore", "--model", "deepseek-reasoner", "--max-steps", "42", "--api-url",
    "http://localhost:9",
  ])
}

///|
async test "a child that dies without a report fails typed WITH its cost" {
  guard can_spawn_sh_here() else {
    println("skipped: cannot spawn sh")
    return
  }
  let script =
    #|read line
    #|printf '{"timestamp":"t","level":"INFO","source":"s","event":"usage","usage":{"prompt_tokens":90,"completion_tokens":10,"total_tokens":100,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":90}}\n'
  let wf = @workflow.Workflow(runner=scripted_subrun(script))
  guard wf.try_agent("q", kind="explore")
    is Err(@workflow.AgentFailed(failure=NoReport, ..)) else {
    fail("expected a typed NoReport failure")
  }
  // The doomed child's spend still lands in the budget — the lossless
  // envelope end to end.
  assert_eq(wf.tokens_spent(), 100)
}

///|
async test "an observed step exhaustion maps to MaxSteps" {
  guard can_spawn_sh_here() else {
    println("skipped: cannot spawn sh")
    return
  }
  let script =
    #|read line
    #|printf '{"timestamp":"t","level":"INFO","source":"s","event":"max_steps_exhausted"}\n'
  let wf = @workflow.Workflow(runner=scripted_subrun(script))
  guard wf.try_agent("q", kind="explore")
    is Err(@workflow.AgentFailed(failure=MaxSteps, ..)) else {
    fail("expected a typed MaxSteps failure")
  }
}

///|
async test "a spawn failure maps to Failed with a zero-cost attempt" {
  let wf = @workflow.Workflow(
    runner=@agent_workflow.subrun_runner(
      exe="/nonexistent/openseek-not-here",
      deadline_ms=2_000,
    ),
    journal=@workflow.Journal::in_memory(),
  )
  match wf.try_agent("q", kind="explore") {
    Err(@workflow.AgentFailed(failure=Failed(_), ..)) => ()
    // Some sandboxes surface spawn refusal as an immediate empty exit:
    // accept NoReport there, but never a success or a crash.
    Err(@workflow.AgentFailed(failure=NoReport, ..)) => ()
    _ => fail("expected the missing binary to fail typed")
  }
  assert_eq(wf.tokens_spent(), 0)
}

///|
async test "journal replay spares the child process entirely" {
  guard can_spawn_sh_here() else {
    println("skipped: cannot spawn sh")
    return
  }
  let dir = @fs.tmpdir(prefix="workflow-subrun-journal-")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let path = "\{dir}/journal.jsonl"
  let live =
    #|read line
    #|printf '{"subrun_report": {"answer": 1}}\n'
  let wf1 = @workflow.Workflow(
    runner=scripted_subrun(live),
    journal=@workflow.Journal::load(path),
  )
  let first = wf1.agent("q", kind="explore")
  // Generation 2's child would report a DIFFERENT value if it ever ran;
  // replay must serve generation 1's report without spawning.
  let poisoned =
    #|read line
    #|printf '{"subrun_report": {"answer": 2}}\n'
  let wf2 = @workflow.Workflow(
    runner=scripted_subrun(poisoned),
    journal=@workflow.Journal::load(path),
  )
  assert_eq(wf2.agent("q", kind="explore"), first)
  assert_eq(wf2.calls_made(), 0)
  assert_eq(wf2.calls_replayed(), 1)
}
