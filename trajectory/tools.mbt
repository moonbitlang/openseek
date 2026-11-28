///|
/// Open a span for one tool call, remembering where it lives so its result can
/// close it.
fn SessionBuilder::open_tool(
  self : SessionBuilder,
  call : @deepseek.ToolCall,
  ts : Int64,
  sequence~ : Int32,
) -> Unit {
  let kind = tool_kind(call.name)
  let job_ids = job_ids_from_arguments(call.arguments)
  let metadata : Map[String, Json] = Map([])
  if !call.arguments.trim().is_empty() {
    metadata["arguments"] = Json(excerpt(call.arguments, 240))
  }
  let index = self.emit_span(
    kind,
    ts,
    None,
    Running,
    Some(self.turn_id),
    tool_label(call.name, call.arguments),
    job_ids,
    None,
    metadata,
    sequence=Some(sequence),
  )
  self.open_tools[call.id] = { index, started_at_ms: ts, job_ids, }
}

///|
/// Close one span in place, merging `metadata` into what it already carries.
fn SessionBuilder::close_span(
  self : SessionBuilder,
  index : Int32,
  ts : Int64,
  status : SpanStatus,
  metadata : Map[String, Json],
) -> Unit {
  let span = self.spans[index]
  let merged = span.metadata.copy()
  for entry in metadata {
    merged[entry.0] = entry.1
  }
  let end = if ts < span.started_at_ms { span.started_at_ms } else { ts }
  self.spans[index] = {
    ..span,
    ended_at_ms: Some(end),
    status,
    metadata: merged,
  }
}

///|
/// Close a span that is still open at `ts`, keeping whatever status it has
/// when the caller has nothing better to say.
fn SessionBuilder::finish_span(
  self : SessionBuilder,
  index : Int32,
  ts : Int64,
  status : SpanStatus,
) -> Unit {
  self.close_span(index, ts, status, {})
}

///|
/// Close every tool span still open, for a turn that ended or a session that
/// stopped mid-call. A call with no result never reported an outcome, so it is
/// `Interrupted`, not `Failed`.
fn SessionBuilder::close_open_tools(
  self : SessionBuilder,
  ts : Int64,
  status : SpanStatus,
) -> Unit {
  for entry in self.open_tools {
    self.finish_span(entry.1.index, ts, status)
  }
  self.open_tools.clear()
}

///|
/// Apply one tool result: close its call's span, note any background job it
/// handed off, and hang the PTC trace it recorded underneath.
fn SessionBuilder::close_tool(
  self : SessionBuilder,
  result : @agent_session.ToolResult,
  ts : Int64,
  sequence~ : Int32,
) -> Unit {
  let status = if result.is_error() { Failed } else { Succeeded }
  let metadata : Map[String, Json] = Map([])
  match result.brief() {
    Some(brief) if !brief.trim().is_empty() =>
      metadata["brief"] = Json(excerpt(brief, 240))
    _ => ()
  }
  let call_id = result.tool_call_id()
  match self.open_tools.get(call_id) {
    Some(open) => {
      let span_id = self.spans[open.index].id
      self.close_span(open.index, ts, status, metadata)
      self.open_tools.remove(call_id)
      // A job tool's own report is the witness of how its jobs ended: a wait
      // that returned says they ended, not that they succeeded.
      let text = first_text(result.content())
      for job_id in open.job_ids {
        let known = match self.jobs.get(job_id) {
          Some(index) => self.spans[index].ended_at_ms is None
          None => false
        }
        if !known {
          continue
        }
        let status = match job_result_status(text, job_id) {
          Some(status) => Some(status)
          None =>
            if self.spans[open.index].kind is JobWait {
              Some(Succeeded)
            } else {
              None
            }
        }
        match status {
          Some(status) =>
            match self.jobs.get(job_id) {
              Some(index) => self.finish_span(index, ts, status)
              None => ()
            }
          None => ()
        }
      }
      // The subagent tool's own result names the child session: the exact
      // mount, with no guessing from timestamps even when two children start
      // inside one concurrent tool batch.
      if result.data() is Some({ "session": String(session), .. }) {
        self.run.child_mounts[session] = span_id
      }
      self.emit_background_job(
        result,
        open.started_at_ms,
        span_id,
        ts,
        sequence~,
      )
      self.emit_ptc_calls(result, span_id, ts, sequence~)
    }
    None => ()
  }
}

