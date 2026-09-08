///|
/// In-flight protocol requests awaiting their response packet, keyed by
/// request id. Each entry owns the caller-token subscription that can retire
/// the request before a late server response arrives.
priv struct PendingProtocolRequest {
  resolve : (@remote_protocol.ServerPacket) -> Unit
  mut cancellation_subscription : @base_common.Disposable?
  mut sent : Bool
}

///|
/// A module-level registry, like `browser_dispatch`.
let pending_requests : Map[String, PendingProtocolRequest] = Map([])

///|
/// Request ids cancelled locally but still capable of receiving a late wire
/// response. Tombstones consume that response instead of misrouting a late
/// `DocumentLoaded` packet into the unrelated watch-push path.
let cancelled_request_ids : Map[String, Unit] = Map([])

///|
let request_counter : Ref[Int] = Ref(0)

///|
/// Sends a client packet over the live protocol socket. Installed at mount
/// so async provider code can transmit without threading a scheduler.
let protocol_send : Ref[((@remote_protocol.ClientPacket) -> Unit)?] = Ref(None)

///|
fn send_protocol_packet(packet : @remote_protocol.ClientPacket) -> Unit {
  if protocol_send.val is Some(send) {
    send(packet)
  }
}

///|
fn next_request_id(prefix : String) -> String {
  request_counter.val += 1
  "\{prefix}-\{request_counter.val.to_string()}"
}

///|
/// Sends a request packet and suspends until the response with the same id
/// arrives. Correlation is by request id, so two in-flight requests of the
/// same kind can no longer cross. The reject continuation is never called;
/// failures resolve as `RemoteError` packets instead.
async fn protocol_request(
  prefix : String,
  make_packet : (String) -> @remote_protocol.ClientPacket,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
) -> @remote_protocol.ServerPacket noraise {
  let id = next_request_id(prefix)
  if token.is_cancellation_requested() {
    return cancelled_protocol_response(id)
  }
  @js.suspend((
    resolve : (@remote_protocol.ServerPacket) -> Unit,
    _reject : (Error) -> Unit,
  ) => {
    let pending : PendingProtocolRequest = {
      resolve,
      cancellation_subscription: None,
      sent: false,
    }
    pending_requests[id] = pending
    let subscription = token.on_cancellation_requested(() => {
      cancel_pending_request(id)
    })
    pending.cancellation_subscription = Some(subscription)
    // Cancellation can be delivered inline while the subscription is being
    // installed. In that case `cancel_pending_request` has already resumed
    // the suspension and the wire request must never be sent.
    if pending_requests.get(id) is Some(_) {
      pending.sent = true
      send_protocol_packet(make_packet(id))
    } else {
      subscription.dispose()
    }
  }) catch {
    _ =>
      RemoteError(
        ProtocolError(
          ProtocolProviderError,
          "Protocol request failed.",
          request_id=id,
        ),
      )
  }
}

///|
fn cancelled_protocol_response(id : String) -> @remote_protocol.ServerPacket {
  RemoteError(
    ProtocolError(
      ProtocolProviderError,
      "Protocol request cancelled.",
      request_id=id,
      provider_code="Cancelled",
    ),
  )
}

///|
/// Removes the pending entry for `id` and releases its cancellation
/// subscription, returning the entry when one was still registered.
fn take_pending_request(id : String) -> PendingProtocolRequest? {
  guard pending_requests.get(id) is Some(pending) else { return None }
  pending_requests.remove(id)
  if pending.cancellation_subscription is Some(subscription) {
    pending.cancellation_subscription = None
    subscription.dispose()
  }
  Some(pending)
}

///|
fn cancel_pending_request(id : String) -> Unit {
  guard take_pending_request(id) is Some(pending) else { return }
  if pending.sent {
    cancelled_request_ids[id] = ()
  }
  (pending.resolve)(cancelled_protocol_response(id))
}

///|
/// Routes a decoded server packet to its waiting request, if any. Returns
/// whether the packet was consumed as a response.
fn resolve_pending_response(packet : @remote_protocol.ServerPacket) -> Bool {
  let id = server_packet_request_id(packet)
  if id == "" {
    return false
  }
  if take_pending_request(id) is Some(pending) {
    (pending.resolve)(packet)
    return true
  }
  if cancelled_request_ids.contains(id) {
    cancelled_request_ids.remove(id)
    return true
  }
  false
}

///|
/// Fails every in-flight request, used when the socket drops so suspended
/// providers resolve instead of leaking.
fn fail_pending_requests(message : String) -> Unit {
  cancelled_request_ids.clear()
  let ids = [ for id, _pending in pending_requests => id ]
  for id in ids {
    if take_pending_request(id) is Some(pending) {
      (pending.resolve)(
        RemoteError(
          ProtocolError(ProtocolProviderError, message, request_id=id),
        ),
      )
    }
  }
}

///|
fn server_packet_request_id(packet : @remote_protocol.ServerPacket) -> String {
  match packet {
    DirectoryResolved(payload) => payload.id
    DocumentLoaded(payload) => payload.id
    DocumentChanged(payload) => payload.id
    // Diagnostics packets are server pushes and never answer a request.
    Diagnostics(_) => ""
    HoverResult(payload) => payload.id
    DefinitionResult(payload) => payload.id
    ReferencesResult(payload) => payload.id
    DocumentSymbolsResult(payload) => payload.id
    HostDirectoryListed(payload) => payload.id
    // Broadcast switches carry an empty id and route as pushes.
    WorkspaceSwitched(payload) => payload.id
    RemoteError(error) => error.request_id
  }
}

///|
fn connect_protocol_cmd(emit : @rabbita.Emit[WorkbenchMsg]) -> @rabbita.Cmd {
  @websocket.connect(
    protocol_connection_id(),
    protocol_websocket_url(),
    on_event=event => emit(ProtocolEvent(event)),
    failed=message => emit(ProtocolSendFailed(message)),
  )
}

///|
fn send_client_packet_cmd(
  emit : @rabbita.Emit[WorkbenchMsg],
  packet : @remote_protocol.ClientPacket,
) -> @rabbita.Cmd {
  @websocket.send(
    protocol_connection_id(),
    Text(packet.to_json().stringify()),
    failed=message => emit(ProtocolSendFailed(message)),
  )
}

///|
fn protocol_connection_id() -> String {
  "readonly-editor-protocol"
}
