///|
/// Fold one session's durable events into spans.
///
/// When `AssistantMessage.started_at_ms` is present, a model span uses that
/// exact request start; older logs lacking it read backwards from the
/// response to the previous step boundary (the turn's input, or the last tool
/// result) and end at the assistant event's own timestamp. Tool spans pair an
/// assistant event's call with the result event that answers it, so their
/// edges are exact.
fn build_session(
  builder : SessionBuilder,
  events : Array[@agent_session.SessionEvent],
) -> Unit {
  let mut first_event = true
  for event in events {
    let ts = event.unix_ms()
    let sequence = event.sequence()
    if first_event {
      builder.first_ms = ts
      builder.last_boundary_ms = ts
      builder.started = true
      first_event = false
    }
    builder.last_ms = ts
    match event.item() {
      User(message) => {
        let text = first_text(message.content())
        match builder.turn_index {
          Some(_) =>
            builder.emit_milestone(
              ts,
              Steer,
              "steer: \{excerpt(text, MaxLabelChars)}",
              { "text": Json(excerpt(text, 240)) },
              sequence~,
            )
          None => builder.open_turn(ts, text, sequence~)
        }
      }
      Assistant(message) => {
        // A checkpoint replay restates an answer an earlier event already
        // owns. Counting it would double the model step and its tool calls.
        if message.is_replay() {
          continue
        }
        builder.ensure_turn(ts, sequence~)
        let metadata : Map[String, Json] = Map([])
        match message.usage() {
          Some(usage) => {
            builder.run.prompt_tokens += usage.prompt_tokens.to_int64()
            builder.run.completion_tokens += usage.completion_tokens.to_int64()
            metadata["prompt_tokens"] = Json(usage.prompt_tokens.to_double())
            metadata["completion_tokens"] = Json(
              usage.completion_tokens.to_double(),
            )
          }
          None => ()
        }
        if !message.content().is_empty() {
          metadata["text"] = Json(excerpt(message.content(), 240))
        }
        // A message written after the request clock exists says when its
        // request was issued, so the step is a real interval. Before that, the
        // previous boundary is the best the log has, and it absorbs any
        // queueing into the model step.
        let started = match message.started_at_ms() {
          Some(start) if start >= builder.first_ms && start <= ts => start
          _ => builder.last_boundary_ms
        }
        ignore(
          builder.emit_span(
            LlmCall,
            started,
            Some(ts),
            Succeeded,
            Some(builder.turn_id),
            "model call",
            [],
            None,
            metadata,
            sequence=Some(sequence),
          ),
        )
        builder.last_boundary_ms = ts
        for call in message.tool_calls() {
          builder.open_tool(call, ts, sequence~)
        }
      }
      Tool(result) => {
        builder.close_tool(result, ts, sequence~)
        builder.last_boundary_ms = ts
      }
      Runtime(notice) =>
        builder.emit_milestone(
          ts,
          RuntimeNotice,
          "notice: \{excerpt(notice.content(), MaxLabelChars)}",
          { "text": Json(excerpt(notice.content(), 240)) },
          sequence~,
        )
      Summary(summary) =>
        builder.emit_milestone(
          ts,
          Compaction,
          "compaction \{summary.from_sequence()}–\{summary.to_sequence()}",
          {
            "from_sequence": Json(summary.from_sequence().to_double()),
            "to_sequence": Json(summary.to_sequence().to_double()),
            "text": Json(excerpt(summary.content(), 240)),
          },
          sequence~,
        )
      Terminal(terminal) => builder.close_turn(ts, terminal, sequence~)
    }
  }
}

///|
/// Open a turn span at `ts`, carrying the prompt that started it.
fn SessionBuilder::open_turn(
  self : SessionBuilder,
  ts : Int64,
  prompt : String,
  sequence~ : Int32,
) -> Unit {
  self.turn_count += 1
  self.run.turn_count += 1
  self.turn_id = "\{self.session_id}:turn:\{self.turn_count}"
  let metadata : Map[String, Json] = Map([])
  if !prompt.trim().is_empty() {
    metadata["prompt"] = Json(excerpt(prompt, 240))
  }
  self.spans.push({
    id: self.turn_id,
    parent_id: None,
    session_id: self.session_id,
    title: self.title,
    depth: 0,
    kind: Turn,
    status: Running,
    label: "Turn \{self.turn_count}",
    started_at_ms: ts,
    ended_at_ms: None,
    job_id: None,
    job_ids: [],
    sequence: Some(sequence),
    tag: None,
    metadata,
  })
  self.turn_index = Some(self.spans.length() - 1)
  self.last_boundary_ms = ts
}

