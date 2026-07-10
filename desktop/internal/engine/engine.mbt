// The persistent-engine machinery: one `serve` process per conversation,
// owned by the `connect` op's task group, fed prompts over stdin and drained
// through a per-engine consumer that forwards events to the webview.

///|
/// A live `serve` engine process: one process serves every prompt of one
/// conversation. Prompts and cancels are JSONL commands on its stdin; its
/// stdout event stream is consumed for the engine's lifetime. Turns are
/// strictly sequential on the wire *per conversation*, so events are stamped
/// with the run id of the prompt this engine saw most recently.
///
/// A handle's identity IS its process: a respawn puts a fresh ServeEngine in
/// the same session slot, and a same-config successor is indistinguishable
/// by value (same `session_key`, same `spec_key`). Cleanup paths that may
/// run after a replacement — the reader's exit handler, a failed write —
/// therefore compare with `physical_equal` before clearing the slot, so a
/// dead engine's teardown can never evict its live successor.
priv struct ServeEngine {
  // The conversation this process serves: its slot in the manager's map.
  session_key : String
  // Fingerprint of the config this process was spawned with; a prompt whose
  // config differs cannot reuse it.
  spec_key : String
  writer : @process.WriteToProcess
  mut latest_run : Int
  mut phase : EnginePhase
  steer_runs : SteerRunTracker
}

///|
/// What the serve engine is doing right now — one value instead of loose
/// booleans, so the impossible combinations (a compaction with an open run,
/// a cancel request with nothing to cancel) cannot be represented, and every
/// operation names the phase it requires instead of consulting flags that
/// can drift apart across suspension points. The steering bookkeeping stays
/// in `SteerRunTracker`: steers deliberately settle across a phase boundary.
priv enum EnginePhase {
  // Between turns; nothing is writing to the durable record. The only phase
  // that accepts a prompt, a compaction, or archiving.
  Idle
  // A prompt's turn is open on the wire. `cancel_requested` marks that a
  // cancel was sent (or must be re-sent once the racing prompt lands).
  // `compact_queued` marks a `/compact` accepted mid-turn: the command sits
  // in the serve engine's queue behind this run, so the turn's terminal
  // event must land in `Compacting`, not `Idle` — otherwise a prompt or an
  // archive slips into the gap before the engine's `compaction_started`
  // and the eventual `compaction_finished` would blindly idle it away.
  Running(cancel_requested~ : Bool, compact_queued~ : Bool)
  // A `/compact` is rewriting the durable record: no run is open, but
  // starts and archiving must wait. Entered by `compact_run` (idle send),
  // a run's terminal event with a compaction queued behind it, or the
  // engine's own `compaction_started`; left on
  // `compaction_finished`/`compaction_failed` — or on engine death, which
  // reports a synthetic failure so the frontend never sticks.
  Compacting
}

///|
/// The phase after a run's terminal event: straight into the compaction the
/// turn queued behind itself, otherwise back between turns. The engine starts
/// a queued compaction the moment the turn ends, so entering Compacting here
/// (rather than waiting for its `compaction_started`) closes the window where
/// a prompt or an archive could slip in ahead of it.
fn EnginePhase::after_run_close(self : EnginePhase) -> EnginePhase {
  if self is Running(compact_queued=true, ..) {
    Compacting
  } else {
    Idle
  }
}

///|
priv struct SteerRunTracker {
  mut settling_run : Int?
  open_steers : Array[String]
  settling_steers : Array[String]
}

///|
fn SteerRunTracker::new() -> SteerRunTracker {
  { settling_run: None, open_steers: [], settling_steers: [] }
}

///|
fn SteerRunTracker::begin_run(self : SteerRunTracker) -> Unit {
  self.open_steers.clear()
}

///|
fn SteerRunTracker::record_sent(self : SteerRunTracker, text : String) -> Unit {
  self.open_steers.push(text)
}

///|
/// Undo a `record_sent` whose write never reached the engine. The steer may
/// already have been swept into the settling set by a terminal event that
/// raced the write, so look there first (mirroring `run_id_for_event`).
fn SteerRunTracker::discard_sent(self : SteerRunTracker, text : String) -> Unit {
  if remove_first_text(self.settling_steers, text) {
    if self.settling_steers.is_empty() {
      self.settling_run = None
    }
  } else {
    ignore(remove_first_text(self.open_steers, text))
  }
}

