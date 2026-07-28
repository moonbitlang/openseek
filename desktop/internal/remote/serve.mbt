// One remote client's connection: JSON-RPC 2.0 over a WebSocket the host
// dialed out through the relay (docs/remote-protocol.md). Requests fan out
// to the shared dispatcher concurrently; notifications flow back from the
// hub. The bridge and this file are the only two transports, and everything
// below the envelope is `@api.dispatch`.

///|
/// Everything the single writer task sends, encoded only at the writer so
/// no other task ever touches the socket.
priv enum Outgoing {
  // A complete JSON-RPC response envelope, built where the request ran.
  Response(Json)
  Notify(@api.Notification)
  // Protocol-level keepalive, serialized with every text frame.
  Ping
}

///|
/// The two queues that make one remote subscription. Opening them also
/// installs the readiness frame: because the fresh bounded outbound queue is
/// empty, that `put` cannot suspend, so no hub publisher can run between
/// subscribe and readiness. Forwarders may only start after this returns.
priv struct ClientSubscription {
  out : @async.Queue[Outgoing]
  notifications : @async.Queue[@api.Notification]
}

///|
/// One remote data WebSocket actor. It creates and closes the socket inside
/// `run`; its subscription, outbound queue, writer, notification forwarder,
/// pinger, and request tasks cannot outlive that run.
priv struct WsClientActor {
  state : @api.ApiState
  host_connection : @host.HostConnection
  url : String
}

///|
fn WsClientActor::new(state : @api.ApiState, url : String) -> WsClientActor {
  { state, host_connection: @host.HostConnection::new(), url }
}

///|
async fn WsClientActor::open_subscription(
  self : WsClientActor,
) -> ClientSubscription {
  let out : @async.Queue[Outgoing] = Queue(kind=Blocking(OutboundQueueCapacity))
  let notifications = self.state.subscribe()
  // Readiness doubles as the resync hint: the client treats
  // `agent.connected` as "state may have changed, reload". Queue it before
  // any notification forwarder exists, making it this subscription's first
  // outbound frame even if the hub publishes immediately after subscribe.
  out.put(Notify({ method_: "agent.connected", params: Json::empty_object() }))
  { out, notifications }
}

///|
/// An inbound frame, classified for routing.
priv enum Inbound {
  // The raw `id` (echoed back verbatim), the method, and the params.
  Request(Json, String, Json)
  // Client notifications are valid JSON-RPC but this transport currently
  // has none to act on, so they are ignored without a response.
  ClientNotification
  // Not JSON at all (-32700).
  Unparsable
  // JSON, but not a JSON-RPC request (-32600).
  Invalid
}

///|
/// The client stopped draining and its outbound queue stood full; raising
/// this out of the notification pump is how the connection gets torn down.
priv suberror SlowClient {
  SlowClient(String)
}

///|
const PingIntervalMs = 30_000

///|
/// How many outbound frames may queue before writers suspend. This is also
/// the slow-client limit: a socket that stalls long enough to fill it gets
/// the connection torn down (the pump must not block on a full queue — a
/// blocked `put` cannot be woken by the hub closing the subscription).
const OutboundQueueCapacity = 64

///|
/// Enforce one outbound bound for notifications and responses. A producer
/// must never park behind a stalled socket: raising from any request task or
/// the notification pump tears down the task group and reconnects cleanly.
fn enqueue_outgoing(
  out : @async.Queue[Outgoing],
  item : Outgoing,
) -> Unit raise {
  guard out.try_put(item) else {
    raise SlowClient("client not draining outbound frames")
  }
}

///|
/// JSON-RPC error codes (docs/remote-protocol.md).
const CodeParseError = -32700

///|
const CodeInvalidRequest = -32600

///|
const CodeMethodNotFound = -32601

///|
const CodeInvalidParams = -32602

///|
const CodeInternalError = -32603

///|
const CodeEngineError = -32000

///|
const CodeHostError = -32001

///|
/// Dial and serve one announced remote client. A client hanging up mid-run
/// is routine and only retires this actor; cancelling the parent relay actor
/// still propagates so every owned resource is closed immediately.
async fn WsClientActor::run(self : WsClientActor) -> Unit {
  let conn = @websocket.Conn::connect(self.url)
  defer conn.close()
  self.serve(conn) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
}