///|
/// Make sure a turn is open. A log whose first item is not a user message (a
/// cut-off write, a session created by a tool) still gets a turn, so its steps
/// are not orphaned.
fn SessionBuilder::ensure_turn(
  self : SessionBuilder,
  ts : Int64,
  sequence~ : Int32,
) -> Unit {
  if self.turn_index is None {
    self.open_turn(ts, "", sequence~)
  }
}

///|
/// Close the open turn with the terminal that ended it.
fn SessionBuilder::close_turn(
  self : SessionBuilder,
  ts : Int64,
  terminal : @agent_session.TurnTerminal,
  sequence~ : Int32,
) -> Unit {
  let (status, message) = match terminal {
    Finished(_) => (Succeeded, None)
    ContextYield(notice) => (Yielded, Some(notice))
    Aborted(reason) => (Aborted, Some(reason))
    Interrupted(reason) => (Interrupted, Some(reason))
    MaxStepsExhausted => (Aborted, Some("max steps exhausted"))
    Failed(error) => (Failed, Some(error))
  }
  self.close_open_tools(ts, Interrupted)
  match self.turn_index {
    Some(index) => {
      let turn = self.spans[index]
      let metadata = turn.metadata.copy()
      if message is Some(text) && !text.trim().is_empty() {
        metadata["message"] = Json(excerpt(text, 240))
      }
      self.spans[index] = { ..turn, ended_at_ms: Some(ts), status, metadata, }
    }
    None => ()
  }
  if terminal is ContextYield(_) {
    self.emit_milestone(ts, ContextYield, "context yield", {}, sequence~)
  }
  self.turn_index = None
}

///|
/// Append one span and add its duration to the run totals for its kind.
fn SessionBuilder::emit_span(
  self : SessionBuilder,
  kind : SpanKind,
  started_at_ms : Int64,
  ended_at_ms : Int64?,
  status : SpanStatus,
  parent_id : String?,
  label : String,
  job_ids : Array[String],
  tag : MilestoneTag?,
  metadata : Map[String, Json],
  sequence~ : Int32?,
) -> Int32 {
  let id = "\{self.session_id}:span:\{self.spans.length()}"
  self.spans.push({
    id,
    parent_id,
    session_id: self.session_id,
    title: self.title,
    depth: 0,
    kind,
    status,
    label,
    started_at_ms,
    ended_at_ms,
    job_id: job_ids.get(0),
    job_ids,
    sequence,
    tag,
    metadata,
  })
  self.spans.length() - 1
}

///|
/// Append a zero-width milestone at `ts`.
fn SessionBuilder::emit_milestone(
  self : SessionBuilder,
  ts : Int64,
  tag : MilestoneTag,
  label : String,
  metadata : Map[String, Json],
  sequence~ : Int32,
) -> Unit {
  let id = "\{self.session_id}:mark:\{self.spans.length()}"
  let parent = match self.turn_index {
    Some(_) => Some(self.turn_id)
    None => None
  }
  self.spans.push({
    id,
    parent_id: parent,
    session_id: self.session_id,
    title: self.title,
    depth: 0,
    kind: Milestone,
    status: Succeeded,
    label,
    started_at_ms: ts,
    ended_at_ms: Some(ts),
    job_id: None,
    job_ids: [],
    sequence: Some(sequence),
    tag: Some(tag),
    metadata,
  })
}

///|
/// The span kind one tool call belongs to.
fn tool_kind(name : String) -> SpanKind {
  match name {
    "mbtx" => WorkflowScript
    "job_wait" => JobWait
    _ => ToolExec
  }
}

///|
/// A one-line label for a tool call: its name plus the call's own description
/// when the arguments carry one.
fn tool_label(name : String, arguments : String) -> String {
  let parsed : Json = @json.parse(arguments) catch { _ => return name }
  let description = match parsed {
    { "description": String(text), .. } => excerpt(text, MaxLabelChars)
    _ => ""
  }
  if description.is_empty() {
    name
  } else {
    "\{name}: \{description}"
  }
}

