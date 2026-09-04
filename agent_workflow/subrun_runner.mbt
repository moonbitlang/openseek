///|
/// The openseek adapter for the engine-neutral `moonbitlang/workflow`
/// library: fan its agent calls out to `openseek subrun <kind>` child
/// processes over the `agent_subrun` contract — one JSON input line on
/// stdin, JSONL events plus a final report line on stdout, stdin EOF as
/// the graceful cancel. The dependency points ENGINE → FRAMEWORK: the
/// workflow library never learns openseek exists; this package hands it a
/// `Runner`.
///
/// The child's report value passes through as Json (typed decoding
/// belongs to the call site that knows the kind); every terminal maps
/// into the lossless `AgentOutcome` envelope, so even a timed-out child's
/// spend survives into the budget and the journal.
///
/// `exe` must be absolute or PATH-resolved: children run with their cwd
/// set to `workspace_root`, so a separator-relative path like
/// `./openseek` would resolve against the WRONG directory.
///
/// Credentials: children inherit the parent's environment, so a provider
/// key exported as an environment variable reaches them automatically. A
/// key held only in memory (e.g. parsed from `--api-key`) must ride
/// `extra_env` — never argv, which is visible in `ps`.
///
/// `map_launch` is the spawn seam: it receives the CANONICAL
/// `@spawn.LaunchSpec` this adapter computed plus the call, and returns
/// what to actually launch — tests redirect to scripted `sh` children,
/// wrappers can prepend a sandbox command, and the canonical spec is in
/// hand either way so nothing is silently bypassed.
pub fn subrun_runner(
  exe~ : String,
  model? : String,
  api_url? : String,
  workspace_root? : String,
  deadline_ms? : Int,
  extra_env? : Map[String, String],
  map_launch? : (@spawn.LaunchSpec, @workflow.AgentCall) -> @spawn.LaunchSpec,
) -> @workflow.Runner {
  @workflow.Runner(call => {
    let canonical : @spawn.LaunchSpec = {
      command: exe,
      args: subrun_args(call, model, api_url),
      cwd: workspace_root,
      extra_env,
      deadline_ms: Some(deadline_ms.unwrap_or(default_deadline_ms(call.kind))),
    }
    let spec = match map_launch {
      Some(map_launch) => map_launch(canonical, call)
      None => canonical
    }
    let result = @agent_subrun.run_subrun(
      command=spec.command,
      args=spec.args,
      input=call.input,
      parse_report=report => Ok(report),
      wall_deadline_ms=spec.deadline_ms.unwrap_or(
        default_deadline_ms(call.kind),
      ),
      kind=call.kind,
      label=call.label,
      cwd?=spec.cwd,
      extra_env?=spec.extra_env,
    )
    outcome_of(result)
  })
}

///|
/// The wall deadline a kind gets when the caller sets none: each kind's
/// own ceiling, sized with its step allowance — a worker slice is allowed
/// 45 minutes of real work, and killing it at explore's 10 would throw
/// away normal runs.
fn default_deadline_ms(kind : String) -> Int {
  match kind {
    "worker" => @agent_worker.default_worker_deadline_ms
    // Mirrors the goal-audit gate's ceiling (cmd/openseek/gate.mbt).
    "review" => 900_000
    // Explore's ceiling; also the conservative default for unknown kinds.
    _ => 600_000
  }
}

///|
/// Map one subrun result into the workflow's lossless outcome envelope.
/// The attempt is attached to every terminal — including a failed spawn,
/// which observed zero cost but WAS an attempt (`None` is reserved for
/// calls that never tried to launch, like a human skip).
fn outcome_of(
  result : @agent_subrun.SubrunResult[Json],
) -> @workflow.AgentOutcome {
  let attempt : @workflow.AgentAttempt = {
    attempt_id: result.subrun_id(),
    steps_used: result.steps_used(),
    prompt_tokens: result.prompt_tokens(),
    completion_tokens: result.completion_tokens(),
    cost_usd: result.cost_usd(),
  }
  match result.terminal() {
    Captured =>
      match result.value() {
        Some(value) => Finished(value~, attempt~)
        // Unreachable by the substrate's contract: refuse to dress an
        // invariant violation up as a clean no-report terminal.
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
/// The child argv for one call: `subrun <kind>` plus whatever engine
/// settings were configured. The step ceiling rides argv per the subrun
/// contract; the input line carries everything else; the API key NEVER
/// rides argv.
fn subrun_args(
  call : @workflow.AgentCall,
  model : String?,
  api_url : String?,
) -> Array[String] {
  let args = ["subrun", call.kind]
  if model is Some(model) {
    args.push("--model")
    args.push(model)
  }
  if call.max_steps is Some(steps) {
    args.push("--max-steps")
    args.push("\{steps}")
  }
  if api_url is Some(url) {
    args.push("--api-url")
    args.push(url)
  }
  args
}
