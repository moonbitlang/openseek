// The persistent-engine machinery: one `serve` process per conversation,
// owned by the `connect` op's task group, fed prompts over stdin and drained
// through a per-engine consumer that forwards events to the webview.

///|
/// A live `serve` engine process: one process serves every prompt of one
/// conversation. Prompts and cancels are JSONL commands on its stdin; its
/// stdout event stream is consumed for the engine's lifetime. Turns are
/// strictly sequential on the wire *per conversation*, so events are stamped
/// with the run id of the prompt this engine saw most recently.
///
/// A handle's identity IS its process: a respawn puts a fresh ServeEngine in
/// the same session slot, and a same-config successor is indistinguishable
/// by value (same `session_key`, same `spec_key`). Cleanup paths that may
/// run after a replacement — the reader's exit handler, a failed write —
/// therefore compare with `physical_equal` before clearing the slot, so a
/// dead engine's teardown can never evict its live successor.
priv struct ServeEngine {
  // The conversation this process serves: its slot in the manager's map.
  session_key : String
  // Canonical durable store selected from host-owned workspace state when
  // this process was spawned. Workspace detach uses this placement to close
  // idle writers before hiding their store, and to refuse while one is busy.
  session_root : @pathx.Absolute?
  // Fingerprint of the config this process was spawned with; a prompt whose
  // config differs cannot reuse it.
  spec_key : String
  // Owned exclusively by this engine's writer task. No request ever touches
  // it, which is what makes a partial JSONL frame impossible and stdin's
  // close a single-owner event.
  writer : @process.WriteToProcess
  // Every JSONL command shares one byte stream, so submission is a
  // synchronous handoff to that one writer rather than a lock a request holds
  // across its own write. Receipt order is enqueue order.
  commands : @async.Queue[EngineCommand]
  process : @process.Process
  sink : EventSink
  // Exact follower generation established for this writer. Cleanup never
  // performs a session-key lookup that could stop a successor generation.
  follower : SessionFollower?
  // This engine's stdout consumer. Its completion IS retirement: it publishes
  // every remaining lifecycle event, stops the owned follower and clears the
  // slot before returning, so waiting on this task is the successor-admission
  // barrier — no second hand-maintained flag needed to say the same thing.
  // None only between building the handle and spawning the task, which has no
  // suspension in it and so is unobservable to any request.
  mut consumer : @async.Task[Unit]?
  mut phase : EnginePhase
  // Wall-clock ms (`@async.now()`) when the current run was admitted —
  // stamped by `start_run` together with the Running flip. The follower's
  // durable close compares terminal record timestamps against it: a
  // terminal committed at or after admission can only belong to this run
  // (turns are strictly sequential, and admission requires the previous
  // terminal to have closed the phase first).
  mut run_admitted_ms : Int64
  // The cause a forced retirement should report instead of the generic
  // "engine exited without a result": stashed (first writer wins) by the
  // path that discovered the failure — a failed stdin write, a dead event
  // consumer — just before it kills the child, and read once by the EOF
  // retirement. Never a settlement itself: the one retirement on the
  // consumer task stays the only lifecycle closer for engine death.
  mut pending_failure : String?
  // Set once, by `condemn`, and never cleared. It is the whole of this
  // engine's death sentence: nothing more can be submitted, `SessionSlot::live`
  // stops offering it to requests, and the conversation's next turn must go to
  // a new process. The handle stays in its slot until EOF proves the child is
  // gone, so a start joins its close barrier instead of racing it.
  mut condemned : Bool
  steer_runs : SteerRunTracker
}

///|
/// Grace period for serve to honor stdin EOF, followed by the deadline for
/// its configured cancellation handler (SIGTERM, then a hard kill) and the
/// stdout consumer to observe/reap that exit.
const ServeCloseGraceMs = 2000

///|
const ServeCancelWaitMs = 3000

///|
/// Wait until this engine's child is reaped.
///
/// The process task is the latch, so there is no second one to publish: it is
/// level-triggered and multi-waiter, and a cancelled process task completes
/// only once its cancellation handler has seen the child actually terminate.
/// A failed or cancelled outcome is still termination, which is all a caller
/// of this waits to learn.
async fn ServeEngine::wait_process(self : ServeEngine) -> Unit {
  ignore(self.process.wait()) catch {
    _ => ()
  }
}

///|
/// Wait until this engine is fully retired: child reaped, follower drained,
/// lifecycle settled, slot cleared. A consumer that failed or was cancelled
/// is still finished, which is all a successor needs to know.
async fn ServeEngine::wait_retired(self : ServeEngine) -> Unit {
  guard self.consumer is Some(consumer) else { return }
  consumer.wait() catch {
    _ => ()
  }
}

///|
/// Ask a serve process to drain normally, but never let a wedged child pin
/// the pump or an archive forever.
///
/// Closing stdin is the engine's documented shutdown protocol: the running
/// work finishes first, then its loop drains and exits. Cancellation is only
/// the escalation for a child that will not honour it — `serve` installs no
/// signal handler, so a SIGTERM is a mid-turn death with no durable flush,
/// which is why this path exists rather than a bare `Process::cancel`.
///
/// Returning is the hard writer-and-event-lifetime barrier: the consumer this
/// waits on ends only after `Process::wait`, the owned follower's final scan,
/// and every terminal lifecycle notification from this engine.
async fn ServeEngine::close_and_wait(self : ServeEngine) -> Unit {
  // Commands already accepted are still the writer's to flush — that is what
  // asks it to close stdin — so this condemns without discarding.
  self.condemn()
  // The grace deadline includes the writer task finishing the commands it
  // already accepted and then closing stdin. Otherwise a backpressured write
  // could pin archive/replacement before their existing process-cancellation
  // fallback is even armed.
  if @async.with_timeout_opt(ServeCloseGraceMs, () => self.wait_process())
    is Some(_) {
    // The process deadline must not include the follower's O(history) final
    // scan. Once EOF is proved, wait for that correctness barrier without
    // misclassifying a long durable log as a wedged child.
    self.wait_retired()
    return
  }
  @xlog.warn() <?
    {
      "event": "desktop_engine_cancel",
      "reason": "graceful close timeout",
      "session": self.session_key,
      "pid": self.process.pid,
    }
  self.process.cancel()
  guard @async.with_timeout_opt(ServeCancelWaitMs, () => self.wait_process())
    is Some(_) else {
    raise EngineError("serve engine did not exit after cancellation")
  }
  self.wait_retired()
}

///|
/// One complete JSONL line for a serve engine's stdin, plus what to tell the
/// conversation if it never gets there.
priv struct EngineCommand {
  line : String
  failure_reason : String
  // Answered once this command's fate is decided: `None` when it reached
  // stdin, the reason otherwise.
  //
  // Only for senders that have no other way to learn it was dropped. A prompt
  // or a compaction is answered by its run's lifecycle events, and a steer by
  // its receipt or the run's durable recovery; a goal has nothing but the
  // durable `[goal]` marker, which would simply never appear.
  ack : @async.Queue[EngineError?]?
}

///|
/// Report this command's fate to a sender waiting for it. Synchronous and
/// total, so it is safe on a cancellation path, and harmless for the commands
/// that ask for no answer.
fn EngineCommand::settle(self : EngineCommand, outcome : EngineError?) -> Unit {
  guard self.ack is Some(ack) else { return }
  ignore(ack.try_put(outcome)) catch {
    _ => ()
  }
}

///|
/// Hand one command to this engine's writer.
///
/// Synchronous and total, which is the whole point: a request decides to
/// submit, mutates whatever public state the command implies, and announces
/// it, all without a suspension in between. There is therefore no window in
/// which the request can be cancelled after going public, and none in which
/// another request can interleave a command — so no lock, no re-validation
/// after waiting for one, and no cancellation-shielded rollback.
///
/// A sender may pass `ack` to learn whether its command actually reached
/// stdin; waiting on it is only safe for a command that made nothing public
/// first, which is exactly why prompts do not.
///
/// The closed queue is the refusal, not a second flag consulted beside it, so
/// there is no ordering to get wrong here: `condemn` closes it in one
/// synchronous step. False therefore means the engine was condemned between
/// the caller's own `SessionSlot::live` lookup and this call, which cannot
/// happen without an intervening suspension; it is reported rather than
/// asserted so a future caller with one is refused rather than silently
/// dropped.
fn ServeEngine::submit(
  self : ServeEngine,
  line : String,
  failure_reason~ : String,
  ack? : @async.Queue[EngineError?],
) -> Bool {
  self.commands.try_put({ line, failure_reason, ack }) catch {
    _ => false
  }
}

///|
/// Condemn this engine: nothing more may be submitted, and no request can find
/// it through its slot. One synchronous step, so a request cannot read the
/// slot as live and then enqueue behind this call. Commands already accepted
/// stay the writer's to flush; `discard_commands` is the variant that also
/// refuses them.
fn ServeEngine::condemn(self : ServeEngine) -> Unit {
  self.condemned = true
  self.commands.close()
}

///|
/// Condemn this engine and answer everything still queued: past this point
/// nothing in the queue can reach stdin. Synchronous, so it is safe on a
/// cancellation path, and idempotent, because a drained queue is empty.
fn ServeEngine::discard_commands(self : ServeEngine, reason : String) -> Unit {
  self.condemn()
  for ;; {
    let next = self.commands.try_get() catch { _ => break }
    guard next is Some(command) else { break }
    command.settle(Some(EngineError(reason)))
  }
}

///|
/// The engine's single writer, for the process's whole life.
///
/// Being the sole owner of stdin makes two things structural rather than
/// coordinated: commands cannot interleave into a partial frame, and stdin is
/// closed exactly once, on every path out of the loop. Callers ask for that
/// close by closing the command queue — `close_and_wait` lets the already
/// accepted commands drain first, the EOF consumer discards them.
async fn ServeEngine::write_commands(self : ServeEngine) -> Unit {
  // Whatever ends this task, cancellation included, no sender may be left
  // waiting for an answer that can no longer come.
  defer self.discard_commands(
    "the engine stopped before this command was written",
  )
  let mut failure : String? = None
  for ;; {
    let command = self.commands.get() catch { _ => break }
    self.writer.write(command.line) catch {
      error if @async.is_being_cancelled() => raise error
      error => {
        let reason = "\{command.failure_reason}: \{error}"
        command.settle(Some(EngineError(reason)))
        failure = Some(reason)
        break
      }
    }
    command.settle(None)
  }
  self.writer.close()
  if failure is Some(reason) {
    // Answer the queued senders right away: none of their commands can
    // reach stdin now, and the pipe may hold a partial JSONL frame, so this
    // handle is permanently unusable.
    self.discard_commands(reason)
    // No lifecycle settlement here — the one EOF retirement on the consumer
    // task remains the only closer for engine death, and it reports this
    // cause. That retirement fires when the reader sees the child exit, so
    // exit must be guaranteed. A write to a healthy child does not fail
    // (a full pipe blocks instead), so the dominant cause is EPIPE from a
    // child that is already dead — the grace reaps it instantly, no kill.
    // One still alive past the grace has broken its own stdin and ignored
    // the EOF close request: kill it, or the retirement — and the slot it
    // must clear — waits on a malfunctioning child indefinitely.
    if self.pending_failure is None {
      self.pending_failure = Some(reason)
    }
    if @async.with_timeout_opt(ServeCloseGraceMs, () => self.wait_process())
      is None {
      @xlog.warn() <?
        {
          "event": "desktop_engine_cancel",
          "reason": "failed command close timeout",
          "session": self.session_key,
          "pid": self.process.pid,
        }
      self.process.cancel()
    }
  }
}