///|
/// Serve the actor's connected socket until it closes (or the hub kicks it
/// for not draining notifications).
async fn WsClientActor::serve(
  self : WsClientActor,
  conn : @websocket.Conn,
) -> Unit {
  let subscription = self.open_subscription()
  let out = subscription.out
  let notifications = subscription.notifications
  defer self.state.unsubscribe(notifications)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      for ;; {
        out.get().write(conn)
      }
    })
    group.spawn_bg(() => {
      // Filesystem watch events belong to this WebSocket connection. They
      // bypass the shared hub so other desktop and remote clients never
      // receive this connection's `fs.changed` notifications.
      self.host_connection.run((method_, params) => {
        enqueue_outgoing(out, Notify({ method_, params }))
      })
    })
    group.spawn_bg(() => {
      // Tears the connection down either way it ends — the client
      // reconnects into a resync: the hub kicking this subscriber (queue
      // closed → `get` raises), or the outbound queue standing full (the
      // socket has stalled for `OutboundQueueCapacity` frames, and the
      // protocol promises a disconnect over a silent gap in the stream).
      for ;; {
        let notification = notifications.get()
        guard notification_for_client(notification) is Some(notification) else {
          continue
        }
        enqueue_outgoing(out, Notify(notification))
      }
    })
    group.spawn_bg(() => {
      // Protocol-level keepalive: a dead middlebox connection surfaces as a
      // failed ping write instead of lingering forever.
      for ;; {
        @async.sleep(PingIntervalMs)
        enqueue_outgoing(out, Ping)
      }
    })
    for ;; {
      let message = conn.recv()
      guard message.kind is Text else {
        // The protocol is JSON text; a binary frame is a peer bug.
        continue
      }
      let text = message.read_all().text()
      match classify(text) {
        Request(id, method_, params) =>
          // Each request runs in its own task so a slow op (an engine
          // start, a big file read) never blocks the reader; replies are
          // correlated by id, not order.
          group.spawn_bg(() => {
            enqueue_outgoing(
              out,
              Response(
                run_request(
                  self.state,
                  self.host_connection,
                  id,
                  method_,
                  params,
                ),
              ),
            )
          })
        ClientNotification => ()
        Unparsable =>
          enqueue_outgoing(
            out,
            Response(
              error_envelope(Json::null(), CodeParseError, "unparsable frame"),
            ),
          )
        Invalid =>
          enqueue_outgoing(
            out,
            Response(
              error_envelope(
                Json::null(),
                CodeInvalidRequest,
                "not a JSON-RPC request",
              ),
            ),
          )
      }
    }
  })
}

///|
/// The socket's only write boundary. Even keepalive frames pass through this
/// method, so the WebSocket implementation never sees interleaved sends.
async fn Outgoing::write(self : Outgoing, conn : @websocket.Conn) -> Unit {
  let envelope : Json = match self {
    Ping => {
      conn.ping()
      return
    }
    Response(envelope) => envelope
    Notify(notification) =>
      {
        "jsonrpc": "2.0",
        "method": Json::string(notification.method_),
        "params": notification.params,
      }
  }
  conn.send_text(envelope.stringify())
}

///|
fn classify(text : String) -> Inbound {
  let message = @json.parse(text) catch { _ => return Unparsable }
  guard message is Object(fields) else { return Invalid }
  guard fields.get("method") is Some(String(method_)) else { return Invalid }
  let params = match fields.get("params") {
    Some(params) => params
    None => Json::empty_object()
  }
  match fields.get("id") {
    Some(id) => Request(id, method_, params)
    None => ClientNotification
  }
}

