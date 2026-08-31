///|
async fn run_pattern_repair_process(
  command : String,
  args : Array[String],
  input : String,
  cwd : String,
  env : Map[String, String],
) -> (Int, String, String) {
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
) -> (String, String)? {
  let input = ({ "pattern": pattern, "instruction": instruction } : Json).stringify() +
    "\n"
  let (code, stdout, _) = run_pattern_repair_process(
    state.engine,
    [
      "subrun", "pattern-repair", "--model", "deepseek-v4-pro", "--thinking", "no",
      "--max-steps", "4",
    ],
    input,
    root.0,
    agent_env,
  ) catch {
    _ => return None
  }
  guard code == 0 else { return None }
  for line in stdout.split("\n") {
    let json = @json.parse(line.trim()) catch { _ => continue }
    guard json is { "subrun_report": report, .. } else { continue }
    guard report
      is {
        "candidate_pattern": String(candidate),
        "message": String(message),
        ..
      } else {
      return None
    }
    return Some((candidate, message))
  }
  None
}

///|
async fn pattern_repair_op(
  state : HostState,
  agent_env : Map[String, String],
  payload : @protocol.PatternRepairPayload,
) -> @protocol.PatternRepairReply {
  let failure = fn(message : String) -> @protocol.PatternRepairReply {
    {
      root: payload.root,
      generation: payload.generation,
      candidate_pattern: payload.pattern,
      valid: false,
      message,
    }
  }
  guard state.engine != "" else {
    return failure("Pattern Repair Agent is unavailable.")
  }
  let root = WirePath::parse(payload.root).absolute
  let mut instruction = payload.instruction
  for attempt in 0..<3 {
    guard request_pattern_repair_candidate(
        state,
        agent_env,
        root,
        payload.pattern,
        instruction,
      )
      is Some((candidate, message)) else {
      return failure("Pattern Repair Agent returned no candidate.")
    }
    match validate_pattern_repair_candidate(state, root, candidate) {
      PatternRepairValid =>
        return {
          root: payload.root,
          generation: payload.generation,
          candidate_pattern: candidate,
          valid: true,
          message,
        }
      PatternRepairInvalid(code, diagnostic) => {
        if attempt == 2 {
          return failure("\{code}: \{diagnostic}")
        }
        instruction = "\{payload.instruction}\n\nPrevious candidate validation failed (attempt \{attempt + 1}): \{diagnostic}\nReturn a corrected candidate."
      }
    }
  }
  failure("Pattern Repair Agent could not produce a valid candidate.")
}
