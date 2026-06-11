///|
const ExtensionId = "openseek-desktop"

///|
const ExtensionNamespace = "openseek"

///|
const DefaultEngine = "openseek"

///|
const DefaultModel = "deepseek-v4-pro"

///|
const DefaultMaxSteps = 1000

///|
const FrontendEntryPath = "assets/index.html"

///|
struct StartPayload {
  task : String
  api_key : String?
  model : String?
  max_steps : Int?
  cwd : String?
  session : String?
  session_root : String?
} derive(FromJson)

///|
struct CancelPayload {
  run_id : Int?
} derive(FromJson)

///|
struct StartedPayload {
  run_id : Int
  task : String
  engine : String
  model : String
  max_steps : Int
  cwd : String?
  session : String?
  session_root : String?
} derive(ToJson)

///|
struct EventPayload {
  run_id : Int
  event : Json
} derive(ToJson)

///|
struct FinishedPayload {
  run_id : Int
  status : String
  answer : String?
  exit_code : Int?
} derive(ToJson)

///|
struct ErrorPayload {
  run_id : Int?
  message : String
  exit_code : Int?
  diagnostics : String?
} derive(ToJson)

///|
/// Terminal state of a run. `wire()` is the string sent to the frontend; the
/// values are part of the IPC contract and must not change casually.
priv enum RunStatus {
  Finished
  Aborted
  Failed
  Cancelled
  MaxStepsExhausted
}

///|
fn RunStatus::wire(self : RunStatus) -> String {
  match self {
    Finished => "finished"
    Aborted => "aborted"
    Failed => "failed"
    Cancelled => "cancelled"
    MaxStepsExhausted => "max_steps_exhausted"
  }
}

///|
struct StartReply {
  run_id : Int
  status : String
  exit_code : Int
} derive(ToJson)

///|
struct LoadSessionPayload {
  session : String
} derive(FromJson)

///|
/// Reply to `list_sessions`: the engine's `--session-list-json` output
/// (an array of `{id, title, updated_at_ms, last_sequence}`, newest first),
/// passed through verbatim.
struct SessionsReply {
  sessions : Json
  session_root : String
} derive(ToJson)

///|
/// Reply to `load_session`: the engine's `--session-show` output (the durable
/// session JSON with its full event log), passed through verbatim.
struct LoadSessionReply {
  session : Json
} derive(ToJson)

///|
struct CancelReply {
  cancelled : Bool
  run_id : Int?
} derive(ToJson)

///|
/// Reply to `connect`, delivered only when the pump stops — in practice
/// never, since the webview holds the call open for the app's lifetime.
struct PumpReply {
  disconnected : Bool
} derive(ToJson)

///|
priv struct RunConfig {
  task : String
  api_key : String
  model : String
  max_steps : Int
  engine : String
  cwd : String?
  session : String?
  session_root : String?
}

///|
/// A live `--serve` engine process: one process serves every prompt of one
/// conversation. Prompts and cancels are JSONL commands on its stdin; its
/// stdout event stream is consumed for the engine's lifetime. Turns are
/// strictly sequential on the wire, so events are stamped with the run id of
/// the most recently submitted prompt.
priv struct ServeEngine {
  // Fingerprint of the config this process was spawned with; a prompt whose
  // config differs cannot reuse it.
  spec_key : String
  writer : @process.WriteToProcess
  mut latest_run : Int
  mut run_open : Bool
  mut cancel_requested : Bool
}

///|
priv enum PumpCommand {
  // Replace the live engine (if any) with one spawned for this config; the
  // queue carries the result back to the requesting `start` op.
  SpawnEngine(RunConfig, @async.Queue[Result[Unit, String]])
}

///|
/// Host-side state of the persistent-engine design: the live serve process
/// (owned by the pump's task group) plus the command queue other ops use to
/// ask the pump for lifecycle changes. stdin writes go directly from any op;
/// only spawning needs the pump, because a process must be owned by a task
/// group that outlives individual IPC requests.
priv struct EngineManager {
  commands : @async.Queue[PumpCommand]
  mut live : ServeEngine?
  mut next_run_id : Int
  mut pump_running : Bool
  mut start_in_flight : Bool
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
    live: None,
    next_run_id: 1,
    pump_running: false,
    start_in_flight: false,
  }
}