///|
/// Apply the remote delivery profile at the WebSocket edge.
/// Full semantic transcript objects have a canonical `session.event` twin;
/// deltas, metrics, errors, acknowledgements, and lifecycle state pass
/// through. Lifecycle frames carrying large durable text are copied and
/// trimmed so the hub's original notification stays untouched for local
/// transports.
fn notification_for_client(
  notification : @api.Notification,
) -> @api.Notification? {
  let method_ = notification.method_
  let params = notification.params
  // A session-less run has no store and therefore no `session.event` twin.
  // Keep its complete semantic stream intact; the same browser may interleave
  // durable and ephemeral runs.
  let has_durable_session = params is Object(fields) &&
    fields.get("session") is Some(String(session)) &&
    !session.is_empty()
  if method_ == "agent.event" &&
    has_durable_session &&
    params is Object(fields) &&
    fields.get("event") is Some(Object(event)) &&
    event.get("event") is Some(String(event_name)) {
    match event_name {
      // These full messages also settle the preceding delta streams. Keep
      // that state transition while removing the durable text itself.
      "reasoning_message" | "assistant_message" => {
        let lifecycle_event = event.copy()
        lifecycle_event["content"] = Json::string("")
        let lifecycle = fields.copy()
        lifecycle["event"] = Json::object(lifecycle_event)
        return Some({ method_, params: Json::object(lifecycle) })
      }
      "tool_result"
      | "auto_compaction_finished"
      // The separate `agent.finished` frame below keeps the terminal state.
      | "agent_finished"
      | "context_yield" => return None
      // The summary is durable, but this frame also clears the client's
      // compaction lifecycle state; retain its shape with an empty summary.
      "compaction_finished" => {
        let lifecycle_event = event.copy()
        lifecycle_event["summary"] = Json::string("")
        let lifecycle = fields.copy()
        lifecycle["event"] = Json::object(lifecycle_event)
        return Some({ method_, params: Json::object(lifecycle) })
      }
      _ => ()
    }
  }
  // `agent.finished` has no session identity, so the edge cannot prove that
  // its answer has a canonical twin. Preserve the answer for every run.
  if method_ == "agent.started" &&
    has_durable_session &&
    params is Object(fields) {
    // Keep the field so clients with a required-string decoder still accept
    // the run lifecycle frame; the prompt itself arrives as a commit.
    let lifecycle = fields.copy()
    lifecycle["task"] = Json::string("")
    return Some({ method_, params: Json::object(lifecycle) })
  }
  Some(notification)
}

///|
/// Run one request through the dispatcher and shape the outcome as a
/// JSON-RPC response, mapping each typed failure to its protocol code.
async fn run_request(
  state : @api.ApiState,
  connection : @host.HostConnection,
  id : Json,
  method_ : String,
  params : Json,
) -> Json {
  let result = @api.dispatch(state, connection, method_, params) catch {
    error if @async.is_being_cancelled() => raise error
    @api.UnknownMethod(name) =>
      return error_envelope(id, CodeMethodNotFound, "unknown method '\{name}'")
    @host.PayloadError(message) =>
      return error_envelope(id, CodeInvalidParams, message)
    @engine.EngineError(message) =>
      return error_envelope(id, CodeEngineError, message)
    @host.HostError(message) =>
      return error_envelope(id, CodeHostError, message)
    error =>
      return error_envelope(id, CodeInternalError, "internal error: \{error}")
  }
  { "jsonrpc": "2.0", "id": id, "result": result }
}

///|
fn error_envelope(id : Json, code : Int, message : String) -> Json {
  {
    "jsonrpc": "2.0",
    "id": id,
    "error": { "code": Json::number(code.to_double()), "message": message },
  }
}

///|
async test "readiness precedes the first forwarded hub notification" {
  let state = @api.ApiState::new(engine="unused")
  let subscription = WsClientActor::new(state, "unused").open_subscription()
  defer state.unsubscribe(subscription.notifications)
  state.publish("session.event", { "sequence": 1 })
  let notification = subscription.notifications.get()
  assert_true(subscription.out.try_put(Notify(notification)))
  guard subscription.out.get() is Notify(readiness) else {
    fail("expected readiness notification")
  }
  assert_eq(readiness.method_, "agent.connected")
  guard subscription.out.get() is Notify(forwarded) else {
    fail("expected forwarded notification")
  }
  assert_eq(forwarded.method_, "session.event")
}

///|
test "a full outbound queue rejects responses instead of blocking tasks" {
  let out : @async.Queue[Outgoing] = Queue(kind=Blocking(1))
  enqueue_outgoing(out, Response(Json::null()))
  try enqueue_outgoing(out, Response(Json::null())) catch {
    SlowClient(_) => ()
    error => raise error
  } noraise {
    _ => fail("a full outbound queue accepted another response")
  }
}

