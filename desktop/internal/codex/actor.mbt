// The app-lifetime owner of the single Codex app-server process. Public API
// calls enter through a bounded command queue; app-server notifications and
// reverse requests enter through a separate bounded event queue so the
// JSON-RPC reader never waits for a browser or Proton command.

///|
pub(all) suberror CodexError {
  JsonRpc(method_~ : String, code~ : Int, message~ : String, data~ : Json?)
  TransportClosed(method_~ : String)
  RequestFailed(method_~ : String, detail~ : String)
  Unavailable(String)
} derive(Debug)

///|
pub impl Show for CodexError with fn output(self, logger) {
  match self {
    JsonRpc(method_~, code~, message~, data~) => {
      logger.write_string(
        "Codex app-server request \{method_} failed: JSON-RPC error \{code}: \{message}",
      )
      if data is Some(data) {
        logger.write_string("; data=" + data.stringify())
      }
    }
    TransportClosed(method_~) =>
      logger.write_string(
        "Codex app-server request \{method_} failed: transport closed before a reply",
      )
    RequestFailed(method_~, detail~) =>
      logger.write_string(
        "Codex app-server request \{method_} failed: \{detail}",
      )
    Unavailable(message) => logger.write_string(message)
  }
}

///|
/// A task created by another Codex client can exist in the state database
/// before its first user message creates a rollout. Summary reads are valid in
/// that interval, but current app-server builds reject `includeTurns=true`
/// without a machine-readable error discriminator.
pub fn CodexError::is_unmaterialized_thread_history(self : CodexError) -> Bool {
  match self {
    JsonRpc(method_~, code~, message~, data=_) =>
      method_ == "thread/read" &&
      code == -32600 &&
      message.contains("is not materialized yet") &&
      message.contains("includeTurns is unavailable before first user message")
    _ => false
  }
}

///|
/// The same pre-rollout task state also rejects `thread/turns/list`. Callers
/// that only need to prove there is no first turn may treat it as an empty page.
pub fn CodexError::is_unmaterialized_thread_turns(self : CodexError) -> Bool {
  match self {
    JsonRpc(method_~, code~, message~, data=_) =>
      method_ == "thread/turns/list" &&
      code == -32600 &&
      message.contains("is not materialized yet") &&
      message.contains(
        "thread/turns/list is unavailable before first user message",
      )
    _ => false
  }
}

///|
/// Write the structured request failure before Proton applies its production
/// error-redaction policy. This keeps app-server fields in the Desktop log
/// without exposing unrelated backend failures to the browser page.
fn CodexError::log(self : CodexError) -> Unit {
  match self {
    JsonRpc(method_~, code~, message~, data~) =>
      @xlog.error(category="codex") <?
        {
          "event": "codex_app_server_jsonrpc_error",
          "method": method_,
          "code": code,
          "error_message": message,
          "data": data.unwrap_or(Json::null()),
        }
    TransportClosed(method_~) =>
      @xlog.error(category="codex") <?
        { "event": "codex_app_server_transport_closed", "method": method_ }
    RequestFailed(method_~, detail~) =>
      @xlog.error(category="codex") <?
        {
          "event": "codex_app_server_request_failed",
          "method": method_,
          "error": detail,
        }
    Unavailable(message) =>
      @xlog.warn(category="codex") <?
        { "event": "codex_app_server_unavailable", "error": message }
  }
}

///|
priv enum ConnectionState {
  Starting
  Ready
  Unavailable(String)
}

///|
priv enum ActorInput {
  Call(String, Json, @async.Queue[Result[Json, CodexError]])
  Respond(Json, Json, @async.Queue[Result[Json, CodexError]])
  ListRequests(@async.Queue[Result[Json, CodexError]])
}

///|
priv enum AppServerEvent {
  Notification(String, Json)
  Request(@jsonrpc.PeerRequest)
  Disconnected
}

///|
priv enum ActorStep {
  Input(ActorInput)
  Event(AppServerEvent)
}

///|
/// The actor is the sole owner of reverse-request membership and its monotonic
/// generation. Both attach snapshots and live events read this same counter,
/// so the frontend can reject an older snapshot without inferring timing.
priv struct ReverseRequestRegistry {
  mut requests : Map[String, @jsonrpc.PeerRequest]
  mut generation : Int
}

///|
fn ReverseRequestRegistry::ReverseRequestRegistry() -> ReverseRequestRegistry {
  { requests: Map([]), generation: 0, }
}

///|
fn ReverseRequestRegistry::reset(self : ReverseRequestRegistry) -> Unit {
  self.requests = Map([])
  self.generation += 1
}

///|
fn ReverseRequestRegistry::contains(
  self : ReverseRequestRegistry,
  key : String,
) -> Bool {
  self.requests.get(key) is Some(_)
}

