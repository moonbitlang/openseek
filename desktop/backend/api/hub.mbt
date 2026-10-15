// The fan-out point between the engine's EventSink and connected clients.
// Notifications go directly to each transport's bounded inbox. A full inbox
// pauses that subscription until its transport reconnects or resyncs through
// session.list and agent.runs (docs/remote-protocol.md).

///|
/// The hub is owned by `ApiState`; transports reach it through
/// `ApiState::subscribe`.
priv struct Hub {
  notifications : @broadcast.Channel[@protocol.Notification]
  // The typed `agent.started` payload of every run still in flight, keyed by run
  // id — the source for `agent.runs`, which is how a client that joins (or
  // reconnects) mid-run learns the run's identity. Insertion order is
  // run-start order.
  active_starts : Map[String, @protocol.StartedPayload]
  // Completed lifecycle records survive client reconnects for this host
  // process, so a reconnecting owner learns how its run ended. Run ids carry
  // host-wide random identity, so they are the deduplication key.
  settlements : Map[String, RunSettlement]
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
  // Host-owned questions survive the originating turn. They are keyed by
  // request id; several messages can be awaiting approval in one chat.
  message_approvals : Map[String, @protocol.PendingApprovalPayload]
  mut approval_generation : Int32
}

///|
fn Hub::Hub() -> Hub {
  {
    notifications: Channel(),
    active_starts: Map([]),
    settlements: Map([]),
    pending_approvals: Map([]),
    message_approvals: Map([]),
    approval_generation: 0,
  }
}

///|
/// The reconnect-safe subset of Finished.
priv struct RunSettlement {
  run_id : String
  mut session : String
  mut submission_id : String?
  status : String
  mut exit_code : Int32?
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
  let (session, submission_id) = match self.active_starts.get(payload.run_id) {
    Some(started) => (started.session, started.submission_id)
    None => ("", None)
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
/// Record the notification's effect on the live-run tables, then append it
/// to every active inbox. Publishing never suspends; a slow destination
/// pauses independently and its transport establishes a resync boundary.
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
    AgentEvent(payload) => self.track_approval(payload)
    _ => ()
  }
  self.notifications.publish(notification)
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
  match payload.event {
    ApprovalRequested(id~, tool_name~, detail~, body~) => {
      if self.pending_approvals.get(payload.session) is Some(existing) &&
        existing.id == id &&
        existing.run_id == payload.run_id {
        return
      }
      self.pending_approvals[payload.session] = {
        id,
        session: payload.session,
        run_id: payload.run_id,
        tool_name,
        detail,
        body,
        answered: false,
      }
      self.publish_approvals()
    }
    // Settled by whoever answered it, including this host's own client. The
    // question is gone for every client at once, which is why the resolution
    // is broadcast rather than sent to the answerer alone.
    //
    // Checked by id as well as session, so a resolution that raced a newer
    // question into the same slot retires nothing.
    ApprovalResolved(id~, ..) =>
      if self.pending_approvals.get(payload.session) is Some(standing) &&
        standing.id == id &&
        standing.run_id == payload.run_id {
        self.pending_approvals.remove(payload.session)
        self.publish_approvals()
      }
    _ => ()
  }
}

///|
/// Drop every question belonging to `run_id`.
fn Hub::forget_run_approvals(self : Hub, run_id : String) -> Unit {
  let before = self.pending_approvals.length()
  self.pending_approvals.retain((_, approval) => {
    !(approval.run_id is Some(owner) && owner == run_id)
  })
  if self.pending_approvals.length() != before {
    self.publish_approvals()
  }
}

///|
/// Register a transport-owned inbox for direct notification delivery.
fn[T] Hub::subscribe(
  self : Hub,
  inbox : @async.Queue[T],
  map~ : (@protocol.Notification) -> T?,
  on_lag~ : (@broadcast.Subscription[@protocol.Notification]) -> Unit,
) -> @broadcast.Subscription[@protocol.Notification] {
  self.notifications.subscribe(inbox, map~, on_lag~)
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
  let runs = self.active_starts.values().to_array()
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
  let approvals = self.approval_snapshot().approvals
  { runs, settled, approvals, approval_generation: self.approval_generation, }
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
    settlement.submission_id is Some(settled) && settled == submission_id
  })
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
  self.active_starts.clear()
  // A question belongs to the engine process that asked it: the reply queue
  // it was blocking on died with that process, so replaying it would offer an
  // answer with nowhere to go.
  if !self.pending_approvals.is_empty() {
    self.pending_approvals.clear()
    self.publish_approvals()
  }
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
      PredictionReady(payload) => self.publish(AgentPrediction(payload))
      // Liveness for a sub-run in flight. Nothing downstream persists it:
      // a client that arrives late simply learns nothing about a child's
      // progress until its next advance.
      SubrunProgress(payload) => self.publish(SubrunProgress(payload))
      // A workflow's ledger row. Like sub-run progress, nothing downstream
      // persists it: the journal in the session store is the record.
      WorkflowEntry(payload) => self.publish(WorkflowEntry(payload))
      // A failed command may have settled lifecycle before its process was
      // reapable. This later durable boundary is not a second finish: it must
      // not post another system notification or mutate the live-runs table.
    }
  })
}