///|
fn SteerRunTracker::record_terminal(
  self : SteerRunTracker,
  run_id : Int,
) -> Unit {
  self.settling_steers.clear()
  if self.open_steers.length() > 0 {
    self.settling_run = Some(run_id)
    for text in self.open_steers {
      self.settling_steers.push(text)
    }
  } else {
    self.settling_run = None
  }
  self.open_steers.clear()
}

///|
fn SteerRunTracker::run_id_for_event(
  self : SteerRunTracker,
  decoded : @event.AgentEvent?,
  latest_run : Int,
) -> Int {
  match decoded {
    Some(SteerApplied(content)) | Some(SteerDropped(content)) => {
      if remove_first_text(self.settling_steers, content) &&
        self.settling_run is Some(run_id) {
        if self.settling_steers.is_empty() {
          self.settling_run = None
        }
        return run_id
      }
      ignore(remove_first_text(self.open_steers, content))
    }
    _ => {
      self.settling_run = None
      self.settling_steers.clear()
    }
  }
  latest_run
}

///|
fn remove_first_text(items : Array[String], text : String) -> Bool {
  for index, item in items {
    if item == text {
      ignore(items.remove(index))
      return true
    }
  }
  false
}

///|
priv enum PumpCommand {
  // Replace the conversation's engine (if any) with one spawned for this
  // config; the queue carries the spawn failure — or None for success —
  // back to the requesting `start` op.
  SpawnEngine(RunConfig, @async.Queue[EngineError?])
}

///|
/// An operation holding a conversation's slot between config validation and
/// its command hitting the wire. A second slot-holding op in that window is
/// refused up front instead of racing the first one's spawn or preempting
/// the phase it is about to enter.
priv enum PendingOp {
  StartPending
  CompactPending
  ArchivePending
}

///|
/// Everything the host tracks for one conversation, in one place. Both
/// fields are optional and every combination is legal — no engine yet, an
/// op preparing to spawn one, a live engine idle or mid-turn, an op
/// preparing on a live engine — but keeping them in a single slot means an
/// op cannot look up the engine without the pending claim being in view:
/// the compact-preempts-starting-prompt race came from exactly that split
/// (a pending-starts set beside the engines map, one checked, one missed).
priv struct SessionSlot {
  mut pending : PendingOp?
  mut engine : ServeEngine?
}

///|
/// Claim the slot for `op`, refusing when another op already holds it.
fn SessionSlot::claim(
  self : SessionSlot,
  op : PendingOp,
) -> Unit raise EngineError {
  if self.pending is Some(current) {
    raise EngineError(
      match current {
        StartPending =>
          "an OpenSeek run is already starting for this conversation"
        CompactPending =>
          "a compaction is already being requested for this conversation"
        ArchivePending => "this conversation is being archived"
      },
    )
  }
  self.pending = Some(op)
}

///|
/// Whether the pump is serving, and the per-conversation slots while it is.
/// The slots live inside the state, so an engine cannot exist without a
/// running pump — stopping the pump drops them wholesale, which is the old
/// `reset()` without the by-hand invariant.
priv enum PumpState {
  Stopped
  Serving(sessions~ : Map[String, SessionSlot])
}

///|
/// Host-side state of the persistent-engine design: one serve process per
/// conversation (all owned by the pump's task group, so different sessions
/// can run turns concurrently) plus the command queue other ops use to ask
/// the pump for lifecycle changes. stdin writes go directly from any op;
/// only spawning needs the pump, because a process must be owned by a task
/// group that outlives individual IPC requests. Idle engines stay alive for
/// the app's lifetime — the durable session makes killing them safe, but
/// keeping them avoids a respawn-and-replay on every conversation switch.
struct EngineManager {
  engine : String
  runtime_dir : @path.Path?
  commands : @async.Queue[PumpCommand]
  mut pump : PumpState
  mut next_run_id : Int
}