///|
fn ReverseRequestRegistry::insert(
  self : ReverseRequestRegistry,
  key : String,
  request : @jsonrpc.PeerRequest,
) -> Unit {
  self.requests[key] = request
  self.generation += 1
}

///|
fn ReverseRequestRegistry::take(
  self : ReverseRequestRegistry,
  key : String,
) -> @jsonrpc.PeerRequest? {
  guard self.requests.get(key) is Some(request) else { return None }
  self.requests.remove(key)
  self.generation += 1
  Some(request)
}

///|
fn ReverseRequestRegistry::remove(
  self : ReverseRequestRegistry,
  key : String,
) -> Unit {
  ignore(self.take(key))
}

///|
fn ReverseRequestRegistry::snapshot(self : ReverseRequestRegistry) -> Json {
  let data : Array[Json] = []
  for _, request in self.requests {
    data.push({
      "request_id": request.id(),
      "method": Json(request.method_name()),
      "params": request.params(),
    })
  }
  { "data": data, "generation": self.generation }
}

///|
const ActorInputCapacity : Int = 256

///|
const AppServerEventCapacity : Int = 2048

///|
const ActorWakeCapacity : Int = 1

///|
/// One per Desktop process. `run` owns its child; `call` and `respond` are the
/// only request-side handles shared with API dispatch tasks.
struct Actor {
  settings : CodexSettings
  inputs : @async.Queue[ActorInput]
  // Inputs and connection events signal after they are safely queued. The
  // single slot deliberately coalesces wakes: the actor drains real queues,
  // so one wake is enough for any number of buffered messages.
  wake : @async.Queue[Unit]
  mut state : ConnectionState
  reverse_requests : ReverseRequestRegistry
}

///|
/// The isolated `CODEX_HOME` this actor spawns the app-server with, or
/// `None` when the inherited environment applies.
pub fn Actor::config_home(self : Actor) -> @pathx.Path? {
  self.settings.home
}

///|
pub fn Actor::Actor(settings : CodexSettings) -> Actor {
  {
    settings,
    inputs: Queue(kind=Blocking(ActorInputCapacity)),
    wake: Queue(kind=Blocking(ActorWakeCapacity)),
    state: Starting,
    reverse_requests: ReverseRequestRegistry(),
  }
}

///|
fn Actor::signal(self : Actor) -> Unit {
  (self.wake.try_put(()) catch { _ => false }) |> ignore
}

///|
/// A synchronous readiness snapshot for settings and startup UI. A successful
/// JSON-RPC call remains the authoritative test of a live connection.
pub fn Actor::status(self : Actor) -> Json {
  match self.state {
    Starting => { "status": "starting" }
    Ready => { "status": "ready" }
    Unavailable(message) => { "status": "unavailable", "message": message }
  }
}

///|
/// Queue one input on its own reply channel, wake the actor, and wait for the
/// single settlement it sends back.
async fn Actor::submit(
  self : Actor,
  input : (@async.Queue[Result[Json, CodexError]]) -> ActorInput,
) -> Json {
  let reply : @async.Queue[Result[Json, CodexError]] = Queue(kind=Blocking(1))
  self.inputs.put(input(reply))
  self.signal()
  match reply.get() {
    Ok(value) => value
    Err(error) => raise error
  }
}

///|
/// Send one allowlisted app-server request through the actor. The API package,
/// not this process owner, decides which method names are exposed to clients.
pub async fn Actor::call(
  self : Actor,
  method_~ : String,
  params~ : Json,
) -> Json {
  self.submit(reply => Call(method_, params, reply))
}

///|
/// Answer an app-server reverse request using the exact opaque id delivered in
/// `codex.server_request`. `result` must match that request method's documented
/// response shape.
pub async fn Actor::respond(
  self : Actor,
  request_id~ : Json,
  result~ : Json,
) -> Json {
  self.submit(reply => Respond(request_id, result, reply))
}

///|
/// List the live reverse requests still owned by this connection. A page calls
/// this after attaching or reloading so a missed approval event cannot leave a
/// turn waiting forever with no visible prompt.
pub async fn Actor::requests(self : Actor) -> Json {
  self.submit(reply => ListRequests(reply))
}

///|
/// Own the app-server for the Desktop lifetime. The first connection is eager;
/// after an unavailable executable or a later disconnect, the next API input
/// triggers one reconnect attempt instead of spinning a failing child loop.
pub async fn Actor::run(self : Actor, emit : (String, Json) -> Unit) -> Unit {
  let mut first = true
  for ;; {
    let pending = if first {
      first = false
      None
    } else {
      Some(self.inputs.get())
    }
    @async.with_task_group(group => self.run_connection(group, pending, emit)) catch {
      // App shutdown must still cancel the actor and every owned child. A
      // child-process failure, however, only ends this connection attempt;
      // keeping the loop alive lets the next API input retry the app-server.
      error if @async.is_being_cancelled() => raise error
      error =>
        self.report_unavailable(
          "Codex app-server stopped unexpectedly: \{error}",
          pending,
          emit,
        )
    }
  }
}

