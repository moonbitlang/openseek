// One remote client's connection: JSON-RPC 2.0 over a WebSocket the host
// dialed out through the relay (docs/remote-protocol.md). Requests fan out
// to the shared dispatcher concurrently; notifications flow back from the
// hub. The bridge and this file are the only two transports, and everything
// below the envelope is the typed Endpoint selected from `@api.endpoints`.

///|
/// Everything the single writer task sends, encoded only at the writer so
/// no other task ever touches the socket.
priv enum Outgoing {
  // A complete JSON-RPC response envelope, built where the request ran.
  Response(Json)
  Notify(@protocol.Notification)
  // Protocol-level keepalive, serialized with every text frame.
  Ping
}

///|
/// The outbound queue and hub subscription that make one remote client.
/// Opening them also installs the readiness frame: because the fresh bounded
/// outbound queue is empty, that `put` cannot suspend, so no hub publisher
/// can run between subscribe and readiness. Forwarders may only start after
/// this returns.
priv struct ClientSubscription {
  out : @async.Queue[Outgoing]
  notifications : @broadcast.Subscription[@protocol.Notification]
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
fn WsClientActor::WsClientActor(
  state : @api.ApiState,
  url : String,
) -> WsClientActor {
  { state, host_connection: HostConnection(), url, }
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
  out.put(Notify(AgentConnected({ stage: Accepted, })))
  { out, notifications, }
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
  // A valid request envelope whose catalog params are not an object (-32602).
  InvalidParams(Json)
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
/// pump parked in `put` would never get back to its subscription to notice
/// that it lagged).
const OutboundQueueCapacity = 64

///|
/// Maximum request bodies and operation tasks retained by one remote client.
/// The reader acquires before spawning, so the socket itself supplies
/// backpressure instead of creating an unbounded crowd of tasks waiting on
/// slower engine, filesystem, or registry work.
const InflightRequestCapacity = 32

///|
/// JSON-RPC requests carry prompts and small operation payloads, never
/// transcripts or file contents. Reading one extra byte distinguishes the
/// allowed exact limit from an oversized message without letting
/// `Reader::read_all` grow until a peer-provided 64-bit frame length.
const InboundFrameMaxBytes : Int = 1024 * 1024

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
/// Serve the actor's connected socket until it closes (or its hub
/// subscription lags for want of draining).
async fn WsClientActor::serve(
  self : WsClientActor,
  conn : @websocket.Conn,
) -> Unit {
  let subscription = self.open_subscription()
  let out = subscription.out
  let notifications = subscription.notifications
  let request_permits : @semaphore.Semaphore = Semaphore(
    InflightRequestCapacity,
    initial_value=InflightRequestCapacity,
  )
  // Endpoint closures capture this connection's watch and PTY ownership once;
  // every request only performs a name lookup in the stable catalog.
  let endpoints = @api.endpoints(self.state, self.host_connection)
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
      self.host_connection.run(
        notification => enqueue_outgoing(out, Notify(notification)),
        notification => enqueue_outgoing(out, Notify(notification)),
      )
    })
    group.spawn_bg(() => {
      // Tears the connection down either way it ends — the client
      // reconnects into a resync: this subscription lagging behind the hub's
      // log (`next` raises), or the outbound queue standing full (the socket
      // has stalled for `OutboundQueueCapacity` frames, and the protocol
      // promises a disconnect over a silent gap in the stream).
      for ;; {
        let notification = notifications.next() catch {
          @broadcast.Lagged(missed~) as lagged => {
            @xlog.warn(category="transport") <?
              {
                "event": "hub_subscription_lagged",
                "transport": "remote",
                "missed": missed,
              }
            raise lagged
          }
          error => raise error
        }
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
      let frame = FixedArray::make(InboundFrameMaxBytes + 1, b'\x00')
      let mut received = 0
      for ;; {
        let count = message.read(
          frame,
          offset=received,
          max_len=frame.length() - received,
        )
        if count == 0 {
          break
        }
        received += count
        if received > InboundFrameMaxBytes {
          conn.send_close(
            code=MessageTooBig,
            reason="JSON-RPC request exceeds 1 MiB",
          )
          return
        }
      }
      let text = @utf8.decode(frame.unsafe_reinterpret_as_bytes()[:received])
      match classify(text) {
        Request(id, method_, params) =>
          if method_ == "fs.watch" || method_ == "fs.unwatch" {
            // Watch ownership is ordered by the client's request stream. Run
            // these two operations at the reader boundary: spawning first
            // would let task scheduling enqueue a later unwatch before an
            // earlier watch (or vice versa), despite the actor's FIFO
            // mailbox. Resolution is rare and only delays later inbound
            // requests; outbound notifications and pings have their own
            // tasks.
            enqueue_outgoing(
              out,
              Response(run_request(endpoints, id, method_, params)),
            )
          } else {
            // Each other request runs in its own task so a slow op (an engine
            // start, a big file read) does not block other admitted requests;
            // acquiring before spawn bounds retained tasks and lets TCP
            // backpressure slow a client that exceeds this connection's
            // concurrency budget. Replies are correlated by id, not order.
            request_permits.acquire()
            group.spawn_bg(() => {
              defer request_permits.release()
              enqueue_outgoing(
                out,
                Response(run_request(endpoints, id, method_, params)),
              )
            })
          }
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
        InvalidParams(id) =>
          enqueue_outgoing(
            out,
            Response(
              error_envelope(
                id,
                CodeInvalidParams,
                "method parameters must be an object",
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
        "method": Json(notification.wire_name()),
        "params": notification.params(),
      }
  }
  conn.send_text(envelope.stringify())
}

///|
fn classify(text : String) -> Inbound {
  let message = @json.parse(text) catch { _ => return Unparsable }
  guard message is Object(fields) else { return Invalid }
  // Reject protocol lookalikes before any catalog method can run.
  guard fields.get("jsonrpc") is Some(String("2.0")) else { return Invalid }
  guard fields.get("method") is Some(String(method_)) else { return Invalid }
  let id = fields.get("id")
  // JSON-RPC request ids may only be strings, numbers, or null. They remain
  // opaque here and are echoed unchanged in the response.
  match id {
    None | Some(String(_)) | Some(Number(_, ..)) | Some(Null) => ()
    Some(_) => return Invalid
  }
  let params = match fields.get("params") {
    Some(Object(_) as params) => params
    // This catalog uses named object parameters rather than positional
    // arrays. A malformed notification still receives no response.
    Some(_) =>
      match id {
        Some(id) => return InvalidParams(id)
        None => return ClientNotification
      }
    None => Json::empty_object()
  }
  match id {
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
  notification : @protocol.Notification,
) -> @protocol.Notification? {
  match notification {
    AgentEvent(payload) => {
      // Desktop starts always name a durable session. An event without one
      // cannot be reconciled with the session transcript and is not part of
      // the supported remote profile.
      guard !payload.session.is_empty() else { return None }
      if payload.event.remote_lifecycle() is Some(event) {
        Some(AgentEvent({ ..payload, event, }))
      } else {
        None
      }
    }
    AgentStarted(payload) if !payload.session.is_empty() =>
      Some(AgentStarted(payload))
    AgentStarted(_) => None
    _ => Some(notification)
  }
}

///|
/// Run one request through the dispatcher and shape the outcome as a
/// JSON-RPC response, mapping each typed failure to its protocol code.
async fn run_request(
  endpoints : Array[@endpoint.Endpoint],
  id : Json,
  method_ : String,
  params : Json,
) -> Json {
  guard endpoints.iter().find_first(endpoint => endpoint.name() == method_)
    is Some(endpoint) else {
    return error_envelope(id, CodeMethodNotFound, "unknown method '\{method_}'")
  }
  let result = endpoint.invoke_remote(params) catch {
    error if @async.is_being_cancelled() => raise error
    @endpoint.InvalidEndpointPayload(message) =>
      return error_envelope(id, CodeInvalidParams, message)
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
    "error": { "code": Json(code.to_double()), "message": message },
  }
}

///|
async test "readiness precedes the first forwarded hub notification" {
  let state = @api.ApiState(engine="unused")
  let subscription = WsClientActor::WsClientActor(state, "unused").open_subscription()
  state.publish(
    SessionEvent({
      session: "session-1",
      sequence: 1,
      event: {
        sequence: 1,
        ts: None,
        item: User({ content: "test", submission_id: None, }),
      },
      session_root: "/sessions/global",
    }),
  )
  let notification = subscription.notifications.next()
  assert_true(subscription.out.try_put(Notify(notification)))
  guard subscription.out.get() is Notify(readiness) else {
    fail("expected readiness notification")
  }
  assert_eq(readiness.wire_name(), "agent.connected")
  guard subscription.out.get() is Notify(forwarded) else {
    fail("expected forwarded notification")
  }
  assert_eq(forwarded.wire_name(), "session.event")
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
test "classify enforces the JSON-RPC 2.0 request envelope" {
  for
    message in [
      Json({ "id": Json(1), "method": Json("session.list") }),
      { "jsonrpc": "1.0", "id": 1, "method": "session.list" },
      { "jsonrpc": "2.0", "id": true, "method": "session.list" },
      { "jsonrpc": "2.0", "id": {}, "method": "session.list" },
      { "jsonrpc": "2.0", "id": [], "method": "session.list" },
    ] {
    assert_true(classify(message.stringify()) is Invalid)
  }
  for id in [Json("request-1"), Json(1), Json::null()] {
    let message : Json = {
      "jsonrpc": "2.0",
      "id": id,
      "method": "session.list",
    }
    match classify(message.stringify()) {
      Request(actual_id, method_, Object(params)) => {
        assert_eq(actual_id, id)
        assert_eq(method_, "session.list")
        assert_eq(params.length(), 0)
      }
      _ => fail("expected a valid request")
    }
  }
}

///|
test "classify rejects non-object catalog parameters" {
  let request : Json = {
    "jsonrpc": "2.0",
    "id": "request-1",
    "method": "update.apply",
    "params": [],
  }
  match classify(request.stringify()) {
    InvalidParams(id) => assert_eq(id, Json("request-1"))
    _ => fail("expected invalid method parameters")
  }
  let notification : Json = {
    "jsonrpc": "2.0",
    "method": "client.notice",
    "params": [],
  }
  // Notifications never receive responses, including when this catalog
  // cannot consume their parameters.
  assert_true(classify(notification.stringify()) is ClientNotification)
}

///|
fn expect_notification(
  value : @protocol.Notification?,
) -> @protocol.Notification raise {
  guard value is Some(notification) else { fail("expected a notification") }
  notification
}

///|
/// One run-scoped agent event as `notification_for_client` sees it.
fn client_frame(event : @wire.Event) -> @protocol.Notification? {
  notification_for_client(
    AgentEvent({
      run_id: None,
      session: "session-1",
      event: { event, submission_id: None, },
    }),
  )
}

///|
test "remote delivery omits only canonical transcript duplicates" {
  let events : Array[@wire.Event] = [
    ToolResult(
      tool_call_id="call-1",
      tool_name="read",
      is_error=false,
      content="result",
      brief=None,
    ),
    AutoCompactionFinished(from_sequence=1, to_sequence=2, summary="summary"),
    AgentFinished(answer="answer"),
    ContextYield(to_sequence=2, answer="answer"),
  ]
  for event in events {
    assert_true(client_frame(event) is None)
  }
}

///|
test "remote delivery retains streaming runtime and error events" {
  let events : Array[@wire.Event] = [
    AgentStep(step=1),
    AssistantDelta(content="delta"),
    ReasoningDelta(content="live reasoning"),
    ReasoningMessage(content="reasoning"),
    Usage(usage={
      prompt_tokens: 1,
      completion_tokens: 2,
      total_tokens: 3,
      prompt_cache_hit_tokens: 0,
      prompt_cache_miss_tokens: 1,
    }),
    ToolCallDecodeError(
      tool_call_id="call-1",
      tool_name="read",
      error="bad arguments",
    ),
    BackgroundNotice(content="notice"),
    GoalUpdated(goal=Some("goal")),
    SteerApplied(kind="prompt", content="steered"),
    SteerDropped(content="late"),
    AgentAborted(reason="cancelled"),
    MaxStepsExhausted,
    AgentSetupFailed(error="setup failed"),
    CompactionStarted(from_sequence=1, to_sequence=2),
    CompactionFailed(error="compact failed"),
  ]
  for event in events {
    assert_true(client_frame(event) is Some(_))
  }
  assert_true(
    notification_for_client(
      SessionEvent({
        session: "session-1",
        sequence: 1,
        event: {
          sequence: 1,
          ts: None,
          item: User({ content: "test", submission_id: None, }),
        },
        session_root: "/sessions/global",
      }),
    )
    is Some(_),
  )
}

///|
test "remote lifecycle frames keep state without transcript text" {
  let started = expect_notification(
    notification_for_client(
      AgentStarted({
        run_id: "run-1",
        submission_id: None,
        engine: None,
        model: None,
        max_steps: None,
        session: "session-1",
        session_root: None,
      }),
    ),
  )
  assert_eq(started.params(), { "run_id": "run-1", "session": "session-1" })
  let finished = expect_notification(
    notification_for_client(
      AgentFinished({
        run_id: "run-1",
        status: "finished",
        answer: Some("large answer"),
        exit_code: None,
      }),
    ),
  )
  assert_eq(finished.params(), {
    "run_id": "run-1",
    "status": "finished",
    "answer": "large answer",
  })
  let compacted = expect_notification(
    client_frame(
      CompactionFinished(
        from_sequence=1,
        to_sequence=2,
        summary="large summary",
      ),
    ),
  )
  assert_eq(compacted.params(), {
    "session": "session-1",
    "event": {
      "event": "compaction_finished",
      "from_sequence": 1,
      "to_sequence": 2,
      "summary": "",
    },
  })
  let settled_events : Array[@wire.Event] = [
    ReasoningMessage(content="large content"),
    AssistantMessage(content="large content"),
  ]
  for event in settled_events {
    let settled = expect_notification(client_frame(event))
    let event_name = match event {
      ReasoningMessage(..) => "reasoning_message"
      AssistantMessage(..) => "assistant_message"
      _ => fail("expected a semantic message")
    }
    assert_eq(settled.params(), {
      "session": "session-1",
      "event": { "event": Json(event_name), "content": "" },
    })
  }
}

///|
test "remote delivery drops notifications without a session" {
  let started_notification : @protocol.Notification = AgentStarted({
    run_id: "run-ephemeral",
    submission_id: None,
    engine: None,
    model: None,
    max_steps: None,
    session: "",
    session_root: None,
  })
  assert_true(notification_for_client(started_notification) is None)
  let event : @protocol.AgentEventPayload = {
    run_id: None,
    session: "",
    event: {
      event: ToolResult(
        tool_call_id="call-1",
        tool_name="read",
        is_error=false,
        content="ephemeral result",
        brief=None,
      ),
      submission_id: None,
    },
  }
  let notification : @protocol.Notification = AgentEvent({ ..event, })
  assert_true(notification_for_client(notification) is None)
}