///|
/// The live sessions table; every op starts here, so a stopped pump answers
/// with the same message everywhere.
fn EngineManager::serving(
  self : EngineManager,
) -> Map[String, SessionSlot] raise EngineError {
  guard self.pump is Serving(sessions~) else {
    raise EngineError("engine host is not connected; reload the app")
  }
  sessions
}

///|
/// This conversation's slot, created empty on first touch.
fn slot_for(sessions : Map[String, SessionSlot], key : String) -> SessionSlot {
  if sessions.get(key) is Some(slot) {
    slot
  } else {
    let slot : SessionSlot = { pending: None, engine: None }
    sessions.set(key, slot)
    slot
  }
}

///|
/// Drop a slot that carries nothing anymore, so abandoned conversations do
/// not accumulate empty entries.
fn EngineManager::prune_slot(self : EngineManager, key : String) -> Unit {
  if self.pump is Serving(sessions~) &&
    sessions.get(key) is Some(slot) &&
    slot.pending is None &&
    slot.engine is None {
    sessions.remove(key)
  }
}

///|
priv enum StreamMessage {
  StreamEvent(Json)
  StreamReaderFailed(String)
  StreamExited(Int)
}

///|
pub fn new_engine_manager(
  engine : String,
  runtime_dir? : @path.Path,
) -> EngineManager {
  {
    engine,
    runtime_dir,
    commands: Queue(kind=Unbounded),
    pump: Stopped,
    next_run_id: 1,
  }
}

///|
/// The engine that owns the open run `run_id` — or, when no id is given, the
/// only open run if exactly one exists (with several conversations running
/// concurrently, an unaddressed cancel/steer would be a guess).
fn open_run_engine(manager : EngineManager, run_id? : Int) -> ServeEngine? {
  guard manager.pump is Serving(sessions~) else { return None }
  if run_id is Some(id) {
    for _, slot in sessions {
      if slot.engine is Some(engine) &&
        engine.phase is Running(..) &&
        engine.latest_run == id {
        return Some(engine)
      }
    }
    return None
  }
  let mut found : ServeEngine? = None
  for _, slot in sessions {
    if slot.engine is Some(engine) && engine.phase is Running(..) {
      if found is Some(_) {
        return None
      }
      found = Some(engine)
    }
  }
  found
}

///|
/// An empty file redirected into one-shot engine runs as stdin. It lives in
/// the per-user runtime dir, not beside the engine binary: the bundle a
/// packaged engine sits in is read-only (App Translocation even enforces
/// it), so writing next to the executable would fail every
/// `sessions list` / `sessions show` in a packaged app.
async fn prepare_engine_stdin(
  runtime_dir : @path.Path?,
  engine : @path.Path,
) -> &@process.ProcessInput {
  let path = if runtime_dir is Some(dir) {
    dir.join("engine.stdin")
  } else {
    engine.to_string() + ".stdin"
  }
  @fs.write_file(path.to_string(), "", create_mode=CreateOrTruncate)
  @process.redirect_from_file(path.to_string())
}

///|
async fn read_engine_stdout(
  reader : @process.ReadFromProcess,
  process : @process.Process,
  messages : @async.Queue[StreamMessage],
) -> Unit {
  @jsonl.each(reader, json => ignore(messages.try_put(StreamEvent(json)))) catch {
    error if @async.is_being_cancelled() => raise error
    _ => {
      messages.put(StreamReaderFailed("engine wrote malformed JSONL"))
      process.cancel()
    }
  }
  reader.close()
  let code = process.wait()
  messages.put(StreamExited(code))
}

///|
async fn handle_decoded_event(
  sink : EventSink,
  run_id : Int,
  decoded : @event.AgentEvent,
) -> Bool {
  match decoded {
    AgentFinished(answer) => {
      emit_finished(sink, run_id, Finished, answer~)
      true
    }
    ContextYield(answer) => {
      emit_finished(sink, run_id, ContextYield, answer~)
      true
    }
    AgentAborted(reason) => {
      emit_error(sink, "agent aborted: " + reason, run_id~)
      emit_finished(sink, run_id, Aborted)
      true
    }
    MaxStepsExhausted => {
      emit_error(sink, "max steps exhausted", run_id~)
      emit_finished(sink, run_id, MaxStepsExhausted)
      true
    }
    AgentError(message) => {
      emit_error(sink, message, run_id~)
      emit_finished(sink, run_id, Failed)
      true
    }
    _ => false
  }
}

