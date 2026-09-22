///|
/// Bound the complete Host Agent run, including setup, provider retries, and
/// candidate submission.
const PatternRepairWallTimeoutSeconds : Int = 120

///|
const PatternRepairWallTimeoutMs : Int = PatternRepairWallTimeoutSeconds * 1000

///|
const PatternRepairTraceMaxItems : Int = 16

///|
const PatternRepairTraceMaxItemUnits : Int = 240

///|
const PatternRepairTraceOmitted : String = "Earlier events omitted"

///|
priv enum PatternRepairProcessOutcome {
  Finished(Int, String, (String, String)?, String?, Array[String])
  TimedOut(Array[String])
}

///|
priv enum PatternRepairCandidateOutcome {
  Candidate(String, String, Array[String])
  TimedOut(Array[String])
  Failed(String, Array[String])
}

///|
fn pattern_repair_trace_push(trace : Array[String], value : String) -> Unit {
  let value = value.trim().to_owned()
  guard !value.is_empty() else { return }
  let value = if value.length() > PatternRepairTraceMaxItemUnits {
    value[:PatternRepairTraceMaxItemUnits].to_owned() + "..."
  } else {
    value
  }
  if trace.length() < PatternRepairTraceMaxItems {
    trace.push(value)
  } else {
    trace[0] = PatternRepairTraceOmitted
    let _ = trace.remove(1)
    trace.push(value)
  }
}

///|
async fn run_pattern_repair_process(
  command : String,
  args : Array[String],
  input : String,
  cwd : String,
  env : Map[String, String],
) -> PatternRepairProcessOutcome {
  // Retain a bounded trace incrementally so a wall timeout can still return
  // the events observed before the child was cancelled.
  let trace : Ref[Array[String]] = { val: [], }
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
        let mut candidate : (String, String)? = None
        let mut agent_error : String? = None
        for ;; {
          let line = stdout_reader.read_until("\n") catch { _ => None }
          guard line is Some(line) else { break }
          let json = @json.parse(line.trim()) catch { _ => continue }
          if json is { "subrun_report": report, .. } {
            match report {
              {
                "candidate_pattern": String(pattern),
                "message": String(message),
                ..
              } => {
                candidate = Some((pattern, message))
                pattern_repair_trace_push(trace.val, "Candidate submitted")
              }
              _ => {
                agent_error = Some(
                  pattern_repair_diagnostic(report.stringify()),
                )
                pattern_repair_trace_push(
                  trace.val,
                  "Agent returned a malformed submission report",
                )
              }
            }
            continue
          }
          let event_error = pattern_repair_record_event(json, trace.val)
          if event_error is Some(error) {
            agent_error = Some(pattern_repair_diagnostic(error))
          }
        }
        (candidate, agent_error)
      })
      let stderr_task = group.spawn(() => {
        defer stderr_reader.close()
        stderr_reader.read_all().text() catch {
          _ => ""
        }
      })
      let code = process.wait()
      stdin_writer.close()
      let (candidate, agent_error) = stdout_task.wait()
      let stderr = stderr_task.wait()
      (code, stderr, candidate, agent_error)
    })
  })
  match result {
    Some((code, stderr, candidate, agent_error)) =>
      Finished(code, stderr, candidate, agent_error, trace.val.copy())
    None => {
      pattern_repair_trace_push(
        trace.val,
        "Host Agent timed out after \{PatternRepairWallTimeoutSeconds} seconds",
      )
      TimedOut(trace.val.copy())
    }
  }
}

