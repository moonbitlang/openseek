// The fan-out point between the engine's EventSink and every connected
// client. Notifications are pushed to each subscriber's bounded queue; a
// subscriber that cannot keep up is dropped, per the protocol's
// reconnect-equals-resync contract (docs/remote-protocol.md) — the client
// reconnects and rebuilds state through `session.list` + `agent.runs`.

///|
/// One server-pushed notification: a catalog method name and its params.
/// Transports encode it at their own edge (JSON-RPC frame, proton event).
pub(all) struct Notification {
  method_ : String
  params : Json
}

///|
/// A subscriber queue's bound. Generous — the desktop webview and a healthy
/// browser drain far faster than the engine produces — so hitting it means
/// the connection is wedged, and the protocol's answer to a wedged
/// connection is to close it.
const SubscriberQueueCapacity = 1024

///|
/// The hub is owned by `ApiState`; transports reach it through
/// `ApiState::subscribe`/`unsubscribe`.
priv struct Hub {
  subscribers : Array[@async.Queue[Notification]]
  // The `agent.started` params of every run still in flight, keyed by run
  // id — the source for `agent.runs`, which is how a client that joins (or
  // reconnects) mid-run learns the run's identity. Insertion order is
  // run-start order.
  active_starts : Map[String, Json]
  // Completed lifecycle records survive client reconnects for this host
  // process. An abnormal finish without an exact durable frontier stays here
  // but is not replayable until its matching `agent.durable` boundary arrives.
  // Run ids carry host-wide random identity, so they are the deduplication key.
  settlements : Map[String, RunSettlement]
}

///|
fn Hub::new() -> Hub {
  { subscribers: [], active_starts: Map([]), settlements: Map([]) }
}

///|
/// The reconnect-safe subset of Finished. `replayable` is host-private: the
/// wire exposes only fully settled entries.
priv struct RunSettlement {
  run_id : String
  mut session : String
  mut submission_id : String?
  status : String
  mut exit_code : Int?
  mut durable_sequence : Int?
  mut replayable : Bool
}

///|
/// Encode only the public lifecycle settlement. `replayable` is a host-side
/// publication gate, not part of the wire contract.
fn RunSettlement::wire_json(self : RunSettlement) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["run_id"] = Json::string(self.run_id)
  fields["session"] = Json::string(self.session)
  if self.submission_id is Some(submission_id) {
    fields["submission_id"] = Json::string(submission_id)
  }
  fields["status"] = Json::string(self.status)
  if self.exit_code is Some(exit_code) {
    fields["exit_code"] = Json::number(exit_code.to_double())
  }
  if self.durable_sequence is Some(sequence) {
    fields["durable_sequence"] = Json::number(sequence.to_double())
  }
  Json::object(fields)
}

///|
/// These statuses are logged only after their Terminal append succeeds. The
/// failure/cancellation statuses can be emitted even when that append failed,
/// so they require an exact sequence from Finished or a later durable boundary.
fn terminal_backed_status(status : String) -> Bool {
  status == "finished" ||
  status == "context_yield" ||
  status == "max_steps_exhausted"
}

///|
/// Capture Finished while its Started row is still present. Duplicate
/// lifecycle events merge only missing evidence; a later notification can
/// strengthen the durable frontier but never lower it.
fn Hub::record_finished(self : Hub, run_id : String, params : Json) -> Unit {
  guard params is Object(finished) &&
    finished.get("status") is Some(String(status)) else {
    return
  }
  let exit_code = if finished.get("exit_code") is Some(Number(value, ..)) {
    Some(value.to_int())
  } else {
    None
  }
  let durable_sequence = if finished.get("durable_sequence")
    is Some(Number(value, ..)) {
    Some(value.to_int())
  } else {
    None
  }
  let mut session = ""
  let mut submission_id : String? = None
  if self.active_starts.get(run_id) is Some(Object(started)) {
    if started.get("session") is Some(String(value)) {
      session = value
    }
    if started.get("submission_id") is Some(String(value)) {
      submission_id = Some(value)
    }
  }
  if self.settlements.get(run_id) is Some(existing) {
    if existing.session.is_empty() && !session.is_empty() {
      existing.session = session
    }
    if existing.submission_id is None && submission_id is Some(value) {
      existing.submission_id = Some(value)
    }
    if existing.exit_code is None && exit_code is Some(value) {
      existing.exit_code = Some(value)
    }
    if durable_sequence is Some(sequence) {
      if existing.durable_sequence is Some(current) {
        if sequence > current {
          existing.durable_sequence = Some(sequence)
        }
      } else {
        existing.durable_sequence = Some(sequence)
      }
      existing.replayable = true
    }
    return
  }
  self.settlements[run_id] = {
    run_id,
    session,
    submission_id,
    status,
    exit_code,
    durable_sequence,
    replayable: durable_sequence is Some(_) || terminal_backed_status(status),
  }
}