///|
fn host_reports_terminal_error(decoded : @event.AgentEvent) -> Bool {
  match decoded {
    AgentAborted(_) | MaxStepsExhausted | AgentError(_) => true
    _ => false
  }
}

///|
/// The `connect` op: the long-lived host half of the persistent-engine
/// design. Lepus runs each IPC request as its own task, so this op's task
/// group is the only context in which a serve process can outlive individual
/// `start`/`cancel` calls — the frontend invokes it once at startup and the
/// call stays open for the app's lifetime. When the webview connection drops
/// the task group is torn down, taking the engine with it.
pub async fn run_engine_pump(
  sink : EventSink,
  manager : EngineManager,
) -> PumpReply {
  guard manager.pump is Stopped else {
    raise EngineError("engine host is already connected")
  }
  let sessions : Map[String, SessionSlot] = {}
  fn reset() -> Unit {
    manager.pump = Stopped
  }

  manager.pump = Serving(sessions~)
  emit(sink, Connected({ ready: true }))
  defer reset()
  @async.with_task_group(group => {
    for ;; {
      match manager.commands.get() {
        SpawnEngine(config, ack) => {
          // Only this conversation's previous process is replaced; engines
          // serving other sessions keep running their own turns.
          let slot = slot_for(sessions, session_key(config))
          if slot.engine is Some(old) {
            // Closing stdin is the serve protocol's EOF signal; an idle
            // engine drains and exits, and its own reader task cleans up.
            old.writer.close()
            slot.engine = None
          }
          start_serve_engine(sink~, group~, manager~, slot~, config~) catch {
            error if @async.is_being_cancelled() => raise error
            error => {
              manager.prune_slot(session_key(config))
              ack.put(Some(EngineError("failed to start engine: \{error}")))
              continue
            }
          }
          ack.put(None)
        }
      }
    }
  })
  { disconnected: true }
}

///|
/// The desktop host owns the Skills panel's library writes, so every serve
/// engine gets the same resolved global library instead of falling back to
/// whatever HOME means inside that engine host.
fn resolved_global_skills_dir() -> @path.Path? {
  if @env.get("OPENSEEK_GLOBAL_SKILLS_DIR") is Some(dir) {
    return Some(Path(dir))
  }
  if @home.dir() is Some(dir) {
    return Some(dir.join(".openseek/skills"))
  }
  None
}

///|
#cfg(platform="windows")
const PathSep : String = ";"

///|
#cfg(not(platform="windows"))
const PathSep : String = ":"

///|
fn prepend_to_path_env(bin_dir : String, current_path : String?) -> String {
  if current_path is Some(path) && !path.is_empty() {
    "\{bin_dir}\{PathSep}\{path}"
  } else {
    bin_dir
  }
}

///|
fn first_path_entry(path : String?) -> String {
  guard path is Some(path) else { return "" }
  match path.split(PathSep).collect() {
    [first, ..] => first.to_owned()
    [] => ""
  }
}

///|
/// The environment block's path variable, whatever its spelling — Windows
/// blocks commonly carry `Path`, which `@sys.get_env_vars` preserves.
fn path_env_value(env : Map[String, String]) -> String? {
  for name, value in env {
    if name.to_upper() == "PATH" {
      return Some(value)
    }
  }
  None
}

///|
/// Prepend `bin_dir` to the environment block's path variable, in place, and
/// return the updated value. Windows blocks commonly spell the key `Path`
/// (and `@sys.get_env_vars` preserves that spelling); the block is passed to
/// the child with `inherit_env=false`, so writing a separate uppercase
/// `PATH` beside it would leave two path variables and make which one the
/// child observes a runtime coin toss. Update the spelling that already
/// exists and drop any duplicates.
fn prepend_path_env_entry(
  env : Map[String, String],
  bin_dir : String,
) -> String {
  let mut key = "PATH"
  let mut current : String? = None
  let duplicates : Array[String] = []
  for name, value in env {
    if name.to_upper() == "PATH" {
      if current is None {
        key = name
        current = Some(value)
      } else {
        duplicates.push(name)
      }
    }
  }
  for name in duplicates {
    env.remove(name)
  }
  let joined = prepend_to_path_env(bin_dir, current)
  env[key] = joined
  joined
}