///|
test "a real engine connection retires old active runs before readiness" {
  let hub = Hub::Hub()
  let inbox : @async.Queue[@protocol.Notification] = Queue(kind=Blocking(8))
  let subscriber = hub.subscribe(inbox, map=value => Some(value), on_lag=sub => {
    sub.close()
  })
  defer subscriber.close()
  hub.publish(
    AgentStarted(@json.from_json({ "run_id": "r-old", "session": "s-old" })),
  )
  guard hub.runs().runs is [_] else {
    fail("expected one active run before reconnect")
  }
  hub.engine_connected({ stage: Serving, })
  guard hub.runs().runs is [] else {
    fail("old active run survived a new engine pump")
  }
  guard inbox.try_get() is Some(started) else {
    fail("missing started notification")
  }
  assert_eq(started.wire_name(), "agent.started")
  guard inbox.try_get() is Some(connected) else {
    fail("missing connected notification")
  }
  assert_eq(connected.wire_name(), "agent.connected")
}

///|
test "an overflowing inbox can still recover the missed finish from runs" {
  let hub = Hub::Hub()
  let inbox : @async.Queue[@protocol.Notification] = Queue(kind=Blocking(1))
  let mut lagged = false
  let subscriber = hub.subscribe(inbox, map=value => Some(value), on_lag=_ => {
    lagged = true
  })
  defer subscriber.close()
  hub.publish(
    AgentStarted(
      @json.from_json({
        "run_id": "r-overflow",
        "session": "s-overflow",
        "submission_id": "sub-overflow",
      }),
    ),
  )
  hub.publish(
    AgentFinished(
      @json.from_json({
        "run_id": "r-overflow",
        "status": "finished",
        "exit_code": 0,
      }),
    ),
  )
  assert_true(lagged)
  assert_true(inbox.try_get() is Some(AgentStarted(_)))
  assert_true(inbox.try_get() is None)
  guard hub.runs(known=[
      {
        session: "s-overflow",
        run_id: Some("r-overflow"),
        submission_id: Some("sub-overflow"),
      },
    ]).settled
    is [settlement] else {
    fail("the missed finish was not retained for lifecycle resync")
  }
  assert_eq(settlement.status, "finished")
  assert_eq(settlement.exit_code, Some(0))
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
    runs_endpoint.invoke(Json::empty_object()),
  )
  guard legacy is { runs: [], settled: [], approvals: [], .. } else {
    fail("legacy agent.runs request changed shape")
  }
  let replay : @protocol.RunsReply = @json.from_json(
    runs_endpoint.invoke({
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
fn Hub::approval_snapshot(self : Hub) -> @protocol.ApprovalSnapshot {
  {
    generation: self.approval_generation,
    approvals: [
      ..self.pending_approvals.values().to_array(),
      ..self.message_approvals.values().to_array(),
    ],
  }
}

///|
fn Hub::publish_approvals(self : Hub) -> Unit {
  self.approval_generation += 1
  self.publish(AgentApprovals(self.approval_snapshot()))
}

///|
/// Matching and submission share one non-suspending actor turn. A second
/// window observes the first accepted answer before it can enqueue another.
fn Hub::answer_approval(
  self : Hub,
  payload : @protocol.ApprovalPayload,
  send : (@protocol.ApprovalPayload) -> @protocol.ApprovalReply,
) -> @protocol.ApprovalReply {
  guard payload.run_id is Some(run_id) else { return { delivered: false, } }
  for session, pending in self.pending_approvals {
    if pending.id == payload.id && pending.run_id == Some(run_id) {
      guard !pending.answered else { return { delivered: false, } }
      let reply = send(payload)
      if reply.delivered {
        self.pending_approvals[session] = { ..pending, answered: true, }
        self.publish_approvals()
      }
      return reply
    }
  }
  { delivered: false, }
}