///|
/// Whether this exact writer still owns its slot in the current pump epoch.
/// A request can find an engine, suspend on anything at all, and resume after
/// the pump has installed a successor under the same session key; a
/// same-config successor is indistinguishable by value, so identity is the
/// only safe commit-time check in that window.
fn ServeEngine::is_current(self : ServeEngine, manager : EngineManager) -> Bool {
  guard manager.pump is Serving(sessions~) &&
    sessions.get(self.session_key) is Some(slot) &&
    slot.live() is Some(current) else {
    return false
  }
  physical_equal(current, self)
}

///|
/// What the serve engine is doing right now, and which run it is doing it for
/// — one value instead of loose booleans beside a separate run id, so the
/// impossible combinations (a compaction with an open run, a cancel request
/// with nothing to cancel, an open turn whose id nobody recorded) cannot be
/// represented, and every operation names the phase it requires instead of
/// consulting fields that can drift apart across suspension points. The
/// steering bookkeeping stays in `SteerRunTracker`: steers deliberately settle
/// across a phase boundary.
///
/// The id rides along because every phase has something to say about it and
/// they do not agree on what. An open turn always has one — that used to be a
/// comment above an `if ... is Some(run)` that could not fail. A closed one
/// only has the run it last opened, which is still what a late diagnostic or a
/// compaction event should be stamped with.
priv enum EnginePhase {
  // Between turns; nothing is writing to the durable record. The only phase
  // that accepts a prompt, a compaction, or archiving. `last_run` is None
  // before this process's first prompt (a spawn for compaction, or events
  // arriving before any turn opened).
  Idle(last_run~ : String?)
  // A prompt's turn is open on the wire, under `run_id`. `cancel_requested`
  // marks that a cancel was sent (or must be re-sent once the racing prompt
  // lands). `compact_queued` marks a `/compact` accepted mid-turn: the command
  // sits in the serve engine's queue behind this run, so the turn's terminal
  // event must land in `Compacting`, not `Idle` — otherwise a prompt or an
  // archive slips into the gap before the engine's `compaction_started`
  // and the eventual `compaction_finished` would blindly idle it away.
  Running(run_id~ : String, cancel_requested~ : Bool, compact_queued~ : Bool)
  // A `/compact` is rewriting the durable record: no run is open, but
  // starts and archiving must wait. Entered by `compact_run` (idle send),
  // a run's terminal event with a compaction queued behind it, or the
  // engine's own `compaction_started`; left on
  // `compaction_finished`/`compaction_failed` — or on engine death, which
  // reports a synthetic failure so the frontend never sticks.
  Compacting(last_run~ : String?)
}

///|
/// The id of the run this engine saw most recently, open or already settled.
fn EnginePhase::latest_run(self : EnginePhase) -> String? {
  match self {
    Idle(last_run~) => last_run
    Compacting(last_run~) => last_run
    Running(run_id~, ..) => Some(run_id)
  }
}

///|
/// Between turns, still remembering the run this process last opened.
fn EnginePhase::to_idle(self : EnginePhase) -> EnginePhase {
  Idle(last_run=self.latest_run())
}

///|
/// The phase after a run's terminal event: straight into the compaction the
/// turn queued behind itself, otherwise back between turns. The engine starts
/// a queued compaction the moment the turn ends, so entering Compacting here
/// (rather than waiting for its `compaction_started`) closes the window where
/// a prompt or an archive could slip in ahead of it.
fn EnginePhase::after_run_close(self : EnginePhase) -> EnginePhase {
  if self is Running(compact_queued=true, ..) {
    Compacting(last_run=self.latest_run())
  } else {
    self.to_idle()
  }
}

///|
priv struct TrackedSteer {
  text : String
  submission_id : String?
}

