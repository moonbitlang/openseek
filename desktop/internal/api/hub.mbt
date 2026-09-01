// The fan-out point between the engine's EventSink and every connected
// client. Notifications are pushed to each subscriber's bounded queue; a
// subscriber that cannot keep up is dropped, per the protocol's
// reconnect-equals-resync contract (docs/remote-protocol.md) — the client
// reconnects and rebuilds state through `session.list` + `agent.runs`.

///|
/// A subscriber queue's bound. Generous — the desktop webview and a healthy
/// browser drain far faster than the engine produces — so hitting it means
/// the connection is wedged, and the protocol's answer to a wedged
/// connection is to close it.
const SubscriberQueueCapacity = 1024

///|
/// A client must acknowledge terminal steer rows. Older or disconnected
/// clients may never do so, therefore admission has a hard process-wide cap:
/// once full, a new id-bearing steer is refused before it reaches the engine.
const SteerSettlementCapacity = 4096

///|
/// The hub is owned by `ApiState`; transports reach it through
/// `ApiState::subscribe`/`unsubscribe`.
priv struct Hub {
  subscribers : Array[@async.Queue[@protocol.Notification]]
  // The typed `agent.started` payload of every run still in flight, keyed by run
  // id — the source for `agent.runs`, which is how a client that joins (or
  // reconnects) mid-run learns the run's identity. Insertion order is
  // run-start order.
  active_starts : Map[String, @protocol.StartedPayload]
  // Completed lifecycle records survive client reconnects for this host
  // process, so a reconnecting owner learns how its run ended. Run ids carry
  // host-wide random identity, so they are the deduplication key.
  settlements : Map[String, RunSettlement]
  // Exact steer submissions accepted by this host process. Unlike the live
  // notification, this ledger survives a subscriber gap long enough for the
  // submitting client to ask whether its input is pending, applied, or
  // dropped. Submission ids are page-unique ownership keys.
  steer_settlements : Map[String, SteerSettlement]
  // The permission question each session's engine is currently blocked on,
  // keyed by SESSION, because one engine can only be blocked on one at a time:
  // the asking tool is not `concurrent_safe`, so nothing runs beside it. That
  // is the same reason the frontend holds a field rather than a queue.
  //
  // The same job `active_starts` does, for the one piece of live state a
  // reloading client cannot rebuild any other way. A transcript comes back
  // from the durable record; an approval request was never in it — it is a
  // live event with no deadline behind it — so without this a reloaded
  // frontend recovers the whole turn except the question holding it up, and
  // the only way out is to cancel the run.
  pending_approvals : Map[String, @protocol.PendingApprovalPayload]
}

///|
fn Hub::Hub() -> Hub {
  {
    subscribers: [],
    active_starts: Map([]),
    settlements: Map([]),
    steer_settlements: Map([]),
    pending_approvals: Map([]),
  }
}

///|
/// The reconnect-safe subset of Finished.
priv struct RunSettlement {
  run_id : String
  mut session : String
  mut submission_id : String?
  status : String
  mut exit_code : Int?
}

///|
priv struct SteerSettlement {
  session : String
  run_id : String
  submission_id : String
  mut status : String
}

///|
fn SteerSettlement::wire_payload(
  self : SteerSettlement,
) -> @protocol.SteerSettlementPayload {
  {
    session: self.session,
    run_id: self.run_id,
    submission_id: self.submission_id,
    status: self.status,
  }
}

///|
fn RunSettlement::wire_payload(
  self : RunSettlement,
) -> @protocol.RunSettlementPayload {
  {
    run_id: self.run_id,
    session: self.session,
    submission_id: self.submission_id,
    status: self.status,
    exit_code: self.exit_code,
  }
}

///|
/// Capture Finished while its Started row is still present. A duplicate
/// lifecycle event fills in evidence the first one lacked and nothing else.
fn Hub::record_finished(
  self : Hub,
  payload : @protocol.FinishedPayload,
) -> Unit {
  let mut session = ""
  let mut submission_id : String? = None
  if self.active_starts.get(payload.run_id) is Some(started) {
    session = started.session
    if started.submission_id is Some(value) {
      submission_id = Some(value)
    }
  }
  if self.settlements.get(payload.run_id) is Some(existing) {
    if existing.session.is_empty() && !session.is_empty() {
      existing.session = session
    }
    if existing.submission_id is None && submission_id is Some(value) {
      existing.submission_id = Some(value)
    }
    if existing.exit_code is None && payload.exit_code is Some(value) {
      existing.exit_code = Some(value)
    }
    return
  }
  self.settlements[payload.run_id] = {
    run_id: payload.run_id,
    session,
    submission_id,
    status: payload.status,
    exit_code: payload.exit_code,
  }
}