///|
/// Keep the child's original terminal event available to the UI. Event names
/// are only used to identify terminal events; the displayed value remains the
/// raw agent diagnostic instead of a Host-side error classification.
fn pattern_repair_agent_error(json : Json) -> String? {
  guard json is { "event": String(event), .. } else { return None }
  if event == "turn_failed" ||
    event == "agent_setup_failed" ||
    event == "command_error" {
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
/// Reduce the child JSONL stream to safe, bounded repair events. Assistant
/// and reasoning content, tool arguments, and unrelated event payloads are
/// never retained in the trace.
fn pattern_repair_record_event(json : Json, trace : Array[String]) -> String? {
  guard json is { "event": String(event), .. } else { return None }
  if event == "agent_step" {
    if json is { "step": Number(step, ..), .. } {
      pattern_repair_trace_push(trace, "Agent step \{step.to_int()}")
    }
    return None
  }
  if event == "stream_retry" {
    if json
      is {
        "attempt": Number(attempt, ..),
        "max_attempts": Number(max_attempts, ..),
        ..
      } {
      pattern_repair_trace_push(
        trace,
        "Provider retry \{attempt.to_int()}/\{max_attempts.to_int()}",
      )
    }
    return None
  }
  if event == "tool_result" {
    guard json
      is {
        "tool_name": String(tool_name),
        "content": String(content),
        "is_error": is_error,
        ..
      } else {
      return None
    }
    if tool_name == "validate_pattern" {
      let result = @json.parse(content) catch { _ => Json::null() }
      if result is { "valid": True, .. } {
        pattern_repair_trace_push(trace, "validate_pattern: passed")
      } else if result
        is { "valid": False, "diagnostic": String(diagnostic), .. } {
        pattern_repair_trace_push(
          trace,
          "validate_pattern: failed — \{diagnostic}",
        )
      } else if is_error is True {
        pattern_repair_trace_push(trace, "validate_pattern: \{content}")
      } else {
        pattern_repair_trace_push(trace, "validate_pattern: returned")
      }
    } else if tool_name == "submit_pattern_repair" {
      pattern_repair_trace_push(trace, "submit_pattern_repair: returned")
    }
    return None
  }
  if pattern_repair_agent_error(json) is Some(error) {
    let summary = if event == "max_steps_exhausted" {
      "Agent step limit exhausted"
    } else if event == "agent_finished" {
      "Agent turn finished without a submission"
    } else if event == "context_yield" {
      "Agent yielded at its context limit"
    } else if event == "agent_aborted" {
      match json {
        { "reason": String(reason), .. } => "Agent aborted: \{reason}"
        _ => "Agent aborted"
      }
    } else {
      error
    }
    pattern_repair_trace_push(trace, summary)
    return Some(error)
  }
  None
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
}

///|
test "pattern repair trace keeps validation outcomes and omits model content" {
  let trace : Array[String] = []
  let _ = pattern_repair_record_event(
    {
      "event": "tool_result",
      "tool_name": "validate_pattern",
      "is_error": false,
      "content": "{\"valid\":false,\"diagnostic\":\"expected expression\"}",
    },
    trace,
  )
  let _ = pattern_repair_record_event(
    { "event": "reasoning_delta", "content": "private reasoning" },
    trace,
  )
  assert_eq(trace, ["validate_pattern: failed — expected expression"])
}

///|
test "pattern repair trace records steps and raw terminal errors" {
  let trace : Array[String] = []
  let _ = pattern_repair_record_event(
    { "event": "agent_step", "step": 3 },
    trace,
  )
  let failure = pattern_repair_record_event(
    {
      "event": "turn_failed",
      "error": "provider response could not be decoded",
    },
    trace,
  )
  assert_eq(failure, Some("provider response could not be decoded"))
  assert_eq(trace, ["Agent step 3", "provider response could not be decoded"])
}

///|
test "pattern repair trace remains bounded and retains recent events" {
  let trace : Array[String] = []
  let final_step = PatternRepairTraceMaxItems + 2
  for step in 1..<=final_step {
    pattern_repair_trace_push(trace, "Agent step \{step}")
  }
  assert_eq(trace.length(), PatternRepairTraceMaxItems)
  assert_eq(trace[0], PatternRepairTraceOmitted)
  assert_eq(trace[trace.length() - 1], "Agent step \{final_step}")
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
    error if @async.is_being_cancelled() => raise error
    error => return Failed("\{error}", [])
  }
  match process {
    TimedOut(trace) => TimedOut(trace)
    Finished(code, stderr, candidate, agent_error, trace) =>
      if candidate is Some((candidate, message)) {
        Candidate(candidate, message, trace)
      } else if agent_error is Some(error) {
        Failed(error, trace)
      } else if !stderr.trim().is_empty() {
        Failed(pattern_repair_diagnostic(stderr), trace)
      } else if code != 0 {
        Failed("Pattern Repair Agent process exited with code \{code}.", trace)
      } else {
        Failed("Pattern Repair Agent did not produce a subrun report.", trace)
      }
  }
}

///|
fn pattern_repair_failure(
  payload : @protocol.PatternRepairPayload,
  validation_status : @protocol.PatternRepairStatus,
  candidate_pattern : String?,
  message : String,
  trace : Array[String],
) -> @protocol.PatternRepairReply {
  {
    root: payload.root,
    generation: payload.generation,
    candidate_pattern,
    validation_status,
    message,
    trace,
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
      [],
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
  let (candidate, message, trace) = match candidate {
    Candidate(candidate, message, trace) => (candidate, message, trace)
    TimedOut(trace) =>
      return pattern_repair_failure(
        payload,
        TimedOut,
        None,
        "Pattern Repair Agent timed out after \{PatternRepairWallTimeoutSeconds} seconds. Try again.",
        trace,
      )
    Failed(error, trace) =>
      return pattern_repair_failure(payload, Failed, None, error, trace)
  }
  match validate_pattern_repair_candidate(root, candidate) {
    PatternRepairValid =>
      {
        root: payload.root,
        generation: payload.generation,
        candidate_pattern: Some(candidate),
        validation_status: Passed,
        message,
        trace,
      }
    PatternRepairUnavailable => {
      pattern_repair_trace_push(trace, "Host validation: unavailable")
      {
        root: payload.root,
        generation: payload.generation,
        candidate_pattern: Some(candidate),
        validation_status: Unavailable,
        message: "Host-side pattern validation is unavailable; candidate was not applied.",
        trace,
      }
    }
    PatternRepairInvalid(diagnostic) => {
      pattern_repair_trace_push(
        trace,
        "Host validation: failed — \{diagnostic}",
      )
      pattern_repair_failure(
        payload,
        Failed,
        Some(candidate),
        diagnostic,
        trace,
      )
    }
  }
}
