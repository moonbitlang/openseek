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
  match live.phase {
    Compacting(..) =>
      raise EngineError(
        "this conversation is compacting; wait for it to finish",
      )
    Running(..) =>
      raise EngineError(
        "this conversation resumed a queued follow-up; wait for it to finish",
      )
    Idle(..) => ()
  }
  let run_id = mint_run_id()
  // The normalized tag rides the wire command so the engine records it on the
  // durable User item this prompt appends. That is what lets a client
  // recognize its own prompt in the record — the host itself never reads it
  // back.
  let submission_id = normalize_submission_id(payload.submission_id)
  let command = @protocol.prompt(config.task, submission_id?)
  // Submitting, opening the run and announcing it are one synchronous step,
  // with no suspension since the claim check above. That is what makes the
  // ordering hold without a lock: no other request can interleave a command
  // between the prompt and the phase it opens, a remote peer that steers on
  // seeing Started necessarily lands behind the complete prompt, and this
  // task cannot be cancelled after Started is public.
  guard live.submit(command, failure_reason="engine write failed") else {
    raise EngineError("engine changed before the prompt was submitted")
  }
  live.phase = Running(run_id~, compact_queued=false)
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
  { run_id, status: "accepted", exit_code: 0, }
}

///|
/// A fresh run id backed by the shared UUID source. The `r` prefix remains
/// engine protocol syntax; UUID formatting and entropy ownership belong to the
/// shared package.
fn mint_run_id() -> String raise EngineError {
  guard @uuid.mint() is Some(id) else {
    raise EngineError("cannot mint a run id: OS entropy unavailable")
  }
  "r\{id}"
}