///|
/// Reserve bounded recovery capacity before an id-bearing steer reaches the
/// engine. This check and the synchronous engine submission have no suspension
/// between them, so another request cannot consume the admitted slot first.
fn Hub::admits_steer(self : Hub, payload : @protocol.SteerPayload) -> Bool {
  guard @engine.normalize_submission_id(payload.submission_id)
    is Some(submission_id) else {
    // Legacy and malformed ids remain untracked; the engine applies the same
    // normalization before echoing a receipt, so the two layers cannot drift.
    return true
  }
  self.steer_settlements.get(submission_id) is None &&
  self.steer_settlements.length() < SteerSettlementCapacity
}

///|
/// Record the synchronous acceptance boundary of one steer. A receipt may
/// race this endpoint return; never overwrite a terminal row already captured
/// from the engine stream.
fn Hub::record_steer_accepted(
  self : Hub,
  payload : @protocol.SteerPayload,
  reply : @protocol.SteerReply,
) -> Unit {
  guard reply.steered &&
    reply.run_id is Some(run_id) &&
    @engine.normalize_submission_id(payload.submission_id)
    is Some(submission_id) &&
    self.active_starts.get(run_id) is Some(started) else {
    return
  }
  if self.steer_settlements.get(submission_id) is Some(existing) {
    // Globally unique ids make a different owner a malformed reuse. Preserve
    // the first identity rather than cross-wiring two clients.
    if existing.session == started.session && existing.run_id == run_id {
      return
    }
    return
  }
  self.steer_settlements[submission_id] = {
    session: started.session,
    run_id,
    submission_id,
    status: "pending",
  }
}

///|
/// Terminal rows remain replayable until their exact owner consumes them.
/// Pending rows cannot be acknowledged: they are the evidence a reconnecting
/// client still needs while the engine owes a receipt.
fn Hub::ack_steer(
  self : Hub,
  payload : @protocol.SteerSettlementAckPayload,
) -> Unit {
  guard self.steer_settlements.get(payload.submission_id) is Some(existing) &&
    existing.session == payload.session &&
    existing.run_id == payload.run_id &&
    existing.status != "pending" else {
    return
  }
  self.steer_settlements.remove(payload.submission_id)
}

///|
/// Capture the exact id-bearing engine receipt before publishing it. If the
/// subscriber drops that live frame, `agent.runs` can replay this outcome.
fn Hub::track_steer(self : Hub, payload : @protocol.AgentEventPayload) -> Unit {
  let status = match payload.event.event {
    SteerApplied(..) => Some("applied")
    SteerDropped(..) => Some("dropped")
    _ => None
  }
  guard status is Some(status) &&
    payload.run_id is Some(run_id) &&
    @engine.normalize_submission_id(payload.event.submission_id)
    is Some(submission_id) else {
    return
  }
  if self.steer_settlements.get(submission_id) is Some(existing) {
    if existing.session == payload.session && existing.run_id == run_id {
      existing.status = status
    }
    return
  }
  guard self.steer_settlements.length() < SteerSettlementCapacity else {
    // Every admitted id already has a pending row. Reaching this branch means
    // an unsolicited/malformed receipt, which must not bypass the hard cap.
    return
  }
  self.steer_settlements[submission_id] = {
    session: payload.session,
    run_id,
    submission_id,
    status,
  }
}

