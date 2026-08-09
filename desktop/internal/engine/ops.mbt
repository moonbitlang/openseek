// Engine operations behind the extension ops: prompt submission, cancel/steer
// for open runs, and the one-shot session-store queries.

///|
/// Submit one prompt to the conversation's serve engine, spawning or
/// replacing the process first when the config demands it. Only this
/// conversation must be idle — other sessions' engines run their own turns
/// concurrently. Returns as soon as the prompt is on the wire; the engine's
/// consumer task reports progress and completion through events, exactly as
/// the frontend already expects. The op only rejects for failures before the
/// run's Started event goes out — once the run is public, a failure is
/// reported through its error and finished events and the op returns
/// normally (status "failed"), never both.
pub async fn start_run(
  sink : EventSink,
  manager : EngineManager,
  payload : @protocol.StartPayload,
) -> StartReply {
  manager.workspace_lifecycle_lock.acquire()
  let mut placement_locked = true
  defer (if placement_locked { manager.workspace_lifecycle_lock.release() })
  // Acquire the persistent record lease from the request's canonical key
  // before run_config probes live/workspace stores. Otherwise an unarchive
  // can move the record between that probe and the archived check, leaving a
  // stale global session_root that forks the conversation.
  let key = payload.session
    .map(session => session.trim().to_owned())
    .unwrap_or("")
  let record_guard = manager.begin_record_op(key)
  defer manager.end_record_op(key, record_guard)
  let config = run_config(manager, payload)
  ensure_session_not_archived(key)
  let sessions = manager.serving()
  let slot = slot_for(sessions, key)
  if slot.engine is Some(live) {
    match live.phase {
      Running(..) =>
        raise EngineError(
          "an OpenSeek run is still active in this conversation",
        )
      // A prompt accepted now would queue behind the compaction, where a
      // Stop (which cancels only the compaction) could not reach it.
      Compacting =>
        raise EngineError(
          "this conversation is compacting; wait for it to finish",
        )
      Idle => ()
    }
  }
  let claim = slot.claim(sessions, key, StartPending)
  defer claim.release(manager)
  // The visible slot claim now bridges every suspension through the prompt
  // write. Detach will refuse it, so unrelated sessions can leave this short
  // global placement critical section and continue concurrently.
  placement_locked = false
  manager.workspace_lifecycle_lock.release()
  ensure_run_cwd(config)
  let need_spawn = if slot.engine is Some(live) {
    !live.accepts_commands || live.spec_key != engine_fingerprint(config)
  } else {
    true
  }
  if need_spawn {
    request_spawn(manager, claim, config)
  }
  claim.require_current(manager)
  guard slot.engine is Some(live) else {
    raise EngineError("engine failed to start")
  }
  // The cwd/spawn waits above are suspension points: a compaction accepted
  // during one of them holds the engine now, and the Running transition
  // below would silently clobber it. Re-check on the engine this run will
  // actually use.
  if live.phase is Compacting {
    raise EngineError("this conversation is compacting; wait for it to finish")
  }
  let run_id = mint_run_id()
  let command = @protocol.prompt(config.task)
  let submission_id = normalize_submission_id(payload.submission_id)
  let mut started_emitted = false
  // Publish the run and write its prompt while holding the engine's one
  // command lock. A remote peer may steer as soon as it sees Started; making
  // the phase visible only after this task owns the lock guarantees that steer
  // (and cancel/compact) lands after the complete prompt on stdin, while the
  // Started notification still precedes every event the prompt can produce.
  live.with_command_lock(() => {
    claim.require_current(manager)
    guard live.accepts_commands &&
      slot.engine is Some(current) &&
      physical_equal(current, live) else {
      raise EngineError("engine changed before the prompt was submitted")
    }
    live.latest_run = Some(run_id)
    live.phase = Running(cancel_requested=false, compact_queued=false)
    live.steer_runs.begin_run()
    started_emitted = true
    let cwd = match config.cwd {
      Some(cwd) => {
        guard cwd.to_absolute() is Some(cwd) else {
          raise EngineError("run working directory is not absolute")
        }
        Some(cwd.resource_path())
      }
      None => None
    }
    emit(
      sink,
      Started({
        run_id,
        task: Some(config.task),
        submission_id,
        engine: Some(config.engine),
        model: Some(config.model),
        max_steps: Some(config.max_steps),
        cwd,
        session: config.session,
        session_root: config.session_root.map(root => root.resource_path()),
      }),
    )
    live.writer.write(command.to_jsonl())
  }) catch {
    error if @async.is_being_cancelled() => {
      if started_emitted {
        live.accepts_commands = false
        retire_failed_command(
          manager, live, "request cancelled while writing to the engine",
        )
      }
      raise error
    }
    error if !started_emitted => raise error
    error => {
      // Started is already public, so settle it through the same bounded,
      // cancellation-shielded cleanup as an interrupted command. Marking the
      // writer unusable before that cleanup prevents a second cancellation or
      // close timeout from exposing a partial stream to a same-config start.
      live.accepts_commands = false
      retire_failed_command(manager, live, "engine write failed: \{error}")
      return { run_id, status: "failed", exit_code: 1 }
    }
  }
  { run_id, status: "accepted", exit_code: 0 }
}

