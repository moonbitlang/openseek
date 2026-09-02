///|
/// Combinator and context tests over FAKE runners: nothing here leaves the
/// process — the engine seam is exactly one async function, so the fakes
/// exercise accounting, policies, concurrency, cancellation, and events
/// hermetically. The scripted runner dispatches on the prompt's prefix:
/// `fail:` is an agent failure THAT STILL SPENT TOKENS, `skip:` a human
/// refusal that never spawned a child, `boom:` an engine bug escaping the
/// seam, `slow:` a long child for cancellation tests, anything else a
/// success echoing its prompt.
priv suberror EngineBoom {
  EngineBoom
}

///|
fn attempt_for(call : @workflow.AgentCall) -> @workflow.AgentAttempt {
  {
    attempt_id: "sr-\{call.label}",
    steps_used: 1,
    prompt_tokens: 7,
    completion_tokens: 3,
  }
}

///|
async fn scripted(call : @workflow.AgentCall) -> @workflow.AgentOutcome {
  @async.pause()
  guard call.input is { "query": String(prompt), .. } else {
    fail("the scripted runner expects the explore-style input")
  }
  if prompt.strip_prefix("fail:") is Some(_) {
    return DidNotFinish(
      failure=@workflow.AgentFailure::Failed("boom"),
      attempt=Some(attempt_for(call)),
    )
  }
  if prompt.strip_prefix("skip:") is Some(_) {
    return DidNotFinish(failure=@workflow.AgentFailure::Skipped, attempt=None)
  }
  if prompt.strip_prefix("boom:") is Some(_) {
    raise EngineBoom
  }
  if prompt.strip_prefix("slow:") is Some(_) {
    @async.sleep(2_000)
  }
  Finished(value={ "echo": prompt }, attempt=attempt_for(call))
}

///|
fn scripted_workflow(
  max_concurrent? : Int = 8,
  max_calls? : Int,
  on_event? : (@workflow.WorkflowEvent) -> Unit,
) -> @workflow.Workflow raise {
  @workflow.Workflow(
    runner=@workflow.Runner(scripted),
    max_concurrent~,
    max_calls?,
    on_event?,
  )
}

///|
async test "agent returns the report value and accounts tokens" {
  let wf = scripted_workflow()
  let value = wf.agent("hello", kind="scout")
  assert_eq(value, { "echo": "hello" })
  assert_eq(wf.tokens_spent(), 10)
  assert_eq(wf.calls_made(), 1)
}

///|
async test "a failed agent still charges its attempt's tokens" {
  let wf = scripted_workflow()
  guard wf.try_agent("fail:a", kind="scout")
    is Err(@workflow.AgentFailed(label="fail:a", failure=Failed("boom"))) else {
    fail("expected AgentFailed with the runner's reason")
  }
  assert_eq(wf.tokens_spent(), 10)
}

///|
async test "a skipped call spends nothing and replays as a refusal" {
  let wf = scripted_workflow()
  guard wf.try_agent("skip:a", kind="scout")
    is Err(@workflow.AgentFailed(failure=Skipped, ..)) else {
    fail("expected the skip to surface as AgentFailed(Skipped)")
  }
  assert_eq(wf.tokens_spent(), 0)
}

///|
async test "the launch allowance ignores calls cancelled while queued" {
  let wf = scripted_workflow(max_concurrent=1, max_calls=3)
  // One slot: `slow:a` launches and holds it while `ok-b`/`ok-c` queue.
  // Cancelling the fan-out WHILE they are queued must leave them undebited
  // — only the launched agent counts, and the fallback below still fits.
  @async.with_task_group(group => {
    let work = group.spawn(() => {
      @workflow.parallel_all([
        () => wf.agent("slow:a", kind="scout"),
        () => wf.agent("ok-b", kind="scout"),
        () => wf.agent("ok-c", kind="scout"),
      ])
    })
    group.spawn_bg(no_wait=true) <| () => {
      // Handshake, not a timer: cancel only once the first agent has
      // launched and the siblings have had scheduler turns to reach the
      // semaphore queue.
      while wf.calls_made() < 1 {
        @async.pause()
      }
      for _ in 0..<10 {
        @async.pause()
      }
      work.cancel()
    }
    let _ : Array[Json] = work.wait() catch {
      error if @async.is_cancellation_error(error) => []
      error => raise error
    }
  })
  assert_eq(wf.calls_made(), 1)
  let _ = wf.agent("ok-fallback", kind="scout")
  assert_eq(wf.calls_made(), 2)
}