///|
priv struct SteerRunTracker {
  mut settling_run : String?
  open_steers : Array[TrackedSteer]
  settling_steers : Array[TrackedSteer]
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
fn SteerRunTracker::record_sent(
  self : SteerRunTracker,
  text : String,
  submission_id : String?,
) -> TrackedSteer {
  let entry : TrackedSteer = { text, submission_id }
  self.open_steers.push(entry)
  entry
}

///|
fn SteerRunTracker::record_terminal(
  self : SteerRunTracker,
  run_id : String,
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
fn SteerRunTracker::route_event(
  self : SteerRunTracker,
  decoded : @event.AgentEvent?,
  prompt_steer_applied : Bool,
  latest_run : String?,
) -> (String?, String?) {
  match decoded {
    Some(SteerApplied(content)) if prompt_steer_applied =>
      self.route_receipt(content, latest_run)
    Some(SteerDropped(content)) => self.route_receipt(content, latest_run)
    // serve drains every old prompt receipt before beginning the next step.
    // AgentStep is therefore the explicit boundary after which an absent old
    // receipt must not steal an equal-text steer from the new run.
    Some(AgentStep) => {
      self.settling_run = None
      self.settling_steers.clear()
      (latest_run, None)
    }
    // Command/notice steer_applied events and unrelated background events may
    // be interleaved between prompt receipts while serve drains its old input
    // queue. They neither consume nor clear prompt correlation state.
    _ => (latest_run, None)
  }
}

///|
fn SteerRunTracker::route_receipt(
  self : SteerRunTracker,
  content : String,
  latest_run : String?,
) -> (String?, String?) {
  if take_first_tracked_steer(self.settling_steers, content) is Some(entry) {
    let run_id = self.settling_run
    if self.settling_steers.is_empty() {
      self.settling_run = None
    }
    if run_id is Some(_) {
      return (run_id, entry.submission_id)
    }
  }
  if take_first_tracked_steer(self.open_steers, content) is Some(entry) {
    return (latest_run, entry.submission_id)
  }
  (latest_run, None)
}

///|
fn take_first_tracked_steer(
  items : Array[TrackedSteer],
  text : String,
) -> TrackedSteer? {
  for index, entry in items {
    if entry.text == text {
      return Some(items.remove(index))
    }
  }
  None
}

///|
priv enum EngineActorCommand {
  // Replace the conversation's engine (if any) with one spawned for this
  // config; the queue carries the spawn failure — or None for success —
  // back to the requesting `start` op. The identity-bearing claim carries
  // both the pump epoch and exact slot ownership across every suspension.
  SpawnEngine(PendingClaim, RunConfig, @async.Queue[EngineError?])
}

///|
/// Lifecycle commands are rare (only a missing or incompatible per-session
/// engine spawns one), but the mailbox is bounded so stalled process teardown
/// can backpressure request tasks instead of growing the host indefinitely.
const EngineActorQueueSize = 64

///|
/// A serve process may briefly produce events faster than its sink can publish
/// them. Backpressure the process stdout at this bound; engine events are
/// lossless and therefore must never use a discard queue.
const EngineStreamQueueSize = 256

///|
/// Delay before starting a fresh process-owning generation after an
/// unexpected actor failure.
const EngineActorRestartDelayMs = 1000

///|
/// An operation holding a conversation's slot between config validation and
/// its command hitting the wire. A second slot-holding op in that window is
/// refused up front instead of racing the first one's spawn or preempting
/// the phase it is about to enter.
priv enum PendingOp {
  StartPending
  CompactPending
  GoalPending
  ArchivePending
}

///|
/// Identity-bearing ownership of one per-pump slot. The sessions map is the
/// pump generation; a claim from an old map cannot authorize work in a new
/// host generation, and identity-scoped release cannot clear another op.
priv struct PendingClaim {
  epoch : Map[String, SessionSlot]
  session_key : String
  op : PendingOp
  mut active : Bool
}

///|
/// Everything the host tracks for one conversation, in one place. Both
/// fields are optional and every combination is legal — no engine yet, an
/// op preparing to spawn one, a live engine idle or mid-turn, an op
/// preparing on a live engine — but keeping them in a single slot means an
/// op cannot look up the engine without the pending claim being in view:
/// the compact-preempts-starting-prompt race came from exactly that split
/// (a pending-starts set beside the engines map, one checked, one missed).
priv struct SessionSlot {
  mut pending : PendingClaim?
  mut engine : ServeEngine?
}

///|
/// The engine a request may be given work: present, and not condemned.
///
/// Every request path goes through this instead of reading `engine` directly,
/// which is what makes "a condemned engine serves no further work" a property
/// of the lookup rather than a check each of half a dozen callers has to
/// remember. A late write from a condemned engine is harmless for the same
/// one-step reason: nothing can be routed to it any more.
///
/// Lifecycle paths deliberately read `engine` instead — a drain, a
/// replacement, or a post-EOF identity check must still see the condemned
/// handle, because joining its close barrier is the whole point.
fn SessionSlot::live(self : SessionSlot) -> ServeEngine? {
  guard self.engine is Some(engine) && !engine.condemned else { return None }
  Some(engine)
}

///|
/// Claim the slot for `op`, refusing when another op already holds it.
fn SessionSlot::claim(
  self : SessionSlot,
  epoch : Map[String, SessionSlot],
  session_key : String,
  op : PendingOp,
) -> PendingClaim raise EngineError {
  if self.pending is Some(current) {
    raise EngineError(
      match current.op {
        StartPending =>
          "an OpenSeek run is already starting for this conversation"
        CompactPending =>
          "a compaction is already being requested for this conversation"
        GoalPending =>
          "a goal update is already being sent for this conversation"
        ArchivePending =>
          "this conversation is moving between live and archived stores"
      },
    )
  }
  let claim : PendingClaim = { epoch, session_key, op, active: true }
  self.pending = Some(claim)
  claim
}

///|
fn PendingClaim::is_current(
  self : PendingClaim,
  manager : EngineManager,
) -> Bool {
  guard self.active &&
    manager.pump is Serving(sessions=current_epoch) &&
    physical_equal(current_epoch, self.epoch) &&
    self.epoch.get(self.session_key) is Some(slot) &&
    slot.pending is Some(current) else {
    return false
  }
  physical_equal(current, self)
}

///|
fn PendingClaim::require_current(
  self : PendingClaim,
  manager : EngineManager,
) -> Unit raise EngineError {
  guard self.is_current(manager) else {
    raise EngineError("engine host restarted while the operation was pending")
  }
}

///|
fn PendingClaim::release(self : PendingClaim, manager : EngineManager) -> Unit {
  self.active = false
  if self.epoch.get(self.session_key) is Some(slot) &&
    slot.pending is Some(current) &&
    physical_equal(current, self) {
    slot.pending = None
  }
  manager.prune_slot(self.session_key)
}

///|
/// Persistent record arbitration lives outside PumpState, so readers and
/// mutations remain mutually visible while the process pump is restarting.
/// Loads share the reader side; start/compact hold `active_ops`; a record move
/// sets `moving` first, blocking newcomers, then waits for both counts to
/// reach zero.
priv struct SessionRecordGuard {
  mut readers : Int
  mut active_ops : Int
  mut moving : Bool
}

///|
/// Whether the pump is serving, and the per-conversation slots while it is.
/// The slots live inside the state, so an engine cannot exist without a
/// running pump — stopping the pump drops them wholesale, which is the old
/// `reset()` without the by-hand invariant.
priv enum PumpState {
  Stopped
  Serving(sessions~ : Map[String, SessionSlot])
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
  runtime_dir : @pathx.Path?
  // Serializes the short placement/slot-claim phase of every operation that
  // can create or move a workspace-backed record with workspace detach.
  // Once a claim is visible, detach refuses it; once a run/compaction is
  // visible in the engine phase, detach refuses that instead. This closes the
  // gap where the registry could disappear after validation but before the
  // writer became observable, without serializing whole turns or sessions.
  workspace_lifecycle_lock : @async.Mutex
  // Serializes publication and physical removal of durable records under
  // `archived/deleting`. A foreground delete and startup/list recovery may
  // discover the same pending directory; only one may advance or erase it.
  archive_cleanup_lock : @async.Mutex
  // Host-owned endpoint settings are a read-modify-write store shared by
  // every client. The lock covers reads too: on Windows the atomic-save
  // fallback briefly removes the target before renaming the complete temp
  // file into place, and a concurrent run configuration must not mistake
  // that internal window for an empty settings store.
  settings_lock : @async.Mutex
  // Connection-visible ordering for successful settings mutations. This is
  // deliberately process-local: BridgeReady starts a fresh revision epoch
  // after a host restart, while the credential file's v1 format stays
  // unchanged.
  mut settings_revision : Int
  commands : @async.Queue[EngineActorCommand]
  mut pump : PumpState
  // Record arbitration must survive pump replacement: a load started under
  // generation A is still a reader that generation B's archive must await.
  record_guards : Map[String, SessionRecordGuard]
  // One session follower per conversation with a live desktop-managed
  // writer, keyed by session id — the canonical `session.event` broadcaster
  // (see follower.mbt). Entries are installed by the spawn path and remove
  // themselves when their actor retires; stopping the pump clears the map
  // wholesale (the group's cancellation kills the actors without their
  // self-removal running).
  followers : Map[String, SessionFollower]
}

///|
/// App-lifetime owner of every desktop-managed engine process. Request tasks
/// collaborate through `manager`; only `run` creates the structured task
/// group that owns serve processes and their follower actors.
struct EngineActor {
  manager : EngineManager
}

///|
fn EngineManager::record_guard(
  self : EngineManager,
  session : String,
) -> SessionRecordGuard {
  if self.record_guards.get(session) is Some(state) {
    state
  } else {
    let state : SessionRecordGuard = {
      readers: 0,
      active_ops: 0,
      moving: false,
    }
    self.record_guards[session] = state
    state
  }
}

///|
fn EngineManager::prune_record_guard(
  self : EngineManager,
  session : String,
  state : SessionRecordGuard,
) -> Unit {
  if state.readers == 0 &&
    state.active_ops == 0 &&
    !state.moving &&
    self.record_guards.get(session) is Some(current) &&
    physical_equal(current, state) {
    self.record_guards.remove(session)
  }
}

///|
fn EngineManager::begin_record_read(
  self : EngineManager,
  session : String,
) -> SessionRecordGuard raise EngineError {
  let state = self.record_guard(session)
  if state.moving {
    self.prune_record_guard(session, state)
    raise EngineError(
      "this conversation is moving between live and archived stores",
    )
  }
  state.readers = state.readers + 1
  state
}

///|
fn EngineManager::end_record_read(
  self : EngineManager,
  session : String,
  state : SessionRecordGuard,
) -> Unit {
  state.readers = state.readers - 1
  self.prune_record_guard(session, state)
}

///|
fn EngineManager::begin_record_op(
  self : EngineManager,
  session : String,
) -> SessionRecordGuard raise EngineError {
  let state = self.record_guard(session)
  if state.moving || state.active_ops > 0 {
    self.prune_record_guard(session, state)
    raise EngineError(
      if state.moving {
        "this conversation is moving between live and archived stores"
      } else {
        "another operation is already preparing this conversation"
      },
    )
  }
  state.active_ops = state.active_ops + 1
  state
}

///|
fn EngineManager::end_record_op(
  self : EngineManager,
  session : String,
  state : SessionRecordGuard,
) -> Unit {
  state.active_ops = state.active_ops - 1
  self.prune_record_guard(session, state)
}

///|
fn EngineManager::claim_record_move(
  self : EngineManager,
  session : String,
) -> SessionRecordGuard raise EngineError {
  let state = self.record_guard(session)
  if state.moving {
    self.prune_record_guard(session, state)
    raise EngineError(
      "this conversation is already moving between live and archived stores",
    )
  }
  state.moving = true
  state
}

///|
async fn SessionRecordGuard::wait_until_idle(self : SessionRecordGuard) -> Unit {
  while self.readers > 0 || self.active_ops > 0 {
    @async.sleep(10)
  }
}

///|
fn EngineManager::release_record_move(
  self : EngineManager,
  session : String,
  state : SessionRecordGuard,
) -> Unit {
  state.moving = false
  self.prune_record_guard(session, state)
}

///|
/// The live sessions table; every op starts here, so a stopped pump answers
/// with the same message everywhere.
fn EngineManager::serving(
  self : EngineManager,
) -> Map[String, SessionSlot] raise EngineError {
  guard self.pump is Serving(sessions~) else {
    raise EngineError("engine host is not connected; reload the app")
  }
  sessions
}

///|
/// The three host facts a worktree lifecycle operation needs, handed to the
/// worktree package as one value. Everything else about a checkout — the
/// registry, git, the placement rules — is that package's own business, and
/// nothing there may reach into the pump.
pub fn EngineManager::worktree_host(
  self : EngineManager,
) -> @worktree.WorktreeHost {
  {
    lifecycle_lock: self.workspace_lifecycle_lock,
    session_is_live: session => {
      self.pump is Serving(sessions~) && sessions.get(session) is Some(_)
    },
    drain_sessions: sessions => self.close_engines_for_sessions(sessions),
  }
}

///|
/// This conversation's slot, created empty on first touch.
fn slot_for(sessions : Map[String, SessionSlot], key : String) -> SessionSlot {
  if sessions.get(key) is Some(slot) {
    slot
  } else {
    let slot : SessionSlot = { pending: None, engine: None }
    sessions.set(key, slot)
    slot
  }
}

///|
/// Drop a slot that carries nothing anymore, so abandoned conversations do
/// not accumulate empty entries.
fn EngineManager::prune_slot(self : EngineManager, key : String) -> Unit {
  if self.pump is Serving(sessions~) &&
    sessions.get(key) is Some(slot) &&
    slot.pending is None &&
    slot.engine is None {
    sessions.remove(key)
  }
}

///|
/// Make a workspace safe to remove from the host registry. Callers hold
/// `workspace_lifecycle_lock`, so no new start/compact/archive claim can
/// appear between this scan and the registry commit. A pending operation is
/// refused conservatively even when its record belongs elsewhere: a new
/// session has no durable path to classify until that operation commits its
/// host-validated configuration. Busy writers are never detached; idle ones
/// receive EOF and join their follower's final durable scan first.
async fn EngineManager::close_engines_for_workspace(
  self : EngineManager,
  workspace : @pathx.Absolute,
) -> Unit {
  guard self.pump is Serving(sessions~) else { return }
  let root = @workspaces.store_root(workspace).to_string()
  let idle : Array[ServeEngine] = []
  for _, slot in sessions {
    if slot.pending is Some(_) {
      raise EngineError(
        "another conversation operation is still being prepared; wait for it to finish",
      )
    }
    if slot.engine is Some(engine) &&
      engine.session_root is Some(session_root) &&
      session_root.to_string() == root {
      match engine.phase {
        Running(..) =>
          raise EngineError(
            "a conversation in this workspace is still running; stop it first",
          )
        Compacting(..) =>
          raise EngineError(
            "a conversation in this workspace is compacting; wait for it to finish",
          )
        Idle(..) => idle.push(engine)
      }
    }
  }
  for engine in idle {
    engine.close_and_wait()
    // EOF cleanup deliberately keeps a follower alive when its final scan
    // fails, so another lifecycle operation can retry instead of pretending
    // the durable tail was drained. Join that exact generation once more and
    // propagate a repeated failure: hiding the workspace while its actor is
    // still rooted there would leave a permanent orphan watcher.
    if engine.follower is Some(follower) {
      stop_follower_instance(self, follower, writer_exited=true)
    }
  }
  // An abrupt EOF removes its dead ServeEngine after publishing lifecycle,
  // even when the final durable scan failed. The retryable follower then has
  // no slot owner for the idle-engine pass above to discover. Drain every
  // exact follower still rooted in this workspace before the registry commit;
  // replacement/start cannot install another one while the lifecycle lock is
  // held, and identity checks make already-retired captures harmless.
  let retained : Array[SessionFollower] = []
  for _, follower in self.followers {
    if follower.root.to_string() == root {
      retained.push(follower)
    }
  }
  for follower in retained {
    stop_follower_instance(self, follower, writer_exited=true)
  }
}

///|
/// `close_engines_for_workspace` narrowed to the given session ids: the
/// drain a worktree removal runs over the entry's mapped conversations,
/// whose idle serve processes still have their cwd inside the directory
/// being deleted. Callers hold `workspace_lifecycle_lock`, so no new
/// start/compact claim can appear between this scan and the registry
/// commit. A pending operation or a busy engine is refused; idle writers
/// receive EOF and join their follower's final durable scan.
async fn EngineManager::close_engines_for_sessions(
  self : EngineManager,
  ids : Array[String],
) -> Unit {
  guard self.pump is Serving(sessions~) else { return }
  let idle : Array[ServeEngine] = []
  for id in ids {
    guard sessions.get(id) is Some(slot) else { continue }
    if slot.pending is Some(_) {
      raise EngineError(
        "another conversation operation is still being prepared; wait for it to finish",
      )
    }
    if slot.engine is Some(engine) {
      match engine.phase {
        Running(..) =>
          raise EngineError(
            "a conversation in this worktree is still running; stop it first",
          )
        Compacting(..) =>
          raise EngineError(
            "a conversation in this worktree is compacting; wait for it to finish",
          )
        Idle(..) => idle.push(engine)
      }
    }
  }
  for engine in idle {
    engine.close_and_wait()
    if engine.follower is Some(follower) {
      stop_follower_instance(self, follower, writer_exited=true)
    }
  }
  // As in the workspace drain: an abrupt EOF can retire the ServeEngine
  // while a retryable follower stays rooted in the store, with no slot owner
  // for the idle-engine pass above to discover. Followers are keyed by
  // session id, so the mapped ids find them directly.
  for id in ids {
    if self.followers.get(id) is Some(follower) {
      stop_follower_instance(self, follower, writer_exited=true)
    }
  }
}

///|
priv enum StreamMessage {
  StreamEvent(DecodedStreamEvent)
  StreamReaderFailed(String)
  StreamExited(Int)
}

///|
/// One engine JSONL event after the process adapter has extracted every fact
/// the actor needs. Keeping the raw JSON out of `StreamMessage` makes the
/// reader/actor channel typed without losing legacy lifecycle normalization.
priv struct DecodedStreamEvent {
  legacy : @event.AgentEvent?
  wire : @wire.Event?
  prompt_steer_applied : Bool
  needs_durable_scan : Bool
}

///|
fn DecodedStreamEvent::from_wire(raw : Json) -> DecodedStreamEvent {
  let (prompt_steer_applied, needs_durable_scan) = match raw {
    Object(fields) => {
      let prompt_steer_applied = match fields.get("kind") {
        None | Some(String("prompt")) => true
        _ => false
      }
      let needs_durable_scan = match fields.get("event") {
        Some(String(name)) =>
          name == "agent_setup_failed" ||
          name == "turn_failed" ||
          name == "agent_aborted"
        _ => false
      }
      (prompt_steer_applied, needs_durable_scan)
    }
    _ => (false, false)
  }
  {
    legacy: @event.decode_event(raw),
    wire: @wire.parse(raw),
    prompt_steer_applied,
    needs_durable_scan,
  }
}

///|
fn new_engine_manager(
  engine : String,
  runtime_dir? : @pathx.Path,
) -> EngineManager {
  {
    engine,
    runtime_dir,
    workspace_lifecycle_lock: Mutex(),
    archive_cleanup_lock: Mutex(),
    settings_lock: Mutex(),
    settings_revision: 0,
    commands: Queue(kind=Blocking(EngineActorQueueSize)),
    pump: Stopped,
    record_guards: Map([]),
    followers: Map([]),
  }
}

///|
pub fn new_engine_actor(
  engine : String,
  runtime_dir? : @pathx.Path,
) -> EngineActor {
  { manager: new_engine_manager(engine, runtime_dir?) }
}

///|
/// The request-side coordination handle belonging to this actor.
pub fn EngineActor::manager(self : EngineActor) -> EngineManager {
  self.manager
}

///|
/// The engine that owns the open run `run_id` — or, when no id is given, the
/// only open run if exactly one exists (with several conversations running
/// concurrently, an unaddressed cancel/steer would be a guess).
fn open_run_engine(manager : EngineManager, run_id? : String) -> ServeEngine? {
  guard manager.pump is Serving(sessions~) else { return None }
  if run_id is Some(id) {
    for _, slot in sessions {
      if slot.live() is Some(engine) &&
        engine.phase is Running(run_id~, ..) &&
        run_id == id {
        return Some(engine)
      }
    }
    return None
  }
  let mut found : ServeEngine? = None
  for _, slot in sessions {
    if slot.live() is Some(engine) && engine.phase is Running(..) {
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
  runtime_dir : @pathx.Path?,
  engine : @pathx.Path,
) -> &@process.ProcessInput {
  let path = if runtime_dir is Some(dir) {
    dir.join("engine.stdin")
  } else {
    "\{engine}.stdin"
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
  try {
    for ;; {
      guard reader.read_until("\n") is Some(line) else { break }
      for json in @jsonl.parse(line) {
        messages.put(StreamEvent(DecodedStreamEvent::from_wire(json)))
      }
    }
  } catch {
    error if @async.is_being_cancelled() => raise error
    _ => {
      messages.put(StreamReaderFailed("engine wrote malformed JSONL"))
      @xlog.warn() <?
        {
          "event": "desktop_engine_cancel",
          "reason": "malformed stdout JSONL",
          "pid": process.pid,
        }
      process.cancel()
    }
  }
  reader.close()
  // A lifecycle timeout cancels the Process task. Its cancellation handler
  // does not finish until the child has actually terminated, but the task's
  // result is `Cancelled` rather than an exit code; normalize that reaped
  // outcome to -1 so the consumer can still publish the EOF latch.
  let code = process.wait() catch {
    error if @async.is_being_cancelled() => raise error
    _ => -1
  }
  messages.put(StreamExited(code))
}

///|
/// The terminal-class stream events whose raw forwarding is suppressed: the
/// follower's durable close publishes the run's one Error/Finished pair, so
/// forwarding these as raw events too would render the same failure twice.
fn host_reports_terminal_error(decoded : @event.AgentEvent) -> Bool {
  match decoded {
    AgentAborted(_) | MaxStepsExhausted | AgentError(_) => true
    _ => false
  }
}

///|
/// Run the engine actor for the app lifetime. A failed process-owning
/// generation is reported through `on_failed`, then restarted after a short
/// delay. Closing the app cancels this task, which tears down every child
/// serve process and follower before the actor returns.
pub async fn EngineActor::run(
  self : EngineActor,
  sink : EventSink,
  on_failed : (String) -> Unit,
) -> Unit {
  defer {
    // Refuse a producer that was backpressured on the bounded lifecycle
    // mailbox, then settle every command that was accepted before closure.
    self.manager.commands.close()
    reset_engine_generation(self.manager, Ref(None))
  }
  for ;; {
    let _ = self.run_generation(sink) catch {
      error if @async.is_being_cancelled() => raise error
      error => {
        on_failed("engine host failed: \{error}")
        @async.sleep(EngineActorRestartDelayMs)
        continue
      }
    }
    @async.sleep(EngineActorRestartDelayMs)
  }
}

///|
/// One process-owning generation of the engine actor. All children are scoped
/// to this task group; reset publishes `Stopped` only after they have unwound.
async fn EngineActor::run_generation(
  self : EngineActor,
  sink : EventSink,
) -> Unit {
  let manager = self.manager
  guard manager.pump is Stopped else {
    raise EngineError("engine host is already connected")
  }
  let sessions : Map[String, SessionSlot] = Map([])
  // The pump handles one spawn command at a time. If teardown cancels the
  // current handler, its ack stays here until the process task group has
  // completely unwound; only then may the requesting op release its slot
  // claim. Queued commands are failed by the same reset path.
  let active_spawn : Ref[@async.Queue[EngineError?]?] = Ref(None)
  fn reset() -> Unit {
    reset_engine_generation(manager, active_spawn)
  }

  manager.pump = Serving(sessions~)
  defer reset()
  emit(sink, Connected({ stage: Serving }))
  @async.with_task_group(group => {
    // A permanent deletion whose physical cleanup failed or was interrupted
    // leaves its condemned records under `archived/deleting`. Erase them once
    // per generation; anything this pass misses waits for the next one.
    group.spawn_bg(allow_failure=true, () => manager.sweep_archived_deletions())
    for ;; {
      match manager.commands.get() {
        SpawnEngine(claim, config, ack) => {
          active_spawn.val = Some(ack)
          let reply = handle_spawn_command(
            sink~,
            group~,
            manager~,
            sessions~,
            claim~,
            config~,
          )
          // Clearing ownership and waking the requester are synchronous: a
          // cancellation cannot land between them and make reset reply twice.
          active_spawn.val = None
          ignore(try! ack.try_put(reply))
        }
      }
    }
  })
}

///|
/// Reset is called only after the pump task group (serve processes and
/// followers included) has fully terminated. Publish Stopped first, then wake
/// the shielded current requester and every queued requester with an error;
/// draining the cross-reconnect queue also prevents a successor pump from
/// executing commands prepared against the departed sessions map.
fn reset_engine_generation(
  manager : EngineManager,
  active_spawn : Ref[@async.Queue[EngineError?]?],
) -> Unit {
  manager.pump = Stopped
  let stopped = Some(EngineError("engine host stopped before spawn completed"))
  if active_spawn.val is Some(ack) {
    ignore(try! ack.try_put(stopped))
    active_spawn.val = None
  }
  while (manager.commands.try_get() catch { _ => None })
        is Some(SpawnEngine(_, _, ack)) {
    ignore(try! ack.try_put(stopped))
  }
  // Actor defers normally retire themselves. Defensively retire any identity
  // still present so queued/in-flight load callers are answered and both
  // control queues close before a successor pump starts.
  let followers : Array[SessionFollower] = []
  for _, follower in manager.followers {
    followers.push(follower)
  }
  for follower in followers {
    retire_follower_actor(manager, follower)
  }
}

///|
/// Install one spawn request without touching its ack. The caller owns ack
/// completion so cancellation can defer it until the entire pump task group
/// has unwound; ordinary success/failure replies immediately.
async fn[G] handle_spawn_command(
  sink~ : EventSink,
  group~ : @async.TaskGroup[G],
  manager~ : EngineManager,
  sessions~ : Map[String, SessionSlot],
  claim~ : PendingClaim,
  config~ : RunConfig,
) -> EngineError? {
  guard claim.is_current(manager) && physical_equal(claim.epoch, sessions) else {
    return Some(EngineError("spawn request belongs to a departed engine host"))
  }
  // Only this conversation's previous process is replaced; engines serving
  // other sessions keep running their own turns.
  let slot = slot_for(sessions, config.session)
  if slot.engine is Some(old) {
    // Closing stdin requests EOF; do not overlap the old writer with its
    // replacement. Its consumer clears the slot before publishing `exited`.
    old.close_and_wait() catch {
      error if @async.is_being_cancelled() => raise error
      error => {
        manager.prune_slot(config.session)
        return Some(EngineError("failed to stop old engine: \{error}"))
      }
    }
    guard claim.is_current(manager) else {
      return Some(EngineError("engine host restarted while replacing engine"))
    }
  }
  // The EOF consumer starts follower retirement independently, but
  // replacement must join that exact drain before initializing the successor,
  // even when both roots match. This makes one writer plus one follower
  // generation the indivisible lifecycle unit.
  stop_follower(manager, config.session, writer_exited=true) catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      manager.prune_slot(config.session)
      return Some(EngineError("failed to start engine: \{error}"))
    }
  }
  guard claim.is_current(manager) else {
    return Some(EngineError("engine host restarted while starting engine"))
  }
  start_serve_engine(sink~, group~, manager~, slot~, config~) catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      manager.prune_slot(config.session)
      return Some(EngineError("failed to start engine: \{error}"))
    }
  }
  guard claim.is_current(manager) && slot.live() is Some(_) else {
    return Some(EngineError("engine host restarted before engine commit"))
  }
  None
}

///|
/// The desktop host owns the Skills panel's library writes, so every serve
/// engine gets the same resolved global library instead of falling back to
/// whatever HOME means inside that engine host.
fn resolved_global_skills_dir() -> @pathx.Path? {
  if @env.get("OPENSEEK_GLOBAL_SKILLS_DIR") is Some(dir) {
    return Some(Path(dir))
  }
  if @home.dir() is Some(dir) {
    return Some(dir.join(".openseek/skills"))
  }
  None
}

///|
fn first_path_entry(path : String?) -> String {
  guard path is Some(path) else { return "" }
  match [..path.split(@env.path_sep)] {
    [first, ..] => first.to_owned()
    [] => ""
  }
}

///|
/// The environment block's path variable, whatever its spelling — Windows
/// blocks commonly carry `Path`, which `@sys.get_env_vars` preserves.
fn path_env_value(env : Map[String, String]) -> String? {
  for name, value in env {
    if name.to_upper() == "PATH" {
      return Some(value)
    }
  }
  None
}

///|
async fn add_moonbit_path_for_native_engine(
  env : Map[String, String],
  config : RunConfig,
  runtime_dir : @pathx.Path?,
) -> Unit {
  // The agent tools spawn `moon` by name, so prepend the resolved toolchain's
  // bin to the path variable (updating `Path` in place on Windows — see
  // `@env.prepend_path_entry`). `MOON_HOME` passes through untouched: moon
  // finds its compiler assets relative to its own executable, and the
  // variable's actual cargo — registry credentials and caches — must keep
  // working (`moon publish`) inside spawned sessions.
  // An unavailable toolchain fails the spawn: a session whose `moon` would
  // break in confusing ways downstream is worth less than a clear error
  // naming the cause now.
  let toolchain = @moonbit.resolve_toolchain(config.engine, runtime_dir?)
  toolchain.apply_to_env(env)
  @xlog.debug() <?
    {
      "event": "desktop_engine_moonbit_path",
      "bin_dir": toolchain.bin_dir.to_string(),
      "path_prefix": first_path_entry(path_env_value(env)),
    }
}

///|
async fn engine_process_env(
  config : RunConfig,
  runtime_dir : @pathx.Path?,
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
  // Desktop engines always run in durable-session mode, so the conversation
  // survives the process and is shared with the CLI/TUI.
  env["OPENSEEK_SESSION"] = config.session
  if config.session_root is Some(root) {
    env["OPENSEEK_SESSION_ROOT"] = root.to_string()
  } else {
    env.remove("OPENSEEK_SESSION_ROOT")
  }
  add_moonbit_path_for_native_engine(env, config, runtime_dir)
  env
}

///|
/// Spawn one `serve` engine inside the pump's task group and wire up its
/// stream tasks: the stdout reader feeding the queue, the stderr drain, and
/// the consumer that forwards events to the webview for the engine's
/// lifetime.
async fn[G] start_serve_engine(
  sink~ : EventSink,
  group~ : @async.TaskGroup[G],
  manager~ : EngineManager,
  slot~ : SessionSlot,
  config~ : RunConfig,
) -> Unit {
  // Establish and baseline the follower before a child can exist. If this
  // fails (including a wrong-root predecessor whose final drain failed),
  // there is no process to leak and no new writer can overlap the old root.
  let startup_follower = ensure_follower(sink~, group~, manager~, config~)
  let engine_follower = manager.followers.get(config.session)
  let mut startup_engine : ServeEngine? = None
  let mut startup_committed = false
  // Everything through scheduling both stream tasks is one initialization
  // transaction. This synchronous identity-scoped rollback also runs when
  // cancellation lands in environment preparation or process spawn; it
  // never waits on an actor in the task group being cancelled.
  defer (if !startup_committed {
    if startup_engine is Some(engine) {
      // Nothing was admitted yet; the writer task closes stdin on its way out.
      engine.discard_commands("the engine failed to start")
      @xlog.debug() <?
        {
          "event": "desktop_engine_cancel",
          "reason": "startup rollback",
          "session": engine.session_key,
          "pid": engine.process.pid,
        }
      engine.process.cancel()
      if slot.engine is Some(current) && physical_equal(current, engine) {
        slot.engine = None
        manager.prune_slot(engine.session_key)
      }
    }
    if startup_follower is Some(follower) {
      discard_follower_startup(manager, follower)
    }
  })
  let (child_stdin, writer) = @process.write_to_process()
  let (reader, child_stdout) = @process.read_from_process()
  let (stderr_reader, child_stderr) = @process.read_from_process()
  let env = engine_process_env(config, manager.runtime_dir)
  let program = config.engine
  let args = ["serve", "--dir", "."]
  let graceful_cancel = @process.graceful_cancel(timeout=1000)
  @xlog.debug() <?
    {
      "event": "desktop_engine_spawn",
      "program": program,
      "cwd": config.cwd.map(cwd => cwd.to_string()).unwrap_or(""),
      "session_key": config.session,
      "runtime_dir": manager.runtime_dir
      .map(dir => dir.to_string())
      .unwrap_or(""),
      "path_prefix": first_path_entry(path_env_value(env)),
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
    cwd?=config.cwd.map(cwd => cwd.to_string().view()),
    // The GUI-subsystem host has no console, so a console-subsystem child
    // would otherwise open its own visible conhost window on Windows.
    no_console_window=true,
    cancel_handler=CancellationHandler(pid => {
      @xlog.warn() <?
        {
          "event": "desktop_engine_process_task_cancelled",
          "session_key": config.session,
          "pid": pid,
        }
      graceful_cancel(pid)
    }),
    no_wait=true,
  )
  @xlog.info() <?
    {
      "event": "desktop_engine_spawned",
      "program": program,
      "session_key": config.session,
      "pid": process.pid,
    }
  let engine : ServeEngine = {
    session_key: config.session,
    session_root: config.session_root,
    spec_key: engine_fingerprint(config),
    writer,
    // Unbounded because submission must never block: a request that could be
    // parked here would be cancellable after it has already gone public,
    // which is exactly the window this shape exists to remove. A child that
    // stops reading is bounded by the close/cancel deadlines instead.
    commands: Queue(kind=Unbounded),
    process,
    sink,
    follower: engine_follower,
    consumer: None,
    phase: Idle(last_run=None),
    run_admitted_ms: 0,
    pending_failure: None,
    condemned: false,
    steer_runs: SteerRunTracker::new(),
  }
  startup_engine = Some(engine)
  // Spawned before the handle is reachable from any request, so stdin has an
  // owner for the engine's whole life — including a rollback, which asks for
  // the close by clearing the queue rather than touching the writer.
  group.spawn_bg(no_wait=true, allow_failure=true, () => engine.write_commands())
  slot.engine = Some(engine)
  let messages : @async.Queue[StreamMessage] = Queue(
    kind=Blocking(EngineStreamQueueSize),
  )
  let stderr_task = group.spawn(no_wait=true) <| () => {
    stderr_reader.read_all().text() catch {
      error if @async.is_being_cancelled() => raise error
      _ => ""
    }
  }
  group.spawn_bg(no_wait=true, allow_failure=true, () => {
    read_engine_stdout(reader, process, messages)
  })
  // Kept as a handle, not a background task: everything that waits for this
  // engine to be retired waits for exactly this task to end.
  engine.consumer = Some(
    group.spawn(no_wait=true, allow_failure=true, () => {
      engine.run(manager, messages, stderr_task)
    }),
  )
  startup_committed = true
}

///|
/// Consume one engine's event stream for its whole lifetime: forward every
/// raw event to the webview stamped with the engine's current run, and
/// report a mid-turn death as that run's failure. Runs until the engine's
/// stdout reader sees EOF. Terminal events close nothing here — the durable
/// record is the close authority, read by the session follower
/// (`close_run_from_terminal` in follower.mbt).
///
/// The consumer is spawned with `allow_failure`, so an error escaping it
/// would otherwise vanish without a trace. Any non-cancellation failure
/// therefore becomes a forced retirement here: the child is killed and the
/// retirement's final durable scan settles the open run — with the record's
/// real outcome when the turn actually ended, as a synthetic failure only
/// when no Terminal was ever committed — plus a log line naming the error
/// the spawn would have swallowed.
async fn ServeEngine::run(
  self : ServeEngine,
  manager : EngineManager,
  messages : @async.Queue[StreamMessage],
  stderr_task : @async.Task[String],
) -> Unit {
  let code = self.consume(manager, messages) catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      @xlog.error() <?
        {
          "event": "desktop_engine_consumer_failed",
          "session": self.session_key,
          "pid": self.process.pid,
          "run_id": self.phase.latest_run().unwrap_or(""),
          "error": "\{error}",
        }
      // The child may be healthy, but its events no longer have a consumer;
      // kill it so the retirement below reaps a real exit instead of leaving
      // an orphan serve process writing into a pipe nobody reads.
      @xlog.warn() <?
        {
          "event": "desktop_engine_cancel",
          "reason": "event consumer failed",
          "pid": self.process.pid,
        }
      self.process.cancel()
      // A wait that errors yields no status; absence stays absent rather
      // than becoming a fabricated exit code downstream.
      let code : Int? = try self.process.wait() catch {
        error if @async.is_being_cancelled() => raise error
        _ => None
      } noraise {
        code => Some(code)
      }
      if self.pending_failure is None {
        self.pending_failure = Some(
          "the engine's event consumer failed: \{error}",
        )
      }
      self.retire(manager, stderr_task, code?)
      return
    }
  }
  self.retire(manager, stderr_task, code~)
}