///|
fn non_empty(value : String?) -> String? {
  match value {
    Some(value) => {
      let value = value.trim().to_owned()
      if value.is_empty() {
        None
      } else {
        Some(value)
      }
    }
    None => None
  }
}

///|
fn option_or_env(
  value : String?,
  env_name : String,
  fallback : String,
) -> String {
  match non_empty(value) {
    Some(value) => value
    None =>
      match non_empty(@env.get_env_var(env_name)) {
        Some(value) => value
        None => fallback
      }
  }
}

///|
fn required_secret(
  value : String?,
  env_name : String,
) -> Result[String, String] {
  match non_empty(value) {
    Some(value) => Ok(value)
    None =>
      match non_empty(@env.get_env_var(env_name)) {
        Some(value) => Ok(value)
        None =>
          Err("DeepSeek API key is required; pass api_key or set " + env_name)
      }
  }
}

///|
fn configured_max_steps(value : Int?) -> Result[Int, String] {
  let parsed = match value {
    Some(value) => value
    None =>
      match non_empty(@env.get_env_var("OPENSEEK_MAX_STEPS")) {
        Some(text) =>
          @string.parse_int(text) catch {
            _ => return Err("OPENSEEK_MAX_STEPS must be a positive integer")
          }
        None => DefaultMaxSteps
      }
  }
  if parsed > 0 {
    Ok(parsed)
  } else {
    Err("max_steps must be a positive integer")
  }
}

///|
fn run_config(
  payload : StartPayload,
  engine : String,
) -> Result[RunConfig, String] {
  let task = payload.task.trim().to_owned()
  guard !task.is_empty() else { return Err("task must not be empty") }
  let api_key = match required_secret(payload.api_key, "DEEPSEEK") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let max_steps = match configured_max_steps(payload.max_steps) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let session = non_empty(payload.session)
  let cwd = match resolved_run_cwd(payload.cwd) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({
    task,
    api_key,
    model: option_or_env(payload.model, "DEEPSEEK_MODEL", DefaultModel),
    max_steps,
    engine,
    cwd,
    session,
    session_root: match session {
      Some(_) => resolved_session_root(payload.session_root)
      None => None
    },
  })
}

///|
/// Engine working directory for a run. An explicit payload value must be an
/// existing directory — a typo fails the run with a clear message instead of a
/// cryptic engine error. When unset, fall back to the user's home directory:
/// inheriting the host's own cwd would hand the agent whatever directory the
/// app happened to be launched from (`/` under Finder), which is never a
/// sensible place to work in.
fn resolved_run_cwd(payload_cwd : String?) -> Result[String?, String] {
  match non_empty(payload_cwd) {
    Some(cwd) => {
      let cwd = expand_home(cwd)
      let is_directory = @mbfs.is_dir(cwd) catch { _ => false }
      if is_directory {
        Ok(Some(cwd))
      } else {
        Err("working directory does not exist: " + cwd)
      }
    }
    None => Ok(home_dir())
  }
}

///|
fn expand_home(cwd : String) -> String {
  match home_dir() {
    Some(home) =>
      if cwd == "~" {
        home
      } else if cwd.has_prefix("~/") {
        home + cwd[1:].to_owned()
      } else {
        cwd
      }
    None => cwd
  }
}

///|
fn home_dir() -> String? {
  match non_empty(@env.get_env_var("HOME")) {
    Some(home) => Some(home)
    None => non_empty(@env.get_env_var("USERPROFILE"))
  }
}

///|
/// Per-user runtime directory for the host's own state. The lepus framework
/// IPC config lives here instead of inside the .app bundle: a signed bundle
/// is read-only by convention (and may be mounted read-only under app
/// translocation), and writing next to the binary also breaks when a
/// repackage replaces the bundle under a running instance. Uses
/// `~/Library/Application Support/OpenSeek Desktop` where that layout exists
/// (macOS) and `~/.openseek-desktop` elsewhere.
fn app_runtime_dir() -> String? {
  guard home_dir() is Some(home) else { return None }
  let home_path : @mbpath.Path = home
  let app_support = home_path.join("Library").join("Application Support")
  let app_support_exists = @mbfs.is_dir(app_support.to_string()) catch {
    _ => false
  }
  let dir = if app_support_exists {
    app_support.join("OpenSeek Desktop")
  } else {
    home_path.join(".openseek-desktop")
  }
  Some(dir.normalize().to_string())
}