///|
/// Push one notification to every live subscriber. `try_put` never
/// suspends, so the order every subscriber sees is the publish order. A
/// full queue marks its subscriber dead: the queue is closed (ending the
/// connection's writer) and dropped. Only the hub ever closes a subscribed
/// queue, and it removes the queue from `subscribers` in the same breath,
/// so `try_put` on a closed queue cannot happen — `try!` turns that
/// invariant into a hard stop instead of a silent discard.
fn Hub::publish(self : Hub, notification : @protocol.Notification) -> Unit {
  match notification {
    AgentStarted(payload) => self.active_starts[payload.run_id] = payload
    // Error is diagnostic, not a lifecycle boundary: the engine publishes
    // Finished only after it has closed the run. Removing on Error would let
    // a concurrent `agent.runs` snapshot report a still-draining run idle.
    AgentFinished(payload) => {
      self.record_finished(payload)
      self.active_starts.remove(payload.run_id)
      // A turn cannot end with a tool still blocked inside it, so anything
      // left here belongs to a question that died with the run. The engine
      // settles its own on the way out; this covers the engine that did not
      // get to — a killed process emits no `approval_resolved`.
      self.forget_run_approvals(payload.run_id)
    }
    AgentEvent(payload) => {
      self.track_approval(payload)
      self.track_steer(payload)
    }
    _ => ()
  }
  let wedged : Array[Int] = []
  for index, queue in self.subscribers {
    if !(try! queue.try_put(notification)) {
      wedged.push(index)
    }
  }
  if wedged.length() > 0 {
    @xlog.warn(category="transport") <?
      {
        "event": "hub_subscriber_evicted",
        "count": wedged.length(),
        "notification": notification.wire_name(),
        "queue_capacity": SubscriberQueueCapacity,
      }
  }
  // Back to front, so the collected indices stay valid while removing.
  for cursor in wedged.rev_iter() {
    let queue = self.subscribers.remove(cursor)
    // The failed put already made this stream incomplete. Drop its buffered
    // prefix as well so the consumer reaches the reconnect/resync boundary
    // immediately instead of rendering stale notifications first.
    queue.close(clear=true)
  }
}

///|
/// Follow one engine event's effect on the standing questions.
///
/// Only the two approval events matter, and only for their bookkeeping — the
/// notification itself is published to live subscribers either way. What this
/// adds is the answer for a subscriber that was not there to hear it.
fn Hub::track_approval(
  self : Hub,
  payload : @protocol.AgentEventPayload,
) -> Unit {
  match payload.event.event {
    ApprovalRequested(id~, tool_name~, detail~, body~) =>
      self.pending_approvals[payload.session] = {
        id,
        session: payload.session,
        run_id: payload.run_id,
        tool_name,
        detail,
        body,
      }
    // Settled by whoever answered it, including this host's own client. The
    // question is gone for every client at once, which is why the resolution
    // is broadcast rather than sent to the answerer alone.
    //
    // Checked by id as well as session, so a resolution that raced a newer
    // question into the same slot retires nothing.
    ApprovalResolved(id~, ..) =>
      if self.pending_approvals.get(payload.session) is Some(standing) &&
        standing.id == id {
        self.pending_approvals.remove(payload.session)
      }
    _ => ()
  }
}

///|
/// Drop every question belonging to `run_id`.
fn Hub::forget_run_approvals(self : Hub, run_id : String) -> Unit {
  let doomed : Array[String] = []
  for session, approval in self.pending_approvals {
    if approval.run_id is Some(owner) && owner == run_id {
      doomed.push(session)
    }
  }
  for session in doomed {
    self.pending_approvals.remove(session)
  }
}

///|
fn Hub::subscribe(self : Hub) -> @async.Queue[@protocol.Notification] {
  let queue : @async.Queue[@protocol.Notification] = Queue(
    kind=Blocking(SubscriberQueueCapacity),
  )
  self.subscribers.push(queue)
  queue
}

///|
/// Drop a subscriber by queue identity and close its queue, waking a writer
/// blocked on `get`. Unsubscribing twice is fine; so is unsubscribing a
/// queue the hub already kicked.
fn Hub::unsubscribe(
  self : Hub,
  queue : @async.Queue[@protocol.Notification],
) -> Unit {
  for index, candidate in self.subscribers {
    if physical_equal(candidate, queue) {
      ignore(self.subscribers.remove(index))
      queue.close()
      break
    }
  }
}

///|
/// The `agent.runs` reply: every in-flight run's `agent.started` params, in
/// run-start order (the map preserves insertion order), plus the settlements
/// named by the caller's own reconnect selectors. This function has no
/// suspension point, so active runs and settlements form one atomic view.
fn Hub::runs(
  self : Hub,
  known? : Array[KnownRunPayload],
) -> @protocol.RunsReply {
  let runs : Array[@protocol.StartedPayload] = []
  for _, payload in self.active_starts {
    runs.push(payload)
  }
  let settled : Array[@protocol.RunSettlementPayload] = []
  if known is Some(selectors) {
    for _, settlement in self.settlements {
      if selectors.any(selector => settlement_matches(settlement, selector)) {
        settled.push(settlement.wire_payload())
      }
    }
  }
  // Replayed unconditionally, unlike `settled`: a settlement is history a
  // client only wants for runs it owns, while a standing question is a turn
  // stopped RIGHT NOW that anyone looking at that session should be able to
  // answer.
  let approvals : Array[@protocol.PendingApprovalPayload] = []
  for _, approval in self.pending_approvals {
    approvals.push(approval)
  }
  let steers : Array[@protocol.SteerSettlementPayload] = []
  if known is Some(selectors) {
    for selector in selectors {
      if selector.submission_id is Some(submission_id) &&
        self.steer_settlements.get(submission_id) is Some(steer) &&
        steer_matches(steer, selector) &&
        !steers.iter().any(row => row.submission_id == submission_id) {
        steers.push(steer.wire_payload())
      }
    }
  }
  { runs, settled, approvals, steers: Some(steers), }
}

