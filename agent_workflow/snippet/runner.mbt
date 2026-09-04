// The `Runner` a snippet's workflow spawns through, and the sidecar that makes
// its launches visible while they are still running.
//
// This is the openseek half of the seam. `moonbitlang/workflow` supplies the
// concurrency gate, the launch allowance, the journal and the combinators; it
// asks only for a function from a call to an outcome. Everything openseek
// needs a child to have — a durable transcript at `<parent>-sr-N`, an ordinal
// from the block mbtx reserved, an `attempt_id` the journal can be joined on —
// is added here, where the coordinates are known.

///|
/// The wall deadline a kind gets. Sized like the engine's own ceilings: a
/// scout that has not answered in ten minutes is lost rather than thorough,
/// while a worker slice is allowed real work and killing it at explore's
/// deadline would throw away everything it had done.
fn deadline_for(kind : String) -> Int {
  match kind {
    "explore" => 600_000
    "review" => 900_000
    "worker" => 2_700_000
    _ => 600_000
  }
}

///|
/// The child argv for one call. The step ceiling rides argv per the subrun
/// contract, the input line carries the question, and the API key NEVER rides
/// argv — it reaches the child through the inherited environment, where `ps`
/// cannot read it.
///
/// `--session`/`--session-root` are what make the child durable, and they are
/// appended HERE rather than by the caller: the ordinal exists only after this
/// runner allocates it.
fn child_args(
  spec : Injected,
  call : @workflow.AgentCall,
  session_id : String,
) -> Array[String] {
  let args = ["subrun", call.kind]
  if spec.model is Some(model) {
    args.push("--model")
    args.push(model)
  }
  if call.max_steps is Some(steps) {
    args.push("--max-steps")
    args.push("\{steps}")
  }
  if spec.api_url is Some(url) {
    args.push("--api-url")
    args.push(url)
  }
  args.push("--session")
  args.push(session_id)
  args.push("--session-root")
  args.push(spec.session_root)
  args
}

///|
/// Map a contract terminal into the lossless outcome envelope, so even a
/// timed-out child's spend survives into the journal and the ledger.
///
/// `attempt_id` is the child's session SUFFIX (`sr-N`), not an opaque id: a
/// journal entry therefore names `<parent>-sr-N` given the parent, which is
/// the same string the transcript viewer links to and the desktop's progress
/// probe tails. That is the whole join between the ledger and the per-subagent
/// view, and it costs nothing because the runner had to mint the ordinal
/// anyway.
fn outcome_of(
  subrun_id : String,
  result : @spawn.ContractResult,
) -> @workflow.AgentOutcome {
  let attempt : @workflow.AgentAttempt = {
    attempt_id: subrun_id,
    steps_used: result.steps_used,
    prompt_tokens: result.prompt_tokens,
    completion_tokens: result.completion_tokens,
    cost_usd: result.cost_usd,
  }
  match result.terminal {
    Captured =>
      match result.report {
        Some(value) => Finished(value~, attempt~)
        // Unreachable by the contract: refuse to dress an invariant
        // violation up as a clean no-report terminal.
        None =>
          DidNotFinish(
            failure=Failed("captured terminal without a report value"),
            attempt=Some(attempt),
          )
      }
    NoReport => DidNotFinish(failure=NoReport, attempt=Some(attempt))
    MaxSteps => DidNotFinish(failure=MaxSteps, attempt=Some(attempt))
    ContextYield => DidNotFinish(failure=ContextYield, attempt=Some(attempt))
    TimedOut => DidNotFinish(failure=TimedOut, attempt=Some(attempt))
    Failed(reason) =>
      DidNotFinish(failure=Failed(reason), attempt=Some(attempt))
  }
}