///|
/// Cancel an open turn by asking its serve engine to interrupt it — the
/// process itself stays alive for the next prompt. The run is addressed by
/// id across all conversations; the reply names the run the cancel reached,
/// which is the only way a caller that omitted the id learns which one that
/// was.
///
/// Nothing open to cancel is an answer, not a failure: a Stop racing a turn
/// that just ended is ordinary, and the caller wanted the run over either
/// way. A cancel that could not be written is the real failure — the turn is
/// still running and nobody asked it to stop.
pub fn cancel_run(
  manager : EngineManager,
  payload : @protocol.CancelPayload,
) -> CancelReply raise EngineError {
  guard open_run_engine(manager, run_id?=payload.run_id) is Some(live) &&
    live.phase is Running(run_id~, ..) else {
    return { run_id: None, }
  }
  if payload.run_id is Some(expected) && run_id != expected {
    return { run_id: None, }
  }
  guard live.submit(
    @protocol.cancel(),
    failure_reason="failed to write cancellation to the engine",
  ) else {
    raise EngineError("the cancellation could not be written to the engine")
  }
  // The phase stays Running: the turn is not over until the engine says so,
  // and its terminal event is what closes the run. A compaction queued behind
  // the dying turn survives too — cancel only aborts the active turn, so the
  // queued command still runs and the phase must still route the terminal
  // event into Compacting.
  { run_id: Some(run_id), }
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
  // async 0.21: `protect_from_cancel` no longer raises after resuming a
  // cancelled shield (the old `resume_on_cancel=false` default), so a
  // requester cancelled while awaiting this ack would otherwise return
  // normally and its caller would proceed as if it had not been cancelled.
  // `pause` re-raises the pending cancellation the moment the shield lifts,
  // preserving the old observable contract for the caller.
  @async.pause()
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
  // A changed model, reasoning choice, or endpoint replaces an idle engine
  // before the compaction. During a turn the compact command must stay behind
  // that turn on its current process; do not resolve new endpoint settings in
  // that active path, because they do not configure the process accepting the
  // queued command. The next start applies the new fingerprint after both
  // settle.
  let replacement = match slot.live() {
    None => Some(compact_config(manager, payload))
    Some(live) =>
      match live.phase {
        Idle(..) => {
          let config = compact_config(manager, payload)
          if live.spec_key != engine_fingerprint(config) {
            Some(config)
          } else {
            None
          }
        }
        Running(..) | Compacting(..) => None
      }
  }
  if replacement is Some(config) {
    ensure_run_cwd(config)
    request_spawn(manager, claim, config)
    claim.require_current(manager)
  }
  guard slot.live() is Some(live) else {
    raise EngineError("engine failed to start")
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
    Running(..) if !live.queued_runs.is_empty() =>
      raise EngineError("cannot compact while follow-up messages are queued")
    // Sent mid-turn, the command queues behind the open run; the flag makes
    // the turn's terminal event land in Compacting so nothing slips into the
    // gap before the engine's own compaction_started.
    Running(run_id~, compact_queued=false) =>
      Running(run_id~, compact_queued=true)
    Idle(last_run~) => Compacting(last_run~)
  }
  // Submitting and entering the phase are one synchronous step, so the
  // classification above still holds and the consumer sees the new phase
  // before any event the command can produce.
  guard live.submit(
    @protocol.compact(),
    failure_reason="failed to write the compaction command",
  ) else {
    raise EngineError("engine changed before compaction was submitted")
  }
  live.phase = compacting_phase
  { compacting: true, }
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
  // A goal sent while idle observes the selected engine settings immediately.
  // Mid-turn and queued-compaction goals stay on the current process because
  // replacing it would destroy the operation they are ordered behind. New
  // endpoint settings are therefore not resolved in that active path; the
  // next idle start applies their fingerprint.
  let replacement = match slot.live() {
    None => Some(goal_config(manager, payload))
    Some(live) =>
      match live.phase {
        Idle(..) => {
          let config = goal_config(manager, payload)
          if live.spec_key != engine_fingerprint(config) {
            Some(config)
          } else {
            None
          }
        }
        Running(..) | Compacting(..) => None
      }
  }
  if replacement is Some(config) {
    ensure_run_cwd(config)
    request_spawn(manager, claim, config)
    claim.require_current(manager)
  }
  guard slot.live() is Some(live) else {
    raise EngineError("engine failed to start")
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
    command,
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
  { delivered: true, }
}

///|
/// Inject steering input into an open turn, addressed by run id: the text
/// rides that serve engine's lossless steering queue and is folded into the
/// conversation at the turn's next step boundary, where the engine echoes it
/// back as a `steer_applied` event (or `steer_dropped` if it raced the turn's
/// end). Blank text is refused: the engine filters blanks without emitting
/// any settling event, which would leave a phantom acknowledgment.
pub fn steer_run(
  manager : EngineManager,
  payload : @protocol.SteerPayload,
) -> SteerReply {
  guard !payload.text.is_blank() else {
    return { steered: false, run_id: None, }
  }
  guard open_run_engine(manager, run_id?=payload.run_id) is Some(live) &&
    live.phase is Running(run_id~, ..) else {
    return { steered: false, run_id: None, }
  }
  if payload.run_id is Some(expected) && run_id != expected {
    return { steered: false, run_id: None, }
  }
  let submission_id = normalize_submission_id(payload.submission_id)
  guard live.submit(
    @protocol.steer(payload.text),
    failure_reason="failed to write steering to the engine",
  ) else {
    return { steered: false, run_id: Some(run_id), }
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
  { steered: true, run_id: Some(run_id), }
}

///|
/// Mutate the currently running turn's in-memory follow-up queue. Queued text
/// stays in the Desktop controller and reaches the serve process only when it
/// is promoted to an ordinary prompt or explicitly steered into the open turn.
pub fn queue_run(
  manager : EngineManager,
  payload : @protocol.QueuePayload,
) -> @protocol.QueueReply raise EngineError {
  let id = match payload.action {
    QueueAdd(id~, ..)
    | QueueEdit(id~, ..)
    | QueueWithdraw(id~)
    | QueueSteer(id~) => id.trim().to_owned()
  }
  guard !id.is_empty() else { return { accepted: false, } }
  guard open_run_engine(manager, run_id=payload.run_id) is Some(live) &&
    live.phase is Running(run_id~, ..) else {
    return { accepted: false, }
  }
  if run_id != payload.run_id {
    return { accepted: false, }
  }
  match payload.action {
    QueueAdd(text~, ..) => {
      guard !(live.phase is Running(compact_queued=true, ..)) else {
        return { accepted: false, }
      }
      guard !text.is_blank() else { return { accepted: false, } }
      guard !live.queued_runs.iter().any(queued => queued.id == id) else {
        return { accepted: false, }
      }
      live.queued_runs.push({ id, run_id: mint_run_id(), content: text, })
    }
    QueueEdit(text~, ..) => {
      guard !text.is_blank() else { return { accepted: false, } }
      guard live.queued_runs.search_by(queued => queued.id == id) is Some(index) else {
        return { accepted: false, }
      }
      let queued = live.queued_runs[index]
      live.queued_runs[index] = { ..queued, content: text, }
    }
    QueueWithdraw(..) => {
      guard live.queued_runs.search_by(queued => queued.id == id) is Some(index) else {
        return { accepted: false, }
      }
      ignore(live.queued_runs.remove(index))
    }
    QueueSteer(..) => {
      guard live.queued_runs.search_by(queued => queued.id == id) is Some(index) else {
        return { accepted: false, }
      }
      let queued = live.queued_runs[index]
      guard live.submit(
        @protocol.steer(queued.content),
        failure_reason="failed to write steering to the engine",
      ) else {
        return { accepted: false, }
      }
      // The ordinary steer receipt carries this queue id, keeping the
      // transient Steering row attached to the exact promoted input.
      ignore(live.steer_runs.record_sent(queued.content, Some(id)))
      ignore(live.queued_runs.remove(index))
    }
  }
  { accepted: true, }
}

///|
/// Answer a permission question the engine is blocked on, addressed by the id
/// its `approval_requested` event carried.
///
/// Modelled on `steer_run` and different from it in one way that matters: a
/// steer is optional input, while this releases a tool that is ALREADY running
/// and waiting. Everything that would defer it — a closed engine, a run that
/// has since ended, a run id that does not match — reports `delivered: false`
/// instead, because the caller is showing a prompt and needs to know it is
/// dead rather than pending.
pub fn approve_run(
  manager : EngineManager,
  payload : @protocol.ApprovalPayload,
) -> ApprovalReply {
  guard !payload.id.is_blank() else { return { delivered: false, } }
  guard open_run_engine(manager, run_id?=payload.run_id) is Some(live) &&
    live.phase is Running(run_id~, ..) else {
    return { delivered: false, }
  }
  if payload.run_id is Some(expected) && run_id != expected {
    return { delivered: false, }
  }
  guard live.submit(
    @protocol.approval(payload.id, allow=payload.allow),
    failure_reason="failed to write the approval decision to the engine",
  ) else {
    return { delivered: false, }
  }
  { delivered: true, }
}

///|
/// Run the bundled engine with `args` and return its stdout. A non-zero exit
/// is reported through stderr's content so the frontend sees the engine's own
/// message rather than a bare exit code when one is available.
async fn engine_stdout(manager : EngineManager, args : Array[String]) -> String {
  let engine = manager.engine
  let (code, stdout, stderr) = @processx.collect_output_no_stdin(engine, args) catch {
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
/// Give one exact live conversation a durable display title without rewriting
/// its append-only transcript. Placement and record-operation guards keep the
/// sidecar write from racing archive, detach, or another preparatory operation.
pub async fn rename_session(
  manager : EngineManager,
  payload : @protocol.SessionRenamePayload,
) -> Unit {
  let session = payload.session.trim().to_owned()
  let title = payload.title.trim().to_owned()
  guard !session.is_empty() else {
    raise EngineError("session id must not be empty")
  }
  guard !title.is_empty() else { raise EngineError("title must not be empty") }
  guard @pathx.Absolute::from_uri_path(payload.workspace) is Some(requested) &&
    @workspaces.registered_dir(requested) is Some(workspace) else {
    raise EngineError("workspace is not a registered workspace")
  }
  manager.workspace_lifecycle_lock.acquire()
  let mut placement_locked = true
  defer (if placement_locked { manager.workspace_lifecycle_lock.release() })
  let record_guard = manager.begin_record_op(session)
  defer manager.end_record_op(session, record_guard)
  placement_locked = false
  manager.workspace_lifecycle_lock.release()
  let store = @store.SessionStore(@workspaces.store_root(workspace).to_string())
  let id : @agent_session.SessionId = SessionId(session)
  store.set_title(id, title) catch {
    error => raise EngineError("session rename failed: \{error}")
  }
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
    { workspace, name, session_root: root, sessions: [], error, }
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
  { workspace, name, session_root: root, sessions, error: "", }
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
  // A record that moved to an archived twin is a different answer than one
  // that was never written: say so, rather than reporting this store's
  // emptiness for a conversation that does have durable content elsewhere.
  if !@fsx.is_dir(root.join("sessions").join(session).to_path()) &&
    @session_store.archived_root_of(session) is Some(_) {
    raise EngineError("this conversation is archived; unarchive it first")
  }
  let document = @session_record.read_document(root, session) catch {
    error if @async.is_being_cancelled() => raise error
    // No record here yet. That is this conversation's answer, not a failed
    // read: a turn that died before the engine created the record leaves
    // exactly this state, and a client told "load failed" can only retry a
    // read that will keep failing.
    @session_record.Absent(_) => return empty_session_reply(session)
    error => raise EngineError("session load failed: \{error}")
  }
  { session: document, watermark: Some(session_max_sequence(document)), }
}

///|
/// The transcript of a conversation with no durable content: what a store
/// holds for a session whose first turn has not committed anything.
fn empty_session_reply(session : String) -> LoadSessionReply {
  {
    session: {
      version: None,
      id: Some(session),
      system_prompt: None,
      events: Some([]),
    },
    watermark: Some(0),
  }
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
  let document = @session_record.read_document(root, session) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise EngineError("archived session load failed: \{error}")
  }
  { session: document, watermark: Some(session_max_sequence(document)), }
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
      // Do not bypass an in-flight final scan with a direct read. Success
      // retires the actor; failure reactivates it, and the load then retries
      // through the actor.
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
fn has_finished_run(events : Array[EngineEvent], run_id : String) -> Bool {
  for event in events {
    if event is Finished(payload) && payload.run_id == run_id {
      return true
    }
  }
  false
}

///|
/// The shell a fake engine runs to commit one durable Terminal before it
/// echoes the matching `agent_finished` — the real engine's append-then-emit
/// order. The run settles on the stream event alone; this is what gives the
/// follower a real record to tail, so a fixture exercises both halves the way
/// a live engine does.
///
/// The child reads its store location and identity from explicit arguments, so
/// this needs no paths baked in. The
/// next sequence is the record's line count: the header occupies line one, so
/// the first turn commits sequence 1 and each later one advances.
#cfg(not(platform="windows"))
fn commit_terminal_sh() -> String {
  // `\{newline}` is the two characters a shell `printf` format needs, not an
  // actual line break.
  let newline = "\\n"
  let script =
    $|session=""
    $|session_root=""
    $|for argument in "$@"; do
    $|  case "$argument" in
    $|    --session=*) session="${argument#--session=}" ;;
    $|    --session-root=*) session_root="${argument#--session-root=}" ;;
    $|  esac
    $|done
    $|record="$session_root/sessions/$session/openseek_session-$session.jsonl"
    $|mkdir -p "$session_root/sessions/$session"
    $|if [ ! -f "$record" ]; then
    $|  printf '{"version":1,"id":"%s","system_prompt":""}\{newline}' "$session" > "$record"
    $|fi
    $|printf '{"sequence":%s,"item":{"kind":"terminal","payload":{"kind":"finished","message":"ok"}}}\{newline}' "$(grep -c '' "$record")" >> "$record"
    $|
  script
}

///|
/// A workspace fixture for the run tests: `<root>/ws` attached as the only
/// registered workspace, with the registry under the test's disposable HOME.
/// Every run belongs to a workspace now, so a test that starts one registers
/// a real directory rather than relying on the removed scratch fallback.
/// Returns the path to send as the start payload's workspace hint.
async fn attach_run_workspace(root : @pathx.Path) -> String {
  let workspace = root.join("ws")
  @fsx.ensure_dir(workspace)
  guard @workspaces.global_store_root() is Some(global) else {
    fail("expected a global store under HOME")
  }
  @fsx.ensure_dir(global.to_path())
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
  defer @fs.rmdir(dir, recursive=true)
  let root : @pathx.Path = Path(dir)
  // A run is handed the global skills library under `HOME`. Own it, so this
  // test neither races one that moves `HOME` nor reads the developer's own.
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_home_env(previous_home)
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
      glm_api_key: None,
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
        thinking: None,
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
}

///|
/// A goal is the one command with no lifecycle event behind it, so its reply
/// is only truthful if it waits for the writer. Both halves matter: the reply
/// must arrive when the command reaches stdin — otherwise the op hangs — and
/// must not arrive when it does not.
#cfg(not(platform="windows"))
async test "a goal is delivered only once its command is on the wire" {
  let dir = @fs.tmpdir(prefix="openseek-goal-ack-")
  defer @fs.rmdir(dir, recursive=true)
  let root : @pathx.Path = Path(dir)
  // A run is handed the global skills library under `HOME`. Own it, so this
  // test neither races one that moves `HOME` nor reads the developer's own.
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_home_env(previous_home)
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
      glm_api_key: None,
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
      thinking: None,
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
    let engine = test_serve_engine(
      "s-discard",
      writer,
      process,
      EventSink(fn(_) { () }),
      phase=Idle(last_run=None),
    )
    let ack : @async.Queue[EngineError?] = Queue(kind=Blocking(1))
    assert_true(
      engine.submit(
        @protocol.goal_clear(),
        failure_reason="failed to write the goal",
        ack~,
      ),
    )
    engine.discard_commands("the engine exited")
    guard ack.try_get() is Some(Some(EngineError(reason))) else {
      fail("expected the discarded command to answer its sender")
    }
    assert_eq(reason, "the engine exited")
    // Discarding also condemns the engine, in the same synchronous step.
    assert_true(engine.condemned)
    assert_false(
      engine.submit(@protocol.goal_clear(), failure_reason="unreachable"),
    )
    group.return_immediately(())
  })
}

