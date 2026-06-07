///|
pub let default_agent_event_capacity : Int = 32

///|
pub(all) enum WatcherStatus {
  Running
  Stopped
}

///|
pub(all) enum AgentEvent {
  MoonCheckUpdate(MoonCheckSnapshot)
}

///|
pub struct MoonCheckSnapshot {
  id : String
  key : String
  command : String
  cwd : String?
  status : WatcherStatus
  seq : Int
  output : String
  output_truncated : Bool
  max_output_chars : Int
  exit_code : Int?
  restart_count : Int
  restart_limit : Int
  restart_reason : String?
}

///|
pub fn MoonCheckSnapshot::MoonCheckSnapshot(
  id~ : String,
  key~ : String,
  command~ : String,
  cwd~ : String?,
  status~ : WatcherStatus,
  seq~ : Int,
  output~ : String,
  output_truncated~ : Bool,
  max_output_chars~ : Int,
  exit_code~ : Int?,
  restart_count~ : Int,
  restart_limit~ : Int,
  restart_reason~ : String?,
) -> MoonCheckSnapshot {
  {
    id,
    key,
    command,
    cwd,
    status,
    seq,
    output,
    output_truncated,
    max_output_chars,
    exit_code,
    restart_count,
    restart_limit,
    restart_reason,
  }
}

///|
priv struct MoonCheckRecord {
  id : String
  key : String
  command : String
  cwd : String?
  process : @process.Process
  max_output_chars : Int
  mut status : WatcherStatus
  mut seq : Int
  mut output : String
  mut output_truncated : Bool
  mut exit_code : Int?
  mut run_complete : Bool
  restart_count : Int
  restart_limit : Int
  restart_reason : String?
}

///|
/// Per-agent-loop state shared between the main chat loop and the
/// side-effectful tools it invokes. Constructed once inside
/// `@async.with_task_group` and threaded into every tool definition.
pub struct AgentRuntime[X] {
  /// Task group the agent runs under; tools spawn background watchers as
  /// children of this group so their lifetime is bounded by the agent's.
  priv group : @async.TaskGroup[X]
  /// Bounded event bus (`DiscardOldest`, see `default_agent_event_capacity`)
  /// that background tools post updates to; the main loop drains it between
  /// steps to surface fresh tool output into the conversation.
  priv events : @aqueue.Queue[AgentEvent]
  /// Registry of currently-running `moon check` watchers keyed by their
  /// assigned id. Each record carries the process handle, latest stdout
  /// buffer, exit code, and restart bookkeeping.
  priv moon_checks : Map[String, MoonCheckRecord]
  /// Monotonic counter used by `next_moon_check_id` to mint unique watcher
  /// ids; only increases for the lifetime of this runtime.
  priv mut next_moon_check_index : Int
}

///|
pub fn[X] AgentRuntime::AgentRuntime(
  group : @async.TaskGroup[X],
) -> AgentRuntime[X] {
  {
    group,
    events: Queue(kind=DiscardOldest(default_agent_event_capacity)),
    moon_checks: {},
    next_moon_check_index: 1,
  }
}

///|
pub fn[X] AgentRuntime::group(self : AgentRuntime[X]) -> @async.TaskGroup[X] {
  self.group
}

///|
pub fn[X] AgentRuntime::next_moon_check_id(self : AgentRuntime[X]) -> String {
  let id = "moon-check-\{self.next_moon_check_index}"
  self.next_moon_check_index += 1
  id
}

///|
pub fn[X] AgentRuntime::register_moon_check(
  self : AgentRuntime[X],
  key~ : String,
  id~ : String,
  command~ : String,
  cwd~ : String?,
  process~ : @process.Process,
  max_output_chars~ : Int,
  restart_count~ : Int,
  restart_limit~ : Int,
  restart_reason~ : String?,
) -> MoonCheckSnapshot {
  let record = {
    id,
    key,
    command,
    cwd,
    process,
    max_output_chars,
    status: Running,
    seq: 0,
    output: "",
    output_truncated: false,
    exit_code: None,
    run_complete: false,
    restart_count,
    restart_limit,
    restart_reason,
  }
  self.moon_checks[record.key] = record
  record.to_snapshot()
}

///|
pub fn[X] AgentRuntime::moon_check_snapshot(
  self : AgentRuntime[X],
  key : String,
) -> MoonCheckSnapshot? {
  match self.moon_checks.get(key) {
    Some(record) => Some(record.to_snapshot())
    None => None
  }
}