///|
async fn add_moonbit_path_for_native_engine(
  env : Map[String, String],
  config : RunConfig,
  runtime_dir : @path.Path?,
) -> Unit {
  guard config.host is Native else {
    @xlog.debug() <?
      {
        "event": "desktop_engine_moonbit_path_skipped",
        "host": config.host.fingerprint(),
      }
    return
  }
  let moon_home = @moonbit.prepare_bundled_home(config.engine, runtime_dir?)
  let moon_bin_dir = moon_home.join("bin")
  let moon = moon_bin_dir.join("moon")
  let moon_exe = moon_bin_dir.join("moon.exe")
  // The agent tools spawn `moon` by name, so prepend the bundled bin to the
  // path variable (updating `Path` in place on Windows — see
  // `prepend_path_env_entry`). Deliberately do not set `MOON_HOME` (it would
  // redirect registry/cache lookup into the bundled payload) and drop any
  // ambient `MOON_HOME` the launching shell exported: moon prefers it over
  // the executable-relative home and would otherwise run the bundled binary
  // against the user's (possibly missing or incompatible) MoonBit home.
  let path = prepend_path_env_entry(env, moon_bin_dir.to_string())
  env.remove("MOON_HOME")
  @xlog.debug() <?
    {
      "event": "desktop_engine_moonbit_path",
      "host": config.host.fingerprint(),
      "moon_home": moon_home.to_string(),
      "moon_bin_dir": moon_bin_dir.to_string(),
      "moon_exists": @fsx.exists(moon),
      "moon_exe_exists": @fsx.exists(moon_exe),
      "path_prefix": first_path_entry(Some(path)),
    }
}

///|
async fn engine_process_env(
  config : RunConfig,
  runtime_dir : @path.Path?,
) -> Map[String, String] {
  // Build a complete environment and pass it with `inherit_env=false`.
  // `moonbitlang/async/process` prepends `extra_env` before inherited env on
  // Unix, so overriding PATH with inheritance enabled can leave two PATH
  // entries and let `/bin/sh` observe the original one.
  let env = @sys.get_env_vars()
  // The engine reads the key from `DEEPSEEK` but the model from `OPENSEEK_MODEL`
  // (the CLI's `--deepseek-api-key`/`--model` env bindings); the prefixes differ
  // on purpose, so the model must not go into `DEEPSEEK_MODEL` — the engine
  // ignores that and falls back to its default model.
  env["DEEPSEEK"] = config.api_key
  env["OPENSEEK_MODEL"] = config.model
  env["OPENSEEK_MAX_STEPS"] = config.max_steps.to_string()
  env["OPENSEEK_DIR"] = "."
  if resolved_global_skills_dir() is Some(dir) {
    env["OPENSEEK_GLOBAL_SKILLS_DIR"] = dir.to_string()
  }
  // The official endpoint leaves `api_url` unset; an `OPENSEEK_API_URL`
  // exported in the parent shell must not leak through and redirect the
  // official key at a stale custom URL.
  if config.api_url is Some(url) {
    env["OPENSEEK_API_URL"] = url
  } else {
    env.remove("OPENSEEK_API_URL")
  }
  // A named session puts the engine in durable-session mode, so the
  // conversation survives the process and is shared with the CLI/TUI.
  if config.session is Some(session) {
    env["OPENSEEK_SESSION"] = session
    if config.session_root is Some(root) {
      env["OPENSEEK_SESSION_ROOT"] = root.to_string()
    }
  }
  add_moonbit_path_for_native_engine(env, config, runtime_dir)
  if config.host is Wsl(..) {
    env["WSLENV"] = wslenv_with_passthrough(@env.get("WSLENV"))
  }
  env
}

