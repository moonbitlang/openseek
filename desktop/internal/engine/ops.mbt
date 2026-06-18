// Engine operations behind the extension ops: prompt submission, cancel/steer
// for open runs, and the one-shot session-store queries.

///|
/// Submit one prompt to the conversation's serve engine, spawning or
/// replacing the process first when the config demands it. Only this
/// conversation must be idle — other sessions' engines run their own turns
/// concurrently. Returns as soon as the prompt is on the wire; the engine's
/// consumer task reports progress and completion through events, exactly as
/// the frontend already expects.
pub async fn start_run(
  sink : EventSink,
  manager : EngineManager,
  payload : StartRequest,
) -> StartReply {
  guard manager.pump_running else {
    raise EngineError("engine host is not connected; reload the app")
  }
  let config = run_config(payload, manager.engine)
  let key = session_key(config)
  if manager.engines.get(key) is Some(live) && live.run_open {
    raise EngineError(
      "OpenSeek run \{live.latest_run} is still active in this conversation",
    )
  }
  if manager.starts_in_flight.contains(key) {
    raise EngineError(
      "an OpenSeek run is already starting for this conversation",
    )
  }
  fn clear_start_flag() -> Unit {
    manager.starts_in_flight.remove(key)
  }

  manager.starts_in_flight.add(key)
  defer clear_start_flag()
  // A WSL run's Linux-path cwd lives inside the distro — the host cannot
  // create it here; `wsl --cd` rejects a missing directory at spawn time.
  if config.cwd is Some(cwd) &&
    !(config.host is Wsl(..) && @path/posix.Path::is_absolute(cwd.0)) {
    @fsx.ensure_dir(cwd) catch {
      error if @async.is_being_cancelled() => raise error
      error =>
        raise EngineError("failed to create working directory \{cwd}: \{error}")
    }
  }
  let need_spawn = if manager.engines.get(key) is Some(live) {
    live.spec_key != engine_fingerprint(config)
  } else {
    true
  }
  if need_spawn {
    let ack : @async.Queue[EngineError?] = Queue(kind=Unbounded)
    manager.commands.put(SpawnEngine(config, ack))
    if ack.get() is Some(error) {
      raise error
    }
  }
  guard manager.engines.get(key) is Some(live) else {
    raise EngineError("engine failed to start")
  }
  let run_id = manager.next_run_id
  manager.next_run_id = manager.next_run_id + 1
  live.latest_run = run_id
  live.run_open = true
  live.cancel_requested = false
  live.steer_runs.begin_run()
  emit(
    sink,
    Started({
      run_id,
      task: config.task,
      engine: config.engine,
      model: config.model,
      max_steps: config.max_steps,
      cwd: config.cwd.map(cwd => cwd.to_string()),
      session: config.session,
      session_root: config.session_root.map(root => root.to_string()),
    }),
  )
  let command = @protocol.prompt(config.task)
  live.writer.write(command.to_jsonl()) catch {
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
      emit_error(sink, message, run_id~)
      emit_finished(sink, run_id, Failed)
      raise EngineError(message)
    }
  }
  { run_id, status: "accepted", exit_code: 0 }
}

///|
/// Cancel an open turn by asking its serve engine to interrupt it — the
/// process itself stays alive for the next prompt. The run is addressed by
/// id across all conversations; with no matching open run there is nothing
/// to cancel.
pub async fn cancel_run(
  manager : EngineManager,
  payload : CancelRequest,
) -> CancelReply {
  guard open_run_engine(manager, run_id?=payload.run_id) is Some(live) else {
    return { cancelled: false, run_id: None }
  }
  live.cancel_requested = true
  let command = @protocol.cancel()
  live.writer.write(command.to_jsonl()) catch {
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
pub async fn steer_run(
  manager : EngineManager,
  payload : SteerRequest,
) -> SteerReply {
  guard !payload.text.trim().is_empty() else {
    return { steered: false, run_id: None }
  }
  guard open_run_engine(manager, run_id?=payload.run_id) is Some(live) &&
    !live.cancel_requested else {
    return { steered: false, run_id: None }
  }
  let command = @protocol.steer(payload.text)
  live.writer.write(command.to_jsonl()) catch {
    error if @async.is_being_cancelled() => raise error
    // The engine just died; its reader task closes the run. The steer
    // never reached it, so report that rather than pretend.
    _ => return { steered: false, run_id: Some(live.latest_run) }
  }
  live.steer_runs.record_sent(payload.text)
  { steered: true, run_id: Some(live.latest_run) }
}

///|
/// Run the bundled engine with `args` and return its stdout. A non-zero exit
/// is reported through stderr's content so the frontend sees the engine's own
/// message rather than a bare exit code when one is available.
async fn engine_stdout(manager : EngineManager, args : Array[String]) -> String {
  let engine = manager.engine
  let child_stdin = prepare_engine_stdin(manager.runtime_dir, engine)
  let (code, stdout, stderr) = @process.collect_output(
    engine,
    args,
    extra_env={ "OPENSEEK_DIR": "." },
    inherit_env=true,
    stdin=child_stdin,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise EngineError("failed to run engine: \{error}")
  }
  if code != 0 {
    let detail = (stderr.text() catch { _ => "" }).trim().to_owned()
    raise EngineError(
      if detail.is_empty() {
        "engine exited with code \{code}"
      } else {
        detail
      },
    )
  }
  stdout.text() catch {
    _ => raise EngineError("engine wrote malformed output")
  }
}

///|
pub async fn list_sessions(manager : EngineManager) -> SessionsReply {
  guard resolved_session_root() is Some(root) else {
    raise EngineError(
      "cannot determine a session root; set OPENSEEK_SESSION_ROOT",
    )
  }
  let root = root.to_string()
  let output = engine_stdout(manager, [
    "--session-root", root, "--session-list", "--format", "json",
  ]) catch {
    EngineError(detail) => raise EngineError("session list failed: " + detail)
    error => raise error
  }
  let sessions = @json.parse(output) catch {
    _ => raise EngineError("engine returned a malformed session list")
  }
  { sessions, session_root: root }
}

///|
pub async fn load_session(
  manager : EngineManager,
  payload : LoadSessionRequest,
) -> LoadSessionReply {
  let session = payload.session.trim().to_owned()
  guard !session.is_empty() else {
    raise EngineError("session id must not be empty")
  }
  guard resolved_session_root() is Some(root) else {
    raise EngineError(
      "cannot determine a session root; set OPENSEEK_SESSION_ROOT",
    )
  }
  let output = engine_stdout(manager, [
    "--session-root",
    root.to_string(),
    "--session-show",
    "--session",
    session,
  ]) catch {
    EngineError(detail) => raise EngineError("session load failed: " + detail)
    error => raise error
  }
  let json = @json.parse(output) catch {
    _ => raise EngineError("engine returned a malformed session")
  }
  { session: json }
}