///|
/// Record a background job a tool result handed off, unless it is already
/// known. The job's own interval starts with the call that started it; nothing
/// in the log says when it ends, so it ends where a later wait observed it.
fn SessionBuilder::emit_background_job(
  self : SessionBuilder,
  result : @agent_session.ToolResult,
  started_at_ms : Int64,
  parent_id : String,
  ts : Int64,
  sequence~ : Int32,
) -> Unit {
  guard job_id_from_result(result) is Some(job_id) else { return }
  if self.jobs.get(job_id) is Some(_) {
    return
  }
  let metadata : Map[String, Json] = {
    "handed_off_at_ms": Json(ts.to_double()),
  }
  let index = self.emit_span(
    BackgroundJob,
    started_at_ms,
    None,
    Running,
    Some(parent_id),
    "background job \{job_id}",
    [job_id],
    None,
    metadata,
    sequence=Some(sequence),
  )
  self.jobs[job_id] = index
}

///|
/// Hang one `.mbtx` program's nested PTC calls under the script's span.
///
/// A call the trace timed — it carries the unix-millisecond stamps the PTC
/// server writes when the call opens and when it ends — is a real interval.
/// An older trace recorded only what was called and how it ended, so such a
/// call stays a zero-width marker at the script's end, flagged
/// `timing: unknown`: a bar there would invent an interval the log never
/// wrote. A timed call with no end was still open when its program stopped, and
/// cannot have outlived it, so the script's end bounds it.
///
/// A call whose own result names the child session it spawned — a `subagent`
/// run from inside the script — also registers that call as the child's mount,
/// so the child hangs under the call that made it and not under the script.
fn SessionBuilder::emit_ptc_calls(
  self : SessionBuilder,
  result : @agent_session.ToolResult,
  parent_id : String,
  ts : Int64,
  sequence~ : Int32,
) -> Unit {
  let calls = match result.data() {
    Some({ "ptc_calls": Array(calls), .. }) => calls
    _ => return
  }
  for call in calls {
    let name = match call {
      { "name": String(name), .. } => name
      _ => "call"
    }
    let status = match call {
      { "status": String("done"), .. } => Succeeded
      { "status": String("interrupted"), .. } => Interrupted
      { "status": String("failed"), .. } => Failed
      { "status": String("error"), .. } => Failed
      _ => Running
    }
    let started_at = match call {
      { "started_at_ms": Number(ms, ..), .. } => Some(ms.to_int64())
      _ => None
    }
    let recorded_end = match call {
      { "ended_at_ms": Number(ms, ..), .. } => Some(ms.to_int64())
      _ => None
    }
    let (start, end, timing) = match started_at {
      Some(start) => {
        let end = match recorded_end {
          Some(end) =>
            if end < start {
              start
            } else if end > ts {
              ts
            } else {
              end
            }
          None => if ts > start { ts } else { start }
        }
        (
          start,
          Some(end),
          if recorded_end is Some(_) {
            "measured"
          } else {
            "open_at_program_end"
          },
        )
      }
      None => (ts, Some(ts), "unknown")
    }
    // A call the program never closed never reported an outcome: it is
    // interrupted, not still running, and the script's end bounds it.
    let span_status = if recorded_end is None && status is Running {
      Interrupted
    } else {
      status
    }
    let metadata : Map[String, Json] = {
      "timing": Json(timing),
      "ptc_status": Json(status.tag()),
    }
    match call {
      { "arguments": arguments, .. } =>
        metadata["arguments"] = Json(excerpt(arguments.stringify(), 240))
      _ => ()
    }
    let index = self.emit_span(
      PtcToolCall,
      start,
      end,
      span_status,
      Some(parent_id),
      "ptc: \{name}",
      [],
      None,
      metadata,
      sequence=Some(sequence),
    )
    // A `subagent` call from inside the script carries the child it spawned in
    // its own result: that call is where the child belongs.
    match call {
      { "result": { "data": { "session": String(child), .. }, .. }, .. } =>
        self.run.child_mounts[child] = self.spans[index].id
      _ => ()
    }
  }
}