///|
/// Present selector fields are conjunctive. At least one owner id is required;
/// a session alone must not expose that session's completion history.
fn settlement_matches(
  settlement : RunSettlement,
  selector : KnownRunPayload,
) -> Bool {
  (selector.run_id is Some(_) || selector.submission_id is Some(_)) &&
  settlement.session == selector.session &&
  selector.run_id.map_or(true, run_id => settlement.run_id == run_id) &&
  selector.submission_id.map_or(true, submission_id => {
    settlement.submission_id == Some(submission_id)
  })
}

///|
fn steer_matches(steer : SteerSettlement, selector : KnownRunPayload) -> Bool {
  selector.run_id is Some(run_id) &&
  selector.submission_id is Some(submission_id) &&
  steer.session == selector.session &&
  steer.run_id == run_id &&
  steer.submission_id == submission_id
}

///|
/// A real engine Connected event marks a new pump lifetime. Consumers from
/// the old task group may have been cancelled before emitting Finished, so
/// their starts are no longer live and must be cleared before readiness is
/// published. Per-WebSocket synthetic ready frames do not pass through here.
fn Hub::engine_connected(
  self : Hub,
  payload : @protocol.ConnectedPayload,
) -> Unit {
  // The old pump can disappear without publishing Finished. Turn every live
  // row into reconnect-safe failure evidence before clearing it, so a delayed
  // accepted start response cannot resurrect a run the new pump does not own.
  for run_id, started in self.active_starts {
    if self.settlements.get(run_id) is None {
      self.settlements[run_id] = {
        run_id,
        session: started.session,
        submission_id: started.submission_id,
        status: "failed",
        exit_code: None,
      }
    }
  }
  // An accepted steer still pending in the departed process can no longer be
  // applied. Exact outcomes already observed remain terminal and unchanged.
  for _, steer in self.steer_settlements {
    if steer.status == "pending" &&
      self.active_starts.get(steer.run_id) is Some(_) {
      steer.status = "dropped"
    }
  }
  self.active_starts.clear()
  // A question belongs to the engine process that asked it: the reply queue
  // it was blocking on died with that process, so replaying it would offer an
  // answer with nowhere to go.
  self.pending_approvals.clear()
  self.publish(AgentConnected(payload))
}

///|
/// The hub as the engine package's event sink, mapping engine events onto
/// the catalog's `agent.*` notifications. `on_finished` additionally hands
/// finished runs to the embedding host — the desktop's system notification.
fn Hub::sink(
  self : Hub,
  on_finished? : (@protocol.FinishedPayload) -> Unit,
) -> @engine.EventSink {
  EventSink(event => {
    match event {
      Connected(payload) => self.engine_connected(payload)
      Started(payload) => self.publish(AgentStarted(payload))
      StreamEvent(payload) => self.publish(AgentEvent(payload))
      Error(payload) => self.publish(AgentError(payload))
      Finished(payload) => {
        if on_finished is Some(notify) {
          notify(payload)
        }
        self.publish(AgentFinished(payload))
      }
      // The canonical transcript channel: one durably committed store event.
      // Clients that understand it build their durable transcript from these
      // plus `session.load` snapshots; the `agent.event` stream above only
      // settles transient stream and lifecycle state in commit-aware clients
      // (docs/remote-protocol.md).
      SessionCommit(payload) => self.publish(SessionEvent(payload))
      // Liveness for a sub-run in flight. Nothing downstream persists it:
      // a client that arrives late simply learns nothing about a child's
      // progress until its next advance.
      SubrunProgress(payload) => self.publish(SubrunProgress(payload))
      // A failed command may have settled lifecycle before its process was
      // reapable. This later durable boundary is not a second finish: it must
      // not post another system notification or mutate the live-runs table.
    }
  })
}

