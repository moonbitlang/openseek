// Engine operations behind the extension ops: prompt submission, cancel/steer
// for open runs, and the one-shot session-store queries.

///|
/// Submit one prompt to the conversation's serve engine, spawning or
/// replacing the process first when the config demands it. Only this
/// conversation must be idle — other sessions' engines run their own turns
/// concurrently. Returns as soon as the prompt is queued for the engine's
/// writer; the engine's consumer task reports progress and completion through
/// events, exactly as the frontend already expects. The op rejects only for
/// failures before the run's Started event goes out. Everything after that —
/// including a stdin write that fails — is reported through the run's error
/// and finished events, never as both an event and a rejection.
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
  let key = payload.session.trim().to_owned()
  // The record lease is acquired before `run_config`, so reject a blank key
  // here as well as at that standalone config boundary. There is no shared
  // empty-session engine slot in the desktop host.
  guard !key.is_empty() else {
    raise EngineError("session id must not be empty")
  }
  let record_guard = manager.begin_record_op(key)
  defer manager.end_record_op(key, record_guard)
  let config = run_config(manager, payload)
  @session_store.ensure_not_archived(key)
  let sessions = manager.serving()
  let slot = slot_for(sessions, key)
  // Busy-ness is a property of the handle, not of admission: a condemned
  // engine whose turn has not settled yet still owns this conversation's
  // durable record, so this reads the slot rather than `live`.
  if slot.engine is Some(engine) {
    match engine.phase {
      Running(..) =>
        raise EngineError(
          "an OpenSeek run is still active in this conversation",
        )
      // A prompt accepted now would queue behind the compaction, where a
      // Stop (which cancels only the compaction) could not reach it.
      Compacting(..) =>
        raise EngineError(
          "this conversation is compacting; wait for it to finish",
        )
      Idle(..) => ()
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
  let need_spawn = if slot.live() is Some(live) {
    live.spec_key != engine_fingerprint(config)
  } else {
    true
  }
  if need_spawn {
    request_spawn(manager, claim, config)
  }
  claim.require_current(manager)
  guard slot.live() is Some(live) else {
    raise EngineError("engine failed to start")
  }
  // The cwd/spawn waits above are suspension points: a compaction accepted
  // during one of them holds the engine now, and the Running transition
  // below would silently clobber it. Re-check on the engine this run will
  // actually use.
  if live.phase is Compacting(..) {
    raise EngineError("this conversation is compacting; wait for it to finish")
  }
  let run_id = mint_run_id()
  let command = @protocol.prompt(config.task)
  let submission_id = normalize_submission_id(payload.submission_id)
  // Submitting, opening the run and announcing it are one synchronous step,
  // with no suspension since the claim check above. That is what makes the
  // ordering hold without a lock: no other request can interleave a command
  // between the prompt and the phase it opens, a remote peer that steers on
  // seeing Started necessarily lands behind the complete prompt, and this
  // task cannot be cancelled after Started is public.
  guard live.submit(command.to_jsonl(), failure_reason="engine write failed") else {
    raise EngineError("engine changed before the prompt was submitted")
  }
  // Stamped with the Running flip (one synchronous step): the follower's
  // durable close attributes terminal records to this run by comparing
  // their commit timestamps against this admission time.
  live.run_admitted_ms = @async.now()
  live.phase = Running(run_id~, cancel_requested=false, compact_queued=false)
  live.steer_runs.begin_run()
  emit(
    sink,
    Started({
      run_id,
      submission_id,
      engine: Some(config.engine),
      model: Some(config.model),
      max_steps: Some(config.max_steps),
      session: config.session,
      session_root: config.session_root.map(root => root.resource_path()),
    }),
  )
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
pub fn cancel_run(
  manager : EngineManager,
  payload : @protocol.CancelPayload,
) -> CancelReply {
  guard open_run_engine(manager, run_id?=payload.run_id) is Some(live) else {
    return { cancelled: false, run_id: None }
  }
  guard live.is_current(manager) else {
    return { cancelled: false, run_id: None }
  }
  guard live.phase is Running(run_id~, compact_queued~, ..) else {
    return { cancelled: false, run_id: None }
  }
  if payload.run_id is Some(expected) && run_id != expected {
    return { cancelled: false, run_id: None }
  }
  guard live.submit(
    @protocol.cancel().to_jsonl(),
    failure_reason="failed to write cancellation to the engine",
  ) else {
    return { cancelled: false, run_id: None }
  }
  // A compaction queued behind the dying turn survives the cancel: the
  // engine's pending queue keeps it (cancel only aborts the active turn), so
  // the flag must ride along or the terminal event would idle past it.
  live.phase = Running(run_id~, cancel_requested=true, compact_queued~)
  { cancelled: true, run_id: Some(run_id) }
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
  @session_store.ensure_not_archived(session)
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
  let live = if slot.live() is Some(live) {
    live
  } else {
    let config = compact_config(manager, payload)
    ensure_run_cwd(config)
    request_spawn(manager, claim, config)
    claim.require_current(manager)
    guard slot.live() is Some(live) else {
      raise EngineError("engine failed to start")
    }
    live
  }
  // Deciding the phase this command implies is also how it is admitted, so
  // there is exactly one place that classifies the current phase instead of
  // the two matching ones a lock-then-revalidate shape needed.
  let compacting_phase = match live.phase {
    Compacting(..) =>
      raise EngineError("this conversation is already compacting")
    Running(compact_queued=true, ..) =>
      raise EngineError(
        "a compaction is already queued behind the running turn",
      )
    // Sent mid-turn, the command queues behind the open run; the flag makes
    // the turn's terminal event land in Compacting so nothing slips into the
    // gap before the engine's own compaction_started.
    Running(run_id~, cancel_requested~, compact_queued=false) =>
      Running(run_id~, cancel_requested~, compact_queued=true)
    Idle(last_run~) => Compacting(last_run~)
  }
  // Submitting and entering the phase are one synchronous step, so the
  // classification above still holds and the consumer sees the new phase
  // before any event the command can produce.
  guard live.submit(
    @protocol.compact().to_jsonl(),
    failure_reason="failed to write the compaction command",
  ) else {
    raise EngineError("engine changed before compaction was submitted")
  }
  live.phase = compacting_phase
  { compacting: true }
}

///|
/// Set or clear a conversation's standing goal: durable session state on the
/// serve engine, addressed by session id like compaction. A conversation with
/// no live engine (resumed after a restart, or whose process died between
/// turns) gets one spawned on the durable session first. Unlike compaction
/// the command is welcome in every phase — the serve engine appends it while
/// idle, steers it into an open turn at a batch-safe boundary, and holds its
/// wire-order position behind a queued compaction — so this op never gates on
/// phase. The engine confirms through the durable `[goal]` marker commit;
/// this op only confirms the command was accepted by a live engine's writer.
pub async fn goal_run(
  manager : EngineManager,
  payload : @protocol.GoalPayload,
) -> GoalReply {
  let goal = if payload.text is Some(text) {
    let text = text.trim().to_owned()
    guard !text.is_empty() else {
      raise EngineError("goal text must not be empty")
    }
    Some(text)
  } else {
    None
  }
  // Arming is not wired end to end. Serve announces the turns autonomous
  // continuation starts with `GoalContinue`, which this host drops, so its
  // phase stays Idle through one — and `start_run`, whose only gate is that
  // phase, would hand the same engine to a prompt the autonomous turn's
  // terminal event then settles. Refuse the capability here rather than
  // trusting clients to ask for manual: this endpoint serves the relay, not
  // only this app's own page.
  guard !(payload.auto is Some(true)) else {
    raise EngineError("autonomous goal continuation is not supported yet")
  }
  manager.workspace_lifecycle_lock.acquire()
  let mut placement_locked = true
  defer (if placement_locked { manager.workspace_lifecycle_lock.release() })
  let session = payload.session.trim().to_owned()
  // Checked before the slot lookup, not inside the spawn path: an engine
  // already accepting on this key skips `goal_config` and its guard. Reject
  // malformed requests at the public operation boundary as well.
  guard !session.is_empty() else {
    raise EngineError("session id must not be empty")
  }
  let record_guard = manager.begin_record_op(session)
  defer manager.end_record_op(session, record_guard)
  @session_store.ensure_not_archived(session)
  let sessions = manager.serving()
  let slot = slot_for(sessions, session)
  // Claim before looking at the engine, exactly as compact_run does: this op
  // may have to spawn one, and a start accepted during that wait could replace
  // the live process and lose the command in the dying engine's stdin.
  let claim = slot.claim(sessions, session, GoalPending)
  defer claim.release(manager)
  placement_locked = false
  manager.workspace_lifecycle_lock.release()
  let live = if slot.live() is Some(live) {
    live
  } else {
    let config = goal_config(manager, payload)
    ensure_run_cwd(config)
    request_spawn(manager, claim, config)
    claim.require_current(manager)
    guard slot.live() is Some(live) else {
      raise EngineError("engine failed to start")
    }
    live
  }
  let command = if goal is Some(text) {
    @protocol.goal_set(text, auto=payload.auto is Some(true))
  } else {
    @protocol.goal_clear()
  }
  // The one command that must be acknowledged. A prompt or a compaction that
  // never reaches stdin is reported by its run's lifecycle events, and a steer
  // by its receipt or the run's durable recovery; a goal has neither. Its only
  // other confirmation is the durable `[goal]` marker, so a dropped goal would
  // leave the client believing a set or clear succeeded that never happened.
  let ack : @async.Queue[EngineError?] = Queue(kind=Blocking(1))
  guard live.submit(
    command.to_jsonl(),
    failure_reason="failed to write the goal command",
    ack~,
  ) else {
    raise EngineError("engine changed before the goal was submitted")
  }
  // Affordable precisely because nothing above went public: no phase
  // transition, no event. A cancellation landing on this wait leaves nothing
  // to unwind, which is why a prompt cannot do the same.
  if ack.get() is Some(error) {
    raise error
  }
  { delivered: true }
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
pub fn steer_run(
  manager : EngineManager,
  payload : @protocol.SteerPayload,
) -> SteerReply {
  guard !payload.text.is_blank() else {
    return { steered: false, run_id: None }
  }
  guard open_run_engine(manager, run_id?=payload.run_id) is Some(live) &&
    live.phase is Running(run_id~, cancel_requested=false, ..) else {
    return { steered: false, run_id: None }
  }
  guard live.is_current(manager) else {
    return { steered: false, run_id: None }
  }
  if payload.run_id is Some(expected) && run_id != expected {
    return { steered: false, run_id: None }
  }
  let submission_id = normalize_submission_id(payload.submission_id)
  guard live.submit(
    @protocol.steer(payload.text).to_jsonl(),
    failure_reason="failed to write steering to the engine",
  ) else {
    return { steered: false, run_id: Some(run_id) }
  }
  // Recorded in the same synchronous step as the submission, so the entry
  // exists before any event this steer can produce and a terminal event that
  // arrives first can still pin it to the finishing run. Identity, not text,
  // drives rollback so equal steering strings retain distinct submission ids.
  //
  // Once submitted the steer is provisionally accepted even if the writer
  // later fails: a complete frame may already be in the pipe and can still
  // produce a durable User plus steer_applied before EOF. The client keeps
  // exact-id ownership, and the trailing receipt or Finished/durable recovery
  // settles it without restoring a duplicate draft.
  live.steer_runs.record_sent(payload.text, submission_id) |> ignore
  { steered: true, run_id: Some(run_id) }
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
    no_console_window=true,
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
      no_console_window=true,
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
/// The sidebar's conversations, one group per registered workspace's
/// in-project store, in registration order. A group whose listing fails
/// reports the failure in its `error` field rather than failing the whole
/// reply.
pub async fn list_sessions(manager : EngineManager) -> SessionsReply {
  let groups : Array[SessionGroup] = []
  for path in @workspaces.registered() {
    groups.push(session_group(manager, path, @workspaces.store_root(path)))
  }
  { groups, }
}

///|
async fn session_group(
  manager : EngineManager,
  workspace : @pathx.Absolute,
  root : @pathx.Absolute,
) -> SessionGroup {
  let name = workspace.to_path().basename().to_owned()
  let workspace = workspace.resource_path()
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
  // detached workspace is rejected instead of silently probing another
  // store, which could return a different history for the same session id.
  let root = if payload.workspace is Some(hint) && !hint.is_blank() {
    guard @pathx.Absolute::from_uri_path(hint) is Some(absolute) &&
      @workspaces.registered_dir(absolute) is Some(workspace) else {
      raise EngineError("\{hint} is not a registered workspace")
    }
    Some(@workspaces.store_root(workspace))
  } else {
    @session_store.root_of(session)
  }
  guard root is Some(root) else {
    raise EngineError(
      "no attached workspace holds this conversation; attach its project first",
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
    if @session_store.archived_root_of(session) is Some(_) {
      raise EngineError("this conversation is archived; unarchive it first")
    }
    raise EngineError(
      "no durable record for this conversation in any attached workspace",
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
/// Read a durable transcript from a store's archived twin without moving it
/// back into the live store. The same manager-global reader lease used by
/// `load_session` makes an archive/unarchive rename wait for this snapshot.
pub async fn load_archived_session(
  manager : EngineManager,
  payload : @protocol.LoadSessionPayload,
) -> LoadSessionReply {
  let session = payload.session.trim().to_owned()
  guard !session.is_empty() else {
    raise EngineError("session id must not be empty")
  }
  let record_guard = manager.begin_record_read(session)
  defer manager.end_record_read(session, record_guard)
  // A workspace hint selects that registered store's archived twin. Without
  // one, find the archived record across all attached stores and the global
  // store, matching the placement rules of the archived index.
  let root = if payload.workspace is Some(hint) && !hint.is_blank() {
    guard @pathx.Absolute::from_uri_path(hint) is Some(absolute) &&
      @workspaces.registered_dir(absolute) is Some(workspace) else {
      raise EngineError("\{hint} is not a registered workspace")
    }
    Some(@session_store.archived_root(@workspaces.store_root(workspace)))
  } else {
    match @session_store.archived_root_of(session) {
      Some(root) => Some(@session_store.archived_root(root))
      None => None
    }
  }
  guard root is Some(root) else {
    if @session_store.live_root_of(session) is Some(_) {
      raise EngineError("this conversation is not archived")
    }
    raise EngineError(
      "no archived record for this conversation in the global store or any attached workspace",
    )
  }
  if !@fsx.is_dir(root.join("sessions").join(session).to_path()) {
    if @session_store.live_root_of(session) is Some(_) {
      raise EngineError("this conversation is not archived")
    }
    raise EngineError("no archived record for this conversation")
  }
  let output = session_show_stdout(manager, session, root) catch {
    EngineError(detail) =>
      raise EngineError("archived session load failed: " + detail)
    error => raise error
  }
  let json = @json.parse(output) catch {
    _ => raise EngineError("engine returned a malformed archived session")
  }
  let document : @protocol.SessionDocument = @json.from_json(json) catch {
    _ => raise EngineError("engine returned a malformed archived session")
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
  Workspaces(@workspaces.registered().map(path => path.resource_path()))
}

///|
pub async fn attach_workspace(
  path : String,
  on_committed : (Array[String]) -> Unit,
) -> WorkspacesReply {
  guard @pathx.Absolute::from_uri_path(path) is Some(absolute) else {
    raise EngineError("workspace is not a supported absolute resource path")
  }
  let paths = @workspaces.add(absolute.0, paths => {
    on_committed(paths.map(path => path.resource_path()))
  })
  Workspaces(paths.map(path => path.resource_path()))
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
  let workspace = @workspaces.expanded_path(absolute.0)
  manager.close_engines_for_workspace(workspace)
  let paths = @workspaces.remove(absolute.0, paths => {
    on_committed(paths.map(path => path.resource_path()))
  })
  Workspaces(paths.map(path => path.resource_path()))
}
