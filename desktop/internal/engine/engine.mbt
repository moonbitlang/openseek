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
  engine_name : String
  model : String
  max_steps : Int
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
  queued_runs : Array[QueuedRun]
}

///|
priv struct QueuedRun {
  id : String
  run_id : String
  content : String
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
/// One command bound for a serve engine's stdin, plus what to tell the
/// conversation if it never gets there.
///
/// Held as the protocol value rather than the line it encodes to: the queue
/// has to answer what a command IS — whether it belongs to the turn in
/// progress — and re-reading that out of serialized text would be a second,
/// drifting decoder for a question the type already answers.
priv struct EngineCommand {
  command : @wire.Command
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
  command : @wire.Command,
  failure_reason~ : String,
  ack? : @async.Queue[EngineError?],
) -> Bool {
  self.commands.try_put({ command, failure_reason, ack, }) catch {
    _ => false
  }
}

///|
/// Whether a command dies with the turn it was written for. A cancel or a
/// steer addresses the turn in progress and means something else entirely to
/// the next one — the engine reads an idle `cancel` as "withdraw the next
/// prompt" and silently does so. Everything else was queued to run AFTER the
/// turn on purpose (a `/compact` accepted mid-turn, a goal), and dropping it
/// is what would strand the conversation.
///
/// Exhaustive on purpose: a new command kind must decide this at compile time.
fn ends_with_turn(command : @wire.Command) -> Bool {
  // An approval answers a question the CURRENT turn is blocked on. Once that
  // turn is gone the question went with it — the engine's desk discards a
  // decision nobody is waiting for — so this dies with the turn like a steer,
  // rather than being delivered into a turn that never asked.
  match command {
    Cancel | Steer(..) | ApprovalDecision(..) => true
    Prompt(..) | Compact | GoalSet(..) | GoalClear => false
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
/// Answer the queued commands that died with the turn, and leave the rest —
/// and the engine — alone. Delivering a turn-scoped command late is worse
/// than dropping it: an idle `cancel` withdraws the engine's NEXT prompt
/// without a word, and a late steer contaminates the next turn.
///
/// The survivors go back in arrival order. This whole call is synchronous, so
/// the writer cannot take from the queue while it is briefly empty, and no
/// request can enqueue into the middle of the sequence being restored.
fn ServeEngine::settle_turn_commands(
  self : ServeEngine,
  reason : String,
) -> Unit {
  let survivors : Array[EngineCommand] = []
  for ;; {
    let next = self.commands.try_get() catch { _ => break }
    guard next is Some(queued) else { break }
    if ends_with_turn(queued.command) {
      queued.settle(Some(EngineError(reason)))
    } else {
      survivors.push(queued)
    }
  }
  for queued in survivors {
    // The queue just gave up these slots, so a refusal here means it was
    // closed under us — the engine is going away and the command cannot be
    // delivered, which is exactly what its sender needs to hear.
    if !(self.commands.try_put(queued) catch { _ => false }) {
      queued.settle(Some(EngineError(reason)))
    }
  }
}

///|
/// Answer everything still queued: past this point nothing in the queue can
/// reach stdin, whatever it was addressed to. Synchronous, so it is safe on a
/// cancellation path, and idempotent, because a drained queue is empty.
fn ServeEngine::settle_queued(self : ServeEngine, reason : String) -> Unit {
  for ;; {
    let next = self.commands.try_get() catch { _ => break }
    guard next is Some(queued) else { break }
    queued.settle(Some(EngineError(reason)))
  }
}

///|
/// Condemn this engine and answer everything still queued: past this point
/// nothing in the queue can reach stdin. Synchronous, so it is safe on a
/// cancellation path, and idempotent, because a drained queue is empty.
fn ServeEngine::discard_commands(self : ServeEngine, reason : String) -> Unit {
  self.condemn()
  self.settle_queued(reason)
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
    self.writer.write(command.command.to_jsonl()) catch {
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
/// What the serve engine is doing right now, and which run it is doing it for
/// — one value instead of loose booleans beside a separate run id, so the
/// impossible combinations (a compaction with an open run, an open turn whose
/// id nobody recorded) cannot be
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
  // A prompt's turn is open on the wire, under `run_id`. `compact_queued`
  // marks a `/compact` accepted mid-turn: the command sits in the serve
  // engine's queue behind this run, so the turn's terminal event must land in
  // `Compacting`, not `Idle` — otherwise a prompt or an archive slips into the
  // gap before the engine's `compaction_started` and the eventual
  // `compaction_finished` would blindly idle it away.
  Running(run_id~ : String, compact_queued~ : Bool)
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
fn SteerRunTracker::SteerRunTracker() -> SteerRunTracker {
  { settling_run: None, open_steers: [], settling_steers: [], }
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
  let entry : TrackedSteer = { text, submission_id, }
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
  event : @wire.Event?,
  latest_run : String?,
) -> (String?, String?) {
  match event {
    // The wire kind is authoritative: only "prompt" consumes a desktop
    // steer. Parse defaults an absent kind to "prompt" — the only engines
    // that omit it predate the field and meant prompt.
    Some(SteerApplied(kind~, content~)) if kind == "prompt" =>
      self.route_receipt(content, latest_run)
    Some(SteerDropped(content~)) => self.route_receipt(content, latest_run)
    // serve drains every old prompt receipt before beginning the next step.
    // AgentStep is therefore the explicit boundary after which an absent old
    // receipt must not steal an equal-text steer from the new run.
    Some(AgentStep(..)) => {
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
  let claim : PendingClaim = { epoch, session_key, op, active: true, }
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
  state.readers += 1
  state
}

///|
fn EngineManager::end_record_read(
  self : EngineManager,
  session : String,
  state : SessionRecordGuard,
) -> Unit {
  state.readers -= 1
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
  state.active_ops += 1
  state
}

///|
fn EngineManager::end_record_op(
  self : EngineManager,
  session : String,
  state : SessionRecordGuard,
) -> Unit {
  state.active_ops -= 1
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
    let slot : SessionSlot = { pending: None, engine: None, }
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
  { manager: new_engine_manager(engine, runtime_dir?), }
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
/// Close an open run on the stream event that ended its turn, and report
/// whether it did. The engine's stdout is the run's lifecycle: a turn is over
/// exactly when the event that ends it arrives, and this is the one place
/// that says so. What the record holds is the transcript's business — the
/// follower broadcasts it, and never touches a run.
///
/// `false` for every event that does not end a turn, so the caller can leave
/// the phase alone.
fn close_run_from_stream(
  sink : EventSink,
  run_id : String,
  event : @wire.Event,
) -> Bool {
  match event {
    AgentFinished(answer~) => {
      emit_finished(sink, run_id, Finished, answer~)
      true
    }
    ContextYield(answer~, ..) => {
      emit_finished(sink, run_id, ContextYield, answer~)
      true
    }
    AgentAborted(reason~) => {
      emit_error(sink, "agent aborted: \{reason}", run_id~)
      emit_finished(sink, run_id, Aborted)
      true
    }
    MaxStepsExhausted => {
      emit_error(sink, "max steps exhausted", run_id~)
      emit_finished(sink, run_id, MaxStepsExhausted)
      true
    }
    AgentSetupFailed(error~) => {
      emit_error(sink, "agent setup failed: \{error}", run_id~)
      emit_finished(sink, run_id, Failed)
      true
    }
    TurnFailed(error~) => {
      emit_error(sink, "turn failed: \{error}", run_id~)
      emit_finished(sink, run_id, Failed)
      true
    }
    _ => false
  }
}

///|
/// Whether a terminal-class stream event carries its own failure text. Those
/// events are published as the run's Error/Finished pair by the close above,
/// so forwarding their raw form as well would render the same failure twice.
fn host_reports_terminal_error(event : @wire.Event) -> Bool {
  match event {
    AgentAborted(..)
    | MaxStepsExhausted
    | AgentSetupFailed(..)
    | TurnFailed(..) => true
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
  emit(sink, Connected({ stage: Serving, }))
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
  // generation the indivisible lifecycle unit, and refusing to spawn when the
  // drain fails is what keeps a predecessor's tail out of the successor's
  // transcript.
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
  // The prepared payload also carries the seed's `share/doc/moonbit/` (the
  // moonbit-docs markdown build), which the engine advertises to the model as
  // its MoonBit reference. Durable session prompts embed the path, and the
  // payload lives in the per-user runtime directory, so it survives bundle
  // moves and AppImage relaunches. A toolchain without docs — an external
  // one, or a seed staged without them — advertises none, and the ambient
  // value is scrubbed so the child never names docs the host did not resolve.
  match toolchain.references {
    Some(docs) => env["OPENSEEK_REFERENCES"] = docs.to_string()
    None => env.remove("OPENSEEK_REFERENCES")
  }
  @xlog.debug() <?
    {
      "event": "desktop_engine_moonbit_path",
      "bin_dir": toolchain.bin_dir.to_string(),
      "references": toolchain.references.map(docs => docs.to_string()),
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
  // The engine reads the key from the provider-specific variable the config
  // resolved (`DEEPSEEK`/`KIMI`/`GLM`; see `key_env_for`) but the model from
  // `OPENSEEK_MODEL` (the CLI's `--model` env binding); the prefixes differ
  // on purpose, so the model must not go into `DEEPSEEK_MODEL` — the engine
  // ignores that and falls back to its default model. Other providers' shell
  // exports inherit untouched: the engine reads only its model's variable
  // for chat, and `web_search` may legitimately use an ambient `DEEPSEEK`.
  env[config.key_env] = config.api_key
  env["OPENSEEK_MODEL"] = config.model
  env["OPENSEEK_THINKING"] = config.thinking.wire()
  env["OPENSEEK_MAX_STEPS"] = config.max_steps.to_string()
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
  add_moonbit_path_for_native_engine(env, config, runtime_dir)
  env
}

///|
fn engine_process_args(config : RunConfig) -> Array[String] {
  // Desktop engines always run in durable-session mode. Passing placement
  // explicitly keeps it out of the ambient environment inherited by tools.
  // Attach values so a leading `-` remains part of the value.
  let args = ["serve", "--session=\{config.session}"]
  if config.session_root is Some(root) {
    args.push("--session-root=\{root.to_string()}")
  }
  args.append(["--dir", ".", "--approval", "ask"])
  args
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
  // `--approval ask` is the host declaring that it CAN answer a permission
  // question: the engine's own default is never, because an engine cannot tell
  // a controller with a person behind it from a script reading its stdout.
  // Saying so here is what makes the escalation argument exist for this
  // session's model at all.
  let args = engine_process_args(config)
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
    engine_name: config.engine,
    model: config.model,
    max_steps: config.max_steps,
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
    pending_failure: None,
    condemned: false,
    steer_runs: SteerRunTracker(),
    queued_runs: [],
  }
  startup_engine = Some(engine)
  // Spawned before the handle is reachable from any request, so stdin has an
  // owner for the engine's whole life — including a rollback, which asks for
  // the close by clearing the queue rather than touching the writer.
  group.spawn_bg(no_wait=true, allow_failure=true, () => engine.write_commands())
  slot.engine = Some(engine)
  let stderr_task = group.spawn(no_wait=true) <| () => {
    stderr_reader.read_all().text() catch {
      error if @async.is_being_cancelled() => raise error
      _ => ""
    }
  }
  // Kept as a handle, not a background task: everything that waits for this
  // engine to be retired waits for exactly this task to end. It owns stdout
  // outright — reading it and acting on it are the same loop, so there is no
  // buffer between them for a half-dead pair of tasks to strand.
  engine.consumer = Some(
    group.spawn(no_wait=true, allow_failure=true, () => {
      engine.run(manager, reader, stderr_task)
    }),
  )
  startup_committed = true
}

///|
/// Consume one engine's event stream for its whole lifetime: forward every
/// raw event to the webview stamped with the engine's current run, and close
/// that run on the event that ends its turn. Runs until the engine's stdout
/// reader sees EOF.
///
/// This task therefore owns the run's whole lifecycle, and it is spawned with
/// `allow_failure`, so an error escaping it would otherwise vanish without a
/// trace — leaving a run open that nothing else can close. That is the
/// stuck-conversation shape this catch exists for. Any non-cancellation
/// failure becomes a forced retirement here: the child is killed and the
/// retirement settles the open run as a failure, with a log line naming the
/// error the spawn would have swallowed. Malformed JSONL arrives here too: it
/// is simply an engine this host cannot go on reading, and retirement already
/// knows how to report a cause for whichever phase the engine is in.
async fn ServeEngine::run(
  self : ServeEngine,
  manager : EngineManager,
  reader : @process.ReadFromProcess,
  stderr_task : @async.Task[String],
) -> Unit {
  let code = self.consume(manager, reader) catch {
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
      // This task is the pipe's drain, not only its interpreter: with it
      // gone nothing reads stdout, the OS pipe fills, and the child freezes
      // mid-turn on a blocked write, so waiting for it to exit on its own
      // would wait forever. Kill it instead, so the retirement below reaps a
      // real exit and settles the open run.
      @xlog.warn() <?
        {
          "event": "desktop_engine_cancel",
          "reason": "event consumer failed",
          "session": self.session_key,
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
/// Whether this wire event means the turn died rather than finished — the
/// engine writes these from a catch block on its way out of the turn, and can
/// follow one with another for the same turn. This child is not trusted with
/// another turn.
fn turn_died(event : @wire.Event) -> Bool {
  match event {
    AgentSetupFailed(..) | TurnFailed(..) | AgentAborted(..) => true
    _ => false
  }
}

///|
/// Whether this stream event starts after, or completes after, a durable
/// transcript span. The host publishes these only after the session follower
/// has broadcast everything currently committed; other progress events stay
/// on the low-latency kick path.
fn event_requires_durable_barrier(event : @wire.Event) -> Bool {
  match event {
    AgentStep(..) | AgentFinished(..) | ContextYield(..) => true
    _ => false
  }
}

///|
test "model-step and successful-terminal events are durable barriers" {
  assert_true(event_requires_durable_barrier(AgentStep(step=1)))
  assert_true(event_requires_durable_barrier(AgentFinished(answer="done")))
  assert_true(
    event_requires_durable_barrier(
      ContextYield(to_sequence=1, answer="continue"),
    ),
  )
  assert_false(event_requires_durable_barrier(AssistantMessage(content="live")))
  assert_false(
    event_requires_durable_barrier(
      Usage(usage={
        prompt_tokens: 1,
        completion_tokens: 2,
        total_tokens: 3,
        prompt_cache_hit_tokens: 0,
        prompt_cache_miss_tokens: 0,
      }),
    ),
  )
}

///|
/// The event pump half of `run`: read the child's stdout to EOF, acting on
/// each event as it is decoded, and hand back the child's exit code. Reading
/// and interpreting are one task on purpose — a split lets the interpreter
/// die while the reader keeps filling a buffer, which is a state with no
/// owner. The transitions that live here (a run's close, compaction phase
/// flips, admission cutoff on a died turn) stay synchronous with the events
/// that cause them, while retirement belongs to `run`, so a pump that dies
/// mid-stream still retires exactly once.
async fn ServeEngine::consume(
  self : ServeEngine,
  manager : EngineManager,
  reader : @process.ReadFromProcess,
) -> Int {
  let engine = self
  let sink = self.sink
  // The read end belongs to this task for its whole life, so every way out —
  // EOF, a stream this host cannot read, cancellation — closes it here.
  defer reader.close()
  // Sub-run probes are children of this task: one per running child, spawned
  // at its `subrun_started` bracket and cancelled at the finish. `no_wait`
  // makes the engine's own EOF their backstop — a child whose finish bracket
  // never arrives cannot outlive the engine that launched it.
  @async.with_task_group() <| group => {
    let probes : Map[String, @async.Task[Unit]] = Map([])
    // Workflow tails likewise: one per run a snippet announced, spawned at
    // its `workflow_started` bracket and cancelled at the finish. A tail
    // turns the run's sidecar into the SAME sub-run brackets an `explore`
    // child gets — so the lane dock and the child's own probe need no new
    // path — and its journal into `workflow.entry` pushes.
    let tails : Map[String, @async.Task[Unit]] = Map([])
    for ;; {
      guard reader.read_until("\n") is Some(line) else { break }
      for json in @jsonl.parse(line) {
        // Every stdout event is a hint that the engine may just have
        // appended to the durable record — the follower's low-latency
        // wakeup (its poll only backstops this).
        manager.kick_follower(engine.session_key)
        let wire_event = @wire.parse(json)
        // The brackets are the only thing that knows a sub-run's lifetime;
        // the probe in between reads the child's own record, which is the
        // only place its progress is visible to this process.
        match wire_event {
          Some(SubrunStarted(id~, ..)) =>
            if engine.session_root is Some(root) && probes.get(id) is None {
              probes[id] = group.spawn(no_wait=true, allow_failure=true, () => {
                @subrun.follow_progress(
                  root~,
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
          Some(
            WorkflowStarted(id~, journal~, events~, first_child~, child_count~)
          ) =>
            if engine.session_root is Some(root) && tails.get(id) is None {
              tails[id] = group.spawn(no_wait=true, allow_failure=true, () => {
                @workflow.follow_run(
                  workflow=id,
                  session=engine.session_key,
                  journal~,
                  events~,
                  on_child_started=started => {
                    // The child's session id is `<parent>-sr-N`; its bracket
                    // id is the `sr-N` suffix, exactly as `run_subrun` names
                    // the children it launches itself.
                    // Only a child inside the announced block is this run's:
                    // the sidecar is the snippet's own writing, and a line
                    // naming an `explore` child's id must not open a second
                    // lane for it.
                    guard @wire.split_child_session_id(started.child)
                      is Some((_, ordinal)) &&
                      @workflow.in_block(ordinal, first_child~, child_count~) else {
                      return
                    }
                    let sr = "sr-\{ordinal}"
                    let event : @wire.Event = SubrunStarted(
                      id=sr,
                      kind=started.kind,
                      label=@workflow.display_label(started.label),
                    )
                    let (run_id, submission_id) = engine.steer_runs.route_event(
                      Some(event),
                      engine.phase.latest_run(),
                    )
                    emit(
                      sink,
                      StreamEvent({
                        run_id,
                        session: engine.session_key,
                        event: { event, submission_id, },
                      }),
                    )
                    if probes.get(sr) is None {
                      probes[sr] = group.spawn(
                        no_wait=true,
                        allow_failure=true,
                        () => {
                          @subrun.follow_progress(
                            root~,
                            parent_session=engine.session_key,
                            id=sr,
                            publish=payload => {
                              emit(sink, SubrunProgress(payload))
                            },
                          )
                        },
                      )
                    }
                  },
                  on_child_finished=finished => {
                    guard @wire.split_child_session_id(finished.child)
                      is Some((_, ordinal)) &&
                      @workflow.in_block(ordinal, first_child~, child_count~) else {
                      return
                    }
                    let sr = "sr-\{ordinal}"
                    // The sidecar reports the spend as one figure; the
                    // bracket wants it split, and the lane only ever shows
                    // the sum.
                    let event : @wire.Event = SubrunFinished(
                      id=sr,
                      status=finished.status,
                      steps=finished.steps,
                      prompt_tokens=finished.tokens,
                      completion_tokens=0,
                    )
                    let (run_id, submission_id) = engine.steer_runs.route_event(
                      Some(event),
                      engine.phase.latest_run(),
                    )
                    emit(
                      sink,
                      StreamEvent({
                        run_id,
                        session: engine.session_key,
                        event: { event, submission_id, },
                      }),
                    )
                    if probes.get(sr) is Some(probe) {
                      probes.remove(sr)
                      probe.cancel()
                    }
                  },
                  on_entry=entry => emit(sink, WorkflowEntry(entry)),
                )
              })
            }
          Some(WorkflowFinished(id~)) =>
            if tails.get(id) is Some(tail) {
              tails.remove(id)
              // Not cancelled on the bracket: the snippet wrote its last
              // sidecar lines and journal entries just before exiting, and
              // the tail's next poll may be a whole interval away. The grace
              // guarantees one full poll over the final files, so a child
              // that finished is never left showing as running.
              group.spawn(no_wait=true, allow_failure=true, () => {
                @async.sleep(@workflow.drain_grace_ms)
                tail.cancel()
              })
              |> ignore
            }
          _ => ()
        }
        // A turn that died takes its child with it: the engine can emit a
        // second terminal event for the same dead turn, so it gets no next
        // one. Synchronously close admission and stdin here, so the next
        // start is forced through this child's close/reap barrier instead of
        // racing it. This is synchronous, so no request can be between its
        // admission check and its enqueue.
        if wire_event is Some(event) && turn_died(event) {
          engine.discard_commands(
            "the engine finished its turn before this command was written",
          )
        }
        let (run_id, submission_id) = engine.steer_runs.route_event(
          wire_event,
          engine.phase.latest_run(),
        )
        // Step and successful terminal events are causal transcript
        // boundaries. Drain the serialized follower before publishing them:
        // the frontend can then use its current durable frontier to associate
        // reasoning with this exact model step, and a finish cannot clear a
        // sealed preview before its canonical Assistant commit is visible.
        if wire_event is Some(event) &&
          event_requires_durable_barrier(event) &&
          manager.followers.get(engine.session_key) is Some(follower) {
          await_follower_barrier(follower)
        }
        match wire_event {
          Some(event) => {
            // Terminal failures are published as the run's Error/Finished
            // pair below; forwarding their raw event as well would make the
            // frontend render the same failure twice. With no run to close
            // (no id recorded yet) that close cannot happen, so the raw
            // event is the report.
            if !host_reports_terminal_error(event) || run_id is None {
              emit(
                sink,
                StreamEvent({
                  run_id,
                  session: engine.session_key,
                  event: { event, submission_id, },
                }),
              )
            }
            match event {
              // A compaction queued behind an open turn begins only now, so
              // the engine's own event is what flips the phase; entering
              // from anything but Idle would clobber a run's state.
              CompactionStarted(..) =>
                if engine.phase is Idle(last_run~) {
                  engine.phase = Compacting(last_run~)
                }
              // Either way the engine is done writing the record's summary,
              // so operations gated on compaction (starts, archiving) may
              // proceed.
              CompactionFinished(..) | CompactionFailed(..) =>
                engine.phase = engine.phase.to_idle()
              _ => ()
            }
            // Closing a run is a state transition, not merely a raw event
            // shape. In particular agent_setup_failed may be followed by
            // turn_failed when its delayed Terminal append itself fails; once
            // the first event idled the run, the second is diagnostic only and
            // must not emit a duplicate Finished for the old run id. The phase
            // flip (into a queued compaction when one is pending, back between
            // turns otherwise) and the steer ledger's terminal cut share this
            // block with the announcement, so no suspension separates them.
            if engine.phase is Running(..) &&
              run_id is Some(id) &&
              close_run_from_stream(sink, id, event) {
              let next_queue = if !turn_died(event) &&
                engine.phase is Running(compact_queued=false, ..) &&
                !engine.queued_runs.is_empty() {
                Some(engine.queued_runs[0])
              } else {
                None
              }
              engine.phase = engine.phase.after_run_close()
              engine.steer_runs.record_terminal(id)
              // A command still queued for the turn that just ended would be
              // misread by the engine, so it is answered here rather than
              // written. What was queued to run AFTER the turn — the
              // compaction `compact_queued` above just entered, a goal —
              // stays: dropping it is what strands a conversation. The sink
              // is a synchronous handoff, so this shares one uninterruptible
              // block with the close above.
              engine.settle_turn_commands(
                "the engine finished its turn before this command was written",
              )
              if next_queue is Some(next) &&
                engine.submit(
                  @protocol.prompt(next.content, submission_id=next.id),
                  failure_reason="failed to promote queued prompt",
                ) {
                ignore(engine.queued_runs.remove(0))
                engine.phase = Running(run_id=next.run_id, compact_queued=false)
                engine.steer_runs.begin_run()
                emit(
                  sink,
                  Started({
                    run_id: next.run_id,
                    submission_id: Some(next.id),
                    engine: Some(engine.engine_name),
                    model: Some(engine.model),
                    max_steps: Some(engine.max_steps),
                    session: engine.session_key,
                    session_root: engine.session_root.map(root => {
                      root.resource_path()
                    }),
                  }),
                )
              }
            }
          }
          None => ()
        }
      }
    }
    // EOF. Retirement is `run`'s, but condemnation must stay synchronous
    // with observing it: leaving this task group is a real suspension, and
    // a cancel or steer admitted in that gap would be accepted for a child
    // that has already stopped reading. Idempotent, so `retire` repeating
    // it is harmless.
    engine.discard_commands("the engine exited")
    // A lifecycle timeout cancels the Process task. Its cancellation handler
    // does not finish until the child has actually terminated, but the task's
    // result is `Cancelled` rather than an exit code; normalize that reaped
    // outcome to -1 so retirement can still publish the EOF latch.
    engine.process.wait() catch {
      error if @async.is_being_cancelled() => raise error
      _ => -1
    }
  }
}

///|
/// EOF retirement — the one lifecycle closer for engine death, whatever
/// discovered it (an observed exit, a failed stdin write, a dead consumer;
/// the discoverer stashes its cause in `pending_failure`). A run still open
/// here is a turn whose terminal event never arrived, so it closes as a
/// failure with that cause. The follower stop below is a drain barrier, not
/// part of the close: it flushes what the departed writer committed to the
/// transcript before the record can be moved.
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
  if owns_slot && owned_follower is Some(follower) {
    stop_follower_instance(manager, follower, writer_exited=true) catch {
      error if @async.is_being_cancelled() => raise error
      // A failed drain leaves the follower installed for archive/detach to
      // retry. Nothing else is owed: what this conversation committed is a
      // question the transcript read answers.
      error =>
        @xlog.debug() <?
          {
            "event": "desktop_follower_final_scan_failed",
            "session": engine.session_key,
            "error": "\{error}",
          }
    }
  }
  match engine.phase {
    // EOF with a run still open means the engine died mid-turn: close
    // that run with its only available diagnostics.
    Running(run_id~, compact_queued~) => {
      engine.phase = engine.phase.to_idle()
      let cause = engine.pending_failure.unwrap_or(
        "engine exited without a result",
      )
      // The stderr tail travels in `diagnostics` only. Repeating it in
      // `message` made every client that renders both print it twice.
      let diagnostics = stderr_task.wait().trim().to_owned()
      emit_error(
        sink,
        cause,
        run_id~,
        exit_code?=code,
        diagnostics?=if diagnostics.is_empty() {
          None
        } else {
          Some(diagnostics)
        },
      )
      emit_finished(sink, run_id, Failed, exit_code?=code)
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
    // A clean exit after a terminal event (session switch, app shutdown)
    // has no cause and reports nothing. One that died holding a cause still
    // has to say so: a command written between turns is confirmed only by
    // the durable item it produces — a goal has nothing but its `[goal]`
    // marker — so a death here leaves that request pending forever with
    // nothing to explain it. Synthesized on the dead engine's behalf, like
    // the compaction failure above, and stamped with the session because an
    // idle engine has no run id to route by.
    Idle(..) =>
      if engine.pending_failure is Some(cause) {
        emit_session_error(sink, engine, cause)
      }
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
/// The engine's "something this session asked for was not persisted", sent on
/// its behalf once it can no longer send anything. It names the failure but
/// not the command that asked, which is exactly what the client does with it:
/// the word gets out, and nothing is settled on it.
fn emit_session_error(
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
        event: (SessionError(error=reason) : @wire.Event),
        submission_id: None,
      },
    }),
  )
}

///|
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
/// A ServeEngine handle for tests, with every bookkeeping field at its spawn
/// default. Adding a field to ServeEngine updates this one site instead of
/// every test that needs a handle.
#cfg(not(platform="windows"))
fn test_serve_engine(
  session : String,
  writer : @process.WriteToProcess,
  process : @process.Process,
  sink : EventSink,
  phase~ : EnginePhase,
  session_root? : @pathx.Absolute,
  follower? : SessionFollower,
  condemned? : Bool = false,
) -> ServeEngine {
  {
    session_key: session,
    session_root,
    spec_key: "test",
    engine_name: "openseek",
    model: "test",
    max_steps: 10,
    writer,
    commands: Queue(kind=Unbounded),
    process,
    sink,
    follower,
    consumer: None,
    phase,
    pending_failure: None,
    condemned,
    steer_runs: SteerRunTracker(),
    queued_runs: [],
  }
}

///|
/// A pump that dies mid-stream must not leave its open run's phase
/// `Running` forever — that state is unreachable by every close path and
/// reads as a turn that never ends. The failure is forced through the same
/// retirement an observed engine death gets, and because this one task both
/// reads and interprets, a stream it cannot read is exactly such a failure:
/// the child is killed rather than left writing into a pipe nobody drains.
#cfg(not(platform="windows"))
async test "a failed pump closes its open run and retires the slot" {
  let manager = new_engine_manager("/bin/sh")
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    let (child_stdin, writer) = @process.write_to_process()
    let (reader, child_stdout) = @process.read_from_process()
    // Unreadable output, then a child that would otherwise outlive the pump:
    // the kill is what ends it, not a cooperative exit.
    let process = @process.spawn(
      group,
      "/bin/sh",
      ["-c", "printf 'not json\\n'; sleep 30"],
      stdin=child_stdin,
      stdout=child_stdout,
      no_wait=true,
    )
    let engine = test_serve_engine(
      "s-consumer-died",
      writer,
      process,
      sink,
      phase=Running(run_id="r-consumer-died", compact_queued=false),
    )
    let sessions : Map[String, SessionSlot] = Map([])
    let slot = slot_for(sessions, "s-consumer-died")
    slot.engine = Some(engine)
    manager.pump = Serving(sessions~)
    let stderr_task = group.spawn(no_wait=true, () => "")
    engine.run(manager, reader, stderr_task)

    // `run` returning is retirement: the run was closed as a failure naming
    // the pump, the child was killed, and the slot is clear.
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
/// An engine that dies between turns still owes the conversation the cause.
/// A command written while idle — a goal, whose only confirmation is its
/// durable `[goal]` marker — would otherwise stay pending forever with
/// nothing to explain it. The report is stamped with the session, because an
/// idle engine has no run id for the client to route by, and it settles
/// nothing: the host cannot know which command the death cost.
#cfg(not(platform="windows"))
async test "an engine that dies between turns still reports why" {
  let manager = new_engine_manager("/bin/sh")
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    let (child_stdin, writer) = @process.write_to_process()
    let (reader, child_stdout) = @process.read_from_process()
    // Malformed stdout from an engine holding no open turn: the pump cannot
    // go on reading it, so the consumer's catch stashes the cause and forces
    // retirement from `Idle`.
    let process = @process.spawn(
      group,
      "/bin/sh",
      ["-c", "printf '%s\\n' 'not json'"],
      stdin=child_stdin,
      stdout=child_stdout,
      no_wait=true,
    )
    let engine = test_serve_engine(
      "s-idle-death",
      writer,
      process,
      sink,
      phase=Idle(last_run=None),
    )
    let sessions : Map[String, SessionSlot] = Map([])
    let slot = slot_for(sessions, "s-idle-death")
    slot.engine = Some(engine)
    manager.pump = Serving(sessions~)
    let stderr_task = group.spawn(no_wait=true, () => "")
    engine.run(manager, reader, stderr_task)

    // No run was open, so nothing is settled — but the cause is out, on the
    // conversation it belongs to.
    assert_true(slot.engine is None)
    assert_false(emitted.any(event => event is Finished(_)))
    let mut reported = ""
    for event in emitted {
      if event is StreamEvent(payload) &&
        payload.event.event is SessionError(error~) {
        assert_eq(payload.session, "s-idle-death")
        assert_true(payload.run_id is None)
        reported = error
      }
    }
    assert_true(reported.contains("the engine's event consumer failed"))
    group.return_immediately(())
  })
}

///|
/// A terminal-class event is reported once, not twice: the close publishes the
/// run's Error/Finished with the engine's own reason, and the raw event that
/// said the same thing stays suppressed. The reason must survive that
/// suppression, or the run would settle as an anonymous "exited without a
/// result".
#cfg(not(platform="windows"))
async test "a failed turn reports its own reason exactly once" {
  let manager = new_engine_manager("/bin/sh")
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    let (child_stdin, writer) = @process.write_to_process()
    let (reader, child_stdout) = @process.read_from_process()
    // A turn that fails and exits: `turn_failed` is both the run's close and
    // the only place its reason is written down.
    let process = @process.spawn(
      group,
      "/bin/sh",
      ["-c", "printf '%s\\n' '{\"event\":\"turn_failed\",\"error\":\"boom\"}'"],
      stdin=child_stdin,
      stdout=child_stdout,
      no_wait=true,
    )
    let engine = test_serve_engine(
      "s-turn-failed",
      writer,
      process,
      sink,
      phase=Running(run_id="r-turn-failed", compact_queued=false),
    )
    let sessions : Map[String, SessionSlot] = Map([])
    let slot = slot_for(sessions, "s-turn-failed")
    slot.engine = Some(engine)
    manager.pump = Serving(sessions~)
    let stderr_task = group.spawn(no_wait=true, () => "")
    engine.run(manager, reader, stderr_task)

    // The raw event stayed suppressed — one report, not two — and the one
    // report carries the engine's own reason rather than the generic cause.
    assert_true(slot.engine is None)
    let mut cause = ""
    let mut finishes = 0
    let mut forwarded = 0
    for event in emitted {
      match event {
        Error(payload) if payload.run_id == Some("r-turn-failed") =>
          cause = payload.message.unwrap_or("")
        Finished(payload) if payload.run_id == "r-turn-failed" => {
          assert_eq(payload.status, "failed")
          finishes += 1
        }
        StreamEvent(_) => forwarded += 1
        _ => ()
      }
    }
    assert_eq(finishes, 1)
    assert_eq(forwarded, 0)
    assert_eq(cause, "turn failed: boom")
    group.return_immediately(())
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
    let (reader, child_stdout) = @process.read_from_process()
    // A child that is already gone, so the first write hits a closed pipe
    // and the pump reaches EOF on its first read.
    let process = @process.spawn(
      group,
      "/bin/sh",
      ["-c", "exit 0"],
      stdin=child_stdin,
      stdout=child_stdout,
      no_wait=true,
    )
    let engine = test_serve_engine(
      "s-write-failed",
      writer,
      process,
      sink,
      phase=Running(run_id="r-write-failed", compact_queued=false),
    )
    let sessions : Map[String, SessionSlot] = Map([])
    let slot = slot_for(sessions, "s-write-failed")
    slot.engine = Some(engine)
    manager.pump = Serving(sessions~)
    engine.wait_process()
    let ack : @async.Queue[EngineError?] = Queue(kind=Blocking(1))
    assert_true(
      engine.submit(
        @protocol.goal_clear(),
        failure_reason="failed to write the goal",
        ack~,
      ),
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
    let stderr_task = group.spawn(no_wait=true, () => "")
    engine.run(manager, reader, stderr_task)
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
  assert_false(host_reports_terminal_error(AgentStep(step=1)))
  assert_false(host_reports_terminal_error(AgentFinished(answer="done")))
  assert_false(
    host_reports_terminal_error(
      ContextYield(to_sequence=1, answer="[context ceiling] checkpointed"),
    ),
  )
  assert_true(host_reports_terminal_error(AgentAborted(reason="interrupted")))
  assert_true(host_reports_terminal_error(MaxStepsExhausted))
  assert_true(host_reports_terminal_error(AgentSetupFailed(error="boom")))
  assert_true(host_reports_terminal_error(TurnFailed(error="boom")))
}

///|
/// A turn's close answers the commands addressed to that turn, and only
/// those. A `/compact` accepted mid-turn is deliberately queued BEHIND the
/// run — the close moves the phase into `Compacting` on its behalf — so
/// dropping it would leave the conversation compacting forever against an
/// engine that was never asked to compact.
#cfg(not(platform="windows"))
async test "a run's close spares the commands queued to outlive its turn" {
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
    let engine = test_serve_engine(
      "s-outlive",
      writer,
      process,
      sink,
      phase=Running(run_id="r-outlive", compact_queued=true),
    )
    // Arrival order: a steer and a cancel aimed at the open turn, with the
    // queued compaction and a goal between them.
    let steer_ack : @async.Queue[EngineError?] = Queue(kind=Blocking(1))
    assert_true(
      engine.submit(
        @protocol.steer("keep going"),
        failure_reason="steer",
        ack=steer_ack,
      ),
    )
    assert_true(engine.submit(@protocol.compact(), failure_reason="compact"))
    let goal_ack : @async.Queue[EngineError?] = Queue(kind=Blocking(1))
    assert_true(
      engine.submit(
        @protocol.goal_set("ship it", auto=false),
        failure_reason="goal",
        ack=goal_ack,
      ),
    )
    assert_true(engine.submit(@protocol.cancel(), failure_reason="cancel"))
    engine.settle_turn_commands("the turn ended")

    // The turn-scoped pair is answered; the engine stays usable.
    guard steer_ack.try_get() is Some(Some(_)) else {
      fail("expected the queued steer to be answered")
    }
    assert_true(goal_ack.try_get() is None)
    assert_false(engine.condemned)

    // The survivors are still queued, still in arrival order.
    let queued = []
    for ;; {
      guard engine.commands.try_get() is Some(next) else { break }
      queued.push(next.command)
    }
    assert_eq(queued, [
      @protocol.compact(),
      @protocol.goal_set("ship it", auto=false),
    ])
    group.return_immediately(())
  })
}

///|
test "a turn that died stops accepting commands for that child" {
  assert_true(turn_died(AgentSetupFailed(error="e")))
  assert_true(turn_died(TurnFailed(error="e")))
  assert_true(turn_died(AgentAborted(reason="r")))
  assert_false(turn_died(AgentFinished(answer="done")))
  assert_false(turn_died(MaxStepsExhausted))
}

///|
/// The stream event that ends a turn is what closes its run, and the outcome
/// it publishes is the one the event spells. An abort reports as aborted: the
/// host no longer tracks whether a cancel is what caused it, and the record
/// keeps the precise account.
test "a terminal stream event closes its run with the event's outcome" {
  fn closed(event : @wire.Event) -> (Bool, Array[EngineEvent]) {
    let emitted : Array[EngineEvent] = []
    let sink = EventSink(fn(event) { emitted.push(event) })
    (close_run_from_stream(sink, "r17", event), emitted)
  }

  assert_eq(closed(AgentStep(step=1)).0, false)
  guard closed(AgentFinished(answer="done")) is (true, [Finished(finish)]) else {
    fail("expected exactly one finished event")
  }
  assert_eq(finish.run_id, "r17")
  assert_eq(finish.status, "finished")
  assert_eq(finish.answer, Some("done"))
  guard closed(
      ContextYield(to_sequence=3, answer="[context ceiling] checkpointed"),
    )
    is (true, [Finished(yielded)]) else {
    fail("expected exactly one finished event")
  }
  assert_eq(yielded.status, "context_yield")
  assert_eq(yielded.answer, Some("[context ceiling] checkpointed"))
  guard closed(AgentAborted(reason="interrupted"))
    is (true, [Error(error), Finished(aborted)]) else {
    fail("expected an error and a finished event")
  }
  assert_eq(error.message, Some("agent aborted: interrupted"))
  assert_eq(aborted.status, "aborted")
  guard closed(MaxStepsExhausted) is (true, [Error(_), Finished(exhausted)]) else {
    fail("expected an error and a finished event")
  }
  assert_eq(exhausted.status, "max_steps_exhausted")
  guard closed(AgentSetupFailed(error="boom"))
    is (true, [Error(setup_failure), Finished(setup_finished)]) else {
    fail("expected an error and a finished event")
  }
  assert_eq(setup_failure.message, Some("agent setup failed: boom"))
  assert_eq(setup_finished.status, "failed")
  guard closed(TurnFailed(error="boom"))
    is (true, [Error(failure), Finished(failed)]) else {
    fail("expected an error and a finished event")
  }
  assert_eq(failure.message, Some("turn failed: boom"))
  assert_eq(failed.status, "failed")
}

///|
test "context yield has a distinct non-success wire status" {
  let status : RunStatus = ContextYield
  assert_eq(status.wire(), "context_yield")
}

///|
test "run ids are distinct" {
  let first = mint_run_id()
  let second = mint_run_id()
  assert_not_eq(first, second)
}

///|
test "terminal closure preserves a queued compaction" {
  assert_true(
    Running(run_id="r-1", compact_queued=false).after_run_close()
    is Idle(last_run=Some("r-1")),
  )
  assert_true(
    Running(run_id="r-1", compact_queued=true).after_run_close()
    is Compacting(last_run=Some("r-1")),
  )
}

///|
test "trailing steer settle events keep the terminal run id" {
  let tracker = SteerRunTracker::SteerRunTracker()
  tracker.begin_run()
  ignore(tracker.record_sent("old steer", Some("submission-old")))
  tracker.record_terminal("r41")
  tracker.begin_run()
  ignore(tracker.record_sent("fresh steer", Some("submission-fresh")))
  let old_drop : @wire.Event? = Some(SteerDropped(content="old steer"))
  let fresh_apply : @wire.Event? = Some(
    SteerApplied(kind="prompt", content="fresh steer"),
  )
  assert_eq(
    tracker.route_event(old_drop, Some("r42")),
    (Some("r41"), Some("submission-old")),
  )
  assert_eq(
    tracker.route_event(fresh_apply, Some("r42")),
    (Some("r42"), Some("submission-fresh")),
  )
}

///|
test "equal steer text receipts retain writer-order submission ids" {
  let tracker = SteerRunTracker::SteerRunTracker()
  tracker.begin_run()
  ignore(tracker.record_sent("same", Some("submission-a")))
  ignore(tracker.record_sent("same", Some("submission-b")))
  let receipt : @wire.Event? = Some(SteerApplied(kind="prompt", content="same"))
  let (first_run, first_submission) = tracker.route_event(receipt, Some("r9"))
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
  let (second_run, second_submission) = tracker.route_event(receipt, Some("r9"))
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
  let tracker = SteerRunTracker::SteerRunTracker()
  tracker.begin_run()
  ignore(tracker.record_sent("legacy", None))
  let decoded : @wire.Event? = Some(
    SteerApplied(kind="prompt", content="legacy"),
  )
  let (_, submission_id) = tracker.route_event(decoded, Some("r11"))
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
  let tracker = SteerRunTracker::SteerRunTracker()
  tracker.begin_run()
  ignore(tracker.record_sent("old steer", Some("submission-old")))
  tracker.record_terminal("r7")
  assert_eq(
    tracker.route_event(Some(AgentStep(step=1)), Some("r8")),
    (Some("r8"), None),
  )
  let old_drop : @wire.Event? = Some(SteerDropped(content="old steer"))
  assert_eq(tracker.route_event(old_drop, Some("r8")), (Some("r8"), None))
}

///|
test "background events do not clear trailing steer receipts" {
  let tracker = SteerRunTracker::SteerRunTracker()
  tracker.begin_run()
  ignore(tracker.record_sent("first", Some("submission-first")))
  ignore(tracker.record_sent("second", Some("submission-second")))
  tracker.record_terminal("r-old")
  tracker.begin_run()
  assert_eq(tracker.route_event(None, Some("r-new")), (Some("r-new"), None))
  assert_eq(
    tracker.route_event(
      Some(SteerApplied(kind="prompt", content="first")),
      Some("r-new"),
    ),
    (Some("r-old"), Some("submission-first")),
  )
  assert_eq(
    tracker.route_event(Some(SteerDropped(content="second")), Some("r-new")),
    (Some("r-old"), Some("submission-second")),
  )
}

///|
test "only prompt steer_applied consumes a desktop steer" {
  let tracker = SteerRunTracker::SteerRunTracker()
  tracker.begin_run()
  ignore(tracker.record_sent("same", Some("submission-prompt")))
  let prompt : @wire.Event? = Some(SteerApplied(kind="prompt", content="same"))
  let command : @wire.Event? = Some(
    SteerApplied(kind="command", content="same"),
  )
  let notice : @wire.Event? = Some(SteerApplied(kind="notice", content="same"))
  assert_eq(tracker.route_event(command, Some("r1")), (Some("r1"), None))
  assert_eq(tracker.route_event(notice, Some("r1")), (Some("r1"), None))
  assert_eq(
    tracker.route_event(prompt, Some("r1")),
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
  defer (@fs.rmdir(root.to_string(), recursive=true) catch { _ => () })
  // Every packaged platform uses the same `seekmoon/` tree below Proton's
  // resource directory, so engine process setup observes one layout.
  let input = root.join("Resources/seekmoon")
  let engine = input.join("bin/openseek")
  let seed = input.join("toolchains/moonbit/macos-arm64")
  let runtime = root.join("runtime")
  let moon_home = runtime.join("toolchains/moonbit/macos-arm64")
  prepare_fake_moonbit_seed(seed, version="0.10.0-test")
  prepare_fake_bundled_moonbit_home(moon_home, version="0.10.0-test")
  let config : RunConfig = {
    task: "t",
    api_key: "k",
    key_env: "DEEPSEEK",
    api_url: None,
    model: "m",
    thinking: ThinkingHigh,
    max_steps: 1,
    engine: engine.to_string(),
    cwd: None,
    session: "s-env",
    session_root: None,
  }
  let env = engine_process_env(config, Some(runtime))
  assert_eq(env["OPENSEEK_THINKING"], "high")
  assert_eq(env["DEEPSEEK"], "k")
  // This payload carries no `share/doc/moonbit/` yet: the engine env must
  // not invent an OPENSEEK_REFERENCES the host did not resolve.
  assert_true(env.get("OPENSEEK_REFERENCES") is None)
  // The moonbit-docs markdown build travels inside the seed and therefore
  // inside the prepared payload, so the engine is pointed at the runtime
  // copy — the durable prompt embeds this path, and it must never name a
  // bundle location that unmounts when the app exits.
  write_fake_file(moon_home.join("share/doc/moonbit/language/index.md"))
  let env_with_references = engine_process_env(config, Some(runtime))
  assert_eq(
    env_with_references["OPENSEEK_REFERENCES"],
    moon_home.join("share/doc/moonbit").to_string(),
  )
  // A GLM run's key travels in GLM, and the resolved variable — not a
  // hardcoded DEEPSEEK — is what the process env honors.
  let glm_env = engine_process_env(
    { ..config, key_env: "GLM", model: "glm-5.3", },
    Some(runtime),
  )
  assert_eq(glm_env["GLM"], "k")
  @debug.assert_eq(engine_process_args(config), [
    "serve", "--session=s-env", "--dir", ".", "--approval", "ask",
  ])
  @debug.assert_eq(engine_process_args({ ..config, session: "--resume", }), [
    "serve", "--session=--resume", "--dir", ".", "--approval", "ask",
  ])
  let explicit_root = root.join("sessions").resolve()
  @debug.assert_eq(
    engine_process_args({ ..config, session_root: Some(explicit_root), }),
    [
      "serve",
      "--session=s-env",
      "--session-root=\{explicit_root.to_string()}",
      "--dir",
      ".",
      "--approval",
      "ask",
    ],
  )
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
  defer @fs.rmdir(dir, recursive=true)
  let baseline_engine = dir + "/baseline.sh"
  @fs.write_file(
    baseline_engine,
    "#!/bin/sh\nprintf '%s' '{\"events\":[]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", baseline_engine]), 0)
  let manager = new_engine_manager(baseline_engine)
  let sink = EventSink(fn(_) { () })
  let slot : SessionSlot = { pending: None, engine: None, }
  let config : RunConfig = {
    task: "test",
    api_key: "test",
    key_env: "DEEPSEEK",
    api_url: None,
    model: "test",
    thinking: ThinkingMax,
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
    key_env: "DEEPSEEK",
    api_url: None,
    model: "test",
    thinking: ThinkingMax,
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