///|

///|
/// The job id a tool result handed off to the background, if it did.
///
/// A PTC program that outlives its foreground deadline is adopted as a job and
/// records its id in the trace; the `mbtx` tool also says so in the text it
/// returns ("moved to the background as job <id>"). Either witness is enough:
/// the span is about the job, not about how the caller learned its id.
fn job_id_from_result(result : @agent_session.ToolResult) -> String? {
  if result.data() is Some({ "ptc_job_id": String(id), .. }) {
    return Some(id)
  }
  let text = first_text(result.content())
  match text.find("as job ") {
    Some(index) => {
      let tail = text[index.to_int() + 7:].to_owned()
      let token = match tail.find(" ") {
        Some(end) => tail[:end.to_int()].to_owned()
        None => tail
      }
      let trimmed = token
        .trim_end(chars=")")
        .trim_end(chars=",")
        .trim_end(chars=".")
        .to_owned()
      if trimmed.is_empty() {
        None
      } else {
        Some(trimmed)
      }
    }
    None => None
  }
}

///|
/// Every job id a tool call names (`job_wait` takes a list; the others one
/// id). Deduplicated, in the order written.
fn job_ids_from_arguments(arguments : String) -> Array[String] {
  let parsed : Json = @json.parse(arguments) catch { _ => return [] }
  match parsed {
    { "job_id": String(id), .. } => [id]
    { "job_ids": Array(items), .. } => {
      let ids : Array[String] = []
      for item in items {
        if item is String(id) && !ids.contains(id) {
          ids.push(id)
        }
      }
      ids
    }
    _ => []
  }
}

///|
/// How a job tool's own report says a job ended, or `None` while it is still
/// running.
///
/// `job_wait`, `job_output` and `job_stop` each print the job id with its
/// state (`<id> exit=3`, `stopped killed_at_time_cap=true`, the
/// `<system>job=<id> exit=0 ...</system>` footer). Reading that is the only
/// honest witness: a wait that returned says the job ended, not that it
/// succeeded.
fn job_result_status(text : String, job_id : String) -> SpanStatus? {
  guard text.contains(job_id) else { return None }
  // Keep only the report segments that name this job: another job's exit code
  // in the same reply must not decide this one's outcome.
  let relevant = relevant_job_segments(text, job_id)
  if relevant.is_empty() {
    return None
  }
  for line_view in relevant.split("\n") {
    let line = line_view.to_owned()
    if line.is_empty() {
      continue
    }
    let tokens : Array[String] = [
      for tok in line.split(" ") => {
        tok
        .trim_end(chars=";")
        .trim_end(chars=",")
        .trim_end(chars=".")
        .trim_end(chars="</system>")
        .to_owned()
      }
    ]
    if tokens.contains("killed_at_output_cap=true") ||
      tokens.contains("killed_at_time_cap=true") {
      return Some(Failed)
    }
    if line.has_prefix("stopped background job \{job_id}") {
      return Some(Aborted)
    }
    for i, tok in tokens {
      if tok.strip_prefix("exit=") is Some(code) {
        return Some(if code == "0" { Succeeded } else { Failed })
      }
      if tok == "exited" && i + 1 < tokens.length() {
        return Some(if tokens[i + 1] == "0" { Succeeded } else { Failed })
      }
      if (tok == job_id || tok == "job=\{job_id}") && i + 1 < tokens.length() {
        let next = tokens[i + 1]
        if next == "failed" {
          return Some(Failed)
        }
        if next == "stopped" {
          return Some(Aborted)
        }
        if next == "running" && !tokens.contains("ended") {
          return None
        }
      }
    }
  }
  Some(Succeeded)
}

///|
/// The lines of a job report that name `job_id`, each newline-terminated so a
/// status cannot leak in from the neighbouring job's line.
fn relevant_job_segments(text : String, job_id : String) -> String {
  let builder = StringBuilder()
  for line in text.split("\n") {
    let owned = line.to_owned()
    if owned.contains(job_id) {
      builder.write_string(owned)
      builder.write_string("\n")
    }
  }
  builder.to_string()
}
