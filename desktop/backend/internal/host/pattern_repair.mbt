///|
/// A bounded wall clock prevents a provider or its retries from holding the
/// search UI indefinitely. The provider has its own shorter idle timeout;
/// this remains the final guard for stalled process setup and future clients.
const PatternRepairWallTimeoutMs = 180_000

///|
priv enum PatternRepairProcessOutcome {
  Finished(Int, String)
  TimedOut
}

///|
priv enum PatternRepairCandidateOutcome {
  Candidate(String, String)
  TimedOut
  NoCandidate
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
      let _ = stderr_task.wait()
      (code, stdout)
    })
  })
  match result {
    Some((code, stdout)) => Finished(code, stdout)
    None => TimedOut
  }
}

///|
/// Run the bundled OpenSeek executable as a one-shot Pattern Repair Agent.
/// The child receives no workspace tools; it can only submit a candidate report.
async fn request_pattern_repair_candidate(
  state : HostState,
  agent_env : Map[String, String],
  root : @pathx.Absolute,
  pattern : String,
  instruction : String,
  model~ : String,
  thinking~ : @protocol.OpenSeekThinking?,
) -> PatternRepairCandidateOutcome {
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
    _ => return NoCandidate
  }
  match process {
    TimedOut => TimedOut
    Finished(code, stdout) => {
      let mut provider_timed_out = false
      for line in stdout.split("\n") {
        let json = @json.parse(line.trim()) catch { _ => continue }
        if json is { "event": String("provider_request_timed_out"), .. } {
          provider_timed_out = true
          continue
        }
        guard code == 0 else { continue }
        guard json is { "subrun_report": report, .. } else { continue }
        guard report
          is {
            "candidate_pattern": String(candidate),
            "message": String(message),
            ..
          } else {
          return NoCandidate
        }
        return Candidate(candidate, message)
      }
      if provider_timed_out {
        TimedOut
      } else {
        NoCandidate
      }
    }
  }
}

///|
async fn pattern_repair_op(
  state : HostState,
  agent_env : Map[String, String],
  payload : @protocol.PatternRepairPayload,
) -> @protocol.PatternRepairReply {
  let failure : (String, String, String) -> @protocol.PatternRepairReply = (
    candidate_pattern,
    validation_status,
    message,
  ) => {
    root: payload.root,
    generation: payload.generation,
    candidate_pattern,
    valid: false,
    validation_status,
    message,
  }
  guard state.engine != "" else {
    return failure(
      payload.pattern,
      "unavailable",
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
      return failure(
        payload.pattern,
        "timed_out",
        "Pattern repair timed out while contacting the AI provider. Check your connection or provider endpoint, then retry.",
      )
    NoCandidate =>
      return failure(
        payload.pattern,
        "unavailable",
        "Pattern Repair Agent returned no candidate.",
      )
  }
  match validate_pattern_repair_candidate(root, candidate) {
    PatternRepairValid =>
      {
        root: payload.root,
        generation: payload.generation,
        candidate_pattern: candidate,
        valid: true,
        validation_status: "passed",
        message,
      }
    PatternRepairUnavailable =>
      {
        root: payload.root,
        generation: payload.generation,
        candidate_pattern: candidate,
        valid: true,
        validation_status: "unavailable",
        message,
      }
    PatternRepairInvalid(code, diagnostic) =>
      failure(candidate, "failed", "\{code}: \{diagnostic}")
  }
}
