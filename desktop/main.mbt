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
struct CancelReply {
  cancelled : Bool
  run_id : Int?
} derive(ToJson)

///|
priv struct RunConfig {
  task : String
  api_key : String
  model : String
  max_steps : Int
  engine : String
  cwd : String?
}

///|
priv struct ActiveRun {
  run_id : Int
  mut process : @process.Process?
  mut messages : @async.Queue[StreamMessage]?
  mut cancel_requested : Bool
}

///|
priv struct RunnerState {
  mut next_run_id : Int
  mut current : ActiveRun?
}

///|
priv enum StreamMessage {
  StreamEvent(Json)
  StreamReaderFailed(String)
  StreamExited(Int)
  StreamCancelled
}

///|
fn new_runner_state() -> RunnerState {
  { next_run_id: 1, current: None }
}

///|
fn RunnerState::begin_run(self : RunnerState) -> Result[ActiveRun, String] {
  match self.current {
    Some(active) => Err("OpenSeek run \{active.run_id} is still active")
    None => {
      let active = ActiveRun::{
        run_id: self.next_run_id,
        process: None,
        messages: None,
        cancel_requested: false,
      }
      self.next_run_id = self.next_run_id + 1
      self.current = Some(active)
      Ok(active)
    }
  }
}

///|
fn RunnerState::clear_run(self : RunnerState, run_id : Int) -> Unit {
  if self.current is Some(active) && active.run_id == run_id {
    self.current = None
  }
}

///|
fn RunnerState::cancel(
  self : RunnerState,
  payload : CancelPayload,
) -> CancelReply {
  match self.current {
    None => { cancelled: false, run_id: None }
    Some(active) =>
      if payload.run_id is Some(requested) && requested != active.run_id {
        { cancelled: false, run_id: Some(active.run_id) }
      } else {
        active.cancel_requested = true
        if active.process is Some(process) {
          process.cancel()
        }
        // Wake the run loop immediately instead of waiting for the engine's
        // stdout to reach EOF: a killed engine may leave child processes that
        // keep the stdout pipe open, so the EOF may never arrive.
        if active.messages is Some(messages) {
          ignore(messages.try_put(StreamCancelled) catch { _ => false })
        }
        { cancelled: true, run_id: Some(active.run_id) }
      }
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
  Ok({
    task,
    api_key,
    model: option_or_env(payload.model, "DEEPSEEK_MODEL", DefaultModel),
    max_steps,
    engine,
    cwd: non_empty(payload.cwd),
  })
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
  emit(
    context,
    Finished({ run_id, status: status.wire(), answer, exit_code }),
  )
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
async fn run_engine(
  context : @app.AppCommandExtensionContext,
  active : ActiveRun,
  config : RunConfig,
) -> StartReply {
  @async.with_task_group(group => {
    let (reader, child_stdout) = @process.read_from_process()
    let (stderr_reader, child_stderr) = @process.read_from_process()
    let args = [config.task]
    let env = {
      "DEEPSEEK": config.api_key,
      "DEEPSEEK_MODEL": config.model,
      "OPENSEEK_MAX_STEPS": config.max_steps.to_string(),
    }
    let process = @process.spawn(
      group,
      config.engine,
      args,
      inherit_env=true,
      extra_env=env,
      stdout=child_stdout,
      stderr=child_stderr,
      cwd?=config.cwd.map(cwd => cwd.view()),
      cancel_handler=@process.graceful_cancel(timeout=1000),
      no_wait=true,
    )
    active.process = Some(process)
    let messages = @async.Queue(kind=Unbounded)
    active.messages = Some(messages)
    let stderr_task = group.spawn(no_wait=true) <| () => {
      stderr_reader.read_all().text() catch {
        _ => ""
      }
    }
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      read_engine_stdout(reader, process, messages)
    })
    let mut saw_terminal = false
    let mut exit_code = 0
    let mut done = false
    while !done {
      match messages.get() {
        StreamEvent(raw) => {
          emit(context, Event({ run_id: active.run_id, event: raw }))
          match @event.decode_event(raw) {
            Some(decoded) =>
              if handle_decoded_event(context, active.run_id, decoded) {
                saw_terminal = true
              }
            None => ()
          }
        }
        StreamReaderFailed(message) =>
          emit_error(context, message, run_id=active.run_id)
        StreamCancelled => {
          // Cancel requested: report it now and let the task group tear down
          // the engine process and the stdout reader on the way out.
          emit_error(context, "cancelled", run_id=active.run_id)
          emit_finished(context, active.run_id, Cancelled)
          done = true
        }
        StreamExited(code) => {
          exit_code = code
          let diagnostics = stderr_task.wait().trim().to_owned()
          if active.cancel_requested {
            emit_error(context, "cancelled", run_id=active.run_id)
            emit_finished(context, active.run_id, Cancelled, exit_code~)
          } else if !saw_terminal {
            let detail = if diagnostics.is_empty() {
              "engine exited without a result"
            } else {
              "engine exited without a result:\n" + diagnostics
            }
            if diagnostics.is_empty() {
              emit_error(context, detail, run_id=active.run_id, exit_code~)
            } else {
              emit_error(
                context,
                detail,
                run_id=active.run_id,
                exit_code~,
                diagnostics~,
              )
            }
            emit_finished(context, active.run_id, Failed, exit_code~)
          }
          done = true
        }
      }
    }
    let status : RunStatus = if active.cancel_requested {
      Cancelled
    } else if saw_terminal {
      Finished
    } else {
      Failed
    }
    { run_id: active.run_id, status: status.wire(), exit_code }
  })
}

///|
async fn start_run(
  context : @app.AppCommandExtensionContext,
  state : RunnerState,
  engine : String,
  payload : StartPayload,
) -> Result[StartReply, String] {
  let active = match state.begin_run() {
    Ok(active) => active
    Err(error) => return Err(error)
  }
  let config = match run_config(payload, engine) {
    Ok(config) => config
    Err(error) => {
      state.clear_run(active.run_id)
      return Err(error)
    }
  }
  emit(
    context,
    Started({
      run_id: active.run_id,
      task: config.task,
      engine: config.engine,
      model: config.model,
      max_steps: config.max_steps,
      cwd: config.cwd,
    }),
  )
  let reply = run_engine(context, active, config) catch {
    error => {
      emit_error(context, error.to_string(), run_id=active.run_id)
      state.clear_run(active.run_id)
      return Err(error.to_string())
    }
  }
  state.clear_run(active.run_id)
  Ok(reply)
}

///|
fn openseek_extension(
  state : RunnerState,
  engine : String,
) -> @app.AppCommandExtensionSpec {
  @app.AppCommandExtensionSpec::new(
    ExtensionId,
    ExtensionNamespace,
    [
      @app.AppCommandApiDescriptor::new("start"),
      @app.AppCommandApiDescriptor::new("cancel"),
    ],
    fn(context) {
      context.op_async_result("start", async fn(payload : StartPayload) {
        start_run(context, state, engine, payload)
      })
      context.op("cancel", fn(payload : CancelPayload) { state.cancel(payload) })
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
    openseek_extension(new_runner_state(), engine_command(framework_command)),
  )
  let _ = registry.register(@clipboard.generated_app_command_extension())
  match
    @app.run_app_command_extensions_with_framework_process(
      manifest,
      framework_command,
      registry,
      framework_args=[@app.framework_process_arg()],
    ) {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}