///|
/// The event pump half of `run`: drain the reader's messages until EOF and
/// hand back the child's exit code. The transitions that remain here
/// (compaction phase flips, admission cutoff on unproven-append events) stay
/// synchronous with the events that cause them, while retirement belongs to
/// `run`, so a pump that dies mid-stream still retires exactly once.
async fn ServeEngine::consume(
  self : ServeEngine,
  manager : EngineManager,
  messages : @async.Queue[StreamMessage],
) -> Int {
  let engine = self
  let sink = self.sink
  // Sub-run probes are children of this consumer: one per running child,
  // spawned at its `subrun_started` bracket and cancelled at the finish.
  // `no_wait` makes the engine's own EOF their backstop — a child whose
  // finish bracket never arrives cannot outlive the engine that launched it.
  @async.with_task_group() <| group => {
    let probes : Map[String, @async.Task[Unit]] = Map([])
    let mut exit_code = 0
    for ;; {
      match messages.get() {
        StreamEvent(stream) => {
          // Every stdout event is a hint that the engine may just have
          // appended to the durable record — the follower's low-latency
          // wakeup (its poll only backstops this).
          manager.kick_follower(engine.session_key)
          let decoded = stream.legacy
          let wire_event = stream.wire
          // The brackets are the only thing that knows a sub-run's lifetime;
          // the probe in between reads the child's own record, which is the
          // only place its progress is visible to this process.
          match wire_event {
            Some(SubrunStarted(id~, ..)) =>
              if engine.session_root is Some(root) && probes.get(id) is None {
                probes[id] = group.spawn(no_wait=true, allow_failure=true, () => {
                  @subrun.follow_progress(
                    root=root.to_string(),
                    parent_session=engine.session_key,
                    id~,
                    publish=payload => emit(sink, SubrunProgress(payload)),
                  )
                })
              }
            Some(SubrunFinished(id~, ..)) =>
              if probes.get(id) is Some(probe) {
                probes.remove(id)
                probe.cancel()
              }
            _ => ()
          }
          let needs_durable_scan = stream.needs_durable_scan
          // These events do not prove their matching Terminal append succeeded.
          // Synchronously close admission and stdin before the first sink
          // suspension; the current turn can finish its append/TurnDone, while
          // the next start is forced through the old child's close/reap barrier
          // and cancel cannot hit stale active_work.
          // Discarded, not drained: a queued cancel/steer is exactly what
          // must be cut off. This is synchronous, so no request can be between
          // its admission check and its enqueue, and every dropped sender is
          // told rather than left waiting.
          if needs_durable_scan {
            engine.discard_commands(
              "the engine finished its turn before this command was written",
            )
          }
          let (run_id, submission_id) = engine.steer_runs.route_event(
            decoded,
            stream.prompt_steer_applied,
            engine.phase.latest_run(),
          )
          // When the Terminal append did succeed, the follower's close will
          // carry its exact sequence. This registration covers the append
          // that failed: the EOF final scan then publishes the
          // `agent.durable` boundary before a successor is admitted.
          if needs_durable_scan &&
            run_id is Some(id) &&
            engine.follower is Some(follower) {
            follower.expect_durable_finish(id)
          }
          match decoded {
            Some(decoded) => {
              // Terminal failures are normalized by the follower's durable
              // close; forwarding their raw event as well would make the
              // frontend render the same failure twice. With no run to close
              // (no id recorded yet) that close cannot happen, so the raw
              // event is the report.
              if (!host_reports_terminal_error(decoded) || run_id is None) &&
                wire_event is Some(event) {
                emit(
                  sink,
                  StreamEvent({
                    run_id,
                    session: engine.session_key,
                    event: { event, submission_id },
                  }),
                )
              }
              match decoded {
                // A compaction queued behind an open turn begins only now, so
                // the engine's own event is what flips the phase; entering
                // from anything but Idle would clobber a run's state.
                CompactionStarted =>
                  if engine.phase is Idle(last_run~) {
                    engine.phase = Compacting(last_run~)
                  }
                // Either way the engine is done writing the record's summary,
                // so operations gated on compaction (starts, archiving) may
                // proceed.
                CompactionFinished | CompactionFailed =>
                  engine.phase = engine.phase.to_idle()
                _ => ()
              }
              // Terminal stream events deliberately close nothing here. The
              // engine appends the turn's durable Terminal before emitting
              // them, so the follower — kicked above — is the single closer:
              // it reads the record, publishes the run's Error/Finished and
              // flips the phase (`close_run_from_terminal`). This consumer
              // only forwards, which is why its silent death can no longer
              // strand a run.
            }
            None if wire_event is Some(event) =>
              emit(
                sink,
                StreamEvent({
                  run_id,
                  session: engine.session_key,
                  event: { event, submission_id },
                }),
              )
            None => ()
          }
        }
        StreamReaderFailed(message) => {
          // Nothing queued can reach a child whose stream is broken. Drop it
          // so the writer closes stdin instead of failing into a second,
          // redundant retirement of the lifecycle settled right here.
          engine.discard_commands("the engine's event stream failed")
          emit_error(sink, message, run_id?=engine.phase.latest_run())
          // A broken stream can no longer deliver compaction_finished/failed;
          // report the compaction as failed now so the frontend does not stay
          // stuck with Send disabled (the exit branch below then has nothing
          // left to report for it).
          if engine.phase is Compacting(..) {
            engine.phase = engine.phase.to_idle()
            emit_compaction_failed(sink, engine, message)
          }
        }
        // Retirement is `run`'s, but condemnation must stay synchronous
        // with consuming the exit: the task-group teardown between this
        // break and `retire` is a real suspension, and a cancel or steer
        // admitted in that gap would be accepted for a child that already
        // exited. Idempotent, so `retire` repeating it is harmless.
        StreamExited(code) => {
          engine.discard_commands("the engine exited")
          exit_code = code
          break
        }
      }
    }
    exit_code
  }
}

