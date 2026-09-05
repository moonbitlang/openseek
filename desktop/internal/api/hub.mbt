// The fan-out point between the engine's EventSink and every connected
// client. Notifications are appended to one bounded broadcast log that every
// subscriber reads through its own cursor. A subscriber that falls further
// behind than the log retains has lagged: its next read says so instead of
// handing over a stream with a hole in it, and the transport applies the
// protocol's reconnect-equals-resync contract (docs/remote-protocol.md) —
// the client rebuilds state through `session.list` + `agent.runs`.

///|
/// How many notifications the log retains behind its head. Generous — the
/// desktop webview and a healthy browser drain far faster than the engine
/// produces — so a subscriber this far behind is a wedged connection, and
/// the protocol's answer to a wedged connection is to resync it.
const NotificationLogCapacity = 4096

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
}

///|
fn Hub::Hub() -> Hub {
  {
    notifications: Channel(capacity=NotificationLogCapacity),
    active_starts: Map([]),
    settlements: Map([]),
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
/// Record the notification's effect on the live-run tables, then append it
/// to the log. Publishing never suspends, so the order every subscriber sees
/// is the publish order. The hub keeps no list of subscribers: one that has
/// fallen behind learns so on its own next read.
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
/// A cursor at the log's head: it yields every notification published from
/// now on. The hub keeps no record of it, so dropping it is the whole of
/// unsubscribing.
fn Hub::subscribe(
  self : Hub,
) -> @broadcast.Subscription[@protocol.Notification] {
  self.notifications.subscribe()
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
  { runs, settled, approvals, }
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
  let subscriber = hub.subscribe()
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
  guard subscriber.try_next() is Some(started) else {
    fail("missing started notification")
  }
  assert_eq(started.wire_name(), "agent.started")
  guard subscriber.try_next() is Some(connected) else {
    fail("missing connected notification")
  }
  assert_eq(connected.wire_name(), "agent.connected")
}

///|
test "a lagged subscriber learns what it missed and can still replay the finish" {
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
  // Let the log roll past the subscriber without draining it. The terminal
  // notification is the first one to push the start out of the window,
  // reproducing a renderer that fell behind during a long, high-volume turn.
  for _ in 1..<NotificationLogCapacity {
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
  // The read reports exactly what was overwritten — the start — and resumes
  // at the oldest retained notification. Whether that partial stream is
  // worth rendering is the transport's decision; the finish itself is
  // recoverable through `agent.runs` either way.
  let missed = try subscriber.try_next() catch {
    Lagged(missed~) => Some(missed)
  } noraise {
    _ => None
  }
  assert_eq(missed, Some(1))
  guard subscriber.try_next() is Some(retained) else {
    fail("the retained window was not readable after the lag")
  }
  assert_eq(retained.wire_name(), "agent.connected")
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
    runs_endpoint.invoke_remote(Json::empty_object()),
  )
  guard legacy is { runs: [], settled: [], approvals: [], } else {
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
