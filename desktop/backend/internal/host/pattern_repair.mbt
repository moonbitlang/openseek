///|
/// A bounded wall clock prevents a provider or its retries from holding the
/// search UI indefinitely. The provider has its own shorter idle timeout;
/// this remains the final guard for stalled process setup and future clients.
const PatternRepairWallTimeoutMs = 180_000

///|
priv enum PatternRepairProcessOutcome {
  Finished(Int, String, String)
  TimedOut
}

///|
priv enum PatternRepairCandidateOutcome {
  Candidate(String, String)
  TimedOut
  Failed(String)
}

///|
async fn run_pattern_repair_process(
  command : String,
  args : Array[String],
  input : String,
  cwd : String,
  env : Map[String, String],
) -> PatternRepairProcessOutcome {
  let result = @async.with_timeout_opt(PatternRepairWallTimeoutMs, () => {
    @async.with_task_group(group => {
      let (stdin_reader, stdin_writer) = @process.write_to_process()
      let (stdout_reader, child_stdout) = @process.read_from_process()
      let (stderr_reader, child_stderr) = @process.read_from_process()
      let process = @process.spawn(
        group,
        command,
        args,
        inherit_env=false,
        extra_env=env,
        stdin=stdin_reader,
        stdout=child_stdout,
        stderr=child_stderr,
        cwd~,
        no_console_window=true,
        cancel_handler=@process.graceful_cancel(timeout=3000),
        no_wait=true,
      )
      errdefer {
        stdin_writer.close()
        process.cancel()
      }
      stdin_writer.write(input)
      let stdout_task = group.spawn(() => {
        defer stdout_reader.close()
        stdout_reader.read_all().text() catch {
          _ => ""
        }
      })
      let stderr_task = group.spawn(() => {
        defer stderr_reader.close()
        stderr_reader.read_all().text() catch {
          _ => ""
        }
      })
      let code = process.wait()
      stdin_writer.close()
      let stdout = stdout_task.wait()
      let stderr = stderr_task.wait()
      (code, stdout, stderr)
    })
  })
  match result {
    Some((code, stdout, stderr)) => Finished(code, stdout, stderr)
    None => TimedOut
  }
}

///|
/// Keep the child's original terminal event available to the UI. Event names
/// are only used to identify terminal events; the displayed value remains the
/// raw provider/agent diagnostic instead of a Host-side error classification.
fn pattern_repair_agent_error(json : Json) -> String? {
  guard json is { "event": String(event), .. } else { return None }
  if event == "turn_failed" {
    match json {
      { "error": String(error), .. } => Some(error)
      _ => Some(json.stringify())
    }
  } else if event == "max_steps_exhausted" ||
    event == "context_yield" ||
    event == "agent_finished" ||
    event == "agent_aborted" {
    Some(json.stringify())
  } else {
    None
  }
}

///|
test "pattern repair preserves raw agent failure diagnostics" {
  assert_eq(
    pattern_repair_agent_error({
      "event": "turn_failed",
      "error": "provider returned an invalid tool call",
    }),
    Some("provider returned an invalid tool call"),
  )
  match pattern_repair_agent_error({ "event": "max_steps_exhausted" }) {
    Some(diagnostic) => assert_true(diagnostic.contains("max_steps_exhausted"))
    None => assert_true(false)
  }
  assert_true(
    pattern_repair_agent_error({ "event": "provider_request_timed_out" })
    is None,
  )
}

