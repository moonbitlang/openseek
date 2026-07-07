// The persistent-engine machinery: one `serve` process per conversation,
// owned by the `connect` op's task group, fed prompts over stdin and drained
// through a per-engine consumer that forwards events to the webview.

///|
/// A live `serve` engine process: one process serves every prompt of one
/// conversation. Prompts and cancels are JSONL commands on its stdin; its
/// stdout event stream is consumed for the engine's lifetime. Turns are
/// strictly sequential on the wire *per conversation*, so events are stamped
/// with the run id of the prompt this engine saw most recently.
priv struct ServeEngine {
  // The conversation this process serves: its slot in the manager's map.
  session_key : String
  // Fingerprint of the config this process was spawned with; a prompt whose
  // config differs cannot reuse it.
  spec_key : String
  writer : @process.WriteToProcess
  mut latest_run : Int
  mut run_open : Bool
  mut cancel_requested : Bool
  steer_runs : SteerRunTracker
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
  engines : Map[String, ServeEngine]
  mut next_run_id : Int
  mut pump_running : Bool
  // Conversations with a `start` op between config validation and the prompt
  // hitting the wire; a second start for the same conversation in that window
  // is refused instead of racing the spawn.
  starts_in_flight : Set[String]
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
    engines: {},
    next_run_id: 1,
    pump_running: false,
    starts_in_flight: Set([]),
  }
}

///|
/// The engine that owns the open run `run_id` — or, when no id is given, the
/// only open run if exactly one exists (with several conversations running
/// concurrently, an unaddressed cancel/steer would be a guess).
fn open_run_engine(manager : EngineManager, run_id? : Int) -> ServeEngine? {
  if run_id is Some(id) {
    for _, engine in manager.engines {
      if engine.run_open && engine.latest_run == id {
        return Some(engine)
      }
    }
    return None
  }
  let mut found : ServeEngine? = None
  for _, engine in manager.engines {
    if engine.run_open {
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
  guard !manager.pump_running else {
    raise EngineError("engine host is already connected")
  }
  fn reset() -> Unit {
    manager.pump_running = false
    manager.engines.clear()
  }

  manager.pump_running = true
  emit(sink, Connected({ ready: true }))
  defer reset()
  @async.with_task_group(group => {
    for ;; {
      match manager.commands.get() {
        SpawnEngine(config, ack) => {
          // Only this conversation's previous process is replaced; engines
          // serving other sessions keep running their own turns.
          if manager.engines.get(session_key(config)) is Some(old) {
            // Closing stdin is the serve protocol's EOF signal; an idle
            // engine drains and exits, and its own reader task cleans up.
            old.writer.close()
            manager.engines.remove(session_key(config))
          }
          start_serve_engine(sink, group, manager, config) catch {
            error if @async.is_being_cancelled() => raise error
            error => {
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
  // The agent tools spawn `moon` by name, so prepend the bundled bin to PATH.
  // Deliberately do not set `MOON_HOME` (it would redirect registry/cache
  // lookup into the bundled payload) and drop any ambient `MOON_HOME` the
  // launching shell exported: moon prefers it over the executable-relative
  // home and would otherwise run the bundled binary against the user's
  // (possibly missing or incompatible) MoonBit home.
  env["PATH"] = prepend_to_path_env(moon_bin_dir.to_string(), env.get("PATH"))
  env.remove("MOON_HOME")
  @xlog.debug() <?
    {
      "event": "desktop_engine_moonbit_path",
      "host": config.host.fingerprint(),
      "moon_home": moon_home.to_string(),
      "moon_bin_dir": moon_bin_dir.to_string(),
      "moon_exists": @fsx.exists(moon),
      "moon_exe_exists": @fsx.exists(moon_exe),
      "path_prefix": first_path_entry(env.get("PATH")),
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
  sink : EventSink,
  group : @async.TaskGroup[G],
  manager : EngineManager,
  config : RunConfig,
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
      "path_prefix": first_path_entry(env.get("PATH")),
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
    run_open: false,
    cancel_requested: false,
    steer_runs: SteerRunTracker::new(),
  }
  manager.engines.set(engine.session_key, engine)
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
          Some(AgentAborted(_)) if engine.cancel_requested => {
            emit_error(sink, "cancelled", run_id~)
            emit_finished(sink, run_id, Cancelled)
            engine.run_open = false
            engine.cancel_requested = false
            engine.steer_runs.record_terminal(run_id)
          }
          Some(decoded) => {
            // Terminal failures are immediately normalized below; forwarding
            // their raw event as well would make the frontend render the same
            // failure twice.
            if !host_reports_terminal_error(decoded) {
              emit(sink, StreamEvent({ run_id, event: raw }))
            }
            if handle_decoded_event(sink, run_id, decoded) {
              engine.run_open = false
              engine.cancel_requested = false
              engine.steer_runs.record_terminal(run_id)
            }
          }
          None => emit(sink, StreamEvent({ run_id, event: raw }))
        }
      }
      StreamReaderFailed(message) =>
        emit_error(sink, message, run_id=engine.latest_run)
      StreamExited(code) => {
        // A respawn may already have replaced this engine in its slot; only
        // clear the slot if it is still ours.
        if manager.engines.get(engine.session_key) is Some(current) &&
          physical_equal(current, engine) {
          manager.engines.remove(engine.session_key)
        }
        // EOF with a run still open means the engine died mid-turn: close
        // that run with its only available diagnostics. A clean exit after a
        // terminal event (session switch, app shutdown) reports nothing.
        if engine.run_open {
          engine.run_open = false
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
        }
        break
      }
    }
  }
}
