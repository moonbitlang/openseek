///|
async fn run_pattern_repair_process(
  command : String,
  args : Array[String],
  input : String,
  cwd : String,
) -> (Int, String, String) {
  @async.with_task_group(group => {
    let (stdin_reader, stdin_writer) = @process.write_to_process()
    let (stdout_reader, child_stdout) = @process.read_from_process()
    let (stderr_reader, child_stderr) = @process.read_from_process()
    let process = @process.spawn(
      group,
      command,
      args,
      inherit_env=true,
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
async fn pattern_repair_op(
  state : HostState,
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
  let input = (
      { "pattern": payload.pattern, "instruction": payload.instruction } : Json).stringify() +
    "\n"
  let (code, stdout, stderr) = run_pattern_repair_process(
    state.engine,
    [
      "subrun", "pattern-repair", "--model", "deepseek-v4-pro", "--max-steps", "8",
    ],
    input,
    root.0,
  ) catch {
    error => return failure("Cannot start Pattern Repair Agent: \{error}")
  }
  guard code == 0 else {
    let detail = stderr.trim().to_owned()
    return failure(
      if detail.is_empty() {
        "Pattern Repair Agent failed."
      } else {
        detail
      },
    )
  }
  for line in stdout.split("\n") {
    let json = @json.parse(line.trim()) catch { _ => continue }
    guard json is { "subrun_report": report, .. } else { continue }
    guard report
      is {
        "candidate_pattern": String(candidate),
        "message": String(message),
        ..
      } else {
      return failure("Pattern Repair Agent returned an invalid candidate.")
    }
    return {
      root: payload.root,
      generation: payload.generation,
      candidate_pattern: candidate,
      valid: true,
      message,
    }
  }
  failure("Pattern Repair Agent returned no candidate.")
}