///|
/// A fresh run id: 128 bits of OS randomness, never intentionally reused
/// across host lifetimes. A remote page that reconnects across a host restart
/// may still hold pre-restart runs, so a counter reset to 1 would hand their
/// ids to new runs and cross-wire two conversations' event streams.
fn mint_run_id() -> String raise EngineError {
  guard @entropy.random_hex(16) is Some(hex) else {
    raise EngineError("cannot mint a run id: OS entropy unavailable")
  }
  "r\{hex}"
}

///|
/// Cancel an open turn by asking its serve engine to interrupt it — the
/// process itself stays alive for the next prompt. The run is addressed by
/// id across all conversations; with no matching open run there is nothing
/// to cancel.
pub async fn cancel_run(
  manager : EngineManager,
  payload : @protocol.CancelPayload,
) -> CancelReply {
  guard open_run_engine(manager, run_id?=payload.run_id) is Some(live) else {
    return { cancelled: false, run_id: None }
  }
  let mut command_started = false
  let cancelled = live.with_command_lock(() => {
    // The run can finish while this request waits behind a prompt or steer.
    // Revalidate under the command lock so a late cancel is not written into
    // the next idle boundary.
    guard live.is_current(manager) else { return false }
    guard live.phase is Running(compact_queued~, ..) else { return false }
    if payload.run_id is Some(expected) && live.latest_run != Some(expected) {
      return false
    }
    // A compaction queued behind the dying turn survives the cancel: the
    // engine's pending queue keeps it (cancel only aborts the active turn), so
    // the flag must ride along or the terminal event would idle past it.
    live.phase = Running(cancel_requested=true, compact_queued~)
    command_started = true
    live.writer.write(@protocol.cancel().to_jsonl())
    true
  }) catch {
    error if @async.is_being_cancelled() => {
      if command_started {
        live.accepts_commands = false
        retire_failed_command(
          manager, live, "request cancelled while writing cancellation to the engine",
        )
      }
      raise error
    }
    error => {
      if command_started {
        live.accepts_commands = false
        retire_failed_command(
          manager,
          live,
          "failed to write cancellation to the engine: \{error}",
        )
      }
      raise error
    }
  }
  if !cancelled {
    return { cancelled: false, run_id: None }
  }
  { cancelled: true, run_id: live.latest_run }
}

///|
/// Create the run's working directory so the spawn cannot fail on a missing
/// cwd.
async fn ensure_run_cwd(config : RunConfig) -> Unit {
  if config.cwd is Some(cwd) {
    @fsx.ensure_dir(cwd) catch {
      error if @async.is_being_cancelled() => raise error
      error =>
        raise EngineError("failed to create working directory \{cwd}: \{error}")
    }
  }
}

///|
/// Ask the pump to spawn (or replace) this conversation's serve engine and
/// wait for its ack; the spawn failure, if any, is re-raised here.
async fn request_spawn(
  manager : EngineManager,
  claim : PendingClaim,
  config : RunConfig,
) -> Unit {
  let ack : @async.Queue[EngineError?] = Queue(kind=Blocking(1))
  @async.protect_from_cancel(() => {
    claim.require_current(manager)
    // The bounded actor mailbox may backpressure here. The identity-bearing
    // claim remains visible while it waits; a restarted generation rejects
    // the stale epoch, and permanent actor shutdown closes the queue.
    manager.commands.put(SpawnEngine(claim, config, ack)) catch {
      _ => raise EngineError("engine host stopped before spawn was accepted")
    }
    if ack.get() is Some(error) {
      raise error
    }
  })
}