///|
/// Publish one failed connection attempt and settle the input that triggered
/// it. The actor loop calls this only after the connection task group has
/// unwound, so the next input can safely create a fresh child process.
fn Actor::report_unavailable(
  self : Actor,
  message : String,
  pending : ActorInput?,
  emit : (String, Json) -> Unit,
) -> Unit {
  let error = CodexError::Unavailable(message)
  error.log()
  self.state = Unavailable(message)
  emit("codex.status_changed", self.status())
  if pending is Some(input) {
    input.reject(error)
  }
}

///|
async fn[G] Actor::run_connection(
  self : Actor,
  group : @async.TaskGroup[G],
  pending : ActorInput?,
  emit : (String, Json) -> Unit,
) -> Unit {
  self.state = Starting
  // A reconnect invalidates every request owned by the previous JSON-RPC
  // peer. Advancing the same lifetime generation also lets the next empty
  // snapshot clear stale approvals in already-attached frontends.
  self.reverse_requests.reset()
  emit("codex.status_changed", self.status())
  let events : @async.Queue[AppServerEvent] = Queue(
    kind=Blocking(AppServerEventCapacity),
  )
  let connection = connect(
    group,
    command=self.settings.command,
    home=self.settings.home,
    version="0.1.0",
    notification_handler=(method_, params) => {
      if !(events.try_put(Notification(method_, params)) catch { _ => false }) {
        // Losing a completion notification is not recoverable from deltas.
        // Close the event lane; the actor reconnects and the UI resyncs from
        // `thread/read(includeTurns=true)`.
        events.close()
      }
      self.signal()
    },
    request_handler=request => {
      let accepted = events.try_put(Request(request)) catch { _ => false }
      self.signal()
      accepted
    },
    on_closed=() => {
      (events.try_put(Disconnected) catch { _ => false }) |> ignore
      self.signal()
    },
  )
  guard connection is Some(connection) else {
    self.report_unavailable("Codex app-server is unavailable", pending, emit)
    return
  }
  self.state = Ready
  emit("codex.status_changed", self.status())
  if pending is Some(input) {
    connection.dispatch_input(group, self.reverse_requests, input)
  }
  for ;; {
    let next = self.next_step(events) catch {
      error if @async.is_being_cancelled() => raise error
      _ => break
    }
    match next {
      Input(input) =>
        connection.dispatch_input(group, self.reverse_requests, input)
      Event(Notification(method_, params)) => {
        if method_ == "serverRequest/resolved" &&
          params is { "requestId": request_id, .. } {
          self.reverse_requests.remove(request_id.stringify())
        }
        emit("codex.notification", {
          "method": Json(method_),
          "params": params,
          "generation": self.reverse_requests.generation,
        })
      }
      Event(Request(request)) => {
        if !self.supports_reverse_request(request.method_name()) {
          group.spawn_bg(allow_failure=true, () => {
            connection.respond_error(
              request,
              code=-32601,
              message="Unsupported Codex request",
            )
          })
          continue
        }
        let request_id = request.id()
        let key = request_id.stringify()
        if self.reverse_requests.contains(key) {
          // Duplicate live JSON-RPC ids are invalid. Keep the first owner and
          // reject the later request so an approval cannot answer the wrong
          // operation.
          group.spawn_bg(allow_failure=true, () => {
            connection.respond_error(
              request,
              code=-32600,
              message="Duplicate request id",
            )
          })
        } else {
          self.reverse_requests.insert(key, request)
          emit("codex.server_request", {
            "request_id": request_id,
            "method": Json(request.method_name()),
            "params": request.params(),
            "generation": self.reverse_requests.generation,
          })
        }
      }
      Event(Disconnected) => break
    }
  }
  connection.shutdown()
  self.state = Unavailable("Codex app-server disconnected")
  emit("codex.status_changed", self.status())
}

///|
/// Prefer API commands, then connection events. Both producers queue their
/// value before signaling `wake`, so waiting never races and cancels a queue
/// read that may already have taken ownership of a message.
async fn Actor::next_step(
  self : Actor,
  events : @async.Queue[AppServerEvent],
) -> ActorStep {
  for ;; {
    if (self.inputs.try_get() catch { _ => None }) is Some(input) {
      return Input(input)
    }
    let event = events.try_get() catch { _ => return Event(Disconnected) }
    if event is Some(event) {
      return Event(event)
    }
    self.wake.get()
  }
}