///|
/// Strengthen an abnormal finish with the exact frontier from the same run
/// and session. Sequence zero is evidence, not absence, and remains `Some(0)`.
fn Hub::record_durable_boundary(
  self : Hub,
  run_id : String,
  params : Json,
) -> Unit {
  guard params is Object(boundary) &&
    boundary.get("session") is Some(String(session)) &&
    boundary.get("sequence") is Some(Number(value, ..)) &&
    self.settlements.get(run_id) is Some(settlement) &&
    settlement.session == session else {
    return
  }
  let sequence = value.to_int()
  if settlement.durable_sequence is Some(current) {
    if sequence > current {
      settlement.durable_sequence = Some(sequence)
    }
  } else {
    settlement.durable_sequence = Some(sequence)
  }
  settlement.replayable = true
}

///|
/// Push one notification to every live subscriber. `try_put` never
/// suspends, so the order every subscriber sees is the publish order. A
/// full queue marks its subscriber dead: the queue is closed (ending the
/// connection's writer) and dropped. Only the hub ever closes a subscribed
/// queue, and it removes the queue from `subscribers` in the same breath,
/// so `try_put` on a closed queue cannot happen — `try!` turns that
/// invariant into a hard stop instead of a silent discard.
fn Hub::publish(self : Hub, method_ : String, params : Json) -> Unit {
  if params_run_id(params) is Some(run_id) {
    match method_ {
      "agent.started" => self.active_starts[run_id] = params
      // Error is diagnostic, not a lifecycle boundary: the engine publishes
      // Finished only after it has closed the run. Removing on Error would let
      // a concurrent `agent.runs` snapshot report a still-draining run idle.
      "agent.finished" => {
        self.record_finished(run_id, params)
        self.active_starts.remove(run_id)
      }
      "agent.durable" => self.record_durable_boundary(run_id, params)
      _ => ()
    }
  }
  let wedged : Array[Int] = []
  for index, queue in self.subscribers {
    if !(try! queue.try_put({ method_, params })) {
      wedged.push(index)
    }
  }
  // Back to front, so the collected indices stay valid while removing.
  for cursor in wedged.rev_iter() {
    let queue = self.subscribers.remove(cursor)
    queue.close()
  }
}

///|
fn params_run_id(params : Json) -> String? {
  guard params is Object(fields) && fields.get("run_id") is Some(String(run_id)) else {
    return None
  }
  Some(run_id)
}

///|
fn Hub::subscribe(self : Hub) -> @async.Queue[Notification] {
  let queue : @async.Queue[Notification] = Queue(
    kind=Blocking(SubscriberQueueCapacity),
  )
  self.subscribers.push(queue)
  queue
}