///|
async test "the launch allowance refuses the call after the cap" {
  let wf = scripted_workflow(max_calls=2)
  let _ = wf.agent("one", kind="scout")
  let _ = wf.agent("two", kind="scout")
  guard wf.try_agent("three", kind="scout")
    is Err(@workflow.CallBudgetExhausted(..)) else {
    fail("expected the third launch to be refused")
  }
  assert_eq(wf.calls_made(), 2)
}

///|
async test "parallel keeps sibling successes when one agent fails" {
  let wf = scripted_workflow()
  let results = @workflow.parallel([
    () => wf.try_agent("a", kind="scout"),
    () => wf.try_agent("fail:b", kind="scout"),
    () => wf.try_agent("c", kind="scout"),
  ])
  guard results is [Ok(_), Err(@workflow.AgentFailed(..)), Ok(_)] else {
    fail("expected exactly the middle slot to fail")
  }
  assert_eq(@workflow.collect_ok(results).length(), 2)
  assert_eq(@workflow.quorum(results, need=2).length(), 2)
  let short : Array[Json] = @workflow.quorum(results, need=3) catch {
    @workflow.QuorumNotReached(need=3, ok=2, of=3) => []
    _ => fail("expected QuorumNotReached(need=3, ok=2, of=3)")
  }
  assert_eq(short.length(), 0)
  let mut reraised = false
  let _ = @workflow.all_ok(results) catch {
    @workflow.AgentFailed(label="fail:b", ..) => {
      reraised = true
      []
    }
    _ => fail("expected all_ok to re-raise the agent failure")
  }
  assert_true(reraised)
}

///|
async test "an engine error is never demoted to a policy slot" {
  let wf = scripted_workflow()
  let mut engine_error = false
  let _ : Array[Result[Json, @workflow.WorkflowError]] = @workflow.parallel([
    () => wf.try_agent("a", kind="scout"),
    () => wf.try_agent("boom:b", kind="scout"),
  ]) catch {
    EngineBoom => {
      engine_error = true
      []
    }
    _ => fail("expected the engine bug to propagate as itself")
  }
  assert_true(engine_error)
}

///|
async test "parallel_all cancels a slow sibling and the workflow survives" {
  let slow_completed : Ref[Bool] = { val: false, }
  let events : Array[String] = []
  let wf = scripted_workflow(on_event=event => events.push(render(event)))
  let _ : Array[Json] = @workflow.parallel_all([
    () => wf.agent("fail:a", kind="scout"),
    () => {
      let value = wf.agent("slow:b", kind="scout")
      slow_completed.val = true
      value
    },
  ]) catch {
    @workflow.AgentFailed(label="fail:a", ..) => []
    _ => fail("expected the failure to propagate")
  }
  assert_false(slow_completed.val)
  // The cancelled sibling still closed its event bracket.
  assert_true(events.contains("finish slow:b interrupted"))
  // The semaphore and allowance are intact: the workflow keeps working.
  let value = wf.agent("ok-after", kind="scout")
  assert_eq(value, { "echo": "ok-after" })
}

///|
async test "fan_out gives every item its own result slot" {
  let wf = scripted_workflow()
  let results = @workflow.fan_out(["p", "q", "r"], item => {
    wf.try_agent(item, kind="scout")
  })
  assert_eq(@workflow.all_ok(results).length(), 3)
  assert_eq(wf.calls_made(), 3)
}

