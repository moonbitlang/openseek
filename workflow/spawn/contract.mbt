///|
/// THE CHILD CONTRACT, and its one implementation.
///
/// A workflow agent can be any process that speaks this wire contract:
///
/// - the runner writes ONE JSON line on the child's stdin and holds the
///   pipe open — closing it is the graceful-cancel signal, not the end
///   of input. The line is the VERSIONED request envelope
///   `{"workflow_contract": 1, "id": ..., "kind": ..., "max_steps"?: ...,
///   "input": ...}` — self-contained, so the request never depends on
///   engine-specific argv (argv remains deployment configuration);
/// - the child emits JSONL on stdout: event lines (an object with an
///   `event` tag — `usage` and `agent_step` are summed/maxed for exact
///   cost accounting; `max_steps_exhausted`, `context_yield`,
///   `turn_failed`, `agent_setup_failed`, `command_error`, and
///   `agent_aborted` classify how a run degraded) and, last, ONE
///   distinguished `{"subrun_report": ...}` line carrying the result;
/// - non-JSON stdout lines are skipped (a leaky tool subprocess must not
///   poison the run);
/// - after `wall_deadline_ms` the runner closes stdin and grants
///   `cancel_grace_ms` to flush and exit — a report landing in the grace
///   window still counts — then terminates the child.
///
/// `openseek subrun <kind>` speaks this contract natively; a shim around
/// any other engine (a Rust CLI, a shell script) needs only to translate
/// framing. External cancellation of the CALLER is never folded into a
/// terminal: it re-raises after teardown, per structured concurrency.
let default_cancel_grace_ms : Int = 5_000

///|
/// How a contract run ended. `Captured` means a report line arrived —
/// whether its CONTENT is acceptable is the caller's judgment, at the
/// layer that knows the report schema.
pub enum ContractTerminal {
  Captured
  NoReport
  MaxSteps
  ContextYield
  TimedOut
  Failed(String)
} derive(Eq)

///|
pub extend ContractTerminal with Eq::{equal, not_equal}

///|
/// One contract run's outcome: the RAW report (when one arrived) plus the
/// cost observed from the child's own event stream.
pub struct ContractResult {
  report : Json?
  terminal : ContractTerminal
  steps_used : Int
  prompt_tokens : Int
  completion_tokens : Int
}

///|
/// Live cost counters, updated AS the child streams. Pass one in to keep
/// visibility into a run that ends by cancellation — the raise unwinds
/// past the return value, but not past this.
pub struct ContractProgress {
  mut steps : Int
  mut prompt_tokens : Int
  mut completion_tokens : Int
}

///|
/// Fresh zeroed counters.
pub fn ContractProgress::ContractProgress() -> ContractProgress {
  { steps: 0, prompt_tokens: 0, completion_tokens: 0, }
}

///|
priv struct Observations {
  progress : ContractProgress
  observe_line : ((Json) -> Unit)?
  mut max_steps_exhausted : Bool
  mut context_yield : Bool
  mut failure : String?
  mut report : Json?
}

///|
/// Classify one child stdout line, structurally — the tags are the wire
/// contract, not any engine's type vocabulary.
fn Observations::observe(self : Observations, line : String) -> Unit {
  let trimmed = line.trim(chars="\r\n")
  if trimmed == "" {
    return
  }
  guard (Some(@json.parse(trimmed.to_owned())) catch { _ => None })
    is Some(json) else {
    return
  }
  if self.observe_line is Some(hook) {
    hook(json)
  }
  if json is { "subrun_report": report, .. } {
    self.report = Some(report)
    return
  }
  match json {
    { "event": "agent_step", "step": Number(step, ..), .. } =>
      if integral(step) is Some(step) {
        self.progress.steps = self.progress.steps.max(step)
      }
    {
      "event": "usage",
      "usage": {
        "prompt_tokens": Number(prompt, ..),
        "completion_tokens": Number(completion, ..),
        "total_tokens": Number(total, ..),
        "prompt_cache_hit_tokens": Number(cache_hit, ..),
        "prompt_cache_miss_tokens": Number(cache_miss, ..),
        ..
      },
      ..
    } =>
      // Integral-only and whole-object, exactly as the engine's typed
      // decoder: a counter of 1.5 is not a token count, and a malformed
      // usage line is ignored WHOLE — never partially charged.
      if integral(prompt) is Some(prompt) &&
        integral(completion) is Some(completion) &&
        integral(total) is Some(_) &&
        integral(cache_hit) is Some(_) &&
        integral(cache_miss) is Some(_) {
        self.progress.prompt_tokens += prompt
        self.progress.completion_tokens += completion
      }
    { "event": "max_steps_exhausted", .. } => self.max_steps_exhausted = true
    {
      "event": "context_yield",
      "to_sequence": Number(to_sequence, ..),
      "answer": String(_),
      ..
    } => if integral(to_sequence) is Some(_) { self.context_yield = true }
    { "event": "turn_failed", "error": String(error), .. }
    | { "event": "agent_setup_failed", "error": String(error), .. }
    | { "event": "command_error", "error": String(error), .. } =>
      self.failure = Some(error)
    { "event": "agent_aborted", "reason": String(reason), .. } =>
      self.failure = Some(reason)
    _ => ()
  }
}