///|
#cfg(not(platform="windows"))
async test "setup failure retires the writer before an immediate next start" {
  let dir = @fs.tmpdir(prefix="openseek-setup-failed-seam-")
  defer @fs.rmdir(dir, recursive=true)
  let root : @pathx.Path = Path(dir)
  // A run is handed the global skills library under `HOME`. Own it, so this
  // test neither races one that moves `HOME` nor reads the developer's own.
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_home_env(previous_home)
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
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then printf '%s' '{\"events\":[]}'; exit 0; fi\nn=0\nif [ -f '\{count}' ]; then n=$(cat '\{count}'); fi\nn=$((n + 1))\nprintf '%s' \"$n\" > '\{count}'\nif [ \"$n\" -eq 1 ]; then\n  IFS= read -r line || exit 0\n  printf '%s\\n' '{\"event\":\"agent_setup_failed\",\"error\":\"boom\"}'\n  sleep 1\n  printf '%s\\n' '{\"event\":\"turn_failed\",\"error\":\"append failed\"}'\n  printf '' > '\{old_done}'\n  exit 0\nfi\nif [ ! -f '\{old_done}' ]; then printf '' > '\{overlapped}'; fi\nwhile IFS= read -r line; do\n\{commit_terminal_sh()}  printf '%s\\n' '{\"event\":\"agent_finished\",\"answer\":\"ok\"}'\ndone\n",
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
      glm_api_key: None,
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
        thinking: None,
        max_steps: None,
        session,
        workspace: Some(workspace),
      }).run_id
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while !has_finished_run(emitted, first) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    // The run settled on the event that ended its turn, not on the child's
    // exit: the engine is still draining here, but no longer live, so nothing
    // can address it — including a Stop aimed at the run that just closed.
    if manager.serving().get(session) is Some(slot) {
      assert_true(slot.live() is None)
    }
    assert_true(cancel_run(manager, { run_id: Some(first), }).run_id is None)
    let second = start_run(sink, manager, {
      task: "second",
      submission_id: None,
      model: None,
      thinking: None,
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
    let first_finishes = for event in emitted; first_finishes = 0 {
      if event is Finished(payload) && payload.run_id == first {
        continue first_finishes + 1
      }
      continue first_finishes
    } nobreak {
      first_finishes
    }
    assert_eq(first_finishes, 1)
    group.return_immediately(())
  })
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
  defer @fs.rmdir(dir, recursive=true)
  let root : @pathx.Path = Path(dir)
  // A run is handed the global skills library under `HOME`. Own it, so this
  // test neither races one that moves `HOME` nor reads the developer's own.
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_home_env(previous_home)
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
      glm_api_key: None,
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
      thinking: None,
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
    let finishes = for event in emitted; finishes = 0 {
      if event is Finished(payload) && payload.run_id == run_id {
        continue finishes + 1
      }
      continue finishes
    } nobreak {
      finishes
    }
    assert_eq(finishes, 1)
    assert_true(open_run_engine(manager, run_id~) is None)
    group.return_immediately(())
  })
}

