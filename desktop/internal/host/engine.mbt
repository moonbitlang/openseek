// The persistent-engine machinery: one `--serve` process per conversation,
// owned by the `connect` op's task group, fed prompts over stdin and drained
// through a per-engine consumer that forwards events to the webview.

///|
/// A live `--serve` engine process: one process serves every prompt of one
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
  raw : Json,
  latest_run : Int,
) -> Int {
  if is_steer_settle_event(raw) {
    let content = stream_event_content(raw)
    if remove_first_text(self.settling_steers, content) &&
      self.settling_run is Some(run_id) {
      if self.settling_steers.is_empty() {
        self.settling_run = None
      }
      return run_id
    }
    ignore(remove_first_text(self.open_steers, content))
  } else {
    self.settling_run = None
    self.settling_steers.clear()
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
fn is_steer_settle_event(raw : Json) -> Bool {
  match stream_event_name(raw) {
    Some("steer_applied") | Some("steer_dropped") => true
    _ => false
  }
}

///|
fn stream_event_name(raw : Json) -> String? {
  match raw {
    Object(fields) =>
      match fields.get("event") {
        Some(String(name)) => Some(name)
        _ => None
      }
    _ => None
  }
}

///|
fn stream_event_content(raw : Json) -> String {
  match raw {
    Object(fields) =>
      match fields.get("content") {
        Some(String(content)) => content
        _ => ""
      }
    _ => ""
  }
}

///|
priv enum PumpCommand {
  // Replace the conversation's engine (if any) with one spawned for this
  // config; the queue carries the spawn failure — or None for success —
  // back to the requesting `start` op.
  SpawnEngine(RunConfig, @async.Queue[HostError?])
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
priv struct EngineManager {
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
fn new_engine_manager() -> EngineManager {
  {
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
/// `--session-list` / `--session-show` in a packaged app.
async fn prepare_engine_stdin(engine : String) -> &@process.ProcessInput {
  let path = if @appdirs.prepared_runtime_dir() is Some(dir) {
    dir + "/engine.stdin"
  } else {
    engine + ".stdin"
  }
  @fs.write_file(path, "", create_mode=CreateOrTruncate)
  @process.redirect_from_file(path)
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
  context : @app.AppCommandExtensionContext,
  run_id : Int,
  decoded : @event.AgentEvent,
) -> Bool {
  match decoded {
    AgentFinished(answer) => {
      emit_finished(context, run_id, Finished, answer~)
      true
    }
    AgentAborted(reason) => {
      emit_error(context, "agent aborted: " + reason, run_id~)
      emit_finished(context, run_id, Aborted)
      true
    }
    MaxStepsExhausted => {
      emit_error(context, "max steps exhausted", run_id~)
      emit_finished(context, run_id, MaxStepsExhausted)
      true
    }
    AgentError(message) => {
      emit_error(context, message, run_id~)
      emit_finished(context, run_id, Failed)
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
async fn run_engine_pump(
  context : @app.AppCommandExtensionContext,
  manager : EngineManager,
) -> PumpReply {
  guard !manager.pump_running else {
    raise HostError("engine host is already connected")
  }
  fn reset() -> Unit {
    manager.pump_running = false
    manager.engines.clear()
  }

  manager.pump_running = true
  emit(context, Connected({ ready: true }))
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
          start_serve_engine(context, group, manager, config) catch {
            error if @async.is_being_cancelled() => raise error
            error => {
              ack.put(Some(HostError("failed to start engine: \{error}")))
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
/// Spawn one `--serve` engine inside the pump's task group and wire up its
/// stream tasks: the stdout reader feeding the queue, the stderr drain, and
/// the consumer that forwards events to the webview for the engine's
/// lifetime.
async fn[G] start_serve_engine(
  context : @app.AppCommandExtensionContext,
  group : @async.TaskGroup[G],
  manager : EngineManager,
  config : RunConfig,
) -> Unit {
  let (child_stdin, writer) = @process.write_to_process()
  let (reader, child_stdout) = @process.read_from_process()
  let (stderr_reader, child_stderr) = @process.read_from_process()
  let env = {
    "DEEPSEEK": config.api_key,
    "DEEPSEEK_MODEL": config.model,
    "OPENSEEK_MAX_STEPS": config.max_steps.to_string(),
    "OPENSEEK_DIR": ".",
  }
  if config.api_url is Some(url) {
    env["OPENSEEK_API_URL"] = url
  }
  // A named session puts the engine in durable-session mode, so the
  // conversation survives the process and is shared with the CLI/TUI.
  if config.session is Some(session) {
    env["OPENSEEK_SESSION"] = session
    if config.session_root is Some(root) {
      env["OPENSEEK_SESSION_ROOT"] = root
    }
  }
  if config.host is Wsl(..) {
    env["WSLENV"] = wslenv_with_passthrough(@env.get("WSLENV"))
  }
  let (program, args) = config.host.serve_command(config.engine, config.cwd)
  // In WSL mode the working directory is `--cd`'s job: a Linux-path cwd
  // does not exist on the Windows side, so chdir'ing wsl.exe into it would
  // fail the spawn.
  let spawn_cwd = if config.host is Wsl(..) { None } else { config.cwd }
  let process = @process.spawn(
    group,
    program,
    args,
    inherit_env=true,
    extra_env=env,
    stdin=child_stdin,
    stdout=child_stdout,
    stderr=child_stderr,
    cwd?=spawn_cwd.map(cwd => cwd.view()),
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
    serve_engine_consumer(context, manager, engine, messages, stderr_task)
  })
}

///|
/// Consume one engine's event stream for its whole lifetime: forward every
/// raw event to the webview stamped with the engine's current run, close
/// runs on terminal events, and report a mid-turn death as that run's
/// failure. Runs until the engine's stdout reader sees EOF.
async fn serve_engine_consumer(
  context : @app.AppCommandExtensionContext,
  manager : EngineManager,
  engine : ServeEngine,
  messages : @async.Queue[StreamMessage],
  stderr_task : @async.Task[String],
) -> Unit {
  for ;; {
    match messages.get() {
      StreamEvent(raw) => {
        let run_id = engine.steer_runs.run_id_for_event(raw, engine.latest_run)
        match @event.decode_event(raw) {
          // The abort the user asked for: report it as a cancellation, the
          // same wire status the pre-serve host used.
          Some(AgentAborted(_)) if engine.cancel_requested => {
            emit_error(context, "cancelled", run_id~)
            emit_finished(context, run_id, Cancelled)
            engine.run_open = false
            engine.cancel_requested = false
            engine.steer_runs.record_terminal(run_id)
          }
          Some(decoded) => {
            // Terminal failures are immediately normalized below; forwarding
            // their raw event as well would make the frontend render the same
            // failure twice.
            if !host_reports_terminal_error(decoded) {
              emit(context, Event({ run_id, event: raw }))
            }
            if handle_decoded_event(context, run_id, decoded) {
              engine.run_open = false
              engine.cancel_requested = false
              engine.steer_runs.record_terminal(run_id)
            }
          }
          None => emit(context, Event({ run_id, event: raw }))
        }
      }
      StreamReaderFailed(message) =>
        emit_error(context, message, run_id=engine.latest_run)
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
              context,
              "engine exited without a result",
              run_id=engine.latest_run,
              exit_code=code,
            )
          } else {
            emit_error(
              context,
              "engine exited without a result:\n" + diagnostics,
              run_id=engine.latest_run,
              exit_code=code,
              diagnostics~,
            )
          }
          emit_finished(context, engine.latest_run, Failed, exit_code=code)
        }
        break
      }
    }
  }
}