///|
/// Spawn one `serve` engine inside the pump's task group and wire up its
/// stream tasks: the stdout reader feeding the queue, the stderr drain, and
/// the consumer that forwards events to the webview for the engine's
/// lifetime.
async fn[G] start_serve_engine(
  sink~ : EventSink,
  group~ : @async.TaskGroup[G],
  manager~ : EngineManager,
  slot~ : SessionSlot,
  config~ : RunConfig,
) -> Unit {
  let (child_stdin, writer) = @process.write_to_process()
  let (reader, child_stdout) = @process.read_from_process()
  let (stderr_reader, child_stderr) = @process.read_from_process()
  let env = engine_process_env(config, manager.runtime_dir)
  let (program, args) = config.host.serve_command(config.engine, config.cwd)
  // In WSL mode the working directory is `--cd`'s job: a Linux-path cwd
  // does not exist on the Windows side, so chdir'ing wsl.exe into it would
  // fail the spawn.
  let spawn_cwd = if config.host is Wsl(..) { None } else { config.cwd }
  @xlog.debug() <?
    {
      "event": "desktop_engine_spawn",
      "host": config.host.fingerprint(),
      "program": program,
      "cwd": spawn_cwd.map(cwd => cwd.to_string()).unwrap_or(""),
      "session_key": session_key(config),
      "runtime_dir": manager.runtime_dir
      .map(dir => dir.to_string())
      .unwrap_or(""),
      "path_prefix": first_path_entry(path_env_value(env)),
      "inherit_env": false,
    }
  let process = @process.spawn(
    group,
    program,
    args,
    inherit_env=false,
    extra_env=env,
    stdin=child_stdin,
    stdout=child_stdout,
    stderr=child_stderr,
    cwd?=spawn_cwd.map(cwd => cwd.to_string().view()),
    cancel_handler=@process.graceful_cancel(timeout=1000),
    no_wait=true,
  )
  let engine : ServeEngine = {
    session_key: session_key(config),
    spec_key: engine_fingerprint(config),
    writer,
    latest_run: 0,
    phase: Idle,
    steer_runs: SteerRunTracker::new(),
  }
  slot.engine = Some(engine)
  let messages : @async.Queue[StreamMessage] = Queue(kind=Unbounded)
  let stderr_task = group.spawn(no_wait=true) <| () => {
    stderr_reader.read_all().text() catch {
      error if @async.is_being_cancelled() => raise error
      _ => ""
    }
  }
  group.spawn_bg(no_wait=true, allow_failure=true, () => {
    read_engine_stdout(reader, process, messages)
  })
  group.spawn_bg(no_wait=true, allow_failure=true, () => {
    serve_engine_consumer(sink, manager, engine, messages, stderr_task)
  })
}

