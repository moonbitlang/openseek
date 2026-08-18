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
/// A workspace fixture for the run tests: `<root>/ws` attached as the only
/// registered workspace, with the registry itself under `<root>/global`.
/// Every run belongs to a workspace now, so a test that starts one registers
/// a real directory rather than relying on the removed scratch fallback.
/// Returns the path to send as the start payload's workspace hint.
async fn attach_run_workspace(root : @pathx.Path) -> String {
  let workspace = root.join("ws")
  @fsx.ensure_dir(workspace)
  let global = root.join("global")
  @fsx.ensure_dir(global)
  @fs.write_file(
    global.join("workspaces.json").to_string(),
    ({ "workspaces": [workspace.to_string()] } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  workspace.to_string()
}

///|
#cfg(not(platform="windows"))
async test "start echoes the client submission id in Started" {
  let dir = @fs.tmpdir(prefix="openseek-start-submission-")
  let root : @pathx.Path = Path(dir)
  // A run is handed the global skills library under `HOME`. Own it, so this
  // test neither races one that moves `HOME` nor reads the developer's own.
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_home_env(previous_home)
  let previous_session_root = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous_session_root)
  let workspace = attach_run_workspace(root)
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
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then printf '%s' '{\"events\":[]}'; exit 0; fi\nwhile IFS= read -r line; do :; done\n",
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
  // Starts are durable now, so each test owns a fresh conversation record
  // instead of sharing a fixed id across test processes.
  let session = "s-" + mint_run_id()
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
        session,
        workspace: Some(workspace),
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
/// A goal is the one command with no lifecycle event behind it, so its reply
/// is only truthful if it waits for the writer. Both halves matter: the reply
/// must arrive when the command reaches stdin — otherwise the op hangs — and
/// must not arrive when it does not.
#cfg(not(platform="windows"))
async test "a goal is delivered only once its command is on the wire" {
  let dir = @fs.tmpdir(prefix="openseek-goal-ack-")
  let root : @pathx.Path = Path(dir)
  // A run is handed the global skills library under `HOME`. Own it, so this
  // test neither races one that moves `HOME` nor reads the developer's own.
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_home_env(previous_home)
  let previous_session_root = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous_session_root)
  let workspace = attach_run_workspace(root)
  let engine = root.join("bin/engine.sh")
  let seed = root.join("bin/toolchains/moonbit/macos-arm64")
  let runtime = root.join("runtime")
  let received = root.join("received")
  prepare_fake_moonbit_seed(seed, version="0.10.0-test")
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  // Echoes every command it reads back into a file, so the test can check the
  // goal really left the host rather than only that the op returned.
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then printf '%s' '{\"events\":[]}'; exit 0; fi\nwhile IFS= read -r line; do printf '%s\\n' \"$line\" >> '\{received}'; done\n",
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
  let session = "s-" + mint_run_id()
  let sink = EventSink(fn(_) { () })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) { () })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    let delivered = goal_run(manager, {
      session,
      text: Some("keep the build green"),
      auto: None,
      model: None,
      max_steps: None,
      workspace: Some(workspace),
    })
    assert_true(delivered.delivered)
    // The reply already means the bytes left this host, so the child has them
    // or is about to; only its append is asynchronous.
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while !@fsx.exists(received) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    assert_true(
      @fs.read_file(received.to_string())
      .text()
      .contains("keep the build green"),
    )
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
/// The other half: a command discarded before it could be written answers its
/// sender rather than leaving it waiting for an acknowledgement that can no
/// longer come. This is what a queued goal hits when an earlier write fails or
/// the child exits.
#cfg(not(platform="windows"))
async test "a discarded command answers its sender" {
  @async.with_task_group(group => {
    let (child_stdin, writer) = @process.write_to_process()
    let process = @process.spawn(
      group,
      "/bin/sh",
      ["-c", "sleep 30"],
      stdin=child_stdin,
      cancel_handler=@process.graceful_cancel(timeout=10),
      no_wait=true,
    )
    let engine : ServeEngine = {
      session_key: "s-discard",
      session_root: None,
      spec_key: "test",
      writer,
      commands: Queue(kind=Unbounded),
      process,
      sink: EventSink(fn(_) { () }),
      follower: None,
      consumer: None,
      phase: Idle(last_run=None),
      run_admitted_ms: 0,
      condemned: false,
      steer_runs: SteerRunTracker::new(),
    }
    let ack : @async.Queue[EngineError?] = Queue(kind=Blocking(1))
    assert_true(
      engine.submit("{}\n", failure_reason="failed to write the goal", ack~),
    )
    engine.discard_commands("the engine exited")
    guard ack.try_get() is Some(Some(EngineError(reason))) else {
      fail("expected the discarded command to answer its sender")
    }
    assert_eq(reason, "the engine exited")
    // Discarding also condemns the engine, in the same synchronous step.
    assert_true(engine.condemned)
    assert_false(engine.submit("{}\n", failure_reason="unreachable"))
    group.return_immediately(())
  })
}

