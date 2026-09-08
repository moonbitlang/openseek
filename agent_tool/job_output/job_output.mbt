///|
/// Tool `job_output`: read a background job's output and status by id.
/// The id comes from a command automatically moved to the background after its
/// foreground grace period.
pub fn definition(
  bg_runtime : @bgjobs.BgJobRuntime,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="job_output",
    description=(
      #|Read a background job's recent output and status by its job_id (returned when
      #|a command moves to the background after its foreground grace period).
      #|Returns the most recent window of captured output (with truncation metadata naming
      #|the total size when output exceeds the window) and whether the job is still
      #|running. Output beyond the window is retained: pass offset (a character offset
      #|from the START) to read an earlier window instead — offsets 0, 12000, 24000, …
      #|page through all of total_chars. If you need the job's result before you can
      #|continue and have no other work to do, call job_wait with job_ids first.
      #|This tool reads immediately without waiting for completion; it has no wait_ms.
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "job_id": { "type": "string" },
        "offset": {
          "type": "number",
          "description": (
            #|Read the window that starts at this character offset from the START of the
            #|captured output, instead of the most recent window. Use it to page through
            #|output larger than one window: the footer's total_chars says how much there
            #|is, so offsets 0, 12000, 24000, … cover all of it.
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
  let input = @decode.decode(arguments) catch {
    error => {
      let message = @tool_error.failure_message("\{error}")
      return @agent_tool.respond("error: \{message}", is_error=true)
    }
  }
  let job_id = input.job_id
  guard bg_runtime.snapshot(job_id) is Some(_) else {
    return @agent_tool.respond(
      "error: no background job with id \{job_id}",
      is_error=true,
    )
  }
  // Recent output, bounded to a window so a poll cannot flood the conversation
  // with a large job's full log. For output over the window, show the *tail*
  // (recent progress).
  let page = input.offset
  let window = 12000
  // A page reads the retained log from the start — the spill file for a large
  // job — so a result bigger than one window (a workflow's several reports)
  // is reachable in full; the default stays the tail, which is what a poll on
  // a running job wants.
  let raw_output = match page {
    Some(offset) =>
      page_of(bg_runtime.read_output(job_id).unwrap_or(""), offset~, window~)
    None => bg_runtime.read_output_tail(job_id, window).unwrap_or("")
  }
  // Re-snapshot *after* the awaited read: the job may have appended more output
  // or exited while the read yielded, so size/status/binary/truncation in the
  // footer must reflect that post-read state, not a stale pre-read one — else a
  // tail could be presented as complete or with an out-of-date status.
  guard bg_runtime.snapshot(job_id) is Some(snapshot) else {
    return @agent_tool.respond(
      "error: no background job with id \{job_id}",
      is_error=true,
    )
  }
  let output = apply_output_rewrites(raw_output, snapshot.output_rewrites)
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
  // (non-UTF-8) output and a refused access are tool errors even when the
  // command exited 0.
  //
  // Running jobs classify only the bounded recent tail. Once terminal, the
  // runtime scans the retained log and caches the result, so a refusal that
  // scrolled out of view is still reported without re-decoding up to 20MB on
  // every later read.
  let sandbox_denied = if snapshot.status is Running {
    if snapshot.moonrun_policy_active &&
      @sandbox.output_reports_policy_refusal(raw_output) {
      Some(@sandbox.policy_refusal_feedback)
    } else if snapshot.sandboxed_command is Some(command) &&
      command.output_reports_denial(raw_output) {
      Some(command.denial_feedback())
    } else {
      None
    }
  } else {
    bg_runtime.terminal_denial_feedback(job_id)
  }
  let is_error = exit_error ||
    snapshot.had_invalid_utf8 ||
    sandbox_denied is Some(_)
  // Truncated whenever what we show is less than what the job produced — this
  // covers the window (large output), a memory-only runtime that dropped output
  // past the budget, and a hard-cap drop — so a prefix is never presented as the
  // complete output.
  let shown = raw_output.char_length()
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
  let paging = match page {
    Some(offset) => " window_offset=\{offset}"
    None => ""
  }
  let footer = "<system>job=\{job_id} \{status_label}\{truncation}\{paging}\{binary}</system>"
  // Assemble: output, then the source-write denial guidance (like the foreground
  // path), then the `<system>` footer LAST so it stays the trailing metadata line.
  let content = StringBuilder()
  if output != "" {
    content.write_string(output)
    if !output.has_suffix("\n") {
      content.write_string("\n")
    }
  }
  if sandbox_denied is Some(guidance) {
    content.write_string(guidance)
    content.write_string("\n")
  }
  content.write_string(footer)
  let content = content.to_string()
  @agent_tool.respond(content, is_error~)
}

///|
fn apply_output_rewrites(
  text : String,
  rewrites : Array[(String, String)],
) -> String {
  rewrites.fold(init=text, (output, rewrite) => {
    let (old, replacement) = rewrite
    output.replace_all(old~, new=replacement)
  })
}

///|
/// The `window` characters of `text` starting at character `offset` — empty
/// past the end. Counted in characters, the unit the footer's `total_chars`
/// and `shown_chars` use, so the offsets a reader computes from them land
/// where it expects.
fn page_of(text : String, offset~ : Int, window~ : Int) -> String {
  // `iter()` yields characters, so drop/take count characters, not code units.
  String::from_iter(text.iter().drop(offset).take(window))
}
