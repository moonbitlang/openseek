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
/// The child's session id inside its private session root.
const PatternRepairSessionId : String = "pattern-repair"

///|
priv enum PatternRepairProcessOutcome {
  /// The child exited with this code and this stderr.
  Finished(Int, String)
  TimedOut
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
/// Run the child and wait for it, within the wall timeout. Its stdout is text
/// for people and is drained unread; what it did is in its session, and how
/// it ended is in its result file.
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
      // One request line; stdin stays open until the child exits, because the
      // child treats its closing as cancellation.
      stdin_writer.write(input)
      let stdout_task = group.spawn(() => {
        defer stdout_reader.close()
        while (stdout_reader.read_some(max_len=4096) catch { _ => None })
              is Some(_) {

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
      stdout_task.wait()
      (code, stderr_task.wait())
    })
  })
  match result {
    Some((code, stderr)) => Finished(code, stderr)
    None => TimedOut
  }
}

///|
/// The bounded trace of a repair, from the child's session: its steps,
/// validation outcomes, submission, and how its turn ended. Assistant and
/// reasoning content and tool arguments never reach the trace.
fn pattern_repair_trace_of(session : @agent_session.Session) -> Array[String] {
  let trace : Array[String] = []
  let mut steps = 0
  for event in session.events() {
    if event.is_agent_step() {
      steps += 1
      pattern_repair_trace_push(trace, "Agent step \{steps}")
    }
    match event.item() {
      Tool(result) if result.tool_name() == "validate_pattern" => {
        let content = result.content().text()
        let outcome = @json.parse(content) catch { _ => Json::null() }
        if outcome is { "valid": True, .. } {
          pattern_repair_trace_push(trace, "validate_pattern: passed")
        } else if outcome
          is { "valid": False, "diagnostic": String(diagnostic), .. } {
          pattern_repair_trace_push(
            trace,
            "validate_pattern: failed — \{diagnostic}",
          )
        } else if result.is_error() {
          pattern_repair_trace_push(trace, "validate_pattern: \{content}")
        } else {
          pattern_repair_trace_push(trace, "validate_pattern: returned")
        }
      }
      Tool(result) if result.tool_name() == "submit_pattern_repair" =>
        pattern_repair_trace_push(trace, "submit_pattern_repair: returned")
      Terminal(MaxStepsExhausted) =>
        pattern_repair_trace_push(trace, "Agent step limit exhausted")
      Terminal(ContextYield(_)) =>
        pattern_repair_trace_push(trace, "Agent yielded at its context limit")
      Terminal(Aborted(reason)) =>
        pattern_repair_trace_push(trace, "Agent aborted: \{reason}")
      Terminal(Interrupted(reason)) =>
        pattern_repair_trace_push(trace, "Agent interrupted: \{reason}")
      Terminal(Failed(error)) => pattern_repair_trace_push(trace, error)
      _ => ()
    }
  }
  trace
}

///|
/// The repair's trace, read from the child's session; empty when the child
/// recorded nothing (it failed before its turn, or its record is unreadable).
async fn pattern_repair_session_trace(session_root : String) -> Array[String] {
  let session = @store.SessionStore(session_root).load(
    SessionId(PatternRepairSessionId),
  ) catch {
    _ => return []
  }
  pattern_repair_trace_of(session)
}

///|
/// How a finished child ended, from its result file: a candidate, or why
/// there is none. `None` only when the child wrote no result, which leaves the
/// exit status and stderr to explain; a result that exists but cannot be read
/// or decoded is an error of its own.
async fn pattern_repair_result(
  path : String,
) -> Result[(String, String), String]? {
  let text = @fs.read_file(path).text() catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => return None
    error =>
      return Some(
        Err("The Pattern Repair Agent's result is unreadable: \{error}"),
      )
  }
  let result = @openseek_protocol.parse_run_result(@json.parse(text)) catch {
    error =>
      return Some(
        Err("The Pattern Repair Agent's result is malformed: \{error}"),
      )
  }
  match result.status {
    Completed(
      output={
        "candidate_pattern": String(pattern),
        "message": String(message),
        ..
      }
    ) => Some(Ok((pattern, message)))
    Completed(output~) =>
      Some(Err(pattern_repair_diagnostic(output.stringify())))
    NoReport => Some(Err("Pattern Repair Agent finished without a submission."))
    MaxStepsExhausted => Some(Err("Pattern Repair Agent exhausted its steps."))
    ContextYield(reason~)
    | Aborted(reason~)
    | Interrupted(reason~)
    | Failed(reason~) => Some(Err(pattern_repair_diagnostic(reason)))
  }
}