///|
/// EOF retirement — the one lifecycle closer for engine death, whatever
/// discovered it (an observed exit, a failed stdin write, a dead consumer;
/// the discoverer stashes its cause in `pending_failure`). The follower
/// stop below runs the final durable scan FIRST: when the dead engine's
/// turn actually ended — its Terminal is in the record — that scan closes
/// the run with the real outcome (`close_run_from_terminal`), and the
/// Running arm below never fires; the synthetic failure is reserved for a
/// child that died without committing one.
async fn ServeEngine::retire(
  self : ServeEngine,
  manager : EngineManager,
  stderr_task : @async.Task[String],
  code? : Int,
) -> Unit {
  let engine = self
  let sink = self.sink
  @xlog.info() <?
    {
      "event": "desktop_engine_exited",
      "session": engine.session_key,
      "pid": engine.process.pid,
      // Absent when the process handle yielded no status (a forced
      // retirement whose wait failed) — never a fabricated sentinel.
      "exit_code": code.map_or(Json::null(), c => c.to_json()),
      "run_id": engine.phase.latest_run().unwrap_or(""),
    }
  engine.discard_commands("the engine exited")
  // Capture ownership only if the slot still contains THIS engine by
  // identity. Correct replacement waits on this handle through final
  // drain, but pump teardown and defensive cleanup can still detach it;
  // a by-value comparison would confuse a same-config successor.
  let mut owns_slot = false
  let mut owned_follower : SessionFollower? = None
  if manager.pump is Serving(sessions~) &&
    sessions.get(engine.session_key) is Some(slot) &&
    slot.engine is Some(current) &&
    physical_equal(current, engine) {
    owns_slot = true
    owned_follower = manager.followers.get(engine.session_key)
  }
  // EOF cleanup always owns an independent retirement attempt. Pending
  // replacement/archive operations join this same generation when they
  // need the drain as a barrier; if one of those callers is cancelled,
  // this consumer still closes the writer/follower lifecycle. Use the
  // identity captured before clearing the slot, so a delayed cleanup
  // cannot stop a successor.
  let mut durable_sequence : Int? = None
  if owns_slot && owned_follower is Some(follower) {
    try {
      stop_follower_instance(manager, follower, writer_exited=true)
      durable_sequence = Some(follower.watermark)
    } catch {
      error if @async.is_being_cancelled() => raise error
      error => {
        // This abrupt EOF will emit a Failed without an exact sequence.
        // Move its durable obligation onto the follower before the
        // lifecycle event; a later archive/detach Stop can then finish
        // the failed drain after this dead serve handle leaves its slot.
        if engine.phase is Running(run_id~, ..) {
          follower.expect_durable_finish(run_id)
        }
        @xlog.debug() <?
          {
            "event": "desktop_follower_final_scan_failed",
            "session": engine.session_key,
            "error": "\{error}",
          }
      }
    }
  }
  match engine.phase {
    // EOF with a run still open means the engine died mid-turn: close
    // that run with its only available diagnostics.
    Running(run_id~, compact_queued~, ..) => {
      engine.phase = engine.phase.to_idle()
      let cause = engine.pending_failure.unwrap_or(
        "engine exited without a result",
      )
      let diagnostics = stderr_task.wait().trim().to_owned()
      if diagnostics.is_empty() {
        emit_error(sink, cause, run_id~, exit_code?=code)
      } else {
        emit_error(
          sink,
          "\{cause}:\n\{diagnostics}",
          run_id~,
          exit_code?=code,
          diagnostics~,
        )
      }
      emit_finished(sink, run_id, Failed, exit_code?=code, durable_sequence?)
      // A compaction queued behind the dead turn died with the engine;
      // only a terminal compaction event clears the frontend's queued
      // notice, so synthesize the failure it can no longer send.
      if compact_queued {
        emit_compaction_failed(
          sink, engine, "engine exited before the queued compaction started",
        )
      }
    }
    // EOF mid-compaction: no run is open, but the frontend set its
    // compacting notice on compaction_started and only a terminal
    // compaction event clears it — synthesize the failure the engine
    // can no longer send.
    Compacting(..) => {
      engine.phase = engine.phase.to_idle()
      let cause = engine.pending_failure.unwrap_or(
        "engine exited during compaction",
      )
      let diagnostics = stderr_task.wait().trim().to_owned()
      let reason = if diagnostics.is_empty() {
        cause
      } else {
        "\{cause}:\n\{diagnostics}"
      }
      emit_compaction_failed(sink, engine, reason)
    }
    // A clean exit after a terminal event (session switch, app
    // shutdown) reports nothing here. A pending exact boundary is
    // published below for every closed phase, including a setup failure
    // that had a compaction queued behind it.
    Idle(..) => ()
  }
  // Keep this exact dead handle in its slot through the final scan and
  // lifecycle publish. A concurrent start then joins `close_and_wait`
  // instead of racing the follower stop and announcing its successor
  // before this run's Finished/boundary. Clear by identity in case an
  // older host generation already replaced it defensively.
  if owns_slot &&
    manager.pump is Serving(sessions~) &&
    sessions.get(engine.session_key) is Some(slot) &&
    slot.engine is Some(current) &&
    physical_equal(current, engine) {
    slot.engine = None
    manager.prune_slot(engine.session_key)
  }
  // Returning from here is the successor-admission barrier, so this must
  // stay the last thing retirement does: the owned slot is clear, the final
  // follower scan is over, and every lifecycle event from this engine has
  // been published.
}

