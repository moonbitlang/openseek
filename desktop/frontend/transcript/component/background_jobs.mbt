///|
/// A projection-local index: a detached call still owns its job's status.
/// Only engine metadata is interpreted, never arbitrary program output.
priv struct BackgroundJobs {
  statuses : Map[String, ToolStatus]
}

///|
fn BackgroundJobs::started(call : @transcript.ToolCall) -> String? {
  guard call.name == "mbtx" &&
    call.outcome is Done(is_error=false, brief=Some(brief), ..) &&
    brief.strip_prefix("mbtx → bg ") is Some(id) &&
    !id.is_blank() else {
    return None
  }
  Some(id.to_owned())
}

///|
fn BackgroundJobs::target(call : @transcript.ToolCall) -> String? {
  guard (call.name == "job_output" || call.name == "job_stop") &&
    call.arguments is Some(arguments) &&
    card_fields(arguments) is Some(fields) &&
    fields.get("job_id") is Some(String(id)) &&
    !id.is_blank() else {
    return None
  }
  Some(id)
}

///|
fn BackgroundJobs::finished_notice(text : String) -> (String, ToolStatus)? {
  guard text.strip_prefix("background job ") is Some(rest) &&
    rest.split_once(" finished (") is Some((id, rest)) &&
    !id.is_blank() &&
    rest.split_once(")") is Some((status, _)) else {
    return None
  }
  // Match the engine's terminal states. A malformed or unrelated notice must
  // remain visible rather than silently completing a job.
  if status == "exit=0" {
    Some((id.to_owned(), RecentlySucceeded))
  } else if status == "stopped" {
    Some((id.to_owned(), Stopped))
  } else if status =~ re"^exit=-?[0-9]+$" ||
    status.has_prefix("cleanup failed: ") ||
    status.has_prefix("output capture failed: ") ||
    status.has_prefix("killed: ") {
    Some((id.to_owned(), Failed))
  } else {
    None
  }
}

///|
fn BackgroundJobs::result(call : @transcript.ToolCall) -> (String, ToolStatus)? {
  guard BackgroundJobs::target(call) is Some(id) &&
    call.outcome is Done(brief~, content~, is_error~) else {
    return None
  }
  if call.name == "job_stop" {
    // stop() waits for a terminal state but is also successful for an already
    // finished job. settle() therefore preserves any recorded exit result.
    return if !is_error && content == "stopped background job \{id}" {
      Some((id, Stopped))
    } else {
      None
    }
  }
  let status = if brief is Some(brief) &&
    brief.strip_prefix("job \{id} (") is Some(rest) &&
    rest.split_once(")") is Some((status, _)) {
    status.to_owned()
  } else {
    // Jobs without descriptions have no brief. Their engine-written footer
    // is always the last line; earlier output cannot impersonate it.
    guard content.split("\n").last() is Some(footer) &&
      footer.strip_prefix("<system>job=\{id} ") is Some(rest) &&
      rest.strip_suffix("</system>") is Some(rest) else {
      return None
    }
    guard rest.split(" ").next() is Some(status) else { return None }
    status.to_owned()
  }
  if status == "running" {
    Some((id, Pending))
  } else if status == "stopped" {
    Some((id, Stopped))
  } else if status =~ re"^exit=-?[0-9]+$" || status.has_prefix("stopped ") {
    Some(
      (
        id,
        if is_error || status != "exit=0" {
          Failed
        } else {
          RecentlySucceeded
        },
      ),
    )
  } else {
    None
  }
}

///|
fn BackgroundJobs::collect(
  self : BackgroundJobs,
  call : @transcript.ToolCall,
) -> Unit {
  if BackgroundJobs::started(call) is Some(id) {
    self.statuses[id] = Pending
  }
  for child in call.children {
    self.collect(child)
  }
}

///|
fn BackgroundJobs::settle(
  self : BackgroundJobs,
  id : String,
  status : ToolStatus,
) -> Unit {
  // A late running read must not undo completion; a later diagnostic failure
  // may still replace success. Unknown jobs retain their standalone rows.
  if self.statuses.get(id) is Some(previous) &&
    (
      previous is Pending ||
      status is Failed ||
      (previous is Stopped && status is RecentlySucceeded)
    ) {
    self.statuses[id] = status
  }
}

///|
fn BackgroundJobs::read_output(
  self : BackgroundJobs,
  call : @transcript.ToolCall,
) -> Unit {
  if BackgroundJobs::result(call) is Some((id, status)) {
    self.settle(id, status)
  }
  for child in call.children {
    self.read_output(child)
  }
}