///|
#cfg(not(platform="windows"))
async test "named session retries after its first prompt creates no record" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let dir = @fs.tmpdir(prefix="openseek-first-prompt-retry-")
  defer @fs.rmdir(dir, recursive=true)
  let root : @pathx.Path = Path(dir)
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_home_env(previous_home)
  let engine = root.join("bin/engine.sh")
  let seed = root.join("bin/toolchains/moonbit/macos-arm64")
  let runtime = root.join("runtime")
  let workspace = attach_run_workspace(root)
  // The conversation's record lives in its workspace's in-project store.
  let store = root.join("ws/.openseek")
  let count = root.join("serve-count")
  let first_ready = root.join("first-ready")
  let session = "s-" + mint_run_id()
  prepare_fake_moonbit_seed(seed, version="0.10.0-test")
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64"),
    version="0.10.0-test",
  )
  // No first-turn record exists to read. The first serve process creates only
  // the session directory, never reads stdin, and dies with the large prompt's
  // JSONL frame still partial. The successor accepts a normal prompt and
  // finishes it.
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then\n  printf '%s\\n' 'session record does not exist' >&2\n  exit 7\nfi\nn=0\nif [ -f '\{count}' ]; then n=$(cat '\{count}'); fi\nn=$((n + 1))\nprintf '%s' \"$n\" > '\{count}'\nif [ \"$n\" -eq 1 ]; then\n  mkdir -p '\{store}/sessions/\{session}'\n  printf '' > '\{first_ready}'\n  exec sleep 1\nfi\nwhile IFS= read -r line; do\n\{commit_terminal_sh()}  printf '%s\\n' '{\"event\":\"agent_finished\",\"answer\":\"ok\"}'\ndone\n",
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
      glm_api_key: None,
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
      thinking: None,
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
      @fsx.exists(@session_record.record_path(store.resolve(), session)),
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
      thinking: None,
      max_steps: None,
      session,
      workspace: Some(workspace),
    })
    assert_eq(second.status, "accepted")
    let second_run_id = second.run_id
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while !has_finished_run(emitted, second_run_id) {
          @async.sleep(1)
        }
      })
      is Some(_),
    )
    assert_eq(@fs.read_file(count.to_string()).text(), "2")
    group.return_immediately(())
  })
}