///|
/// A synthetic `compaction_failed` stream event for a compaction whose
/// engine died before reporting one itself, so the frontend's one decoder
/// clears its compacting notice either way. Routed like every compaction
/// event: by the engine's session, with the latest run id as the frontend's
/// fallback.
///
/// The payload is built from `@protocol.Event` rather than written by hand.
/// It used to be a literal keyed `reason`, under a comment claiming it was
/// "the same wire shape the engine emits" — which it was not: the engine
/// emits `error`. Nothing caught it because the frontend's decoder happened
/// to accept either spelling, so a host-made event and an engine-made one
/// had quietly different shapes. Going through the type makes that class of
/// claim checkable instead of aspirational.
fn emit_compaction_failed(
  sink : EventSink,
  engine : ServeEngine,
  reason : String,
) -> Unit {
  emit(
    sink,
    StreamEvent({
      run_id: engine.phase.latest_run(),
      session: engine.session_key,
      event: {
        event: (CompactionFailed(error=reason) : @wire.Event),
        submission_id: None,
      },
    }),
  )
}

///|
/// A consumer that dies mid-stream must not leave its open run's phase
/// `Running` forever — that state is unreachable by every close path and
/// reads as a turn that never ends. The failure is forced through the same
/// retirement an observed engine death gets.
#cfg(not(platform="windows"))
async test "a failed consumer closes its open run and retires the slot" {
  let manager = new_engine_manager("/bin/sh")
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    let (child_stdin, writer) = @process.write_to_process()
    let process = @process.spawn(
      group,
      "/bin/sh",
      ["-c", "sleep 30"],
      stdin=child_stdin,
      no_wait=true,
    )
    let engine : ServeEngine = {
      session_key: "s-consumer-died",
      session_root: None,
      spec_key: "test",
      writer,
      commands: Queue(kind=Unbounded),
      process,
      sink,
      follower: None,
      consumer: None,
      phase: Running(
        run_id="r-consumer-died",
        cancel_requested=false,
        compact_queued=false,
      ),
      run_admitted_ms: 0,
      pending_failure: None,
      condemned: false,
      steer_runs: SteerRunTracker::new(),
    }
    let sessions : Map[String, SessionSlot] = Map([])
    let slot = slot_for(sessions, "s-consumer-died")
    slot.engine = Some(engine)
    manager.pump = Serving(sessions~)
    let messages : @async.Queue[StreamMessage] = Queue(
      kind=Blocking(EngineStreamQueueSize),
    )
    // The pump's only suspension is this queue's read; failing it stands in
    // for any error escaping the consumer.
    messages.close(error=EngineError("boom"))
    let stderr_task = group.spawn(no_wait=true, () => "")
    engine.run(manager, messages, stderr_task)

    // `run` returning is retirement: the run was closed as a failure naming
    // the consumer, the child was killed, and the slot is clear.
    assert_true(slot.engine is None)
    assert_true(engine.condemned)
    assert_true(engine.phase is Idle(..))
    let mut cause = ""
    let mut status = ""
    for event in emitted {
      match event {
        Error(payload) if payload.run_id == Some("r-consumer-died") =>
          cause = payload.message.unwrap_or("")
        Finished(payload) if payload.run_id == "r-consumer-died" =>
          status = payload.status
        _ => ()
      }
    }
    assert_true(cause.contains("the engine's event consumer failed"))
    assert_eq(status, "failed")
  })
}