///|
/// Ask a conversation's serve engine to compact its history: summarize the
/// turns so far into a checkpoint and drop the raw events behind it, shrinking
/// the context the next prompt carries. Addressed by session id, not run id —
/// compaction is normally requested while the engine sits idle between turns.
/// A conversation with no live engine (resumed after a restart, or whose
/// process died between turns) gets one spawned on the durable session first,
/// exactly as the next prompt would. The engine reports the real progress
/// (started/finished/failed) through its event stream; this op only confirms
/// the command reached a live engine.
pub async fn compact_run(
  manager : EngineManager,
  payload : @protocol.CompactPayload,
) -> CompactReply {
  manager.workspace_lifecycle_lock.acquire()
  let mut placement_locked = true
  defer (if placement_locked { manager.workspace_lifecycle_lock.release() })
  let session = payload.session.trim().to_owned()
  let record_guard = manager.begin_record_op(session)
  defer manager.end_record_op(session, record_guard)
  ensure_session_not_archived(session)
  let sessions = manager.serving()
  let slot = slot_for(sessions, session)
  // Claim before anything else — even with a live engine. A start between
  // its validation and the prompt hitting the wire has claimed the slot but
  // not yet flipped the engine to Running; a compact accepted in that window
  // would mark the engine Compacting under the starting prompt and preempt
  // it at start_run's phase re-check.
  let claim = slot.claim(sessions, session, CompactPending)
  defer claim.release(manager)
  placement_locked = false
  manager.workspace_lifecycle_lock.release()
  let live = if slot.engine is Some(live) && live.accepts_commands {
    live
  } else {
    let config = compact_config(manager, payload)
    ensure_run_cwd(config)
    request_spawn(manager, claim, config)
    claim.require_current(manager)
    guard slot.engine is Some(live) else {
      raise EngineError("engine failed to start")
    }
    live
  }
  match live.phase {
    Compacting => raise EngineError("this conversation is already compacting")
    Running(compact_queued=true, ..) =>
      raise EngineError(
        "a compaction is already queued behind the running turn",
      )
    Running(compact_queued=false, ..) | Idle => ()
  }
  let command = @protocol.compact()
  let mut command_started = false
  live.with_command_lock(() => {
    claim.require_current(manager)
    guard live.accepts_commands &&
      slot.engine is Some(current) &&
      physical_equal(current, live) else {
      raise EngineError("engine changed before compaction was submitted")
    }
    match live.phase {
      Compacting => raise EngineError("this conversation is already compacting")
      Running(compact_queued=true, ..) =>
        raise EngineError(
          "a compaction is already queued behind the running turn",
        )
      // Sent mid-turn, the command queues behind the open run; the flag makes
      // the turn's terminal event land in Compacting so nothing slips into
      // the gap before the engine's own compaction_started. Set before the
      // potentially suspending write so the consumer already sees it.
      Running(cancel_requested~, compact_queued=false) =>
        live.phase = Running(cancel_requested~, compact_queued=true)
      // Likewise, enter Compacting before the write so a short compaction's
      // terminal event cannot be overwritten by this request resuming later.
      Idle => live.phase = Compacting
    }
    command_started = true
    live.writer.write(command.to_jsonl())
  }) catch {
    error if @async.is_being_cancelled() => {
      if command_started {
        live.accepts_commands = false
        retire_failed_command(
          manager, live, "request cancelled while writing the compaction command",
        )
      }
      raise error
    }
    error if !command_started => raise error
    error => {
      live.accepts_commands = false
      retire_failed_command(
        manager,
        live,
        "failed to write the compaction command: \{error}",
      )
      raise EngineError("failed to request compaction: \{error}")
    }
  }
  { compacting: true }
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
  payload : @protocol.SteerPayload,
) -> SteerReply {
  guard !payload.text.trim().is_empty() else {
    return { steered: false, run_id: None }
  }
  guard open_run_engine(manager, run_id?=payload.run_id) is Some(live) &&
    live.phase is Running(cancel_requested=false, ..) else {
    return { steered: false, run_id: None }
  }
  let command = @protocol.steer(payload.text)
  let submission_id = normalize_submission_id(payload.submission_id)
  let mut entry : TrackedSteer? = None
  let steered = live.with_command_lock(() => {
    // Concurrent steer requests wait here in their actual stdin order. The
    // run may finish (or be cancelled) while this one waits, so validate again
    // before recording an entry that would otherwise never receive a receipt.
    guard live.is_current(manager) else { return false }
    guard live.phase is Running(cancel_requested=false, ..) else {
      return false
    }
    if payload.run_id is Some(expected) && live.latest_run != Some(expected) {
      return false
    }
    // Record immediately before this locked write: if the terminal event is
    // processed while write suspends, record_terminal can still pin the entry
    // to the finishing run. Identity, not text, drives rollback so equal
    // steering strings retain distinct submission ids.
    let sent = live.steer_runs.record_sent(payload.text, submission_id)
    entry = Some(sent)
    live.writer.write(command.to_jsonl())
    true
  }) catch {
    error if @async.is_being_cancelled() => {
      if entry is Some(_) {
        live.accepts_commands = false
        retire_failed_command(
          manager, live, "request cancelled while writing steering to the engine",
        )
      }
      raise error
    }
    error => {
      let run_id = live.latest_run
      if entry is Some(_) {
        live.accepts_commands = false
        retire_failed_command(
          manager,
          live,
          "failed to write steering to the engine: \{error}",
        )
        // A write error after record_sent is not a definitive refusal: a
        // complete frame may already be in the pipe and can still produce a
        // durable User plus steer_applied before EOF. Report provisional
        // acceptance so the client keeps exact-id ownership; the trailing
        // receipt or Finished/durable recovery settles it without restoring a
        // duplicate draft.
        return { steered: true, run_id }
      }
      return { steered: false, run_id }
    }
  }
  if !steered {
    return { steered: false, run_id: None }
  }
  { steered: true, run_id: live.latest_run }
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
/// A `sessions show` must never pin the follower actor. Unlike the generic
/// one-shot helper, this path gives the child a hard cancellation handler;
/// timing out the structured task group therefore kills and reaps the
/// command before returning, so the next scan can spawn normally.
const SessionShowTimeoutMs = 10000

///|
async fn session_show_output(
  manager : EngineManager,
  session : String,
  root : @pathx.Absolute,
) -> (Int, String, String) {
  let engine = manager.engine
  let child_stdin = prepare_engine_stdin(manager.runtime_dir, engine)
  let (stdout_reader, child_stdout) = @process.read_from_process()
  let (stderr_reader, child_stderr) = @process.read_from_process()
  @async.with_task_group(group => {
    let process = @process.spawn(
      group,
      engine,
      ["sessions", "show", session, "--session-root", root.to_string()],
      extra_env={ "OPENSEEK_DIR": "." },
      inherit_env=true,
      stdin=child_stdin,
      stdout=child_stdout,
      stderr=child_stderr,
      cancel_handler=@process.hard_cancel(),
      no_wait=false,
    )
    let stdout = group.spawn(() => {
      defer stdout_reader.close()
      stdout_reader.read_all().text()
    })
    let stderr = group.spawn(() => {
      defer stderr_reader.close()
      stderr_reader.read_all().text()
    })
    (process.wait(), stdout.wait(), stderr.wait())
  })
}

///|
async fn session_show_stdout(
  manager : EngineManager,
  session : String,
  root : @pathx.Absolute,
  timeout_ms? : Int = SessionShowTimeoutMs,
) -> String {
  let (code, stdout, stderr) = @async.with_timeout(timeout_ms, () => {
    session_show_output(manager, session, root)
  }) catch {
    error if @async.is_being_cancelled() => raise error
    @async.TimeoutError =>
      raise EngineError("session read timed out after \{timeout_ms}ms")
    error => raise EngineError("failed to run engine: \{error}")
  }
  if code != 0 {
    let detail = stderr.trim().to_owned()
    raise EngineError(
      if detail.is_empty() {
        "engine exited with code \{code}"
      } else {
        detail
      },
    )
  }
  stdout
}

///|
/// The sidebar's conversations, one group per session store: the global root
/// first (scratch conversations), then each registered workspace's in-project
/// store, in registration order. A group whose listing fails reports the
/// failure in its `error` field rather than failing the whole reply.
pub async fn list_sessions(manager : EngineManager) -> SessionsReply {
  guard resolved_session_root() is Some(root) else {
    raise EngineError(
      "cannot determine a session root; set OPENSEEK_SESSION_ROOT",
    )
  }
  let groups : Array[SessionGroup] = [session_group(manager, None, root)]
  for path in registered_workspaces() {
    groups.push(
      session_group(manager, Some(path), workspace_session_root(path)),
    )
  }
  { groups, }
}

///|
async fn session_group(
  manager : EngineManager,
  workspace : @pathx.Absolute?,
  root : @pathx.Absolute,
) -> SessionGroup {
  let (workspace, name) = match workspace {
    Some(workspace) =>
      (workspace.resource_path(), workspace.to_path().basename().to_owned())
    None => ("", "")
  }
  let native_root = root.to_string()
  let root = root.resource_path()
  fn failed(error : String) -> SessionGroup {
    { workspace, name, session_root: root, sessions: [], error }
  }

  let output = engine_stdout(manager, [
    "sessions", "list", "--session-root", native_root, "--format", "json",
  ]) catch {
    error if @async.is_being_cancelled() => raise error
    EngineError(detail) => return failed("session list failed: \{detail}")
    error => return failed("session list failed: \{error}")
  }
  let sessions_json = @json.parse(output) catch {
    _ => return failed("engine returned a malformed session list")
  }
  guard sessions_json is Array(_) else {
    return failed("engine returned a malformed session list")
  }
  let sessions = @protocol.SessionListEntry::array_from_wire(sessions_json)
  { workspace, name, session_root: root, sessions, error: "" }
}

///|
pub async fn load_session(
  manager : EngineManager,
  payload : @protocol.LoadSessionPayload,
) -> LoadSessionReply {
  let session = payload.session.trim().to_owned()
  guard !session.is_empty() else {
    raise EngineError("session id must not be empty")
  }
  // The reader lease is manager-global rather than per pump generation: a
  // sessions-show started under generation A remains visible to generation
  // B's archive after a host restart.
  let record_guard = manager.begin_record_read(session)
  defer manager.end_record_read(session, record_guard)
  // The client's workspace hint says which registered store to read. A
  // detached workspace is rejected instead of silently probing the global
  // store, which could return a different history for the same session id.
  let root = if payload.workspace is Some(hint) && !hint.trim().is_empty() {
    guard @pathx.Absolute::from_uri_path(hint) is Some(absolute) &&
      registered_workspace(absolute) is Some(workspace) else {
      raise EngineError("\{hint} is not a registered workspace")
    }
    Some(workspace_session_root(workspace))
  } else {
    session_store_root(session)
  }
  guard root is Some(root) else {
    raise EngineError(
      "cannot determine a session root; set OPENSEEK_SESSION_ROOT",
    )
  }
  // A followed session (a live engine is writing to it) is read through its
  // follower actor: the snapshot then comes out of the same serial loop
  // that broadcasts `session.event` commits, so the two can never disagree
  // about what has been committed. The reply's watermark tells the client
  // which commits its snapshot already contains.
  if follower_snapshot(manager, session, root) is Some(document) {
    return {
      session: document,
      watermark: Some(session_max_sequence(document)),
    }
  }
  // Name the missing-record states before spending an engine read that can
  // only fail with a raw file error: a stale client asks for conversations
  // whose store just detached (or whose record moved to an archived twin),
  // and the answer should say that, not ENOENT.
  if !@fsx.is_dir(root.join("sessions").join(session).to_path()) {
    if archived_record_root(session) is Some(_) {
      raise EngineError("this conversation is archived; unarchive it first")
    }
    raise EngineError(
      "no durable record for this conversation in the global store or any attached workspace",
    )
  }
  let output = session_show_stdout(manager, session, root) catch {
    EngineError(detail) => raise EngineError("session load failed: " + detail)
    error => raise error
  }
  let json = @json.parse(output) catch {
    _ => raise EngineError("engine returned a malformed session")
  }
  let document : @protocol.SessionDocument = @json.from_json(json) catch {
    _ => raise EngineError("engine returned a malformed session")
  }
  { session: document, watermark: Some(session_max_sequence(document)) }
}

///|
/// Read a followed session's snapshot through its actor; `None` when the
/// session has no live follower (idle sessions read the store directly).
async fn follower_snapshot(
  manager : EngineManager,
  session : String,
  root : @pathx.Absolute,
) -> @protocol.SessionDocument? {
  for ;; {
    guard manager.followers.get(session) is Some(follower) else { return None }
    // Session ids can exist in several stores. Never return a snapshot from
    // a follower attached to a different root than the requested record.
    if follower.root.to_string() != root.to_string() {
      return None
    }
    if follower.stopping {
      // Do not bypass an in-flight final scan with a direct `sessions show`.
      // The hard scan timeout bounds this wait; success retires the actor,
      // failure reactivates it for the load to retry through the actor.
      @async.sleep(10)
      continue
    }
    match request_follower_load(follower) {
      LoadOk(document) => return Some(document)
      LoadStopped => continue
      LoadFailed(detail) => raise EngineError("session load failed: " + detail)
    }
  }
}

///|
/// A host-native absolute path at the protocol boundary. Resource URIs use
/// their authority for the device, so UNC paths have no reversible encoding
/// and are rejected explicitly instead of being published under a new host.
fn @pathx.Absolute::resource_path(
  self : @pathx.Absolute,
) -> String raise EngineError {
  guard self.to_uri_path() is Some(path) else {
    raise EngineError("UNC paths are not supported by frontend resources")
  }
  path
}

///|
pub async fn list_workspaces() -> WorkspacesReply {
  { workspaces: registered_workspaces().map(path => path.resource_path()) }
}

///|
pub async fn attach_workspace(
  path : String,
  on_committed : (Array[String]) -> Unit,
) -> WorkspacesReply {
  guard @pathx.Absolute::from_uri_path(path) is Some(absolute) else {
    raise EngineError("workspace is not a supported absolute resource path")
  }
  let paths = add_workspace(absolute.0, paths => {
    on_committed(paths.map(path => path.resource_path()))
  })
  { workspaces: paths.map(path => path.resource_path()) }
}

///|
pub async fn detach_workspace(
  manager : EngineManager,
  path : String,
  on_committed : (Array[String]) -> Unit,
) -> WorkspacesReply {
  guard @pathx.Absolute::from_uri_path(path) is Some(absolute) else {
    raise EngineError("workspace is not a supported absolute resource path")
  }
  manager.workspace_lifecycle_lock.acquire()
  defer manager.workspace_lifecycle_lock.release()
  let workspace = expanded_workspace_path(absolute.0)
  manager.close_engines_for_workspace(workspace)
  let paths = remove_workspace(absolute.0, paths => {
    on_committed(paths.map(path => path.resource_path()))
  })
  { workspaces: paths.map(path => path.resource_path()) }
}

///|
#cfg(not(platform="windows"))
async test "one-shot session engine overrides ambient OPENSEEK_DIR" {
  let previous = @sys.get_env_var("OPENSEEK_DIR")
  @sys.set_env_var("OPENSEEK_DIR", "/missing/openseek-dir")
  let dir = @fs.tmpdir(prefix="openseek-session-env-")
  let engine = "\{dir}/engine.sh"
  @fs.write_file(
    engine,
    "#!/bin/sh\nprintf '%s' \"$OPENSEEK_DIR\"\n",
    create_mode=CreateOrTruncate,
  )
  let chmod = @process.run("chmod", ["+x", engine])
  assert_eq(chmod, 0)
  let manager = new_engine_manager(engine)
  let output = engine_stdout(manager, []) catch {
    error => {
      restore_openseek_dir(previous)
      @fs.rmdir(dir, recursive=true) catch {
        _ => ()
      }
      raise error
    }
  }
  restore_openseek_dir(previous)
  @fs.rmdir(dir, recursive=true)
  assert_eq(output, ".")
}

///|
#cfg(not(platform="windows"))
fn restore_openseek_dir(previous : String?) -> Unit {
  if previous is Some(value) {
    @sys.set_env_var("OPENSEEK_DIR", value)
  } else {
    @sys.unset_env_var("OPENSEEK_DIR")
  }
}

///|
#cfg(not(platform="windows"))
fn has_finished_run(events : Array[EngineEvent], run_id : String) -> Bool {
  for event in events {
    if event is Finished(payload) && payload.run_id == run_id {
      return true
    }
  }
  false
}

///|
#cfg(not(platform="windows"))
async test "start echoes the client submission id in Started" {
  let dir = @fs.tmpdir(prefix="openseek-start-submission-")
  let root : @pathx.Path = Path(dir)
  let engine = root.join("bin/engine.sh")
  let seed = root.join("bin/toolchains/moonbit/macos-arm64")
  let runtime = root.join("runtime")
  prepare_fake_moonbit_seed(seed, version="0.10.0-test")
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nwhile IFS= read -r line; do :; done\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let actor = new_engine_actor(engine.to_string(), runtime_dir=runtime)
  let manager = actor.manager()
  ignore(
    update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://example.invalid/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: None,
    }),
  )
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) { () })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    ignore(
      start_run(sink, manager, {
        task: "hello",
        submission_id: Some("submission-start"),
        model: None,
        max_steps: None,
        session: None,
        workspace: None,
      }),
    )
    let mut echoed : String? = None
    for event in emitted {
      if event is Started(payload) {
        echoed = payload.submission_id
      }
    }
    assert_eq(echoed, Some("submission-start"))
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "setup failure retires the writer before an immediate next start" {
  let dir = @fs.tmpdir(prefix="openseek-setup-failed-seam-")
  let root : @pathx.Path = Path(dir)
  let engine = root.join("bin/engine.sh")
  let seed = root.join("bin/toolchains/moonbit/macos-arm64")
  let runtime = root.join("runtime")
  let count = root.join("count")
  let old_done = root.join("old-done")
  let overlapped = root.join("overlapped")
  prepare_fake_moonbit_seed(seed, version="0.10.0-test")
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nn=0\nif [ -f '\{count}' ]; then n=$(cat '\{count}'); fi\nn=$((n + 1))\nprintf '%s' \"$n\" > '\{count}'\nif [ \"$n\" -eq 1 ]; then\n  IFS= read -r line || exit 0\n  printf '%s\\n' '{\"event\":\"agent_setup_failed\",\"error\":\"boom\"}'\n  sleep 1\n  printf '%s\\n' '{\"event\":\"turn_failed\",\"error\":\"append failed\"}'\n  printf '' > '\{old_done}'\n  exit 0\nfi\nif [ ! -f '\{old_done}' ]; then printf '' > '\{overlapped}'; fi\nwhile IFS= read -r line; do\n  printf '%s\\n' '{\"event\":\"agent_finished\",\"answer\":\"ok\"}'\ndone\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let actor = new_engine_actor(engine.to_string(), runtime_dir=runtime)
  let manager = actor.manager()
  ignore(
    update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://example.invalid/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: None,
    }),
  )
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) { () })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    let first = start_run(sink, manager, {
      task: "first",
      submission_id: None,
      model: None,
      max_steps: None,
      session: None,
      workspace: None,
    })
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while !has_finished_run(emitted, first.run_id) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    let cancelled = cancel_run(manager, { run_id: Some(first.run_id) })
    assert_false(cancelled.cancelled)
    let second = start_run(sink, manager, {
      task: "second",
      submission_id: None,
      model: None,
      max_steps: None,
      session: None,
      workspace: None,
    })
    assert_eq(second.status, "accepted")
    assert_true(@fsx.exists(old_done))
    assert_false(@fsx.exists(overlapped))
    assert_true(
      @async.with_timeout_opt(1000, () => {
        while @fs.read_file(count.to_string()).text() != "2" {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    assert_eq(@fs.read_file(count.to_string()).text(), "2")
    let mut first_finishes = 0
    for event in emitted {
      if event is Finished(payload) && payload.run_id == first.run_id {
        first_finishes = first_finishes + 1
      }
    }
    assert_eq(first_finishes, 1)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "cancelling a backpressured prompt retires its partial writer" {
  let dir = @fs.tmpdir(prefix="openseek-backpressured-command-")
  let root : @pathx.Path = Path(dir)
  let engine = root.join("bin/engine.sh")
  let seed = root.join("bin/toolchains/moonbit/macos-arm64")
  let runtime = root.join("runtime")
  prepare_fake_moonbit_seed(seed, version="0.10.0-test")
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  // Deliberately never read stdin: a prompt much larger than the pipe buffer
  // suspends inside WriteToProcess after Started is already public.
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nsleep 30\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let actor = new_engine_actor(engine.to_string(), runtime_dir=runtime)
  let manager = actor.manager()
  ignore(
    update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://example.invalid/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: None,
    }),
  )
  let emitted : Array[EngineEvent] = []
  let started : Ref[String?] = Ref(None)
  let sink = EventSink(fn(event) {
    if event is Started(payload) {
      started.val = Some(payload.run_id)
    }
    emitted.push(event)
  })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) { () })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    let request = group.spawn(() => {
      ignore(
        start_run(sink, manager, {
          task: "x".repeat(4_000_000),
          submission_id: None,
          model: None,
          max_steps: None,
          session: None,
          workspace: None,
        }),
      )
    })
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while started.val is None {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    request.cancel()
    let cancelled = try {
      request.wait()
      false
    } catch {
      error if @async.is_cancellation_error(error) => true
      _ => false
    }
    assert_true(cancelled)
    guard started.val is Some(run_id) else { fail("missing Started") }
    let mut finishes = 0
    for event in emitted {
      if event is Finished(payload) && payload.run_id == run_id {
        finishes = finishes + 1
      }
    }
    assert_eq(finishes, 1)
    assert_true(open_run_engine(manager, run_id~) is None)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "named session retries after its first prompt creates no record" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let dir = @fs.tmpdir(prefix="openseek-first-prompt-retry-")
  let root : @pathx.Path = Path(dir)
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer (if previous_home is Some(home) {
    @sys.set_env_var("HOME", home)
  } else {
    @sys.unset_env_var("HOME")
  })
  let engine = root.join("bin/engine.sh")
  let seed = root.join("bin/toolchains/moonbit/macos-arm64")
  let runtime = root.join("runtime")
  let store = root.join("store")
  let previous_session_root = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", store.to_string())
  defer restore_session_root_env(previous_session_root)
  let count = root.join("serve-count")
  let first_ready = root.join("first-ready")
  let session = "s-" + mint_run_id()
  let workspace = session_workspace_dir(session)
  prepare_fake_moonbit_seed(seed, version="0.10.0-test")
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  // `sessions show` reports the missing first-turn record. The first serve
  // process creates only the session directory and never reads stdin, so a
  // large prompt is cancelled while its JSONL frame is still partial. The
  // successor accepts a normal prompt and finishes it.
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then\n  printf '%s\\n' 'session record does not exist' >&2\n  exit 7\nfi\nn=0\nif [ -f '\{count}' ]; then n=$(cat '\{count}'); fi\nn=$((n + 1))\nprintf '%s' \"$n\" > '\{count}'\nif [ \"$n\" -eq 1 ]; then\n  mkdir -p '\{store}/sessions/\{session}'\n  printf '' > '\{first_ready}'\n  exec sleep 30\nfi\nwhile IFS= read -r line; do\n  printf '%s\\n' '{\"event\":\"agent_finished\",\"answer\":\"ok\"}'\ndone\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let actor = new_engine_actor(engine.to_string(), runtime_dir=runtime)
  let manager = actor.manager()
  ignore(
    update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://example.invalid/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: None,
    }),
  )
  let emitted : Array[EngineEvent] = []
  let started : Ref[String?] = Ref(None)
  let sink = EventSink(fn(event) {
    if event is Started(payload) {
      started.val = Some(payload.run_id)
    }
    emitted.push(event)
  })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) { () })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    let first_request = group.spawn(() => {
      ignore(
        start_run(sink, manager, {
          task: "x".repeat(4_000_000),
          submission_id: None,
          model: None,
          max_steps: None,
          session: Some(session),
          workspace: None,
        }),
      )
    })
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while started.val is None || !@fsx.exists(first_ready) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    assert_true(@fsx.is_dir(store.join("sessions").join(session)))
    assert_false(
      @fsx.exists(Path(session_store_file(store.resolve(), session))),
    )
    first_request.cancel()
    let cancelled = try {
      first_request.wait()
      false
    } catch {
      error if @async.is_cancellation_error(error) => true
      _ => false
    }
    assert_true(cancelled)
    guard started.val is Some(first_run_id) else {
      fail("missing first Started")
    }
    assert_true(has_finished_run(emitted, first_run_id))
    assert_true(manager.followers.get(session) is None)

    let second = start_run(sink, manager, {
      task: "retry",
      submission_id: None,
      model: None,
      max_steps: None,
      session: Some(session),
      workspace: None,
    })
    assert_eq(second.status, "accepted")
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while !has_finished_run(emitted, second.run_id) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    assert_eq(@fs.read_file(count.to_string()).text(), "2")
    group.return_immediately(())
  })
  if workspace is Some(workspace) {
    @fs.rmdir(workspace.to_string(), recursive=true) catch {
      _ => ()
    }
  }
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "timed out sessions show is killed and the next read can run" {
  let dir = @fs.tmpdir(prefix="openseek-session-timeout-")
  let engine = dir + "/engine.sh"
  let fast = dir + "/fast"
  @fs.write_file(
    engine,
    "#!/bin/sh\nif [ ! -f '\{fast}' ]; then while :; do :; done; fi\nprintf '%s' '{\"events\":[]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let root : @pathx.Absolute = @pathx.Path(dir + "/root").resolve()
  let detail = try {
    ignore(session_show_stdout(manager, "s-timeout", root, timeout_ms=50))
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(detail.contains("timed out"))
  @fs.write_file(fast, "", create_mode=CreateOrTruncate)
  assert_eq(
    session_show_stdout(manager, "s-timeout", root, timeout_ms=1000),
    "{\"events\":[]}",
  )
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "session load preserves a future item without hiding known events" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let dir = @fs.tmpdir(prefix="openseek-load-future-item-")
  let engine = dir + "/engine.sh"
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", dir)
  defer restore_session_root_env(previous)
  @fsx.ensure_dir(Path(dir + "/sessions/s-future"))
  @fs.write_file(
    engine,
    "#!/bin/sh\nprintf '%s' '{\"events\":[{\"sequence\":1,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"question\"}}},{\"sequence\":2,\"item\":{\"kind\":\"future_item\",\"payload\":{\"value\":42}}},{\"sequence\":3,\"item\":{\"kind\":\"assistant\",\"payload\":{\"content\":\"answer\"}}}]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let reply = load_session(new_engine_manager(engine), {
    session: "s-future",
    workspace: None,
  })
  guard reply.session.events is Some(events) else {
    fail("expected session events")
  }
  assert_eq(events.length(), 3)
  assert_true(events[1].item is Unknown(_))
  assert_eq(reply.watermark, Some(3))
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "load rejects a detached workspace hint instead of probing global" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let dir = @fs.tmpdir(prefix="openseek-load-detached-")
  let marker = dir + "/engine-ran"
  let engine = dir + "/engine.sh"
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", dir)
  defer restore_session_root_env(previous)
  @fsx.ensure_dir(Path(dir + "/sessions/s-detached"))
  @fs.write_file(
    engine,
    "#!/bin/sh\nprintf '' > '\{marker}'\nprintf '%s' '{\"events\":[]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let detail = try {
    ignore(
      load_session(manager, {
        session: "s-detached",
        workspace: Some(dir + "/detached-workspace"),
      }),
    )
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(detail.contains("not a registered workspace"))
  assert_false(@fsx.exists(Path(marker)))
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "workspace detach refuses a running conversation without hiding it" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  // The registry canonicalizes workspace paths, so build the fixture from
  // the tmpdir's physical spelling (`/tmp` is a symlink on macOS).
  let root : @pathx.Path = Path(
    @fs.realpath(@fs.tmpdir(prefix="openseek-detach-running-")),
  )
  let global_store = root.join("global")
  let workspace = root.join("workspace")
  let engine = root.join("bin/engine.sh")
  let runtime = root.join("runtime")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", global_store.to_string())
  defer restore_session_root_env(previous)
  @fsx.ensure_dir(workspace)
  prepare_fake_moonbit_seed(
    root.join("bin/toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then printf '%s' '{\"events\":[]}' ; exit 0; fi\nwhile IFS= read -r line; do sleep 30; done\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let actor = new_engine_actor(engine.to_string(), runtime_dir=runtime)
  let manager = actor.manager()
  ignore(
    update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://example.invalid/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: None,
    }),
  )
  let sink = EventSink(fn(_) { () })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) { () })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    ignore(attach_workspace(workspace.to_string(), fn(_) { () }))
    let reply = start_run(sink, manager, {
      task: "keep running",
      submission_id: None,
      model: None,
      max_steps: None,
      session: Some("s-detach-running"),
      workspace: Some(workspace.to_string()),
    })
    assert_eq(reply.status, "accepted")
    let committed : Ref[Bool] = Ref(false)
    let detail = try {
      ignore(
        detach_workspace(manager, workspace.to_string(), fn(_) {
          committed.val = true
        }),
      )
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
    assert_true(detail.contains("still running"))
    assert_false(committed.val)
    guard workspace.to_absolute() is Some(workspace_path) else {
      fail("expected an absolute workspace fixture")
    }
    assert_true(registered_workspaces().contains(workspace_path))
    group.return_immediately(())
  })
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "workspace detach drains an idle writer and its follower first" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  // The registry canonicalizes workspace paths, so build the fixture from
  // the tmpdir's physical spelling (`/tmp` is a symlink on macOS).
  let root : @pathx.Path = Path(
    @fs.realpath(@fs.tmpdir(prefix="openseek-detach-idle-")),
  )
  let global_store = root.join("global")
  let workspace = root.join("workspace")
  let engine = root.join("bin/engine.sh")
  let runtime = root.join("runtime")
  let exited = root.join("writer-exited")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", global_store.to_string())
  defer restore_session_root_env(previous)
  @fsx.ensure_dir(workspace)
  prepare_fake_moonbit_seed(
    root.join("bin/toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then printf '%s' '{\"events\":[]}' ; exit 0; fi\nwhile IFS= read -r line; do printf '%s\\n' '{\"event\":\"agent_finished\",\"answer\":\"ok\"}'; done\nprintf '' > '\{exited}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let actor = new_engine_actor(engine.to_string(), runtime_dir=runtime)
  let manager = actor.manager()
  ignore(
    update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://example.invalid/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: None,
    }),
  )
  let events : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { events.push(event) })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) { () })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    ignore(attach_workspace(workspace.to_string(), fn(_) { () }))
    let reply = start_run(sink, manager, {
      task: "finish",
      submission_id: None,
      model: None,
      max_steps: None,
      session: Some("s-detach-idle"),
      workspace: Some(workspace.to_string()),
    })
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while !has_finished_run(events, reply.run_id) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    let committed : Ref[Bool] = Ref(false)
    let detached = detach_workspace(manager, workspace.to_string(), fn(_) {
      committed.val = true
    })
    assert_true(committed.val)
    assert_eq(detached.workspaces, [])
    assert_true(@fsx.exists(exited))
    assert_true(manager.followers.get("s-detach-idle") is None)
    guard manager.pump is Serving(sessions~) else {
      fail("engine pump stopped during detach")
    }
    assert_true(sessions.get("s-detach-idle") is None)
    group.return_immediately(())
  })
  @fs.rmdir(root.to_string(), recursive=true)
}
