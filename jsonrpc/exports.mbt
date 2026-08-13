// Deliberate exports with no in-repo production consumer (see
// shrink_package.md): test seams, round-trip/protocol surface, and
// future-proof API kept on purpose. Each entry documents its reason.

///|
/// Whether the client has closed. A closed client never answers again — every
/// later request fails fast with `Closed` — so a pool holding one should discard
/// it and connect afresh.
pub fn Client::is_closed(self : Client) -> Bool {
  self.closed
}

///|
/// Install the handler run for each peer-initiated notification (`method`,
/// `params`). Replaces any previous handler; it runs on the reader task, so it
/// must not block on I/O.
pub fn Client::set_notification_handler(
  self : Client,
  handler : (String, Json) -> Unit,
) -> Unit {
  self.on_notification = handler
}

///|
/// Install the receiver for non-ping requests initiated by the peer. The
/// receiver runs on the reader task and therefore must not block. Return true
/// only after transferring the request into caller-owned bounded state; that
/// caller must later answer it with `respond` or `respond_error`. Returning
/// false immediately answers with a server-busy error. If the receiver raises,
/// the client answers that request with an internal error and keeps routing
/// unrelated traffic.
pub fn Client::set_request_handler(
  self : Client,
  handler : (PeerRequest) -> Bool raise,
) -> Unit {
  self.on_request = handler
  self.accepts_requests = true
}

///|
/// The peer method name for this request.
pub fn PeerRequest::method_name(self : PeerRequest) -> String {
  self.method_
}

///|
/// The exact JSON-RPC id to carry as an opaque correlation value in a host UI.
/// Answer the original `PeerRequest`; do not construct a reply from this value.
pub fn PeerRequest::id(self : PeerRequest) -> Json {
  self.id
}

///|
/// The peer parameters, or JSON null when the request omitted `params`.
pub fn PeerRequest::params(self : PeerRequest) -> Json {
  self.params
}