///|
test "a real engine connection retires old active runs before readiness" {
  let hub = Hub::Hub()
  let subscriber = hub.subscribe()
  hub.publish(
    AgentStarted(
      @json.from_json({
        "run_id": "r-old",
        "session": "s-old",
        "submission_id": "sub-old",
      }),
    ),
  )
  guard hub.runs().runs is [_] else {
    fail("expected one active run before reconnect")
  }
  hub.engine_connected({ stage: Serving, })
  guard hub.runs().runs is [] else {
    fail("old active run survived a new engine pump")
  }
  guard hub.runs(known=[
      { session: "s-old", run_id: None, submission_id: Some("sub-old"), },
    ]).settled
    is [{ run_id: "r-old", status: "failed", .. }] else {
    fail("the departed pump did not leave reconnect-safe settlement evidence")
  }
  guard subscriber.try_get() is Some(started) else {
    fail("missing started notification")
  }
  assert_eq(started.wire_name(), "agent.started")
  guard subscriber.try_get() is Some(connected) else {
    fail("missing connected notification")
  }
  assert_eq(connected.wire_name(), "agent.connected")
}

///|
test "agent.runs replays exact steer state across a subscriber gap" {
  let hub = Hub::Hub()
  hub.publish(
    AgentStarted(
      @json.from_json({
        "run_id": "r-steer",
        "session": "s-steer",
        "submission_id": "prompt-steer",
      }),
    ),
  )
  let payload : @protocol.SteerPayload = {
    text: "turn left",
    run_id: Some("r-steer"),
    submission_id: Some("steer-1"),
  }
  hub.record_steer_accepted(payload, { steered: true, run_id: Some("r-steer"), })
  let selector : KnownRunPayload = {
    session: "s-steer",
    run_id: Some("r-steer"),
    submission_id: Some("steer-1"),
  }
  guard hub.runs(known=[selector]).steers is Some([{ status: "pending", .. }]) else {
    fail("accepted steer was not replayed as pending")
  }
  hub.publish(
    AgentEvent({
      run_id: Some("r-steer"),
      session: "s-steer",
      event: {
        event: SteerApplied(kind="prompt", content="turn left"),
        submission_id: Some("steer-1"),
      },
    }),
  )
  guard hub.runs(known=[selector]).steers is Some([{ status: "applied", .. }]) else {
    fail("lost applied receipt was not replayable")
  }
  // A selector must carry the complete owner; the submission id alone cannot
  // expose another run's steering history.
  guard hub.runs(known=[
      { session: "s-steer", run_id: None, submission_id: Some("steer-1"), },
    ]).steers
    is Some([]) else {
    fail("an incomplete steer selector received a settlement")
  }
}

///|
test "steer ledger normalizes ids, acknowledges terminal rows, and stays bounded" {
  let hub = Hub::Hub()
  hub.publish(
    AgentStarted(
      @json.from_json({ "run_id": "r-ledger", "session": "s-ledger" }),
    ),
  )
  let overlong = "x".repeat(129)
  let malformed : @protocol.SteerPayload = {
    text: "legacy input",
    run_id: Some("r-ledger"),
    submission_id: Some(overlong),
  }
  assert_true(hub.admits_steer(malformed))
  hub.record_steer_accepted(malformed, {
    steered: true,
    run_id: Some("r-ledger"),
  })
  assert_eq(hub.steer_settlements.length(), 0)

  let payload : @protocol.SteerPayload = {
    text: "tracked input",
    run_id: Some("r-ledger"),
    submission_id: Some("steer-ledger"),
  }
  assert_true(hub.admits_steer(payload))
  hub.record_steer_accepted(payload, {
    steered: true,
    run_id: Some("r-ledger"),
  })
  let ack : @protocol.SteerSettlementAckPayload = {
    session: "s-ledger",
    run_id: "r-ledger",
    submission_id: "steer-ledger",
  }
  hub.ack_steer(ack)
  assert_eq(hub.steer_settlements.length(), 1)
  hub.publish(
    AgentEvent({
      run_id: Some("r-ledger"),
      session: "s-ledger",
      event: {
        event: SteerApplied(kind="prompt", content="tracked input"),
        submission_id: Some("steer-ledger"),
      },
    }),
  )
  hub.ack_steer(ack)
  assert_eq(hub.steer_settlements.length(), 0)

  for index = 0; index < SteerSettlementCapacity; index = index + 1 {
    let submission_id = "held-" + index.to_string()
    hub.steer_settlements[submission_id] = {
      session: "s-ledger",
      run_id: "r-ledger",
      submission_id,
      status: "applied",
    }
  }
  assert_false(
    hub.admits_steer({
      text: "one too many",
      run_id: Some("r-ledger"),
      submission_id: Some("overflow"),
    }),
  )
  hub.ack_steer({
    session: "s-ledger",
    run_id: "r-ledger",
    submission_id: "held-0",
  })
  assert_true(
    hub.admits_steer({
      text: "slot released",
      run_id: Some("r-ledger"),
      submission_id: Some("replacement"),
    }),
  )
}