///|
pub fn[X] AgentRuntime::record_moon_check_output(
  self : AgentRuntime[X],
  key : String,
  id : String,
  chunk : String,
) -> MoonCheckSnapshot? {
  match self.moon_checks.get(key) {
    None => None
    Some(record) if record.id != id => None
    Some(record) => {
      let segment = if record.run_complete {
        latest_run_segment(chunk)
      } else {
        latest_run_segment(record.output + chunk)
      }
      record.output = retain_output_tail(segment, record.max_output_chars)
      record.output_truncated = segment.char_length() > record.max_output_chars
      record.run_complete = moon_check_run_complete(record.output)
      record.seq += 1
      let snapshot = record.to_snapshot()
      self.emit_moon_check(snapshot)
      Some(snapshot)
    }
  }
}

///|
pub fn[X] AgentRuntime::replace_moon_check_output(
  self : AgentRuntime[X],
  key : String,
  id : String,
  output : String,
) -> MoonCheckSnapshot? {
  match self.moon_checks.get(key) {
    None => None
    Some(record) if record.id != id => None
    Some(record) => {
      record.output = retain_output_tail(output, record.max_output_chars)
      record.output_truncated = output.char_length() > record.max_output_chars
      record.run_complete = moon_check_run_complete(record.output)
      record.seq += 1
      let snapshot = record.to_snapshot()
      self.emit_moon_check(snapshot)
      Some(snapshot)
    }
  }
}

///|
pub fn[X] AgentRuntime::mark_moon_check_stopped(
  self : AgentRuntime[X],
  key : String,
  id : String,
  exit_code : Int?,
) -> MoonCheckSnapshot? {
  match self.moon_checks.get(key) {
    None => None
    Some(record) if record.id != id => None
    Some(record) => {
      record.status = Stopped
      record.exit_code = exit_code
      record.seq += 1
      let snapshot = record.to_snapshot()
      self.emit_moon_check(snapshot)
      Some(snapshot)
    }
  }
}

///|
pub fn[X] AgentRuntime::stop_moon_check(
  self : AgentRuntime[X],
  key : String,
) -> MoonCheckSnapshot? {
  match self.moon_checks.get(key) {
    None => None
    Some(record) =>
      if record.status is Running {
        record.process.cancel()
        self.mark_moon_check_stopped(key, record.id, None)
      } else {
        Some(record.to_snapshot())
      }
  }
}

///|
pub fn[X] AgentRuntime::emit_moon_check(
  self : AgentRuntime[X],
  snapshot : MoonCheckSnapshot,
) -> Unit {
  ignore(self.events.try_put(MoonCheckUpdate(snapshot)) catch { _ => false })
}

///|
pub fn[X] AgentRuntime::drain_events(
  self : AgentRuntime[X],
) -> Array[AgentEvent] {
  let events : Array[AgentEvent] = []
  for ;; {
    let next = self.events.try_get() catch { _ => None }
    match next {
      None => return events
      Some(event) => events.push(event)
    }
  }
}

///|
fn MoonCheckRecord::to_snapshot(self : MoonCheckRecord) -> MoonCheckSnapshot {
  {
    id: self.id,
    key: self.key,
    command: self.command,
    cwd: self.cwd,
    status: self.status,
    seq: self.seq,
    output: self.output,
    output_truncated: self.output_truncated,
    max_output_chars: self.max_output_chars,
    exit_code: self.exit_code,
    restart_count: self.restart_count,
    restart_limit: self.restart_limit,
    restart_reason: self.restart_reason,
  }
}

///|
fn retain_output_tail(content : String, max_chars : Int) -> String {
  if content.char_length() <= max_chars {
    content
  } else {
    let keep_from = content.char_length() - max_chars
    match content.offset_of_nth_char(keep_from) {
      Some(offset) => content[offset:].to_owned()
      None => content
    }
  }
}

///|
fn latest_run_segment(content : String) -> String {
  let success = "Success, waiting for filesystem changes..."
  let errors = "Had errors, waiting for filesystem changes..."
  let mut start = 0
  let mut offset = 0
  for line in content.split("\n") {
    offset += line.length() + 1
    if line.contains(success) || line.contains(errors) {
      start = offset
    }
  }
  let segment = content[start:]
  if segment == "" {
    content
  } else {
    segment.to_owned()
  }
}

///|
fn moon_check_run_complete(content : String) -> Bool {
  content.contains("Success, waiting for filesystem changes...") ||
  content.contains("Had errors, waiting for filesystem changes...")
}