///|
/// The status word for a finished child, matching the engine's own wire
/// vocabulary so a reader does not have to learn two.
fn status_of(outcome : @workflow.AgentOutcome) -> String {
  match outcome {
    Finished(..) => "captured"
    DidNotFinish(failure=NoReport, ..) => "no_report"
    DidNotFinish(failure=MaxSteps, ..) => "max_steps"
    DidNotFinish(failure=ContextYield, ..) => "context_yield"
    DidNotFinish(failure=TimedOut, ..) => "timed_out"
    DidNotFinish(failure=Skipped, ..) => "skipped"
    DidNotFinish(failure=Failed(_), ..) => "failed"
  }
}

///|
/// Append one line to the sidecar the host tails.
///
/// Deliberately best-effort: a sidecar is a view, and a snippet whose work
/// succeeded must not fail because a progress line could not be written. The
/// journal is the record, and it has its own durability.
async fn note(path : String, line : Json) -> Unit {
  @fs.write_file(
    path,
    line.stringify() + "\n",
    append=true,
    create_mode=OpenOrCreate,
  ) catch {
    _ => ()
  }
}

///|
/// A `Runner` that spawns `openseek subrun <kind>` children, giving each the
/// durable child session mbtx reserved for it.
///
/// Ordinals come from the injected block and are handed out in order. The
/// block is also the ceiling: a call past its end is refused as `Skipped`
/// rather than launched without a session, because a child with no transcript
/// is exactly the thing this package exists to prevent.
///
/// Two sidecar lines bracket every launch. They exist because the journal
/// cannot: a `JournalEntry` carries an outcome, so it is written when a call
/// RESOLVES, and a reader with only the journal learns about a child no
/// earlier than its completion. The `started` line is what makes a running
/// child visible, and it carries the session id so the host can begin tailing
/// the child's own record immediately.
/// `map_launch` is the spawn seam, the same one `subrun_runner` carries: it
/// receives the CANONICAL `LaunchSpec` this runner computed plus the call and
/// returns what to actually launch, so a test can redirect to a scripted child
/// with the real argv — including the reserved `--session` — still in hand.
pub fn runner(
  spec : Injected,
  phase~ : Ref[String?],
  emit_line? : async (String, Json) -> Unit = note,
  map_launch? : (@spawn.LaunchSpec, @workflow.AgentCall) -> @spawn.LaunchSpec,
) -> @workflow.Runner {
  let next = Ref(spec.base)
  @workflow.Runner(call => {
    guard next.val < spec.base + spec.limit else {
      return DidNotFinish(failure=Skipped, attempt=None)
    }
    let subrun_id = "sr-\{next.val}"
    next.val += 1
    let session_id = "\{spec.parent}-\{subrun_id}"
    emit_line(spec.events_path, {
      "event": "agent_started",
      "id": subrun_id,
      "session": session_id,
      "kind": call.kind,
      "label": call.label,
      "phase": match phase.val {
        Some(phase) => Json::string(phase)
        None => Json::null()
      },
    })
    let canonical : @spawn.LaunchSpec = {
      command: spec.exe,
      args: child_args(spec, call, session_id),
      cwd: Some(spec.session_root),
      extra_env: None,
      deadline_ms: Some(deadline_for(call.kind)),
    }
    let launch = match map_launch {
      Some(map_launch) => map_launch(canonical, call)
      None => canonical
    }
    let result = @spawn.contract_run(
      command=launch.command,
      args=launch.args,
      input=call.input,
      kind=call.kind,
      id=subrun_id,
      max_steps?=call.max_steps,
      schema?=call.schema,
      wall_deadline_ms=launch.deadline_ms.unwrap_or(deadline_for(call.kind)),
      cwd?=launch.cwd,
      extra_env?=launch.extra_env,
    )
    let outcome = outcome_of(subrun_id, result)
    emit_line(spec.events_path, {
      "event": "agent_finished",
      "id": subrun_id,
      "session": session_id,
      "status": status_of(outcome),
      "steps": result.steps_used,
      "tokens": result.prompt_tokens + result.completion_tokens,
    })
    outcome
  })
}
