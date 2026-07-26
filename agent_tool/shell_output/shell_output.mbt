///|
/// Tool `shell_output`: read a background shell job's output and status by id.
/// The id comes from `shell run_in_background`, or from a foreground command that
/// was moved to the background when it exceeded its `timeout_ms`.
pub fn definition(
  bg_runtime : @bgjobs.BgJobRuntime,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="shell_output",
    description=(
      #|Read a background shell job's recent output and status by its job_id (returned by
      #|shell run_in_background, or by a command moved to the background on timeout).
      #|Returns the most recent window of captured output (with truncation metadata naming
      #|the total size when output exceeds the window) and whether the job is still
      #|running. If you need the job's result before you can continue and have no other
      #|work to do, pass wait_ms to block until it finishes instead of checking
      #|repeatedly.
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "job_id": { "type": "string" },
        "wait_ms": {
          "type": "number",
          "description": (
            #|Wait up to this many milliseconds (capped at 120000) for the job to finish
            #|before reading. Use when you need the result now and have nothing else to
            #|do; never poll in a loop.
          ),
        },
      },
      "required": ["job_id"],
    }),
    execute=Async(arguments => execute(bg_runtime, arguments)),
  )
}

///|
async fn execute(
  bg_runtime : @bgjobs.BgJobRuntime,
  arguments : Json,
) -> @agent_tool.ToolAction {
  guard arguments is { "job_id": String(job_id), .. } else {
    return @agent_tool.ToolAction::respond(
      "error: shell_output requires a string job_id",
      is_error=true,
    )
  }
  guard bg_runtime.snapshot(job_id) is Some(_) else {
    return @agent_tool.ToolAction::respond(
      "error: no background job with id \{job_id}",
      is_error=true,
    )
  }
  // Await-before-read: with wait_ms the caller blocks (bounded) until the job
  // exits — one efficient await instead of a model round trip per poll. A
  // deadline expiry is not an error; the response simply reports the job still
  // running. The cap keeps a single tool call from holding the turn for long —
  // the model can always call again.
  match wait_ms(arguments) {
    Ok(Some(wait)) => {
      let _ = bg_runtime.wait_exit(job_id, wait)
    }
    Ok(None) => ()
    Err(message) =>
      return @agent_tool.ToolAction::respond(message, is_error=true)
  }
  // Recent output, bounded to a window so a poll cannot flood the conversation
  // with a large job's full log. For output over the window, show the *tail*
  // (recent progress).
  let window = 12000
  let output = bg_runtime.read_output_tail(job_id, window).unwrap_or("")
  // Re-snapshot *after* the awaited read: the job may have appended more output
  // or exited while the read yielded, so size/status/binary/truncation in the
  // footer must reflect that post-read state, not a stale pre-read one — else a
  // tail could be presented as complete or with an out-of-date status.
  guard bg_runtime.snapshot(job_id) is Some(snapshot) else {
    return @agent_tool.ToolAction::respond(
      "error: no background job with id \{job_id}",
      is_error=true,
    )
  }
  let (status_label, exit_error) = match snapshot.status {
    Running => ("running", false)
    Exited(code) => ("exit=\{code}", code != 0)
    // A watchdog kill (flooded past the hard cap) is named as such, so the model
    // does not read it as a requested stop.
    Stopped if snapshot.killed_by_output_limit =>
      ("stopped killed_at_output_cap=true", true)
    Stopped if snapshot.killed_by_time_limit =>
      ("stopped killed_at_time_cap=true", true)
    Stopped => ("stopped", true)
  }
  // Preserve the foreground path's error semantics for a job read later: binary
  // (non-UTF-8) output and a sandboxed source-write denial are tool errors even
  // when the command exited 0. Scan the *full* retained output for a denial (the
  // denial line can be earlier than the displayed tail), but only for a sandboxed
  // job — so a full read is done only in that rare case.
  let sandbox_denied = if snapshot.sandboxed_command is Some(command) {
    let full = bg_runtime.read_output(job_id).unwrap_or(output)
    command.output_reports_denial(full)
  } else {
    false
  }
  let is_error = exit_error || snapshot.had_invalid_utf8 || sandbox_denied
  // Truncated whenever what we show is less than what the job produced — this
  // covers the window (large output), a memory-only runtime that dropped output
  // past the budget, and a hard-cap drop — so a prefix is never presented as the
  // complete output.
  let shown = output.char_length()
  let truncation = if shown < snapshot.size || snapshot.output_truncated {
    let cap = if snapshot.output_truncated {
      " output_dropped_at_cap=true"
    } else {
      ""
    }
    " truncated=true total_chars=\{snapshot.size} shown_chars=\{shown}\{cap}"
  } else {
    ""
  }
  let binary = if snapshot.had_invalid_utf8 {
    " binary_output=true"
  } else {
    ""
  }
  let footer = "<system>job=\{job_id} \{status_label}\{truncation}\{binary}</system>"
  // Assemble: output, then the source-write denial guidance (like the foreground
  // path), then the `<system>` footer LAST so it stays the trailing metadata line.
  let content = StringBuilder()
  if output != "" {
    content.write_string(output)
    if !output.has_suffix("\n") {
      content.write_string("\n")
    }
  }
  if sandbox_denied {
    content.write_string(@shell.source_write_denial_feedback())
    content.write_string("\n")
  }
  content.write_string(footer)
  let content = content.to_string()
  @agent_tool.ToolAction::respond(content, is_error~)
}

///|
/// Longest a single shell_output call may block awaiting a job, so one tool
/// call cannot hold the turn indefinitely; the model can always call again.
let max_wait_ms : Int = 120_000

///|
/// Decode the optional `wait_ms` argument: a positive number, capped at
/// `max_wait_ms`. Absent/null means no waiting.
fn wait_ms(arguments : Json) -> Result[Int?, String] {
  match arguments {
    { "wait_ms": Number(value, ..), .. } => {
      let wait = value.to_int()
      if wait <= 0 {
        Err("error: shell_output wait_ms must be a positive number")
      } else if wait > max_wait_ms {
        Ok(Some(max_wait_ms))
      } else {
        Ok(Some(wait))
      }
    }
    { "wait_ms": Null, .. } => Ok(None)
    // Present but not a number (e.g. a stringified "30000"): reject rather than
    // silently skip the wait — the local dispatcher does not enforce the JSON
    // schema, so the decoder must.
    { "wait_ms": _, .. } => Err("error: shell_output wait_ms must be a number")
    _ => Ok(None)
  }
}