///|
/// A failed stdin write condemns the handle and answers its senders, but
/// settles no lifecycle itself: the one EOF retirement stays the only
/// closer for engine death and reports the stashed cause.
#cfg(not(platform="windows"))
async test "a failed command leaves settlement to the EOF retirement" {
  let manager = new_engine_manager("/bin/sh")
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    let (child_stdin, writer) = @process.write_to_process()
    // A child that is already gone, so the first write hits a closed pipe.
    let process = @process.spawn(
      group,
      "/bin/sh",
      ["-c", "exit 0"],
      stdin=child_stdin,
      no_wait=true,
    )
    let engine : ServeEngine = {
      session_key: "s-write-failed",
      session_root: None,
      spec_key: "test",
      writer,
      commands: Queue(kind=Unbounded),
      process,
      sink,
      follower: None,
      consumer: None,
      phase: Running(
        run_id="r-write-failed",
        cancel_requested=false,
        compact_queued=false,
      ),
      run_admitted_ms: 0,
      pending_failure: None,
      condemned: false,
      steer_runs: SteerRunTracker::new(),
    }
    let sessions : Map[String, SessionSlot] = Map([])
    let slot = slot_for(sessions, "s-write-failed")
    slot.engine = Some(engine)
    manager.pump = Serving(sessions~)
    engine.wait_process()
    let ack : @async.Queue[EngineError?] = Queue(kind=Blocking(1))
    assert_true(
      engine.submit("{}\n", failure_reason="failed to write the goal", ack~),
    )
    engine.write_commands()

    // The sender learned the exact failure, the handle is condemned with
    // the cause stashed — and nothing was settled: the phase still belongs
    // to the EOF retirement.
    guard ack.try_get() is Some(Some(EngineError(reason))) else {
      fail("expected the failed write to answer its sender")
    }
    assert_true(reason.has_prefix("failed to write the goal"))
    assert_true(engine.condemned)
    assert_true(engine.pending_failure is Some(_))
    assert_true(engine.phase is Running(..))
    assert_true(emitted.is_empty())

    // EOF retirement settles exactly once, naming the stashed cause.
    let messages : @async.Queue[StreamMessage] = Queue(
      kind=Blocking(EngineStreamQueueSize),
    )
    messages.put(StreamExited(0))
    let stderr_task = group.spawn(no_wait=true, () => "")
    engine.run(manager, messages, stderr_task)
    assert_true(slot.engine is None)
    assert_true(engine.phase is Idle(..))
    let mut finishes = 0
    let mut cause = ""
    for event in emitted {
      match event {
        Error(payload) if payload.run_id == Some("r-write-failed") =>
          cause = payload.message.unwrap_or("")
        Finished(payload) if payload.run_id == "r-write-failed" => {
          assert_eq(payload.status, "failed")
          finishes += 1
        }
        _ => ()
      }
    }
    assert_eq(finishes, 1)
    assert_true(cause.has_prefix("failed to write the goal"))
    group.return_immediately(())
  })
}

///|
test "terminal failures are normalized by the host" {
  assert_false(host_reports_terminal_error(AgentStep))
  assert_false(host_reports_terminal_error(AgentFinished("done")))
  assert_false(
    host_reports_terminal_error(ContextYield("[context ceiling] checkpointed")),
  )
  assert_true(host_reports_terminal_error(AgentAborted("interrupted")))
  assert_true(host_reports_terminal_error(MaxStepsExhausted))
  assert_true(host_reports_terminal_error(AgentError("boom")))
}

///|
test "unproven terminal logs require an EOF durable scan" {
  assert_true(
    DecodedStreamEvent::from_wire({ "event": "agent_setup_failed" }).needs_durable_scan,
  )
  assert_true(
    DecodedStreamEvent::from_wire({ "event": "turn_failed" }).needs_durable_scan,
  )
  assert_true(
    DecodedStreamEvent::from_wire({ "event": "agent_aborted" }).needs_durable_scan,
  )
  assert_false(
    DecodedStreamEvent::from_wire({ "event": "agent_finished" }).needs_durable_scan,
  )
  assert_false(
    DecodedStreamEvent::from_wire({ "event": "max_steps_exhausted" }).needs_durable_scan,
  )
}

///|
test "context yield has a distinct non-success wire status" {
  let status : RunStatus = ContextYield
  assert_eq(status.wire(), "context_yield")
}

///|
test "run ids carry 128 bits of cross-host entropy" {
  let id = mint_run_id()
  assert_true(id.has_prefix("r"))
  assert_eq(id.length(), 33)
}

///|
test "terminal closure preserves a queued compaction" {
  assert_true(
    Running(run_id="r-1", cancel_requested=false, compact_queued=false).after_run_close()
    is Idle(last_run=Some("r-1")),
  )
  assert_true(
    Running(run_id="r-1", cancel_requested=false, compact_queued=true).after_run_close()
    is Compacting(last_run=Some("r-1")),
  )
}

///|
test "trailing steer settle events keep the terminal run id" {
  let tracker = SteerRunTracker::new()
  tracker.begin_run()
  ignore(tracker.record_sent("old steer", Some("submission-old")))
  tracker.record_terminal("r41")
  tracker.begin_run()
  ignore(tracker.record_sent("fresh steer", Some("submission-fresh")))
  let old_drop : @event.AgentEvent? = Some(SteerDropped("old steer"))
  let fresh_apply : @event.AgentEvent? = Some(SteerApplied("fresh steer"))
  assert_eq(
    tracker.route_event(old_drop, false, Some("r42")),
    (Some("r41"), Some("submission-old")),
  )
  assert_eq(
    tracker.route_event(fresh_apply, true, Some("r42")),
    (Some("r42"), Some("submission-fresh")),
  )
}

///|
test "equal steer text receipts retain writer-order submission ids" {
  let tracker = SteerRunTracker::new()
  tracker.begin_run()
  ignore(tracker.record_sent("same", Some("submission-a")))
  ignore(tracker.record_sent("same", Some("submission-b")))
  let receipt : @event.AgentEvent? = Some(SteerApplied("same"))
  let (first_run, first_submission) = tracker.route_event(
    receipt,
    true,
    Some("r9"),
  )
  assert_eq(first_run, Some("r9"))
  let first_event : @protocol.AgentStreamEvent = {
    event: (SteerApplied(kind="prompt", content="same") : @wire.Event),
    submission_id: first_submission,
  }
  guard first_event.to_json() is Object(first_fields) &&
    first_fields.get("submission_id") is Some(String(first_id)) else {
    fail("first receipt did not carry a submission id")
  }
  assert_eq(first_id, "submission-a")
  let (second_run, second_submission) = tracker.route_event(
    receipt,
    true,
    Some("r9"),
  )
  assert_eq(second_run, Some("r9"))
  let second_event : @protocol.AgentStreamEvent = {
    event: (SteerApplied(kind="prompt", content="same") : @wire.Event),
    submission_id: second_submission,
  }
  guard second_event.to_json() is Object(second_fields) &&
    second_fields.get("submission_id") is Some(String(second_id)) else {
    fail("second receipt did not carry a submission id")
  }
  assert_eq(second_id, "submission-b")
}

///|
test "legacy steer receipt does not gain a submission field" {
  let tracker = SteerRunTracker::new()
  tracker.begin_run()
  ignore(tracker.record_sent("legacy", None))
  let decoded : @event.AgentEvent? = Some(SteerApplied("legacy"))
  let (_, submission_id) = tracker.route_event(decoded, true, Some("r11"))
  let event : @protocol.AgentStreamEvent = {
    event: (SteerApplied(kind="prompt", content="legacy") : @wire.Event),
    submission_id,
  }
  guard event.to_json() is Object(fields) else {
    fail("expected receipt object")
  }
  assert_true(fields.get("submission_id") is None)
}

///|
test "submission ids are non-blank and bounded by UTF-8 bytes" {
  assert_true(normalize_submission_id(None) is None)
  assert_true(normalize_submission_id(Some(" \t\n")) is None)
  assert_eq(
    normalize_submission_id(Some("x".repeat(128))),
    Some("x".repeat(128)),
  )
  assert_true(normalize_submission_id(Some("x".repeat(129))) is None)
  // U+754C occupies three UTF-8 bytes: count wire bytes, not UTF-16 units.
  assert_eq(
    normalize_submission_id(Some("界".repeat(42))),
    Some("界".repeat(42)),
  )
  assert_true(normalize_submission_id(Some("界".repeat(43))) is None)
  // Accepted ids stay opaque rather than being trimmed before the echo.
  assert_eq(normalize_submission_id(Some(" id ")), Some(" id "))
}

///|
test "started payload omits a missing submission id" {
  let payload : StartedPayload = {
    run_id: "r1",
    submission_id: None,
    engine: Some("openseek"),
    model: Some("model"),
    max_steps: Some(10),
    session: "s-started",
    session_root: None,
  }
  guard payload.to_json() is Object(fields) else {
    fail("expected started payload object")
  }
  assert_true(fields.get("submission_id") is None)
}

///|
test "new turn events clear stale settling state" {
  let tracker = SteerRunTracker::new()
  tracker.begin_run()
  ignore(tracker.record_sent("old steer", Some("submission-old")))
  tracker.record_terminal("r7")
  assert_eq(
    tracker.route_event(Some(AgentStep), false, Some("r8")),
    (Some("r8"), None),
  )
  let old_drop : @event.AgentEvent? = Some(SteerDropped("old steer"))
  assert_eq(
    tracker.route_event(old_drop, false, Some("r8")),
    (Some("r8"), None),
  )
}

///|
test "background events do not clear trailing steer receipts" {
  let tracker = SteerRunTracker::new()
  tracker.begin_run()
  ignore(tracker.record_sent("first", Some("submission-first")))
  ignore(tracker.record_sent("second", Some("submission-second")))
  tracker.record_terminal("r-old")
  tracker.begin_run()
  assert_eq(
    tracker.route_event(None, false, Some("r-new")),
    (Some("r-new"), None),
  )
  assert_eq(
    tracker.route_event(Some(SteerApplied("first")), true, Some("r-new")),
    (Some("r-old"), Some("submission-first")),
  )
  assert_eq(
    tracker.route_event(Some(SteerDropped("second")), false, Some("r-new")),
    (Some("r-old"), Some("submission-second")),
  )
}

///|
test "only prompt steer_applied consumes a desktop steer" {
  let tracker = SteerRunTracker::new()
  tracker.begin_run()
  ignore(tracker.record_sent("same", Some("submission-prompt")))
  let decoded : @event.AgentEvent? = Some(SteerApplied("same"))
  for _ in ["command", "notice"] {
    assert_eq(
      tracker.route_event(decoded, false, Some("r1")),
      (Some("r1"), None),
    )
  }
  assert_eq(
    tracker.route_event(decoded, true, Some("r1")),
    (Some("r1"), Some("submission-prompt")),
  )
}