///|
/// Index original calls before reading later results and notices, so a
/// completion updates its earlier row even across prose and turn boundaries.
fn BackgroundJobs::from_input(input : Input) -> BackgroundJobs {
  let jobs : BackgroundJobs = { statuses: Map([]), }
  for row in input.items {
    if row.item.kind is Assistant(calls~, ..) {
      for call in calls {
        jobs.collect(call)
      }
    }
  }
  for row in input.items {
    match row.item.kind {
      Assistant(calls~, ..) =>
        for call in calls {
          jobs.read_output(call)
        }
      Notice(label="runtime notice", brief~, body~, ..) => {
        let text = match brief {
          Some(text) => Some(text)
          None => body
        }
        if text is Some(text) &&
          BackgroundJobs::finished_notice(text) is Some((id, status)) {
          jobs.settle(id, status)
        }
      }
      _ => ()
    }
  }
  // The Jobs panel already receives durable execution records, including
  // direct panel stops and executions whose owner disappeared without a
  // transcript notice. Use only the current conversation's records. Legacy
  // IDs can repeat across generations; ambiguous records cannot identify an
  // original call and must not update it.
  for view in input.background_jobs {
    if input.background_jobs.any(other => {
        other.job.id == view.job.id &&
        other.job.generation != view.job.generation
      }) {
      continue
    }
    let status = match view.job.state {
      Running | Stopping => Pending
      _ if view.job.cleanup_error is Some(_) ||
        view.job.output_error is Some(_) ||
        view.job.invalid_utf8 => Failed
      Exited(0) => RecentlySucceeded
      Exited(_) | Interrupted => Failed
      Stopped("output_limit" | "time_limit" | "capture_failed") => Failed
      Stopped(_) => Stopped
    }
    jobs.settle(view.job.id, status)
  }
  jobs
}

///|
fn BackgroundJobs::absorbs(
  self : BackgroundJobs,
  call : @transcript.ToolCall,
) -> Bool {
  // Keep read errors that carry no terminal metadata visible: a failed read
  // is not evidence that the background process itself has stopped.
  if BackgroundJobs::target(call) is Some(id) && self.statuses.contains(id) {
    match (call.outcome, BackgroundJobs::result(call)) {
      (Pending(..), _) => true
      (Done(is_error=true, ..), Some((_, Pending))) => false
      (_, Some(_)) => true
      _ => false
    }
  } else {
    false
  }
}

///|
priv enum JobCompletion {
  Showing
  Hidden
} derive(Eq)

///|
/// Component-owned completion lifetime. Historical completions start hidden;
/// new completions get exactly one timer, even if later reads repeat them.
priv struct JobCompletions {
  entries : @vector.Vector[(String, JobCompletion)]
} derive(Eq)

///|
fn JobCompletions::history(input : Input) -> JobCompletions {
  let mut entries = @vector.Vector::new()
  for id, status in BackgroundJobs::from_input(input).statuses {
    if status is RecentlySucceeded {
      entries = entries.push((id, Hidden))
    }
  }
  { entries, }
}

///|
fn JobCompletions::hidden(self : JobCompletions, id : String) -> Bool {
  self.entries.iter().any(entry => entry is (key, Hidden) && key == id)
}

///|
fn JobCompletions::observe(
  self : JobCompletions,
  input : Input,
  emit : @cmd.Emit[Msg],
) -> (JobCompletions, @cmd.Cmd) {
  let mut entries = self.entries
  let commands : Array[@cmd.Cmd] = []
  for id, status in BackgroundJobs::from_input(input).statuses {
    if status is RecentlySucceeded &&
      !entries.iter().any(entry => entry.0 == id) {
      entries = entries.push((id, Showing))
      commands.push(@cmd.delay(emit(JobCompletionExpired(id)), 1000))
    }
  }
  ({ entries, }, @cmd.batch(commands))
}

///|
fn JobCompletions::expire(self : JobCompletions, id : String) -> JobCompletions {
  {
    entries: self.entries.map(entry => {
      if entry.0 == id {
        (id, Hidden)
      } else {
        entry
      }
    }),
  }
}

///|
fn BackgroundJobs::minimal_call(
  locale? : @i18n.Locale = English,
  self : BackgroundJobs,
  call : @transcript.ToolCall,
  completions : JobCompletions,
  wait_label? : String,
) -> MinimalCall {
  let minimal = MinimalCall::from_tool(locale~, call, wait_label?)
  if BackgroundJobs::started(call) is Some(id) &&
    self.statuses.get(id) is Some(status) {
    {
      ..minimal,
      status: if status is RecentlySucceeded && completions.hidden(id) {
        Succeeded
      } else {
        status
      },
    }
  } else {
    minimal
  }
}
