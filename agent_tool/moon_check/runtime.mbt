///|
priv enum WatcherStatus {
  Running
  Stopped
}

///|
/// Immutable view of a watcher's most recently observed state. Snapshots are
/// what `moon_check` returns to the agent and what it broadcasts through
/// `MoonCheckUpdate` events; the live `MoonCheckRecord` is kept private to the
/// runtime.
priv struct MoonCheckSnapshot {
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
fn MoonCheckSnapshot::MoonCheckSnapshot(
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
/// Extends the shared agent event stream with `MoonCheckUpdate(snapshot)`.
/// The events are queued by `@agent_runtime.AgentRuntime` (just the event bus)
/// and coalesced by `runtime_update_text` (see `output.mbt`), which the agent
/// loop calls between turns to render a single update block per batch.
extenum @agent_runtime.AgentEvent += {
  MoonCheckUpdate(MoonCheckSnapshot)
}

///|
/// Mutable book-keeping for a single live watcher. Owned by `MoonCheckRuntime`
/// and never returned to callers directly — `to_snapshot` produces the public
/// view.
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
/// Session-scoped state for the `moon_check` tool. One `MoonCheckRuntime` is
/// created inside `definition` and captured by the `execute` closure, so
/// every tool call from the same agent session shares it — that's what makes
/// the reuse and restart branches in `moon_check` work across turns. The
/// type parameter `X` matches the return type of the enclosing
/// `@async.with_task_group()` that owns `scope`.
priv struct MoonCheckRuntime[X] {
  /// Event-bus handle used by `emit_moon_check` to publish
  /// `MoonCheckUpdate(snapshot)` after every state transition (output append,
  /// replace, stop). The agent loop drains the bus between steps via
  /// `runtime_update_text` (output.mbt) and surfaces a coalesced
  /// `[moon_check update]` block back into the conversation. The bus is
  /// `DiscardOldest`-bounded, so a flood of chunks from a busy watcher can't
  /// starve other tools.
  runtime : @agent_runtime.AgentRuntime
  /// Structured-concurrency scope used to spawn child work. `scope.group()`
  /// is the `@async.TaskGroup` passed to both `@process.spawn` (for the
  /// `moon check --watch` child) and `group.spawn_bg(...)` (for the
  /// `monitor_moon_check` task that drains its pipes). Tying all watcher
  /// children to the scope means they're cancelled together when the agent
  /// session ends — there are no orphan `moon` processes after a session
  /// exit.
  scope : @agent_runtime.AgentTaskScope[X]
  /// Watcher registry keyed by `moon_check_key(input)` — the watcher's
  /// `cwd`. One entry per directory is the core invariant: a `moon_check`
  /// call whose command matches an existing **running** record reuses it; a
  /// running record with a *different* command (the options changed) is
  /// stopped and replaced; a **stopped** record triggers a manual restart
  /// that overwrites the entry. Records are never removed, only
  /// superseded — a stopped record stays in the map until either a restart
  /// replaces it or the agent session ends.
  moon_checks : Map[String, MoonCheckRecord]
  /// Monotonic counter for assigning watcher ids. Each
  /// `next_moon_check_id()` call produces `moon-check-<N>` and bumps the
  /// counter. The id is the **per-spawn** identity (distinct from the
  /// per-key map identity): after a restart, the same `key` is associated
  /// with a fresh id. `record_moon_check_output` and
  /// `mark_moon_check_stopped` compare against the current record's id, so
  /// late chunks from an old monitor task — whose pipe is still draining
  /// after its watcher was replaced — are silently dropped instead of
  /// clobbering the fresh replacement's state.
  mut next_moon_check_index : Int
}

///|
fn[X] MoonCheckRuntime::MoonCheckRuntime(
  runtime : @agent_runtime.AgentRuntime,
  scope : @agent_runtime.AgentTaskScope[X],
) -> MoonCheckRuntime[X] {
  { runtime, scope, moon_checks: {}, next_moon_check_index: 1 }
}

///|
fn[X] MoonCheckRuntime::group(
  self : MoonCheckRuntime[X],
) -> @async.TaskGroup[X] {
  self.scope.group()
}

///|
fn[X] MoonCheckRuntime::next_moon_check_id(
  self : MoonCheckRuntime[X],
) -> String {
  let id = "moon-check-\{self.next_moon_check_index}"
  self.next_moon_check_index += 1
  id
}

///|
/// Insert a freshly spawned watcher under `key`, returning the initial
/// snapshot.
fn[X] MoonCheckRuntime::register_moon_check(
  self : MoonCheckRuntime[X],
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
fn[X] MoonCheckRuntime::moon_check_snapshot(
  self : MoonCheckRuntime[X],
  key : String,
) -> MoonCheckSnapshot? {
  match self.moon_checks.get(key) {
    Some(record) => Some(record.to_snapshot())
    None => None
  }
}

///|
/// Append a chunk of process output. Outputs whose `id` doesn't match the
/// current record are dropped — after a restart, the old (now-stopped)
/// watcher's monitor task is still draining its pipe, and this guard keeps
/// those late chunks from clobbering the fresh replacement's state. The
/// retained tail is trimmed to the latest run segment (split on moon's
/// `Success/Had errors, waiting for filesystem changes...` markers) and
/// capped at `max_output_chars`. Each successful update bumps `seq` and emits
/// a `MoonCheckUpdate` event.
fn[X] MoonCheckRuntime::record_moon_check_output(
  self : MoonCheckRuntime[X],
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
/// Wholesale replacement of the recorded output. Used when a watcher exits
/// with a crash (to substitute the full panic banner with a compact summary)
/// and when seeding a freshly restarted watcher with that previous summary.
fn[X] MoonCheckRuntime::replace_moon_check_output(
  self : MoonCheckRuntime[X],
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
fn[X] MoonCheckRuntime::mark_moon_check_stopped(
  self : MoonCheckRuntime[X],
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
fn[X] MoonCheckRuntime::stop_moon_check(
  self : MoonCheckRuntime[X],
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
fn[X] MoonCheckRuntime::emit_moon_check(
  self : MoonCheckRuntime[X],
  snapshot : MoonCheckSnapshot,
) -> Unit {
  self.runtime.emit_event(MoonCheckUpdate(snapshot))
}

///|
/// Stable string identifying a watcher by its directory — one watcher per
/// cwd is the invariant. A call with the same cwd reuses the running
/// watcher when its command matches and *replaces* it (stopping the old
/// process) when the options changed. Keying on the full option set instead
/// used to stack concurrent watchers on one directory; they competed for
/// moon's build lock with each other and with the agent's own `moon test`
/// runs, reported stale results, and a real session ended with the model
/// running `pkill -9 -f "moon check"` to recover.
fn moon_check_key(input : @decode.MoonCheckInput) -> String {
  match input.cwd {
    Some(cwd) => "cwd=\{cwd}"
    None => "cwd=."
  }
}

///|
async test "moon_check runtime ignores stale watcher id updates" {
  @async.with_task_group() <| group => {
    let runtime = MoonCheckRuntime(AgentRuntime(), AgentTaskScope(group))
    let key = "cwd=/tmp"
    let (reader1, writer1) = @process.read_from_process()
    let process1 = @process.spawn(
      group,
      "moon",
      ["--version"],
      stdout=writer1,
      stderr=writer1,
      no_wait=true,
    )
    let (reader2, writer2) = @process.read_from_process()
    let process2 = @process.spawn(
      group,
      "moon",
      ["--version"],
      stdout=writer2,
      stderr=writer2,
      no_wait=true,
    )
    ignore(
      runtime.register_moon_check(
        key~,
        id="moon-check-1",
        command="moon check --watch",
        cwd=None,
        process=process1,
        max_output_chars=12000,
        restart_count=0,
        restart_limit=3,
        restart_reason=None,
      ),
    )
    ignore(
      runtime.register_moon_check(
        key~,
        id="moon-check-2",
        command="moon check --watch",
        cwd=None,
        process=process2,
        max_output_chars=12000,
        restart_count=0,
        restart_limit=3,
        restart_reason=None,
      ),
    )
    assert_true(
      runtime.record_moon_check_output(key, "moon-check-1", "stale") is None,
    )
    assert_true(
      runtime.mark_moon_check_stopped(key, "moon-check-1", Some(101)) is None,
    )
    guard runtime.record_moon_check_output(key, "moon-check-2", "fresh")
      is Some(snapshot) else {
      fail("expected current watcher update")
    }
    assert_eq(snapshot.output, "fresh")
    assert_true(snapshot.status is Running)
    ignore(process1.wait())
    ignore(process2.wait())
    reader1.close()
    reader2.close()
  }
}

///|
async test "moon_check keeps crash summary in replacement output" {
  @async.with_task_group() <| group => {
    let runtime = MoonCheckRuntime(AgentRuntime(), AgentTaskScope(group))
    let key = "cwd=/tmp"
    let (reader, writer) = @process.read_from_process()
    let process = @process.spawn(
      group,
      "moon",
      ["--version"],
      stdout=writer,
      stderr=writer,
      no_wait=true,
    )
    ignore(
      runtime.register_moon_check(
        key~,
        id="moon-check-2",
        command="moon check --watch",
        cwd=None,
        process~,
        max_output_chars=12000,
        restart_count=1,
        restart_limit=3,
        restart_reason=Some("auto restart after exit 101"),
      ),
    )
    let summary =
      #|[moon_check watcher exited]
      #|exit=101
      #|restart=attempt 1/3
      #|
    ignore(runtime.replace_moon_check_output(key, "moon-check-2", summary))
    let first_replacement_output =
      #|Finished. moon: ran 2 tasks, now up to date
      #|Success, waiting for filesystem changes...
      #|
    guard runtime.record_moon_check_output(
        key, "moon-check-2", first_replacement_output,
      )
      is Some(snapshot) else {
      fail("expected replacement watcher output")
    }
    assert_true(snapshot.output.contains("[moon_check watcher exited]"))
    assert_true(snapshot.output.contains("restart=attempt 1/3"))
    assert_true(
      snapshot.output.contains("Success, waiting for filesystem changes..."),
    )
    ignore(process.wait())
    reader.close()
  }
}