///|
async test "timed out command-lock waiter is removed" {
  let lock : @async.Mutex = Mutex()
  lock.acquire()
  assert_true(@async.with_timeout_opt(10, () => lock.acquire()) is None)
  lock.release()
  // The timed-out waiter must not consume the later release; close_and_wait's
  // cancellation fallback depends on the mutex queue removing it cleanly.
  assert_true(@async.with_timeout_opt(100, () => lock.acquire()) is Some(_))
  lock.release()
}

///|
async test "native engine env has one authoritative bundled moon path" {
  let ambient_path = @sys.get_env_var("PATH")
  let root = @pathx.Path(@fs.tmpdir(prefix="openseek-engine-env-"))
  // The macOS bundle's real shape (`package/macos/main.mbt`): the engine is
  // staged in the Proton package input's `bin/`, with the toolchain seed
  // beside that directory rather than inside it.
  let input = root.join("Contents/Resources/target/proton-package-input")
  let engine = input.join("bin/openseek")
  let seed = input.join("toolchains/moonbit/macos-arm64")
  let runtime = root.join("runtime")
  let moon_home = runtime.join("toolchains/moonbit/macos-arm64")
  prepare_fake_moonbit_seed(seed, version="0.10.0-test") catch {
    error => {
      @fs.rmdir(root.to_string(), recursive=true) catch {
        _ => ()
      }
      raise error
    }
  }
  prepare_fake_bundled_moonbit_home(moon_home, version="0.10.0-test") catch {
    error => {
      @fs.rmdir(root.to_string(), recursive=true) catch {
        _ => ()
      }
      raise error
    }
  }
  let config : RunConfig = {
    task: "t",
    api_key: "k",
    api_url: None,
    model: "m",
    max_steps: 1,
    engine: engine.to_string(),
    cwd: None,
    session: "s-env",
    session_root: None,
  }
  let env = engine_process_env(config, Some(runtime)) catch {
    error => {
      @fs.rmdir(root.to_string(), recursive=true) catch {
        _ => ()
      }
      raise error
    }
  }
  @fs.rmdir(root.to_string(), recursive=true)
  assert_eq(env["OPENSEEK_SESSION"], "s-env")
  assert_true(env.get("OPENSEEK_SESSION_ROOT") is None)
  let moon_bin = moon_home.join("bin").to_string()
  let expected_path = if ambient_path is Some(path) && !path.is_empty() {
    "\{moon_bin}\{@env.path_sep}\{path}"
  } else {
    moon_bin
  }
  assert_eq(env["PATH"], expected_path)
}

///|
async fn prepare_fake_moonbit_seed(
  seed : @pathx.Path,
  version~ : String,
) -> Unit {
  write_fake_executable(seed.join("bin/moon"))
  write_fake_executable(seed.join("bin/moonc"))
  write_fake_file(seed.join("lib/core/moon.mod"))
  @fs.write_file(
    seed.join(".openseek-moonbit-seed-version").to_string(),
    version,
    create_mode=CreateOrTruncate,
  )
}

///|
async fn prepare_fake_bundled_moonbit_home(
  moon_home : @pathx.Path,
  version~ : String,
) -> Unit {
  prepare_fake_moonbit_seed(moon_home, version~)
  @fs.write_file(
    moon_home.join(".openseek-moonbit-bundle-version").to_string(),
    "version=\{version}",
    create_mode=CreateOrTruncate,
  )
  write_fake_file(
    moon_home.join("lib/core/_build/native/release/bundle/prelude/prelude.mi"),
  )
  write_fake_file(
    moon_home.join("lib/core/_build/wasm-gc/release/bundle/prelude/prelude.mi"),
  )
}

///|
async fn write_fake_file(path : @pathx.Path) -> Unit {
  @fsx.ensure_dir(path.dirname())
  @fs.write_file(path.to_string(), "", create_mode=CreateOrTruncate)
}

///|
/// The resolver only assembles a toolchain around a regular executable `moon`,
/// and initialization executes `moonc`, so both fakes must carry the bit.
async fn write_fake_executable(path : @pathx.Path) -> Unit {
  @fsx.ensure_dir(path.dirname())
  @fs.write_file(
    path.to_string(),
    "",
    create_mode=CreateOrTruncate,
    permission=0o755,
  )
}

///|
#cfg(not(platform="windows"))
async test "engine startup rolls back follower on pre-spawn failure" {
  let dir = @fs.tmpdir(prefix="openseek-engine-startup-")
  let baseline_engine = dir + "/baseline.sh"
  @fs.write_file(
    baseline_engine,
    "#!/bin/sh\nprintf '%s' '{\"events\":[]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", baseline_engine]), 0)
  let manager = new_engine_manager(baseline_engine)
  let sink = EventSink(fn(_) { () })
  let slot : SessionSlot = { pending: None, engine: None }
  let config : RunConfig = {
    task: "test",
    api_key: "test",
    api_url: None,
    model: "test",
    max_steps: 1,
    engine: dir + "/missing/openseek",
    cwd: None,
    session: "s-startup-failure",
    session_root: Some(@pathx.Path(dir + "/root").resolve()),
  }
  @async.with_task_group(group => {
    let failed = try {
      start_serve_engine(sink~, group~, manager~, slot~, config~)
      false
    } catch {
      error if @async.is_being_cancelled() => raise error
      _ => true
    }
    assert_true(failed)
    assert_true(manager.followers.get("s-startup-failure") is None)
    assert_true(slot.engine is None)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
/// The slot claim is what closes the compact-preempts-starting-prompt race:
/// whichever op (start, compact, archive) validated first holds the slot
/// through its command hitting the wire, and every later claimant is refused
/// with the holder's message — releasing reopens the slot.
test "a claimed session slot refuses every other op until released" {
  let manager = new_engine_manager("unused")
  let sessions : Map[String, SessionSlot] = Map([])
  manager.pump = Serving(sessions~)
  let slot = slot_for(sessions, "s")
  let start_claim = slot.claim(sessions, "s", StartPending)
  let refused = try slot.claim(sessions, "s", CompactPending) catch {
    EngineError(message) => message
  } noraise {
    _ => ""
  }
  assert_true(refused.contains("already starting"))
  start_claim.release(manager)
  let compact_claim = slot.claim(sessions, "s", CompactPending)
  let refused = try slot.claim(sessions, "s", ArchivePending) catch {
    EngineError(message) => message
  } noraise {
    _ => ""
  }
  assert_true(refused.contains("compaction is already being requested"))
  compact_claim.release(manager)
}

///|
test "loads coexist with start and compact but not archive" {
  let manager = new_engine_manager("unused")
  let read_guard = manager.begin_record_read("s")
  let op_guard = manager.begin_record_op("s")
  let second_op = try manager.begin_record_op("s") catch {
    EngineError(message) => message
  } noraise {
    _ => ""
  }
  assert_true(second_op.contains("already preparing"))
  manager.end_record_op("s", op_guard)
  manager.end_record_read("s", read_guard)
  let move_guard = manager.claim_record_move("s")
  let refused = try manager.begin_record_read("s") catch {
    EngineError(message) => message
  } noraise {
    _ => ""
  }
  assert_true(refused.contains("moving between live and archived"))
  manager.release_record_move("s", move_guard)
}

///|
test "a slot claim cannot cross an engine pump generation" {
  let manager = new_engine_manager("unused")
  let departed : Map[String, SessionSlot] = Map([])
  manager.pump = Serving(sessions=departed)
  let claim = slot_for(departed, "s").claim(departed, "s", StartPending)
  let successor : Map[String, SessionSlot] = Map([])
  manager.pump = Serving(sessions=successor)
  assert_false(claim.is_current(manager))
  let refused = try claim.require_current(manager) catch {
    EngineError(message) => message
  } noraise {
    _ => ""
  }
  assert_true(refused.contains("restarted"))
  claim.release(manager)
  assert_true(successor.get("s") is None)
}

///|
async test "record move waits for readers across pump replacement" {
  let manager = new_engine_manager("unused")
  let reader = manager.begin_record_read("s")
  let moving = manager.claim_record_move("s")
  manager.pump = Serving(sessions=Map([]))
  @async.with_task_group(group => {
    let waiter = group.spawn(() => moving.wait_until_idle())
    @async.pause()
    assert_true(waiter.try_wait() is None)
    manager.pump = Serving(sessions=Map([]))
    manager.end_record_read("s", reader)
    waiter.wait()
  })
  manager.release_record_move("s", moving)
}

///|
fn pump_test_config(session : String) -> RunConfig {
  {
    task: "test",
    api_key: "test",
    api_url: None,
    model: "test",
    max_steps: 1,
    engine: "unused",
    cwd: None,
    session,
    session_root: Some(@pathx.Path("/tmp/openseek-pump-test").resolve()),
  }
}

///|
async test "pump reset acks active and queued spawn requests" {
  let manager = new_engine_manager("unused")
  let sessions : Map[String, SessionSlot] = Map([])
  manager.pump = Serving(sessions~)
  let active_claim = slot_for(sessions, "active").claim(
    sessions,
    "active",
    StartPending,
  )
  let queued_claim = slot_for(sessions, "queued").claim(
    sessions,
    "queued",
    StartPending,
  )
  let active_ack : @async.Queue[EngineError?] = Queue(kind=Blocking(1))
  let queued_ack : @async.Queue[EngineError?] = Queue(kind=Blocking(1))
  manager.commands.put(
    SpawnEngine(queued_claim, pump_test_config("queued"), queued_ack),
  )
  let active = Ref(Some(active_ack))
  reset_engine_generation(manager, active)
  assert_true(manager.pump is Stopped)
  assert_true(active_ack.try_get() is Some(Some(EngineError(_))))
  assert_true(queued_ack.try_get() is Some(Some(EngineError(_))))
  assert_true(manager.commands.try_get() is None)
  // Ack completion, not reset itself, lets each requester release its claim.
  assert_true(active_claim.is_current(manager) == false)
  assert_true(queued_claim.active)
  active_claim.release(manager)
  queued_claim.release(manager)
}

///|
async test "cancelled spawn requester holds its claim until pump ack" {
  let manager = new_engine_manager("unused")
  let sessions : Map[String, SessionSlot] = Map([])
  manager.pump = Serving(sessions~)
  let claim = slot_for(sessions, "s").claim(sessions, "s", StartPending)
  @async.with_task_group(group => {
    let requester = group.spawn(() => {
      defer claim.release(manager)
      request_spawn(manager, claim, pump_test_config("s"))
    })
    let SpawnEngine(queued, _, ack) = manager.commands.get()
    assert_true(physical_equal(queued, claim))
    requester.cancel()
    @async.pause()
    assert_true(claim.is_current(manager))
    assert_true(ack.try_get() is None)
    ack.put(None)
    let cancelled = try {
      requester.wait()
      false
    } catch {
      error if @async.is_cancellation_error(error) => true
      _ => false
    }
    assert_true(cancelled)
    assert_false(claim.active)
  })
}