///|
test "classify accepts client notifications" {
  let message : Json = {
    "jsonrpc": "2.0",
    "method": "client.notice",
    "params": { "value": true },
  }
  match classify(message.stringify()) {
    ClientNotification => ()
    _ => fail("expected a client notification")
  }
}

///|
fn expect_notification(value : @api.Notification?) -> @api.Notification raise {
  guard value is Some(notification) else { fail("expected a notification") }
  notification
}

///|
test "remote delivery omits only canonical transcript duplicates" {
  for
    event_name in [
      "tool_result", "auto_compaction_finished", "agent_finished", "context_yield",
    ] {
    assert_true(
      notification_for_client({
        method_: "agent.event",
        params: {
          "session": "session-1",
          "event": { "event": Json::string(event_name) },
        },
      })
      is None,
    )
  }
}

///|
test "remote delivery retains streaming runtime and error events" {
  for
    event_name in [
      "agent_step", "assistant_delta", "reasoning_delta", "usage", "tool_call_decode_error",
      "background_notice", "runtime_update", "steer_applied", "steer_dropped", "agent_aborted",
      "max_steps_exhausted", "agent_setup_failed", "compaction_started", "compaction_failed",
      "unknown_future_event",
    ] {
    assert_true(
      notification_for_client({
        method_: "agent.event",
        params: {
          "session": "session-1",
          "event": { "event": Json::string(event_name) },
        },
      })
      is Some(_),
    )
  }
  assert_true(
    notification_for_client({
      method_: "session.event",
      params: Json::empty_object(),
    })
    is Some(_),
  )
}

///|
test "remote lifecycle frames keep state and trim transcript text" {
  let started = expect_notification(
    notification_for_client({
      method_: "agent.started",
      params: {
        "run_id": "run-1",
        "session": "session-1",
        "task": "large prompt",
      },
    }),
  )
  assert_eq(started.params, {
    "run_id": "run-1",
    "session": "session-1",
    "task": "",
  })
  let finished = expect_notification(
    notification_for_client({
      method_: "agent.finished",
      params: {
        "run_id": "run-1",
        "status": "finished",
        "answer": "large answer",
      },
    }),
  )
  assert_eq(finished.params, {
    "run_id": "run-1",
    "status": "finished",
    "answer": "large answer",
  })
  let compacted = expect_notification(
    notification_for_client({
      method_: "agent.event",
      params: {
        "session": "session-1",
        "event": { "event": "compaction_finished", "summary": "large summary" },
      },
    }),
  )
  assert_eq(compacted.params, {
    "session": "session-1",
    "event": { "event": "compaction_finished", "summary": "" },
  })
  for event_name in ["reasoning_message", "assistant_message"] {
    let settled = expect_notification(
      notification_for_client({
        method_: "agent.event",
        params: {
          "session": "session-1",
          "event": {
            "event": Json::string(event_name),
            "content": "large content",
          },
        },
      }),
    )
    assert_eq(settled.params, {
      "session": "session-1",
      "event": { "event": Json::string(event_name), "content": "" },
    })
  }
}

///|
test "remote delivery preserves session-less transcript events" {
  let started_params : Json = {
    "run_id": "run-ephemeral",
    "task": "ephemeral prompt",
  }
  let started = expect_notification(
    notification_for_client({ method_: "agent.started", params: started_params }),
  )
  assert_eq(started.params, started_params)
  for
    event_name in [
      "reasoning_message", "assistant_message", "tool_result", "agent_finished",
      "context_yield",
    ] {
    let params : Json = {
      "event": {
        "event": Json::string(event_name),
        "content": "ephemeral content",
      },
    }
    let delivered = expect_notification(
      notification_for_client({ method_: "agent.event", params }),
    )
    assert_eq(delivered.params, params)
  }
}

///|
test "empty session is not treated as durable" {
  let params : Json = {
    "session": "",
    "event": { "event": "tool_result", "content": "ephemeral result" },
  }
  let delivered = expect_notification(
    notification_for_client({ method_: "agent.event", params }),
  )
  assert_eq(delivered.params, params)
}