///|
#cfg(not(platform="windows"))
async test "setup failure retires the writer before an immediate next start" {
  let dir = @fs.tmpdir(prefix="openseek-setup-failed-seam-")
  let root : @pathx.Path = Path(dir)
  // A run is handed the global skills library under `HOME`. Own it, so this
  // test neither races one that moves `HOME` nor reads the developer's own.
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_home_env(previous_home)
  let previous_session_root = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous_session_root)
  let workspace = attach_run_workspace(root)
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
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then printf '%s' '{\"events\":[]}'; exit 0; fi\nn=0\nif [ -f '\{count}' ]; then n=$(cat '\{count}'); fi\nn=$((n + 1))\nprintf '%s' \"$n\" > '\{count}'\nif [ \"$n\" -eq 1 ]; then\n  IFS= read -r line || exit 0\n  printf '%s\\n' '{\"event\":\"agent_setup_failed\",\"error\":\"boom\"}'\n  sleep 1\n  printf '%s\\n' '{\"event\":\"turn_failed\",\"error\":\"append failed\"}'\n  printf '' > '\{old_done}'\n  exit 0\nfi\nif [ ! -f '\{old_done}' ]; then printf '' > '\{overlapped}'; fi\nwhile IFS= read -r line; do\n  printf '%s\\n' '{\"event\":\"agent_finished\",\"answer\":\"ok\"}'\ndone\n",
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
  let session = "s-" + mint_run_id()
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
      session,
      workspace: Some(workspace),
    })
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while !has_finished_run(emitted, first.run_id) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    // No durable Terminal was ever committed, so the run settles at EOF
    // retirement — which publishes Finished and clears the slot in one
    // synchronous block. Once Finished is observable, the dead writer has
    // already left its slot.
    if manager.serving().get(session) is Some(slot) {
      assert_true(slot.engine is None)
    }
    let cancelled = cancel_run(manager, { run_id: Some(first.run_id) })
    assert_false(cancelled.cancelled)
    let second = start_run(sink, manager, {
      task: "second",
      submission_id: None,
      model: None,
      max_steps: None,
      session,
      workspace: Some(workspace),
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
/// The prompt is far larger than the pipe buffer and the child never reads,
/// so the write is still in flight when the child dies. Submission itself
/// never waits for it — that is what removed the cancel-after-public window
/// this test used to cover — and the run is still settled exactly once,
/// whether the writer's failure or the consumer's EOF gets there first.
#cfg(not(platform="windows"))
async test "a prompt bigger than the pipe still settles exactly once" {
  let dir = @fs.tmpdir(prefix="openseek-backpressured-command-")
  let root : @pathx.Path = Path(dir)
  // A run is handed the global skills library under `HOME`. Own it, so this
  // test neither races one that moves `HOME` nor reads the developer's own.
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_home_env(previous_home)
  let previous_session_root = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous_session_root)
  let workspace = attach_run_workspace(root)
  let engine = root.join("bin/engine.sh")
  let seed = root.join("bin/toolchains/moonbit/macos-arm64")
  let runtime = root.join("runtime")
  prepare_fake_moonbit_seed(seed, version="0.10.0-test")
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  // Deliberately never read stdin, then die with the prompt still half
  // written: the JSONL frame on the wire is partial, so the handle must
  // become unusable and the run must be reported as failed.
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then printf '%s' '{\"events\":[]}'; exit 0; fi\nsleep 1\n",
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
  let session = "s-" + mint_run_id()
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
    // Returns without waiting for the 4MB to reach the child.
    let reply = start_run(sink, manager, {
      task: "x".repeat(4_000_000),
      submission_id: None,
      model: None,
      max_steps: None,
      session,
      workspace: Some(workspace),
    })
    assert_eq(reply.status, "accepted")
    assert_eq(started.val, Some(reply.run_id))
    let run_id = reply.run_id
    assert_true(
      @async.with_timeout_opt(10_000, () => {
        while !has_finished_run(emitted, run_id) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    // Both the writer's failed write and the consumer's EOF want to settle
    // this run; they share the engine's phase, so only one of them does.
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
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let dir = @fs.tmpdir(prefix="openseek-first-prompt-retry-")
  let root : @pathx.Path = Path(dir)
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_home_env(previous_home)
  let engine = root.join("bin/engine.sh")
  let seed = root.join("bin/toolchains/moonbit/macos-arm64")
  let runtime = root.join("runtime")
  let previous_session_root = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous_session_root)
  let workspace = attach_run_workspace(root)
  // The conversation's record lives in its workspace's in-project store.
  let store = root.join("ws/.openseek")
  let count = root.join("serve-count")
  let first_ready = root.join("first-ready")
  let settled = root.join("settled")
  let session = "s-" + mint_run_id()
  prepare_fake_moonbit_seed(seed, version="0.10.0-test")
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  // `sessions show` reports the missing first-turn record. The first serve
  // process creates only the session directory, never reads stdin, and dies
  // with the large prompt's JSONL frame still partial. The successor commits
  // a durable Terminal before echoing `agent_finished` — the real engine's
  // append-then-emit order — so the follower's scan settles its run.
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then\n  if [ -f '\{settled}' ]; then\n    printf '%s' '{\"events\":[{\"sequence\":1,\"ts\":4000000000000.0,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"finished\",\"message\":\"ok\"}}}]}'\n    exit 0\n  fi\n  printf '%s\\n' 'session record does not exist' >&2\n  exit 7\nfi\nn=0\nif [ -f '\{count}' ]; then n=$(cat '\{count}'); fi\nn=$((n + 1))\nprintf '%s' \"$n\" > '\{count}'\nif [ \"$n\" -eq 1 ]; then\n  mkdir -p '\{store}/sessions/\{session}'\n  printf '' > '\{first_ready}'\n  exec sleep 1\nfi\nwhile IFS= read -r line; do\n  printf '' > '\{settled}'\n  printf '%s\\n' '{\"event\":\"agent_finished\",\"answer\":\"ok\"}'\ndone\n",
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
    let first = start_run(sink, manager, {
      task: "x".repeat(4_000_000),
      submission_id: None,
      model: None,
      max_steps: None,
      session,
      workspace: Some(workspace),
    })
    assert_eq(first.status, "accepted")
    assert_eq(started.val, Some(first.run_id))
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while !@fsx.exists(first_ready) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    assert_true(@fsx.is_dir(store.join("sessions").join(session)))
    assert_false(
      @fsx.exists(Path(session_store_file(store.resolve(), session))),
    )
    let first_run_id = first.run_id
    assert_true(
      @async.with_timeout_opt(10_000, () => {
        while !has_finished_run(emitted, first_run_id) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    assert_true(
      @async.with_timeout_opt(10_000, () => {
        while manager.followers.get(session) is Some(_) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )

    let second = start_run(sink, manager, {
      task: "retry",
      submission_id: None,
      model: None,
      max_steps: None,
      session,
      workspace: Some(workspace),
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
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let dir = @fs.tmpdir(prefix="openseek-load-future-item-")
  let engine = dir + "/engine.sh"
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", dir + "/global")
  defer restore_session_root_env(previous)
  // A hint-less load resolves the store from where the record actually
  // lives, so the record goes in an attached workspace's own store.
  ignore(attach_run_workspace(Path(dir)))
  @fsx.ensure_dir(Path(dir + "/ws/.openseek/sessions/s-future"))
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
async test "archived session load reads without restoring the record" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let dir = @fs.tmpdir(prefix="openseek-load-archived-")
  let engine = dir + "/engine.sh"
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", dir + "/global")
  defer restore_session_root_env(previous)
  // A hint-less load resolves the store from where the record actually
  // lives, so the record goes in an attached workspace's own store.
  ignore(attach_run_workspace(Path(dir)))
  let store = dir + "/ws/.openseek"
  @fsx.ensure_dir(Path(store + "/archived/sessions/s-archived"))
  @fs.write_file(
    engine,
    "#!/bin/sh\nprintf '%s' '{\"events\":[{\"sequence\":1,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"question\"}}},{\"sequence\":2,\"item\":{\"kind\":\"assistant\",\"payload\":{\"content\":\"answer\"}}}]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let reply = load_archived_session(manager, {
    session: "s-archived",
    workspace: None,
  })
  guard reply.session.events is Some(events) else {
    fail("expected archived session events")
  }
  assert_eq(events.length(), 2)
  assert_eq(reply.watermark, Some(2))
  assert_true(@fsx.is_dir(Path(store + "/archived/sessions/s-archived")))
  assert_false(@fsx.exists(Path(store + "/sessions/s-archived")))
  assert_true(manager.record_guards.is_empty())
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "load rejects a detached workspace hint instead of probing global" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
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
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
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
      session: "s-detach-running",
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
    assert_true(@workspaces.registered().contains(workspace_path))
    group.return_immediately(())
  })
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "workspace detach drains an idle writer and its follower first" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
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
  // The serve branch commits a durable Terminal (the `settled` marker)
  // before echoing `agent_finished` — the real engine's append-then-emit
  // order — so the follower's scan settles the run and detach finds the
  // writer idle.
  let settled = root.join("settled")
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then\n  if [ -f '\{settled}' ]; then\n    printf '%s' '{\"events\":[{\"sequence\":1,\"ts\":4000000000000.0,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"finished\",\"message\":\"ok\"}}}]}'\n  else\n    printf '%s' '{\"events\":[]}'\n  fi\n  exit 0\nfi\nwhile IFS= read -r line; do printf '' > '\{settled}'; printf '%s\\n' '{\"event\":\"agent_finished\",\"answer\":\"ok\"}'; done\nprintf '' > '\{exited}'\n",
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
      session: "s-detach-idle",
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
    assert_true(detached is Workspaces([]))
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

///|
/// Both refusals land before the op can touch an engine, so no fake one is
/// needed — reaching a live engine is precisely what they must prevent.
async test "a goal request is refused before it can reach the wrong engine" {
  let manager = new_engine_manager("/nonexistent/engine")
  async fn refusal(payload : @protocol.GoalPayload) -> String {
    try {
      ignore(goal_run(manager, payload))
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
  }

  // Arming is not wired end to end, and this endpoint serves the relay: a
  // remote client must not be able to ask for what the app's own page no
  // longer offers.
  assert_true(
    refusal({
      session: "s-armed",
      text: Some("ship it"),
      auto: Some(true),
      model: None,
      max_steps: None,
      workspace: None,
    }).contains("autonomous goal continuation is not supported yet"),
  )
  // Manual, named: past the refusal and on to the engine, which is where a
  // nonexistent binary makes itself known.
  assert_false(
    refusal({
      session: "s-named",
      text: Some("ship it"),
      auto: None,
      model: None,
      max_steps: None,
      workspace: None,
    }).contains("not supported yet"),
  )
}