///|
test "a new engine pump drops steers still pending in the old process" {
  let hub = Hub::Hub()
  hub.publish(
    AgentStarted(@json.from_json({ "run_id": "r-old", "session": "s-old" })),
  )
  hub.record_steer_accepted(
    {
      text: "old input",
      run_id: Some("r-old"),
      submission_id: Some("steer-old"),
    },
    { steered: true, run_id: Some("r-old"), },
  )
  hub.engine_connected({ stage: Serving, })
  guard hub.runs(known=[
      {
        session: "s-old",
        run_id: Some("r-old"),
        submission_id: Some("steer-old"),
      },
    ]).steers
    is Some([{ status: "dropped", .. }]) else {
    fail("the departed engine left an accepted steer pending forever")
  }
}

///|
test "an agent error does not retire a run before its finished boundary" {
  let hub = Hub::Hub()
  hub.publish(
    AgentStarted(@json.from_json({ "run_id": "r1", "session": "s1" })),
  )
  hub.publish(
    AgentError(@json.from_json({ "run_id": "r1", "message": "boom" })),
  )
  guard hub.runs().runs is [_] else {
    fail("agent.error retired a still-draining run")
  }
  hub.publish(
    AgentFinished(@json.from_json({ "run_id": "r1", "status": "failed" })),
  )
  guard hub.runs().runs is [] else {
    fail("agent.finished did not retire the run")
  }
}

///|
test "a kicked subscriber drops its stale backlog but keeps the finish replayable" {
  let hub = Hub::Hub()
  let subscriber = hub.subscribe()
  hub.publish(
    AgentStarted(
      @json.from_json({
        "run_id": "r-overflow",
        "session": "s-overflow",
        "submission_id": "sub-overflow",
      }),
    ),
  )
  // Fill the subscriber without draining it. The terminal notification is
  // the first frame that cannot fit, reproducing a renderer that fell behind
  // during a long, high-volume turn.
  for _ in 1..<SubscriberQueueCapacity {
    hub.publish(AgentConnected({ stage: Serving, }))
  }
  hub.publish(
    AgentFinished(
      @json.from_json({
        "run_id": "r-overflow",
        "status": "finished",
        "exit_code": 0,
      }),
    ),
  )
  assert_eq(hub.subscribers.length(), 0)
  // Once one frame is missing, none of the queued frames is a complete
  // stream any more. A reconnect must start from agent.connected + resync,
  // not spend time rendering a stale prefix first.
  let retained = subscriber.try_get() catch { _ => None }
  assert_eq(retained, None)
  guard hub.runs(known=[
      {
        session: "s-overflow",
        run_id: Some("r-overflow"),
        submission_id: Some("sub-overflow"),
      },
    ]).settled
    is [settlement] else {
    fail("the dropped finish was not retained for lifecycle resync")
  }
  assert_eq(settlement.status, "finished")
  assert_eq(settlement.exit_code, Some(0))
}

///|
test "a normal terminal-backed finish is replayable only to a matching caller" {
  let hub = Hub::Hub()
  hub.publish(
    AgentStarted(
      @json.from_json({
        "run_id": "r-normal",
        "session": "s-normal",
        "submission_id": "sub-normal",
      }),
    ),
  )
  hub.publish(
    AgentFinished(
      @json.from_json({
        "run_id": "r-normal",
        "status": "finished",
        "exit_code": 0,
      }),
    ),
  )
  let reply = hub.runs(known=[
    {
      session: "s-normal",
      run_id: Some("r-normal"),
      submission_id: Some("sub-normal"),
    },
    // A second matching selector must not duplicate the ledger row.
    { session: "s-normal", run_id: None, submission_id: Some("sub-normal"), },
  ])
  guard reply.runs is [] && reply.settled is [settlement] else {
    fail("matching reconnect identity did not receive one settlement")
  }
  assert_eq(settlement.run_id, "r-normal")
  assert_eq(settlement.session, "s-normal")
  assert_eq(settlement.submission_id, Some("sub-normal"))
  assert_eq(settlement.status, "finished")
  assert_eq(settlement.exit_code, Some(0))

  let mismatched = hub.runs(known=[
    {
      session: "other-session",
      run_id: Some("r-normal"),
      submission_id: Some("sub-normal"),
    },
    { session: "s-normal", run_id: Some("other-run"), submission_id: None, },
    {
      session: "s-normal",
      run_id: None,
      submission_id: Some("other-submission"),
    },
    // A session alone is not an owner selector and must not expose that
    // session's process-lifetime completion history.
    { session: "s-normal", run_id: None, submission_id: None, },
  ])
  guard mismatched.settled is [] else {
    fail("a non-matching reconnect identity received a settlement")
  }
}