///|
/// Consume one engine's event stream for its whole lifetime: forward every
/// raw event to the webview stamped with the engine's current run, close
/// runs on terminal events, and report a mid-turn death as that run's
/// failure. Runs until the engine's stdout reader sees EOF.
async fn serve_engine_consumer(
  sink : EventSink,
  manager : EngineManager,
  engine : ServeEngine,
  messages : @async.Queue[StreamMessage],
  stderr_task : @async.Task[String],
) -> Unit {
  for ;; {
    match messages.get() {
      StreamEvent(raw) => {
        let decoded = @event.decode_event(raw)
        let run_id = engine.steer_runs.run_id_for_event(
          decoded,
          engine.latest_run,
        )
        match decoded {
          // The abort the user asked for: report it as a cancellation, the
          // same wire status the pre-serve host used.
          Some(AgentAborted(_)) if engine.phase
            is Running(cancel_requested=true, ..) => {
            emit_error(sink, "cancelled", run_id~)
            emit_finished(sink, run_id, Cancelled)
            engine.phase = engine.phase.after_run_close()
            engine.steer_runs.record_terminal(run_id)
          }
          Some(decoded) => {
            // Terminal failures are immediately normalized below; forwarding
            // their raw event as well would make the frontend render the same
            // failure twice.
            if !host_reports_terminal_error(decoded) {
              emit(
                sink,
                StreamEvent({ run_id, session: engine.session_key, event: raw }),
              )
            }
            match decoded {
              // A compaction queued behind an open turn begins only now, so
              // the engine's own event is what flips the phase; entering
              // from anything but Idle would clobber a run's state.
              CompactionStarted =>
                if engine.phase is Idle {
                  engine.phase = Compacting
                }
              // Either way the engine is done writing the record's summary,
              // so operations gated on compaction (starts, archiving) may
              // proceed.
              CompactionFinished | CompactionFailed => engine.phase = Idle
              _ => ()
            }
            if handle_decoded_event(sink, run_id, decoded) {
              engine.phase = engine.phase.after_run_close()
              engine.steer_runs.record_terminal(run_id)
            }
          }
          None =>
            emit(
              sink,
              StreamEvent({ run_id, session: engine.session_key, event: raw }),
            )
        }
      }
      StreamReaderFailed(message) => {
        emit_error(sink, message, run_id=engine.latest_run)
        // A broken stream can no longer deliver compaction_finished/failed;
        // report the compaction as failed now so the frontend does not stay
        // stuck with Send disabled (the exit branch below then has nothing
        // left to report for it).
        if engine.phase is Compacting {
          engine.phase = Idle
          emit_compaction_failed(sink, engine, message)
        }
      }
      StreamExited(code) => {
        // Clear the slot only if the engine in it is still THIS one, by
        // identity. This consumer outlives its process: by the time the EOF
        // reaches here, the pump may already have replaced the dying engine
        // with a respawned ServeEngine for the same session (a config-change
        // respawn closes the old stdin and installs the successor in the
        // same slot before the old reader drains). Any by-value comparison
        // would confuse the two — a same-config respawn shares session_key
        // AND spec_key — so `physical_equal` (reference identity) is load-
        // bearing here: it is what stops a dead engine's cleanup from
        // evicting its live successor.
        if manager.pump is Serving(sessions~) &&
          sessions.get(engine.session_key) is Some(slot) &&
          slot.engine is Some(current) &&
          physical_equal(current, engine) {
          slot.engine = None
          manager.prune_slot(engine.session_key)
        }
        match engine.phase {
          // EOF with a run still open means the engine died mid-turn: close
          // that run with its only available diagnostics.
          Running(compact_queued~, ..) => {
            engine.phase = Idle
            let diagnostics = stderr_task.wait().trim().to_owned()
            if diagnostics.is_empty() {
              emit_error(
                sink,
                "engine exited without a result",
                run_id=engine.latest_run,
                exit_code=code,
              )
            } else {
              emit_error(
                sink,
                "engine exited without a result:\n" + diagnostics,
                run_id=engine.latest_run,
                exit_code=code,
                diagnostics~,
              )
            }
            emit_finished(sink, engine.latest_run, Failed, exit_code=code)
            // A compaction queued behind the dead turn died with the engine;
            // only a terminal compaction event clears the frontend's queued
            // notice, so synthesize the failure it can no longer send.
            if compact_queued {
              emit_compaction_failed(
                sink, engine, "engine exited before the queued compaction started",
              )
            }
          }
          // EOF mid-compaction: no run is open, but the frontend set its
          // compacting notice on compaction_started and only a terminal
          // compaction event clears it — synthesize the failure the engine
          // can no longer send.
          Compacting => {
            engine.phase = Idle
            let diagnostics = stderr_task.wait().trim().to_owned()
            let reason = if diagnostics.is_empty() {
              "engine exited during compaction"
            } else {
              "engine exited during compaction:\n" + diagnostics
            }
            emit_compaction_failed(sink, engine, reason)
          }
          // A clean exit after a terminal event (session switch, app
          // shutdown) reports nothing.
          Idle => ()
        }
        break
      }
    }
  }
}

///|
/// A synthetic `compaction_failed` stream event for a compaction whose
/// engine died before reporting one itself — the same wire shape the engine
/// emits, so the frontend's one decoder clears its compacting notice either
/// way. Routed like every compaction event: by the engine's session, with
/// the latest run id as the frontend's fallback.
async fn emit_compaction_failed(
  sink : EventSink,
  engine : ServeEngine,
  reason : String,
) -> Unit {
  emit(
    sink,
    StreamEvent({
      run_id: engine.latest_run,
      session: engine.session_key,
      event: { "event": "compaction_failed", "reason": Json::string(reason) },
    }),
  )
}