///|
fn ActorInput::reject(self : ActorInput, error : CodexError) -> Unit {
  match self {
    Call(_, _, reply) | Respond(_, _, reply) | ListRequests(reply) =>
      (reply.try_put(Err(error)) catch { _ => false }) |> ignore
  }
}

///|
/// Reverse requests the Desktop has a typed response UI for. Experimental
/// attestation, externally-managed token refresh, and dynamic-tool calls are
/// not advertised during initialize, so receiving one is a protocol mismatch
/// and fails closed instead of showing an unanswerable raw request.
fn Actor::supports_reverse_request(_self : Actor, method_ : String) -> Bool {
  method_ == "item/commandExecution/requestApproval" ||
  method_ == "item/fileChange/requestApproval" ||
  method_ == "item/permissions/requestApproval" ||
  method_ == "item/tool/requestUserInput" ||
  method_ == "mcpServer/elicitation/request"
}

///|
fn[G] Connection::dispatch_input(
  self : Connection,
  group : @async.TaskGroup[G],
  reverse_requests : ReverseRequestRegistry,
  input : ActorInput,
) -> Unit {
  match input {
    Call(method_, params, reply) =>
      group.spawn_bg(allow_failure=true, () => {
        let outcome = try self.request(method_~, params~) catch {
          error if @async.is_being_cancelled() => {
            // The connection task group is cancelled on disconnect. Settle
            // the API caller before preserving that cancellation; otherwise
            // Actor::call waits forever on a reply only this child owned.
            let closed = TransportClosed(method_~)
            closed.log()
            (reply.try_put(Err(closed)) catch { _ => false }) |> ignore
            raise error
          }
          @jsonrpc.Failed(code~, message~, data~) => {
            let error = JsonRpc(method_~, code~, message~, data~)
            error.log()
            Err(error)
          }
          @jsonrpc.Closed => {
            let error = TransportClosed(method_~)
            error.log()
            Err(error)
          }
          error => {
            let error = RequestFailed(method_~, detail="\{error}")
            error.log()
            Err(error)
          }
        } noraise {
          value => Ok(value)
        }
        (reply.try_put(outcome) catch { _ => false }) |> ignore
      })
    Respond(request_id, result, reply) => {
      let key = request_id.stringify()
      guard reverse_requests.take(key) is Some(request) else {
        let error = RequestFailed(
          method_="serverRequest/respond",
          detail="Unknown or resolved Codex request",
        )
        error.log()
        (reply.try_put(Err(error)) catch { _ => false }) |> ignore
        return
      }
      group.spawn_bg(allow_failure=true, () => {
        let outcome = try {
          self.respond(request, result)
          Ok(Json::empty_object())
        } catch {
          error if @async.is_being_cancelled() => {
            let closed = TransportClosed(method_="serverRequest/respond")
            closed.log()
            (reply.try_put(Err(closed)) catch { _ => false }) |> ignore
            raise error
          }
          error => {
            let error = RequestFailed(
              method_="serverRequest/respond",
              detail="\{error}",
            )
            error.log()
            Err(error)
          }
        }
        (reply.try_put(outcome) catch { _ => false }) |> ignore
      })
    }
    ListRequests(reply) =>
      (reply.try_put(Ok(reverse_requests.snapshot())) catch { _ => false })
      |> ignore
  }
}

///|
async test "Codex actor consumes a buffered API command before events" {
  let actor = Actor(CodexSettings::default())
  let events : @async.Queue[AppServerEvent] = Queue(kind=Blocking(1))
  let reply : @async.Queue[Result[Json, CodexError]] = Queue(kind=Blocking(1))
  actor.inputs.put(ListRequests(reply))
  let step = actor.next_step(events)
  assert_true(step is Input(ListRequests(_)))
}

///|
async test "Codex actor wakes for an API command without racing queue reads" {
  @async.with_task_group(group => {
    let actor = Actor(CodexSettings::default())
    let events : @async.Queue[AppServerEvent] = Queue(kind=Blocking(1))
    let waiting = group.spawn(() => actor.next_step(events))
    let reply : @async.Queue[Result[Json, CodexError]] = Queue(kind=Blocking(1))
    actor.inputs.put(ListRequests(reply))
    actor.signal()
    assert_true(waiting.wait() is Input(ListRequests(_)))
  })
}

///|
test "Codex reverse-request generations advance only on ownership changes" {
  let requests = ReverseRequestRegistry()
  assert_eq(requests.generation, 0)
  requests.reset()
  assert_eq(requests.generation, 1)
  // Resolving an id that this connection no longer owns must not create a
  // phantom generation between the response and resolved notification.
  requests.remove(Json("missing").stringify())
  assert_eq(requests.generation, 1)
  @debug.assert_eq(requests.snapshot(), { "data": [], "generation": 1 })
}

///|
pub extend CodexError with Debug::{to_repr}

///|
pub extend CodexError with Show::{output, to_string}