///|
#cfg(not(platform="windows"))
async test "session load preserves a future item without hiding known events" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let dir = @fs.tmpdir(prefix="openseek-load-future-item-")
  defer @fs.rmdir(dir, recursive=true)
  @sys.set_env_var("HOME", dir + "/global")
  defer restore_home_env(previous)
  // A hint-less load resolves the store from where the record actually
  // lives, so the record goes in an attached workspace's own store.
  ignore(attach_run_workspace(Path(dir)))
  write_session_record(
    @pathx.Path(dir + "/ws/.openseek").resolve(),
    "s-future",
    [
      session_user_event(1, "question"),
      "{\"sequence\":2,\"item\":{\"kind\":\"future_item\",\"payload\":{\"value\":42}}}",
      "{\"sequence\":3,\"item\":{\"kind\":\"assistant\",\"payload\":{\"content\":\"answer\"}}}",
    ],
  )
  // The engine path is never resolved: an idle conversation's transcript is
  // read in this process.
  let reply = load_session(new_engine_manager(dir + "/engine.sh"), {
    session: "s-future",
    workspace: None,
  })
  guard reply.session.events is Some(events) else {
    fail("expected session events")
  }
  assert_eq(events.length(), 3)
  assert_true(events[1].item is Unknown(_))
  assert_eq(reply.watermark, Some(3))
}