///|
async test "max_concurrent bounds in-flight agents" {
  let in_flight : Ref[Int] = { val: 0, }
  let peak : Ref[Int] = { val: 0, }
  let runner = @workflow.Runner(call => {
    in_flight.val += 1
    if in_flight.val > peak.val {
      peak.val = in_flight.val
    }
    @async.sleep(5)
    in_flight.val -= 1
    Finished(value=Json::null(), attempt=attempt_for(call))
  })
  let wf = @workflow.Workflow(runner~, max_concurrent=1)
  let _ = @workflow.parallel_all([
    () => wf.agent("a", kind="scout"),
    () => wf.agent("b", kind="scout"),
    () => wf.agent("c", kind="scout"),
  ])
  assert_eq(peak.val, 1)
}

///|
async test "event brackets balance on success, failure, and engine error" {
  let events : Array[String] = []
  let wf = scripted_workflow(on_event=event => events.push(render(event)))
  wf.phase("Scan")
  wf.log("starting")
  let _ = wf.agent("q", kind="scout", label="scout")
  let _ = wf.try_agent("fail:x", kind="scout")
  let _ = wf.agent("boom:y", kind="scout") catch { _ => Json::null() }
  assert_eq(events, [
    "phase Scan", "log starting", "start scout scout Scan", "finish scout ok", "start fail:x scout Scan",
    "finish fail:x failed", "start boom:y scout Scan", "finish boom:y errored",
  ])
}

///|
async test "outcomes and failures survive the JSON round trip" {
  let attempt : @workflow.AgentAttempt = {
    attempt_id: "sr-1",
    steps_used: 4,
    prompt_tokens: 11,
    completion_tokens: 5,
  }
  let outcomes : Array[@workflow.AgentOutcome] = [
    Finished(value={ "answer": 42 }, attempt~),
    DidNotFinish(
      failure=@workflow.AgentFailure::TimedOut,
      attempt=Some(attempt),
    ),
    DidNotFinish(
      failure=@workflow.AgentFailure::NoReport,
      attempt=Some(attempt),
    ),
    DidNotFinish(
      failure=@workflow.AgentFailure::MaxSteps,
      attempt=Some(attempt),
    ),
    DidNotFinish(
      failure=@workflow.AgentFailure::ContextYield,
      attempt=Some(attempt),
    ),
    DidNotFinish(failure=@workflow.AgentFailure::Skipped, attempt=None),
    DidNotFinish(failure=@workflow.AgentFailure::Failed("reason"), attempt=None),
  ]
  for outcome in outcomes {
    let back : @workflow.AgentOutcome = @json.from_json(outcome.to_json())
    assert_true(back == outcome)
  }
}

///|
async test "quorum boundaries: zero and negative thresholds collect" {
  let wf = scripted_workflow()
  let results = @workflow.parallel([() => wf.try_agent("fail:a", kind="scout")])
  assert_eq(@workflow.quorum(results, need=0).length(), 0)
  assert_eq(@workflow.collect_ok(results, min_ok=-1).length(), 0)
}

///|
fn render(event : @workflow.WorkflowEvent) -> String {
  match event {
    @workflow.PhaseStarted(title) => "phase \{title}"
    @workflow.Log(message) => "log \{message}"
    @workflow.AgentStarted(label~, kind~, phase~) =>
      "start \{label} \{kind} \{phase.unwrap_or("-")}"
    @workflow.AgentFinished(label~, disposition~) =>
      "finish \{label} \{disposition_word(disposition)}"
    @workflow.AgentReplayed(label~, disposition~) =>
      "replay \{label} \{disposition_word(disposition)}"
  }
}

///|
fn disposition_word(disposition : @workflow.AgentDisposition) -> String {
  match disposition {
    @workflow.Succeeded => "ok"
    @workflow.FailedAgent => "failed"
    @workflow.Interrupted => "interrupted"
    @workflow.Errored => "errored"
  }
}