///|
/// The runtime directory, created on demand. `None` when it cannot be
/// determined or created; callers then fall back to lepus defaults.
fn prepared_runtime_dir() -> String? {
  guard app_runtime_dir() is Some(dir) else { return None }
  let exists = @mbfs.is_dir(dir) catch { _ => false }
  if !exists {
    @mbfs.create_dir(dir) catch {
      _ => return None
    }
  }
  Some(dir)
}

///|
/// Drop framework configs left behind by earlier launches. Each launch writes
/// a fresh timestamped file (so two concurrent instances never clobber each
/// other); without this sweep they would accumulate forever.
fn remove_stale_framework_configs(dir : String) -> Unit {
  let entries = @mbfs.read_dir(dir) catch { _ => return }
  for entry in entries {
    if entry.has_prefix("lepus-framework-") && entry.has_suffix(".json") {
      @mbfs.remove_file(dir + "/" + entry) catch {
        _ => ()
      }
    }
  }
}

///|
/// Where durable sessions live when a run names a session: the payload's
/// explicit root, then the OPENSEEK_SESSION_ROOT environment, then a stable
/// absolute default under the user's home directory. The absolute fallback
/// matters because a packaged app can run with `/` as its working directory,
/// where the engine's relative `.openseek` default could never be created.
fn resolved_session_root(payload_root : String?) -> String? {
  match non_empty(payload_root) {
    Some(root) => Some(root)
    None =>
      match non_empty(@env.get_env_var("OPENSEEK_SESSION_ROOT")) {
        Some(root) => Some(root)
        None => home_session_root()
      }
  }
}

///|
fn home_session_root() -> String? {
  match home_dir() {
    Some(home) => {
      let home_path : @mbpath.Path = home
      Some(home_path.join(".openseek").normalize().to_string())
    }
    None => None
  }
}

///|
fn frontend_entry_path(framework_command : String) -> String {
  let command_path : @mbpath.Path = framework_command
  let resource_path = command_path
    .dirname()
    .resolve()
    .join(FrontendEntryPath)
    .normalize()
    .to_string()
  if @mbfs.path_exists(resource_path) {
    resource_path
  } else {
    FrontendEntryPath
  }
}

///|
fn bundled_engine_path(framework_command : String) -> String? {
  let command_path : @mbpath.Path = framework_command
  let command_dir = command_path.dirname().resolve()
  let candidates = match @env.get_env_var("OS") {
    Some("Windows_NT") => ["openseek.exe", "openseek"]
    _ => ["openseek", "openseek.exe"]
  }
  for candidate in candidates {
    let path = command_dir.join(candidate).normalize().to_string()
    if @mbfs.path_exists(path) {
      return Some(path)
    }
  }
  None
}

///|
fn engine_command(framework_command : String) -> String {
  match bundled_engine_path(framework_command) {
    Some(path) => path
    None => option_or_env(None, "OPENSEEK_ENGINE", DefaultEngine)
  }
}

///|
/// Every outbound event the runner can send to the frontend. `emit` is the
/// single place that maps a variant to its wire name and payload, so the
/// name/payload pairing can never drift out of sync.
priv enum OutEvent {
  Started(StartedPayload)
  Event(EventPayload)
  Error(ErrorPayload)
  Finished(FinishedPayload)
}

///|
async fn emit(
  context : @app.AppCommandExtensionContext,
  event : OutEvent,
) -> Unit {
  match event {
    Started(payload) => context.emit("started", payload)
    Event(payload) => context.emit("event", payload)
    Error(payload) => context.emit("error", payload)
    Finished(payload) => context.emit("finished", payload)
  }
}

///|
async fn emit_error(
  context : @app.AppCommandExtensionContext,
  message : String,
  run_id? : Int,
  exit_code? : Int,
  diagnostics? : String,
) -> Unit {
  emit(context, Error({ run_id, message, exit_code, diagnostics }))
}