///|
#cfg(not(platform="windows"))
async test "archived session load reads without restoring the record" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let dir = @fs.tmpdir(prefix="openseek-load-archived-")
  defer @fs.rmdir(dir, recursive=true)
  @sys.set_env_var("HOME", dir + "/global")
  defer restore_home_env(previous)
  // A hint-less load resolves the store from where the record actually
  // lives, so the record goes in an attached workspace's own store.
  ignore(attach_run_workspace(Path(dir)))
  let store = dir + "/ws/.openseek"
  write_session_record(
    @pathx.Path(store + "/archived").resolve(),
    "s-archived",
    [
      session_user_event(1, "question"),
      "{\"sequence\":2,\"item\":{\"kind\":\"assistant\",\"payload\":{\"content\":\"answer\"}}}",
    ],
  )
  let manager = new_engine_manager(dir + "/engine.sh")
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
}

///|
#cfg(not(platform="windows"))
async test "load rejects a detached workspace hint instead of probing global" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let dir = @fs.tmpdir(prefix="openseek-load-detached-")
  defer @fs.rmdir(dir, recursive=true)
  let marker = dir + "/engine-ran"
  let engine = dir + "/engine.sh"
  @sys.set_env_var("HOME", dir)
  defer restore_home_env(previous)
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
}