///|
/// JSON has one number type, so an `Int` field arrives as a `Number`;
/// reject a fractional value rather than silently truncating it.
fn integral(value : Double) -> Int? {
  let rounded = value.to_int()
  if rounded.to_double() == value {
    Some(rounded)
  } else {
    None
  }
}

///|
/// Run one child over the contract: spawn, feed the input line, drain and
/// account the event stream, enforce the wall deadline with its grace
/// window, and tear the child down on every path. Crash isolation is
/// structural: a dead or unspawnable child is a `Failed` terminal, never
/// a dead caller. External cancellation re-raises after teardown.
pub async fn contract_run(
  command~ : String,
  args~ : Array[String],
  input~ : Json,
  kind~ : String,
  id~ : String,
  max_steps? : Int,
  wall_deadline_ms~ : Int,
  cancel_grace_ms? : Int = default_cancel_grace_ms,
  cwd? : String,
  extra_env? : Map[String, String],
  progress? : ContractProgress,
  observe_line? : (Json) -> Unit,
) -> ContractResult {
  let progress = match progress {
    Some(progress) => progress
    None => ContractProgress()
  }
  let observations : Observations = {
    progress,
    observe_line,
    max_steps_exhausted: false,
    context_yield: false,
    failure: None,
    report: None,
  }
  let mut timed_out = false
  // The group call is itself fold-guarded: a spawn failure can surface
  // ASYNCHRONOUSLY (the spawn's internal reaper task raising at group
  // exit, e.g. EAGAIN under fork pressure), bypassing the per-call
  // catches inside. Cancellation still re-raises; anything else becomes
  // a Failed terminal — a loaded machine must degrade the run, never
  // crash the caller.
  try
    @async.with_task_group() <| group => {
      let (child_stdin, stdin_writer) = @process.write_to_process() catch {
        error if @async.is_being_cancelled() => raise error
        error => {
          observations.failure = Some("subrun pipes unavailable: \{error}")
          return
        }
      }
      let (stdout_reader, child_stdout) = @process.read_from_process() catch {
        error if @async.is_being_cancelled() => {
          stdin_writer.close()
          raise error
        }
        error => {
          stdin_writer.close()
          observations.failure = Some("subrun pipes unavailable: \{error}")
          return
        }
      }
      // `no_wait`: the group terminates the child at teardown rather than
      // waiting for an exit that may only come once its stdin is closed.
      let process = @process.spawn(
        group,
        command,
        args,
        inherit_env=true,
        // Credentials that only exist in the caller's memory ride this
        // overlay into the child's environment — argv would be visible
        // in `ps`, the environment is not.
        extra_env?,
        stdin=child_stdin,
        stdout=child_stdout,
        cwd?=cwd.map(dir => dir.view()),
        no_wait=true,
      ) catch {
        error if @async.is_being_cancelled() => {
          stdout_reader.close()
          stdin_writer.close()
          raise error
        }
        error => {
          stdout_reader.close()
          stdin_writer.close()
          observations.failure = Some("subrun spawn failed: \{error}")
          return
        }
      }
      async fn drain() -> Unit {
        while stdout_reader.read_until("\n") is Some(line) {
          observations.observe(line)
        }
      }
      async fn feed_and_drain() -> Unit {
        // One input line — the v1 request envelope; the pipe stays open,
        // EOF is the cancel signal, not the end of input. The write sits
        // INSIDE the deadline scope: an input larger than the pipe
        // capacity against a child that never reads must hit the wall
        // deadline, not block forever.
        let request : Json = match max_steps {
          Some(steps) =>
            {
              "workflow_contract": 1,
              "id": id,
              "kind": kind,
              "max_steps": steps,
              "input": input,
            }
          None =>
            { "workflow_contract": 1, "id": id, "kind": kind, "input": input }
        }
        stdin_writer.write("\{request.stringify()}\n")
        drain()
      }
      try {
        match @async.with_timeout_opt(wall_deadline_ms, feed_and_drain) {
          Some(_) =>
            // Clean EOF: the child closed stdout. Read its exit status — a
            // crash-class failure (panic, signal, nonzero exit) emits no
            // failure event, and without this the runner is structurally
            // blind to it and would misclassify the run as NoReport.
            // Bounded: a child that closed stdout but lingers falls
            // through to the cancel below.
            match @async.with_timeout_opt(2_000, () => process.wait()) {
              Some(code) if code != 0 &&
                observations.report is None &&
                observations.failure is None =>
                observations.failure = Some("subrun exited \{code}")
              _ => ()
            }
          None => {
            // Deadline: graceful cancel first — close stdin, let the child
            // flush; a report arriving in the grace window still counts.
            timed_out = true
            stdin_writer.close()
            let _ = @async.with_timeout_opt(cancel_grace_ms, drain)
          }
        }
      } catch {
        error => {
          // External cancellation (or a pipe failure): tear the child down
          // and re-raise cancellation; fold anything else into the
          // terminal.
          @async.protect_from_cancel(() => {
            stdout_reader.close()
            stdin_writer.close()
            process.cancel()
          })
          if @async.is_being_cancelled() {
            raise error
          }
          if observations.failure is None {
            observations.failure = Some("subrun stream failed: \{error}")
          }
          return
        }
      }
      stdout_reader.close()
      stdin_writer.close()
      process.cancel()
    }
  catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) =>
      raise error
    error =>
      if observations.failure is None {
        observations.failure = Some("subrun runner failed: \{error}")
      }
  }
  let terminal = match observations.report {
    Some(_) => Captured
    None =>
      match observations.failure {
        Some(error) => Failed(error)
        None if timed_out => TimedOut
        None if observations.max_steps_exhausted => MaxSteps
        None if observations.context_yield => ContextYield
        None => NoReport
      }
  }
  {
    report: observations.report,
    terminal,
    steps_used: progress.steps,
    prompt_tokens: progress.prompt_tokens,
    completion_tokens: progress.completion_tokens,
  }
}