///|
/// Drop a subscriber by queue identity and close its queue, waking a writer
/// blocked on `get`. Unsubscribing twice is fine; so is unsubscribing a
/// queue the hub already kicked.
fn Hub::unsubscribe(self : Hub, queue : @async.Queue[Notification]) -> Unit {
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
/// run-start order (the map preserves insertion order), plus only replayable
/// settlements named by the caller's reconnect selectors. This function has
/// no suspension point, so active runs and settlements form one atomic view.
fn Hub::runs(self : Hub, known? : Array[KnownRunPayload]) -> Json {
  let runs : Array[Json] = []
  for _, params in self.active_starts {
    runs.push(params)
  }
  let settled : Array[Json] = []
  if known is Some(selectors) {
    for _, settlement in self.settlements {
      if settlement.replayable &&
        selectors.any(selector => settlement_matches(settlement, selector)) {
        settled.push(settlement.wire_json())
      }
    }
  }
  { "runs": Json::array(runs), "settled": Json::array(settled) }
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
fn Hub::engine_connected(self : Hub, params : Json) -> Unit {
  self.active_starts.clear()
  self.publish("agent.connected", params)
}

///|
/// The hub as the engine package's event sink, mapping engine events onto
/// the catalog's `agent.*` notifications. `on_finished` additionally hands
/// finished runs to the embedding host — the desktop's system notification.
fn Hub::sink(
  self : Hub,
  on_finished? : (@engine.FinishedPayload) -> Unit,
) -> @engine.EventSink {
  EventSink(event => {
    match event {
      Connected(payload) => self.engine_connected(payload.to_json())
      Started(payload) => self.publish("agent.started", payload.to_json())
      StreamEvent(payload) => self.publish("agent.event", payload.to_json())
      Error(payload) => self.publish("agent.error", payload.to_json())
      Finished(payload) => {
        if on_finished is Some(notify) {
          notify(payload)
        }
        self.publish("agent.finished", payload.to_json())
      }
      // The canonical transcript channel: one durably committed store event.
      // Clients that understand it build their durable transcript from these
      // plus `session.load` snapshots; the `agent.event` stream above only
      // settles transient stream and lifecycle state in commit-aware clients
      // (docs/remote-protocol.md).
      SessionCommit(payload) => self.publish("session.event", payload.to_json())
      // A failed command may have settled lifecycle before its process was
      // reapable. This later durable boundary is not a second finish: it must
      // not post another system notification or mutate the live-runs table.
      DurableBoundary(payload) =>
        self.publish("agent.durable", payload.to_json())
    }
  })
}

///|
test "a real engine connection retires old active runs before readiness" {
  let hub = Hub::new()
  let subscriber = hub.subscribe()
  hub.publish("agent.started", { "run_id": "r-old", "task": "old" })
  guard hub.runs() is Object(before) && before.get("runs") is Some(Array([_])) else {
    fail("expected one active run before reconnect")
  }
  hub.engine_connected({ "ready": true })
  guard hub.runs() is Object(after) && after.get("runs") is Some(Array([])) else {
    fail("old active run survived a new engine pump")
  }
  guard subscriber.try_get() is Some(started) else {
    fail("missing started notification")
  }
  assert_eq(started.method_, "agent.started")
  guard subscriber.try_get() is Some(connected) else {
    fail("missing connected notification")
  }
  assert_eq(connected.method_, "agent.connected")
}

///|
test "an agent error does not retire a run before its finished boundary" {
  let hub = Hub::new()
  hub.publish("agent.started", { "run_id": "r1", "task": "work" })
  hub.publish("agent.error", { "run_id": "r1", "message": "boom" })
  guard hub.runs() is Object(after_error) &&
    after_error.get("runs") is Some(Array([_])) else {
    fail("agent.error retired a still-draining run")
  }
  hub.publish("agent.finished", { "run_id": "r1", "status": "failed" })
  guard hub.runs() is Object(after_finish) &&
    after_finish.get("runs") is Some(Array([])) else {
    fail("agent.finished did not retire the run")
  }
}

///|
test "a normal terminal-backed finish is replayable only to a matching caller" {
  let hub = Hub::new()
  hub.publish("agent.started", {
    "run_id": "r-normal",
    "session": "s-normal",
    "submission_id": "sub-normal",
    "task": "work",
  })
  hub.publish("agent.finished", {
    "run_id": "r-normal",
    "status": "finished",
    "exit_code": 0,
  })
  guard hub.runs(known=[
      {
        session: "s-normal",
        run_id: Some("r-normal"),
        submission_id: Some("sub-normal"),
      },
      // A second matching selector must not duplicate the ledger row.
      { session: "s-normal", run_id: None, submission_id: Some("sub-normal") },
    ])
    is Object(reply) &&
    reply.get("runs") is Some(Array([])) &&
    reply.get("settled") is Some(Array([Object(settlement)])) else {
    fail("matching reconnect identity did not receive one settlement")
  }
  assert_eq(settlement.get("run_id"), Some(Json::string("r-normal")))
  assert_eq(settlement.get("session"), Some(Json::string("s-normal")))
  assert_eq(settlement.get("submission_id"), Some(Json::string("sub-normal")))
  assert_eq(settlement.get("status"), Some(Json::string("finished")))
  assert_eq(settlement.get("exit_code"), Some(Json::number(0)))
  assert_eq(settlement.get("replayable"), None)

  guard hub.runs(known=[
      {
        session: "other-session",
        run_id: Some("r-normal"),
        submission_id: Some("sub-normal"),
      },
      { session: "s-normal", run_id: Some("other-run"), submission_id: None },
      {
        session: "s-normal",
        run_id: None,
        submission_id: Some("other-submission"),
      },
      // A session alone is not an owner selector and must not expose that
      // session's process-lifetime completion history.
      { session: "s-normal", run_id: None, submission_id: None },
    ])
    is Object(mismatched) &&
    mismatched.get("settled") is Some(Array([])) else {
    fail("a non-matching reconnect identity received a settlement")
  }
}

///|
test "an abnormal finish waits for an exact durable boundary including zero" {
  let hub = Hub::new()
  hub.publish("agent.started", {
    "run_id": "r-zero",
    "session": "s-zero",
    "submission_id": "sub-zero",
  })
  hub.publish("agent.finished", {
    "run_id": "r-zero",
    "status": "failed",
    "exit_code": 1,
  })
  let known : Array[KnownRunPayload] = [
    {
      session: "s-zero",
      run_id: Some("r-zero"),
      submission_id: Some("sub-zero"),
    },
  ]
  guard hub.runs(known~) is Object(pending) &&
    pending.get("settled") is Some(Array([])) else {
    fail("an unbounded abnormal finish was replayed")
  }
  hub.publish("agent.durable", {
    "run_id": "r-zero",
    "session": "other-session",
    "sequence": 99,
  })
  guard hub.runs(known~) is Object(still_pending) &&
    still_pending.get("settled") is Some(Array([])) else {
    fail("a boundary from another session settled the run")
  }
  hub.publish("agent.durable", {
    "run_id": "r-zero",
    "session": "s-zero",
    "sequence": 0,
  })
  guard hub.runs(known~) is Object(settled_reply) &&
    settled_reply.get("settled") is Some(Array([Object(settlement)])) else {
    fail("exact-zero boundary did not settle the abnormal finish")
  }
  assert_eq(settlement.get("durable_sequence"), Some(Json::number(0)))
}

///|
test "duplicate finish and durable boundaries never downgrade a settlement" {
  let hub = Hub::new()
  hub.publish("agent.started", {
    "run_id": "r-dedup",
    "session": "s-dedup",
    "submission_id": "sub-dedup",
  })
  hub.publish("agent.finished", {
    "run_id": "r-dedup",
    "status": "failed",
    "exit_code": 9,
  })
  hub.publish("agent.durable", {
    "run_id": "r-dedup",
    "session": "s-dedup",
    "sequence": 12,
  })
  // Both messages are idempotent. A stale lower boundary and a duplicate
  // Finished without a sequence cannot erase the stronger frontier.
  hub.publish("agent.durable", {
    "run_id": "r-dedup",
    "session": "s-dedup",
    "sequence": 3,
  })
  hub.publish("agent.finished", { "run_id": "r-dedup", "status": "failed" })
  guard hub.runs(known=[
      {
        session: "s-dedup",
        run_id: Some("r-dedup"),
        submission_id: Some("sub-dedup"),
      },
    ])
    is Object(reply) &&
    reply.get("settled") is Some(Array([Object(settlement)])) else {
    fail("deduplicated settlement missing")
  }
  assert_eq(settlement.get("exit_code"), Some(Json::number(9)))
  assert_eq(settlement.get("durable_sequence"), Some(Json::number(12)))
}

///|
async test "agent.runs keeps old requests compatible and decodes known selectors" {
  let state = ApiState::new(engine="unused")
  state.hub.publish("agent.started", {
    "run_id": "r-api",
    "session": "s-api",
    "submission_id": "sub-api",
  })
  state.hub.publish("agent.finished", {
    "run_id": "r-api",
    "status": "finished",
  })
  let legacy = dispatch(state, "agent.runs", Json::empty_object())
  guard legacy is Object(legacy_reply) &&
    legacy_reply.get("runs") is Some(Array([])) &&
    legacy_reply.get("settled") is Some(Array([])) else {
    fail("legacy agent.runs request changed shape")
  }
  let replay = dispatch(state, "agent.runs", {
    "known": [
      { "session": "s-api", "run_id": "r-api", "submission_id": "sub-api" },
    ],
  })
  guard replay is Object(replay_reply) &&
    replay_reply.get("settled") is Some(Array([Object(settlement)])) else {
    fail("agent.runs did not decode the known selector")
  }
  assert_eq(settlement.get("run_id"), Some(Json::string("r-api")))
}