///|
#cfg(not(platform="windows"))
async test "workspace detach refuses a running conversation without hiding it" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  // The registry canonicalizes workspace paths, so build the fixture from
  // the tmpdir's physical spelling (`/tmp` is a symlink on macOS).
  let root : @pathx.Path = Path(
    @fs.realpath(@fs.tmpdir(prefix="openseek-detach-running-")),
  )
  defer @fs.rmdir(root.to_string(), recursive=true)
  let global_store = root.join("global")
  let workspace = root.join("workspace")
  let engine = root.join("bin/engine.sh")
  let runtime = root.join("runtime")
  @sys.set_env_var("HOME", global_store.to_string())
  defer restore_home_env(previous)
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
      glm_api_key: None,
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
      thinking: None,
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
}

///|
#cfg(not(platform="windows"))
async test "workspace detach drains an idle writer and its follower first" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  // The registry canonicalizes workspace paths, so build the fixture from
  // the tmpdir's physical spelling (`/tmp` is a symlink on macOS).
  let root : @pathx.Path = Path(
    @fs.realpath(@fs.tmpdir(prefix="openseek-detach-idle-")),
  )
  defer @fs.rmdir(root.to_string(), recursive=true)
  let global_store = root.join("global")
  let workspace = root.join("workspace")
  let engine = root.join("bin/engine.sh")
  let runtime = root.join("runtime")
  let exited = root.join("writer-exited")
  @sys.set_env_var("HOME", global_store.to_string())
  defer restore_home_env(previous)
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
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then printf '%s' '{\"events\":[]}' ; exit 0; fi\nwhile IFS= read -r line; do\n\{commit_terminal_sh()}  printf '%s\\n' '{\"event\":\"agent_finished\",\"answer\":\"ok\"}'\ndone\nprintf '' > '\{exited}'\n",
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
      glm_api_key: None,
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
      thinking: None,
      max_steps: None,
      session: "s-detach-idle",
      workspace: Some(workspace.to_string()),
    })
    let run_id = reply.run_id
    assert_true(
      @async.with_timeout_opt(3000, () => {
        while !has_finished_run(events, run_id) {
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
      thinking: None,
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
      thinking: None,
      max_steps: None,
      workspace: None,
    }).contains("not supported yet"),
  )
}