///|
/// A run that ended abnormally is as replayable as one that ended cleanly.
/// The host published that outcome; a reconnecting owner is entitled to it,
/// and how much the run wrote is a question the record answers when it is
/// read — not something the settlement has to prove first.
test "an abnormal finish is replayable to its own caller" {
  let hub = Hub::Hub()
  hub.publish(
    AgentStarted(
      @json.from_json({
        "run_id": "r-zero",
        "session": "s-zero",
        "submission_id": "sub-zero",
      }),
    ),
  )
  hub.publish(
    AgentFinished(
      @json.from_json({ "run_id": "r-zero", "status": "failed", "exit_code": 1 }),
    ),
  )
  guard hub.runs(known=[
      {
        session: "s-zero",
        run_id: Some("r-zero"),
        submission_id: Some("sub-zero"),
      },
    ]).settled
    is [settlement] else {
    fail("an abnormal finish was withheld from its own caller")
  }
  assert_eq(settlement.status, "failed")
  assert_eq(settlement.exit_code, Some(1))
  guard hub.runs(known=[
      {
        session: "other-session",
        run_id: Some("r-zero"),
        submission_id: Some("sub-zero"),
      },
    ]).settled
    is [] else {
    fail("a non-matching reconnect identity received a settlement")
  }
}

///|
test "a duplicate finish never downgrades a settlement" {
  let hub = Hub::Hub()
  hub.publish(
    AgentStarted(
      @json.from_json({
        "run_id": "r-dedup",
        "session": "s-dedup",
        "submission_id": "sub-dedup",
      }),
    ),
  )
  hub.publish(
    AgentFinished(
      @json.from_json({
        "run_id": "r-dedup",
        "status": "failed",
        "exit_code": 9,
      }),
    ),
  )
  // Finish is idempotent: a replay that carries less than the first one —
  // no exit code, no sequence — cannot erase what was already recorded.
  hub.publish(
    AgentFinished(@json.from_json({ "run_id": "r-dedup", "status": "failed" })),
  )
  let reply = hub.runs(known=[
    {
      session: "s-dedup",
      run_id: Some("r-dedup"),
      submission_id: Some("sub-dedup"),
    },
  ])
  guard reply.settled is [settlement] else {
    fail("deduplicated settlement missing")
  }
  assert_eq(settlement.exit_code, Some(9))
}

///|
async test "agent.runs keeps old requests compatible and decodes known selectors" {
  let state = ApiState::ApiState(engine="unused")
  let connection = @host.HostConnection()
  state.hub.publish(
    AgentStarted(
      @json.from_json({
        "run_id": "r-api",
        "session": "s-api",
        "submission_id": "sub-api",
      }),
    ),
  )
  state.hub.publish(
    AgentFinished(@json.from_json({ "run_id": "r-api", "status": "finished" })),
  )
  let mut runs_endpoint = None
  for endpoint in endpoints(state, connection) {
    if endpoint.name() == "agent.runs" {
      runs_endpoint = Some(endpoint)
      break
    }
  }
  guard runs_endpoint is Some(runs_endpoint) else {
    fail("agent.runs endpoint missing")
  }
  let legacy : @protocol.RunsReply = @json.from_json(
    runs_endpoint.invoke_remote(Json::empty_object()),
  )
  guard legacy is { runs: [], settled: [], approvals: [], steers: Some([]), } else {
    fail("legacy agent.runs request changed shape")
  }
  let replay : @protocol.RunsReply = @json.from_json(
    runs_endpoint.invoke_remote({
      "known": [
        { "session": "s-api", "run_id": "r-api", "submission_id": "sub-api" },
      ],
    }),
  )
  guard replay is { settled: [settlement], .. } else {
    fail("agent.runs did not decode the known selector")
  }
  assert_eq(settlement.run_id, "r-api")
}

///|
/// Build the `agent.event` notification carrying one engine event.
fn approval_event(
  session : String,
  run_id : String?,
  event : @protocol.AgentStreamEvent,
) -> @protocol.Notification {
  AgentEvent({ run_id, session, event, })
}

