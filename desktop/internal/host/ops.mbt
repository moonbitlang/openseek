// The bodies of the IPC ops the extension registers: prompt submission,
// cancel/steer for open runs, and the one-shot session-store queries.

///|
/// Submit one prompt to the conversation's serve engine, spawning or
/// replacing the process first when the config demands it. Only this
/// conversation must be idle — other sessions' engines run their own turns
/// concurrently. Returns as soon as the prompt is on the wire; the engine's
/// consumer task reports progress and completion through events, exactly as
/// the frontend already expects.
async fn start_run(
  context : @app.AppCommandExtensionContext,
  manager : EngineManager,
  engine : String,
  payload : StartPayload,
) -> StartReply {
  guard manager.pump_running else {
    raise HostError("engine host is not connected; reload the app")
  }
  let config = run_config(payload, engine)
  let key = session_key(config)
  if manager.engines.get(key) is Some(live) && live.run_open {
    raise HostError(
      "OpenSeek run \{live.latest_run} is still active in this conversation",
    )
  }
  if manager.starts_in_flight.contains(key) {
    raise HostError("an OpenSeek run is already starting for this conversation")
  }
  fn clear_start_flag() -> Unit {
    manager.starts_in_flight.remove(key)
  }

  manager.starts_in_flight.add(key)
  defer clear_start_flag()
  if config.cwd is Some(cwd) {
    ensure_run_cwd(cwd) catch {
      error if @async.is_being_cancelled() => raise error
      error =>
        raise HostError("failed to create working directory \{cwd}: \{error}")
    }
  }
  let need_spawn = if manager.engines.get(key) is Some(live) {
    live.spec_key != engine_fingerprint(config)
  } else {
    true
  }
  if need_spawn {
    let ack : @async.Queue[HostError?] = Queue(kind=Unbounded)
    manager.commands.put(SpawnEngine(config, ack))
    if ack.get() is Some(error) {
      raise error
    }
  }
  guard manager.engines.get(key) is Some(live) else {
    raise HostError("engine failed to start")
  }
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
    error if @async.is_being_cancelled() => raise error
    error => {
      // The engine died between turns: close the run and drop the handle so
      // the next prompt respawns on the same durable session.
      live.run_open = false
      if manager.engines.get(key) is Some(current) &&
        physical_equal(current, live) {
        manager.engines.remove(key)
      }
      let message = "engine write failed: \{error}"
      emit_error(context, message, run_id~)
      emit_finished(context, run_id, Failed)
      raise HostError(message)
    }
  }
  { run_id, status: "accepted", exit_code: 0 }
}

///|
/// Create the run's working directory if it is missing — a conversation's
/// derived workspace does not exist before its first prompt. `@fs.mkdir`
/// raises EEXIST even with `recursive=true`, so probe first; losing a
/// creation race to another process leaves the directory present, which is
/// just as good.
async fn ensure_run_cwd(cwd : String) -> Unit {
  if @fs.exists(cwd) {
    return
  }
  @fs.mkdir(cwd, recursive=true) catch {
    error if @async.is_being_cancelled() => raise error
    error => if @fs.exists(cwd) { () } else { raise error }
  }
}

///|
/// Cancel an open turn by asking its serve engine to interrupt it — the
/// process itself stays alive for the next prompt. The run is addressed by
/// id across all conversations; with no matching open run there is nothing
/// to cancel.
async fn cancel_run(
  manager : EngineManager,
  payload : CancelPayload,
) -> CancelReply {
  guard open_run_engine(manager, run_id?=payload.run_id) is Some(live) else {
    return { cancelled: false, run_id: None }
  }
  live.cancel_requested = true
  let command : Json = { "command": "cancel" }
  live.writer.write(command.stringify() + "\n") catch {
    error if @async.is_being_cancelled() => raise error
    // The engine just died; its reader task closes the run.
    _ => ()
  }
  { cancelled: true, run_id: Some(live.latest_run) }
}

///|
/// Inject steering input into an open turn, addressed by run id: the text
/// rides that serve engine's lossless steering queue and is folded into the
/// conversation at the turn's next step boundary, where the engine echoes it
/// back as a `steer_applied` event (or `steer_dropped` if it raced the turn's
/// end). Steering a turn that is being cancelled is refused — the steer could
/// outlive the dying turn in the engine's queue and contaminate a later
/// prompt. Blank text is refused too: the engine filters blanks without
/// emitting any settling event, which would leave a phantom acknowledgment.
async fn steer_run(
  manager : EngineManager,
  payload : SteerPayload,
) -> SteerReply {
  guard !payload.text.trim().is_empty() else {
    return { steered: false, run_id: None }
  }
  guard open_run_engine(manager, run_id?=payload.run_id) is Some(live) &&
    !live.cancel_requested else {
    return { steered: false, run_id: None }
  }
  let command : Json = { "command": "steer", "text": payload.text }
  live.writer.write(command.stringify() + "\n") catch {
    error if @async.is_being_cancelled() => raise error
    // The engine just died; its reader task closes the run. The steer
    // never reached it, so report that rather than pretend.
    _ => return { steered: false, run_id: Some(live.latest_run) }
  }
  { steered: true, run_id: Some(live.latest_run) }
}

///|
/// Run the bundled engine with `args` and return its stdout. A non-zero exit
/// is reported through stderr's content so the frontend sees the engine's own
/// message rather than a bare exit code when one is available.
async fn engine_stdout(engine : String, args : Array[String]) -> String {
  let child_stdin = prepare_engine_stdin(engine)
  let (code, stdout, stderr) = @process.collect_output(
    engine,
    args,
    inherit_env=true,
    stdin=child_stdin,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("failed to run engine: \{error}")
  }
  if code != 0 {
    let detail = (stderr.text() catch { _ => "" }).trim().to_owned()
    raise HostError(
      if detail.is_empty() {
        "engine exited with code \{code}"
      } else {
        detail
      },
    )
  }
  stdout.text() catch {
    _ => raise HostError("engine wrote malformed output")
  }
}

///|
async fn list_sessions(engine : String) -> SessionsReply {
  guard @paths.resolved_session_root(None) is Some(root) else {
    raise HostError(
      "cannot determine a session root; set OPENSEEK_SESSION_ROOT",
    )
  }
  let output = engine_stdout(engine, [
    "--session-root", root, "--session-list", "--format", "json",
  ]) catch {
    HostError(detail) => raise HostError("session list failed: " + detail)
    error => raise error
  }
  let sessions = @json.parse(output) catch {
    _ => raise HostError("engine returned a malformed session list")
  }
  { sessions, session_root: root }
}

///|
async fn load_session(
  engine : String,
  payload : LoadSessionPayload,
) -> LoadSessionReply {
  let session = payload.session.trim().to_owned()
  guard !session.is_empty() else {
    raise HostError("session id must not be empty")
  }
  guard @paths.resolved_session_root(None) is Some(root) else {
    raise HostError(
      "cannot determine a session root; set OPENSEEK_SESSION_ROOT",
    )
  }
  let output = engine_stdout(engine, [
    "--session-root", root, "--session-show", "--session", session,
  ]) catch {
    HostError(detail) => raise HostError("session load failed: " + detail)
    error => raise error
  }
  let json = @json.parse(output) catch {
    _ => raise HostError("engine returned a malformed session")
  }
  { session: json }
}