///|
/// HOW one call becomes a process: the executable, its argv, and the
/// per-launch execution envelope. Everything a sandbox wrapper or a
/// deployment would want to rewrite lives HERE, in one immutable value —
/// never scattered across positional tuples.
pub(all) struct LaunchSpec {
  command : String
  args : Array[String]
  cwd : String?
  extra_env : Map[String, String]?
  deadline_ms : Int?
} derive(Eq)

///|
pub extend LaunchSpec with Eq::{equal, not_equal}

///|
/// A `Runner` for ANY engine speaking the child contract: `launch` turns
/// each call into a `LaunchSpec`, the request envelope carries the
/// call's kind/limits/input, and every terminal maps into the lossless
/// `AgentOutcome` envelope. For engines whose reports are pure values
/// this is the whole adapter — an openseek-independent codex shim plugs
/// in right here. An engine whose reports name STATEFUL resources must
/// also pass `validate_replay`, or resumed journals can serve outcomes
/// whose referents no longer exist.
pub fn contract_runner(
  launch~ : (@workflow.AgentCall) -> LaunchSpec,
  deadline_ms? : Int = 600_000,
  validate_replay? : async (@workflow.AgentCall, @workflow.AgentOutcome) -> @workflow.ReplayDecision,
) -> @workflow.Runner {
  let ids : Ref[Int] = { val: 0, }
  @workflow.Runner(validate_replay?, call => {
    let spec = launch(call)
    ids.val += 1
    let id = "cr-\{ids.val}"
    let cwd = spec.cwd
    let extra_env = spec.extra_env
    let result = contract_run(
      command=spec.command,
      args=spec.args,
      input=call.input,
      kind=call.kind,
      id~,
      max_steps?=call.max_steps,
      wall_deadline_ms=spec.deadline_ms.unwrap_or(deadline_ms),
      cwd?,
      extra_env?,
    )
    let attempt : @workflow.AgentAttempt = {
      attempt_id: id,
      steps_used: result.steps_used,
      prompt_tokens: result.prompt_tokens,
      completion_tokens: result.completion_tokens,
    }
    match result.terminal {
      Captured =>
        match result.report {
          Some(value) => Finished(value~, attempt~)
          None =>
            DidNotFinish(
              failure=Failed("captured terminal without a report"),
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
  })
}