///|
/// The hub retains a standing question the same way it retains an active run,
/// and for the same reason: it is live state a reloading client cannot rebuild
/// from anywhere else. The transcript comes back from the durable record; an
/// approval request was never in it.
test "a standing question is replayed until it is answered" {
  let hub = Hub::Hub()
  hub.publish(
    approval_event("s1", Some("r1"), {
      event: ApprovalRequested(
        id="ap-1",
        tool_name="mbtx",
        detail="run with no sandbox policy",
        body=Some("fn main { println(1) }"),
      ),
      submission_id: None,
    }),
  )
  guard hub.runs().approvals is [pending] else {
    fail("the question was not retained")
  }
  // Everything a rejoining client needs to render it AND answer it — the id
  // above all, since a replay must address the question the engine is blocked
  // on rather than open a new one.
  assert_eq(pending.id, "ap-1")
  assert_eq(pending.session, "s1")
  assert_eq(pending.run_id, Some("r1"))
  assert_eq(pending.body, Some("fn main { println(1) }"))
  // Settled by whoever answered it — this client or another — and gone for
  // everyone at once.
  hub.publish(
    approval_event("s1", Some("r1"), {
      event: ApprovalResolved(id="ap-1", outcome="allowed_once"),
      submission_id: None,
    }),
  )
  guard hub.runs().approvals is [] else {
    fail("an answered question was still replayed")
  }
}

///|
/// Two ways a question dies without an answer, both of which must stop it
/// being offered to the next client that looks.
test "a question does not outlive the engine that asked it" {
  let hub = Hub::Hub()
  let ask = approval_event("s1", Some("r1"), {
    event: ApprovalRequested(
      id="ap-1",
      tool_name="mbtx",
      detail="run with no sandbox policy",
      body=None,
    ),
    submission_id: None,
  })
  // A run that ended without resolving its question: the engine settles its
  // own on the way out, so reaching here means one that could not — a killed
  // process emits no `approval_resolved`.
  hub.publish(
    AgentStarted(@json.from_json({ "run_id": "r1", "session": "s1" })),
  )
  hub.publish(ask)
  hub.publish(
    AgentFinished(
      @json.from_json({
        "run_id": "r1",
        "session": "s1",
        "status": "finished",
        "terminal": true,
      }),
    ),
  )
  guard hub.runs().approvals is [] else {
    fail("a question outlived the run it belonged to")
  }
  // A new engine process: the reply queue the question was blocking on died
  // with the old one, so replaying it would offer an answer with nowhere to
  // go.
  hub.publish(ask)
  hub.engine_connected({ stage: Serving, })
  guard hub.runs().approvals is [] else {
    fail("a question outlived the engine that asked it")
  }
}

///|
/// Two conversations blocked at once are two questions, and answering one
/// retires exactly one. The hub is host-wide while a question belongs to one
/// session's engine, so this is the isolation the session key buys.
test "questions from two engines are kept and retired independently" {
  let hub = Hub::Hub()
  for session in ["s1", "s2"] {
    hub.publish(
      approval_event(session, Some("r-" + session), {
        event: ApprovalRequested(
          id="ap-" + session,
          tool_name="mbtx",
          detail="run with no sandbox policy",
          body=Some("// " + session),
        ),
        submission_id: None,
      }),
    )
  }
  guard hub.runs().approvals is [first, second] else {
    fail("one of the two questions was lost")
  }
  assert_true(
    (first.session == "s1" && second.session == "s2") ||
    (first.session == "s2" && second.session == "s1"),
  )
  hub.publish(
    approval_event("s1", Some("r-s1"), {
      event: ApprovalResolved(id="ap-s1", outcome="allowed_once"),
      submission_id: None,
    }),
  )
  guard hub.runs().approvals is [survivor] else {
    fail("resolving one question disturbed the other")
  }
  assert_eq(survivor.session, "s2")
  assert_eq(survivor.body, Some("// s2"))
}

///|
/// A resolution names both a session and an id. The id half matters because a
/// late one must not retire whatever has since taken that session's slot.
test "a resolution for a superseded id leaves the standing question" {
  let hub = Hub::Hub()
  hub.publish(
    approval_event("s1", Some("r1"), {
      event: ApprovalRequested(
        id="ap-7",
        tool_name="mbtx",
        detail="run with no sandbox policy",
        body=None,
      ),
      submission_id: None,
    }),
  )
  hub.publish(
    approval_event("s1", Some("r1"), {
      event: ApprovalResolved(id="ap-1", outcome="allowed_once"),
      submission_id: None,
    }),
  )
  guard hub.runs().approvals is [standing] else {
    fail("a resolution for another id retired the standing question")
  }
  assert_eq(standing.id, "ap-7")
}