///|
/// Run the bundled OpenSeek executable as a one-shot Pattern Repair Agent.
/// The child receives no workspace tools; its sole non-submit tool validates a
/// pattern through the provider command selected by this Host.
async fn request_pattern_repair_candidate(
  state : HostState,
  agent_env : Map[String, String],
  root : @pathx.Absolute,
  pattern : String,
  instruction : String,
  model~ : String,
  thinking~ : @protocol.OpenSeekThinking?,
) -> PatternRepairCandidateOutcome {
  // The Agent receives only a closed validator configuration. It cannot
  // select another executable or alter the dump arguments.
  if moongrep_command() is Some(command) {
    agent_env[PatternRepairValidatorEnvironment] = pattern_repair_validator_config(
      command,
    ).stringify()
  }
  let input = ({ "pattern": pattern, "instruction": instruction } : Json).stringify() +
    "\n"
  let args = ["subrun", "pattern-repair", "--model", model]
  if thinking is Some(thinking) {
    args.push("--thinking")
    args.push(thinking.wire())
  }
  let process = run_pattern_repair_process(
    state.engine,
    args,
    input,
    root.0,
    agent_env,
  ) catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) =>
      raise error
    error => return Failed("\{error}")
  }
  guard process is Finished(code, stdout, stderr) else { return TimedOut }
  let mut provider_timed_out = false
  let mut agent_error : String? = if code == 0 || stderr.trim().is_empty() {
    None
  } else {
    Some(pattern_repair_diagnostic(stderr))
  }
  for line in stdout.split("\n") {
    let json = @json.parse(line.trim()) catch { _ => continue }
    if json is { "event": String("provider_request_timed_out"), .. } {
      provider_timed_out = true
      continue
    }
    if pattern_repair_agent_error(json) is Some(error) {
      agent_error = Some(pattern_repair_diagnostic(error))
      continue
    }
    guard json is { "subrun_report": report, .. } else { continue }
    guard report
      is {
        "candidate_pattern": String(candidate),
        "message": String(message),
        ..
      } else {
      return Failed(pattern_repair_diagnostic(report.stringify()))
    }
    return Candidate(candidate, message)
  }
  if provider_timed_out {
    TimedOut
  } else if agent_error is Some(error) {
    Failed(error)
  } else if !stdout.trim().is_empty() {
    Failed(pattern_repair_diagnostic(stdout))
  } else if code != 0 {
    Failed("Pattern Repair Agent process exited with code \{code}.")
  } else {
    Failed("Pattern Repair Agent did not produce a subrun report.")
  }
}

///|
fn pattern_repair_failure(
  payload : @protocol.PatternRepairPayload,
  validation_status : @protocol.PatternRepairStatus,
  candidate_pattern : String?,
  message : String,
) -> @protocol.PatternRepairReply {
  {
    root: payload.root,
    generation: payload.generation,
    candidate_pattern,
    valid: false,
    validation_status,
    message,
  }
}

///|
async fn pattern_repair_op(
  state : HostState,
  agent_env : Map[String, String],
  payload : @protocol.PatternRepairPayload,
) -> @protocol.PatternRepairReply {
  guard state.engine != "" else {
    return pattern_repair_failure(
      payload,
      Unavailable,
      None,
      "Pattern Repair Agent is unavailable.",
    )
  }
  let root = WirePath::parse(payload.root).absolute
  let candidate = request_pattern_repair_candidate(
    state,
    agent_env,
    root,
    payload.pattern,
    payload.instruction,
    model=payload.model,
    thinking=payload.thinking,
  )
  let (candidate, message) = match candidate {
    Candidate(candidate, message) => (candidate, message)
    TimedOut =>
      return pattern_repair_failure(
        payload,
        TimedOut,
        None,
        "Pattern repair timed out while contacting the AI provider. Check your connection or provider endpoint, then retry.",
      )
    Failed(error) => return pattern_repair_failure(payload, Failed, None, error)
  }
  match validate_pattern_repair_candidate(root, candidate) {
    PatternRepairValid =>
      {
        root: payload.root,
        generation: payload.generation,
        candidate_pattern: Some(candidate),
        valid: true,
        validation_status: Passed,
        message,
      }
    PatternRepairUnavailable =>
      {
        root: payload.root,
        generation: payload.generation,
        candidate_pattern: Some(candidate),
        valid: false,
        validation_status: Unavailable,
        message,
      }
    PatternRepairInvalid(diagnostic) =>
      pattern_repair_failure(payload, Failed, Some(candidate), diagnostic)
  }
}