///|
async fn emit_finished(
  context : @app.AppCommandExtensionContext,
  run_id : Int,
  status : RunStatus,
  answer? : String,
  exit_code? : Int,
) -> Unit {
  emit(context, Finished({ run_id, status: status.wire(), answer, exit_code }))
}

///|
async fn read_engine_stdout(
  reader : @process.ReadFromProcess,
  process : @process.Process,
  messages : @async.Queue[StreamMessage],
) -> Unit {
  @jsonl.each(reader, json => ignore(messages.try_put(StreamEvent(json)))) catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) =>
      raise error
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
/// Everything that pins a serve process to a config: a prompt whose
/// fingerprint differs (model change, new session, …) must replace the
/// process. The task is deliberately excluded — prompts vary per turn.
fn engine_fingerprint(config : RunConfig) -> String {
  [
    config.engine,
    config.api_key,
    config.model,
    config.max_steps.to_string(),
    config.cwd.unwrap_or(""),
    config.session.unwrap_or(""),
    config.session_root.unwrap_or(""),
  ].join("\u{0}")
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
) -> Result[PumpReply, String] {
  if manager.pump_running {
    return Err("engine host is already connected")
  }
  fn reset() -> Unit {
    manager.pump_running = false
    manager.live = None
  }

  manager.pump_running = true
  defer reset()
  @async.with_task_group(group => {
    for ;; {
      match manager.commands.get() {
        SpawnEngine(config, ack) => {
          if manager.live is Some(old) {
            // Closing stdin is the serve protocol's EOF signal; an idle
            // engine drains and exits, and its own reader task cleans up.
            old.writer.close()
            manager.live = None
          }
          start_serve_engine(context, group, manager, config) catch {
            error if @async.is_being_cancelled() ||
              @async.is_cancellation_error(error) => raise error
            error => {
              ack.put(Err("failed to start engine: \{error}"))
              continue
            }
          }
          ack.put(Ok(()))
        }
      }
    }
  })
  Ok({ disconnected: true })
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
  }
  // A named session puts the engine in durable-session mode, so the
  // conversation survives the process and is shared with the CLI/TUI.
  if config.session is Some(session) {
    env["OPENSEEK_SESSION"] = session
    if config.session_root is Some(root) {
      env["OPENSEEK_SESSION_ROOT"] = root
    }
  }
  let process = @process.spawn(
    group,
    config.engine,
    ["--serve"],
    inherit_env=true,
    extra_env=env,
    stdin=child_stdin,
    stdout=child_stdout,
    stderr=child_stderr,
    cwd?=config.cwd.map(cwd => cwd.view()),
    cancel_handler=@process.graceful_cancel(timeout=1000),
    no_wait=true,
  )
  let engine : ServeEngine = {
    spec_key: engine_fingerprint(config),
    writer,
    latest_run: 0,
    run_open: false,
    cancel_requested: false,
  }
  manager.live = Some(engine)
  let messages : @async.Queue[StreamMessage] = Queue(kind=Unbounded)
  let stderr_task = group.spawn(no_wait=true) <| () => {
    stderr_reader.read_all().text() catch {
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
        let run_id = engine.latest_run
        emit(context, Event({ run_id, event: raw }))
        match @event.decode_event(raw) {
          // The abort the user asked for: report it as a cancellation, the
          // same wire status the pre-serve host used.
          Some(AgentAborted(_)) if engine.cancel_requested => {
            emit_error(context, "cancelled", run_id~)
            emit_finished(context, run_id, Cancelled)
            engine.run_open = false
            engine.cancel_requested = false
          }
          Some(decoded) =>
            if handle_decoded_event(context, run_id, decoded) {
              engine.run_open = false
              engine.cancel_requested = false
            }
          None => ()
        }
      }
      StreamReaderFailed(message) =>
        emit_error(context, message, run_id=engine.latest_run)
      StreamExited(code) => {
        // A respawn may already have replaced this engine; only clear the
        // slot if it is still ours.
        if manager.live is Some(current) && physical_equal(current, engine) {
          manager.live = None
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

///|
/// Submit one prompt to the conversation's serve engine, spawning or
/// replacing the process first when the config demands it. Returns as soon
/// as the prompt is on the wire; the engine's consumer task reports progress
/// and completion through events, exactly as the frontend already expects.
async fn start_run(
  context : @app.AppCommandExtensionContext,
  manager : EngineManager,
  engine : String,
  payload : StartPayload,
) -> Result[StartReply, String] {
  if manager.live is Some(live) && live.run_open {
    return Err("OpenSeek run \{live.latest_run} is still active")
  }
  if manager.start_in_flight {
    return Err("an OpenSeek run is already starting")
  }
  guard manager.pump_running else {
    return Err("engine host is not connected; reload the app")
  }
  fn clear_start_flag() -> Unit {
    manager.start_in_flight = false
  }

  manager.start_in_flight = true
  defer clear_start_flag()
  let config = match run_config(payload, engine) {
    Ok(config) => config
    Err(error) => return Err(error)
  }
  let need_spawn = match manager.live {
    Some(live) => live.spec_key != engine_fingerprint(config)
    None => true
  }
  if need_spawn {
    let ack : @async.Queue[Result[Unit, String]] = Queue(kind=Unbounded)
    manager.commands.put(SpawnEngine(config, ack))
    match ack.get() {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  guard manager.live is Some(live) else { return Err("engine failed to start") }
  let run_id = manager.next_run_id
  manager.next_run_id = manager.next_run_id + 1
  live.latest_run = run_id
  live.run_open = true
  live.cancel_requested = false
  emit(
    context,
    Started({
      run_id,
      task: config.task,
      engine: config.engine,
      model: config.model,
      max_steps: config.max_steps,
      cwd: config.cwd,
      session: config.session,
      session_root: config.session_root,
    }),
  )
  let command : Json = { "command": "prompt", "text": config.task }
  live.writer.write(command.stringify() + "\n") catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) =>
      raise error
    error => {
      // The engine died between turns: close the run and drop the handle so
      // the next prompt respawns on the same durable session.
      live.run_open = false
      if manager.live is Some(current) && physical_equal(current, live) {
        manager.live = None
      }
      emit_error(context, "engine write failed: \{error}", run_id~)
      emit_finished(context, run_id, Failed)
      return Err("engine write failed: \{error}")
    }
  }
  Ok({ run_id, status: "accepted", exit_code: 0 })
}

///|
/// Cancel the open turn by asking the serve engine to interrupt it — the
/// process itself stays alive for the next prompt. With no live engine or
/// open run there is nothing to cancel.
async fn cancel_run(
  manager : EngineManager,
  payload : CancelPayload,
) -> CancelReply {
  match manager.live {
    Some(live) if live.run_open => {
      if payload.run_id is Some(requested) && requested != live.latest_run {
        return { cancelled: false, run_id: Some(live.latest_run) }
      }
      live.cancel_requested = true
      let command : Json = { "command": "cancel" }
      live.writer.write(command.stringify() + "\n") catch {
        error if @async.is_being_cancelled() ||
          @async.is_cancellation_error(error) => raise error
        // The engine just died; its reader task closes the run.
        _ => ()
      }
      { cancelled: true, run_id: Some(live.latest_run) }
    }
    _ => { cancelled: false, run_id: None }
  }
}

///|
/// Run the bundled engine with `args` and return its stdout. A non-zero exit
/// is reported through stderr's content so the frontend sees the engine's own
/// message rather than a bare exit code when one is available.
async fn engine_stdout(
  engine : String,
  args : Array[String],
) -> Result[String, String] {
  let (code, stdout, stderr) = @process.collect_output(
    engine,
    args,
    inherit_env=true,
  ) catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) =>
      raise error
    error => return Err("failed to run engine: \{error}")
  }
  if code != 0 {
    let detail = (stderr.text() catch { _ => "" }).trim().to_owned()
    return Err(
      if detail.is_empty() {
        "engine exited with code \{code}"
      } else {
        detail
      },
    )
  }
  Ok(stdout.text() catch { _ => return Err("engine wrote malformed output") })
}

///|
async fn list_sessions(engine : String) -> Result[SessionsReply, String] {
  guard resolved_session_root(None) is Some(root) else {
    return Err("cannot determine a session root; set OPENSEEK_SESSION_ROOT")
  }
  let output = match
    engine_stdout(engine, ["--session-root", root, "--session-list-json"]) {
    Ok(output) => output
    Err(error) => return Err("session list failed: " + error)
  }
  let sessions = @json.parse(output) catch {
    _ => return Err("engine returned a malformed session list")
  }
  Ok({ sessions, session_root: root })
}

///|
async fn load_session(
  engine : String,
  payload : LoadSessionPayload,
) -> Result[LoadSessionReply, String] {
  guard non_empty(Some(payload.session)) is Some(session) else {
    return Err("session id must not be empty")
  }
  guard resolved_session_root(None) is Some(root) else {
    return Err("cannot determine a session root; set OPENSEEK_SESSION_ROOT")
  }
  let output = match
    engine_stdout(engine, [
      "--session-root", root, "--session-show", "--session", session,
    ]) {
    Ok(output) => output
    Err(error) => return Err("session load failed: " + error)
  }
  let json = @json.parse(output) catch {
    _ => return Err("engine returned a malformed session")
  }
  Ok({ session: json })
}

///|
fn openseek_extension(
  manager : EngineManager,
  engine : String,
) -> @app.AppCommandExtensionSpec {
  @app.AppCommandExtensionSpec::new(
    ExtensionId,
    ExtensionNamespace,
    [
      @app.AppCommandApiDescriptor::new("connect"),
      @app.AppCommandApiDescriptor::new("start"),
      @app.AppCommandApiDescriptor::new("cancel"),
      @app.AppCommandApiDescriptor::new("list_sessions"),
      @app.AppCommandApiDescriptor::new("load_session"),
    ],
    fn(context) {
      context.op_async_result("connect", async fn(_payload : Json) {
        run_engine_pump(context, manager)
      })
      context.op_async_result("start", async fn(payload : StartPayload) {
        start_run(context, manager, engine, payload)
      })
      context.op_async("cancel", async fn(payload : CancelPayload) {
        cancel_run(manager, payload)
      })
      context.op_async_result("list_sessions", async fn(_payload : Json) {
        list_sessions(engine)
      })
      context.op_async_result("load_session", async fn(
        payload : LoadSessionPayload,
      ) {
        load_session(engine, payload)
      })
      Ok(())
    },
  )
}

///|
fn main {
  if @app.is_framework_process() {
    match @app.run_framework_process_from_cli() {
      Ok(_) => ()
      Err(error) => abort(error)
    }
    return
  }
  let framework_command = match @app.current_executable_command() {
    Ok(command) => command
    Err(error) => abort(error)
  }
  let extensions : Map[String, @manifest.ExtensionSetting] = {}
  extensions[ExtensionId] = @manifest.ExtensionSetting::enabled()
  extensions["justjavac/lepus-clipboard"] = @manifest.ExtensionSetting::enabled()
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new("OpenSeek Desktop", 1120, 760, size_hint=None),
    File(frontend_entry_path(framework_command)),
    debug=1,
    extensions~,
  )
  let registry = @app.AppCommandExtensionRegistry::new()
  let _ = registry.register(
    openseek_extension(new_engine_manager(), engine_command(framework_command)),
  )
  let _ = registry.register(@clipboard.generated_app_command_extension())
  // Keep all runtime state out of the bundle: the framework IPC config is
  // written to the per-user runtime dir, and the framework child runs there
  // too, so neither process depends on the bundle directory being writable —
  // or on it continuing to exist while the app runs.
  let runtime_dir = prepared_runtime_dir()
  let framework_config_path = match runtime_dir {
    Some(dir) => {
      remove_stale_framework_configs(dir)
      Some("\{dir}/lepus-framework-\{@env.now()}.json")
    }
    None => None
  }
  match
    @app.run_app_command_extensions_with_framework_process(
      manifest,
      framework_command,
      registry,
      framework_args=[@app.framework_process_arg()],
      framework_cwd=runtime_dir,
      framework_config_path~,
    ) {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}