///|
test "pattern repair trace keeps validation outcomes and omits model content" {
  let session = @agent_session.Session(SessionId("t"), system_prompt="")
    .append(Assistant(AssistantMessage("private reasoning about the pattern")))
    .append(
      Tool(
        ToolResult(tool_call_id="c1", tool_name="validate_pattern", content=[
          Text("{\"valid\":false,\"diagnostic\":\"expected expression\"}"),
        ]),
      ),
    )
    .append(Terminal(MaxStepsExhausted))
  assert_eq(pattern_repair_trace_of(session), [
    "Agent step 1", "validate_pattern: failed — expected expression", "Agent step limit exhausted",
  ])
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
  // A private directory for the child's result and session, removed when
  // the repair is done: nothing of a repair outlives it but its reply.
  let dir = @fs.tmpdir(prefix="openseek-pattern-repair-") catch {
    error => return Failed("\{error}", [])
  }
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let result_path = "\{dir}/result.json"
  let session_root = "\{dir}/sessions"
  let request : @openseek_protocol.RunRequest = {
    request_id: None,
    kind: Some("pattern-repair"),
    input: { "pattern": pattern, "instruction": instruction },
    max_steps: None,
  }
  let args = [
    "run",
    "--input-format",
    "json",
    "--cancel-on-stdin-eof",
    "--kind",
    "pattern-repair",
    "--result-file",
    result_path,
    "--session",
    PatternRepairSessionId,
    "--session-root",
    session_root,
    "--model",
    model,
  ]
  if thinking is Some(thinking) {
    args.push("--thinking")
    args.push(thinking.wire())
  }
  let process = run_pattern_repair_process(
    state.engine,
    args,
    request.to_json().stringify() + "\n",
    root.0,
    agent_env,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    error => return Failed("\{error}", [])
  }
  let trace = pattern_repair_session_trace(session_root)
  match process {
    TimedOut => {
      pattern_repair_trace_push(
        trace,
        "Host Agent timed out after \{PatternRepairWallTimeoutSeconds} seconds",
      )
      TimedOut(trace)
    }
    Finished(code, stderr) =>
      match pattern_repair_result(result_path) {
        Some(Ok((candidate, message))) => {
          pattern_repair_trace_push(trace, "Candidate submitted")
          Candidate(candidate, message, trace)
        }
        Some(Err(error)) => Failed(error, trace)
        None if !stderr.trim().is_empty() =>
          Failed(pattern_repair_diagnostic(stderr), trace)
        None if code != 0 =>
          Failed(
            "Pattern Repair Agent process exited with code \{code}.",
            trace,
          )
        None => Failed("Pattern Repair Agent did not produce a result.", trace)
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

///|
async test "pattern repair reads its candidate, or why there is none, from the result" {
  let dir = @fs.tmpdir(prefix="openseek-pattern-repair-result-")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let path = "\{dir}/result.json"
  async fn read(result : String) -> Result[(String, String), String]? {
    @fs.write_file(path, result, create_mode=CreateOrTruncate)
    pattern_repair_result(path)
  }
  assert_eq(
    read(
      (
        #|{"version":1,"status":"completed","output":{"candidate_pattern":"foo($x)","message":"closed the call"}}
      ),
    ),
    Some(Ok(("foo($x)", "closed the call"))),
  )
  assert_eq(
    read(
      (
        #|{"version":1,"status":"no_report"}
      ),
    ),
    Some(Err("Pattern Repair Agent finished without a submission.")),
  )
  assert_eq(
    read(
      (
        #|{"version":1,"status":"failed","reason":"an API key is required"}
      ),
    ),
    Some(Err("an API key is required")),
  )
  // A result that exists but cannot be decoded says so; only a missing one
  // leaves the exit status to explain.
  guard read("not json") is Some(Err(error)) else {
    fail("a malformed result must be reported")
  }
  assert_true(error.contains("malformed"))
  @fs.remove(path)
  assert_eq(pattern_repair_result(path), None)
}
