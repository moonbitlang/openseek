///|
/// One saved working-host identity, shared by this host's window connections.
/// The SSH destination is configuration, never the identity. Persist id and
/// server_id in the desktop profile store; a changed server needs a new profile
/// or explicit reassociation after every old connection has been closed.
pub struct Host {
  id : String
  config : SshHost
  priv mut server_id : String?
}

///|
pub fn Host::Host(id~ : String, config : SshHost) -> Host raise {
  guard id.has_prefix("ssh_") && id.length() > 4 else {
    raise HostClientError("SSH host identity must use the ssh_ namespace")
  }
  { id, config, server_id: config.expected_server_id, }
}

///|
pub fn Host::server_id(self : Host) -> String? {
  self.server_id
}

///|
fn Host::pin(self : Host, identity : @host_control.Identity) -> Unit raise {
  if self.server_id is Some(expected) && identity.server_id != expected {
    raise IdentityChanged(
      "working-host server identity changed; explicit reassociation is required",
    )
  }
  self.server_id = Some(identity.server_id)
}

///|
/// A window owns a Connection, while its profile owns Host. Epochs are scoped
/// to this Connection and never become part of the saved host or resource ID.
pub struct Connection {
  host : Host
  priv mut epoch : Int32
  priv mut client : Client?
  priv mut running : Bool
}

///|
pub fn Connection::Connection(host : Host) -> Connection {
  { host, epoch: 0, client: None, running: false, }
}

///|
/// Delivery is synchronous and must enqueue without blocking. Returning false
/// means the bounded consumer has overflowed: the connection closes and the
/// caller must rebuild its subscription and resynchronize before running again.
pub(all) enum ConnectionEvent {
  Connecting(epoch~ : Int32)
  Connected(epoch~ : Int32, identity~ : @host_control.Identity)
  Notification(epoch~ : Int32, value~ : Json)
  Disconnected(epoch~ : Int32, message~ : String, retry_ms~ : Int32)
  IdentityBlocked(epoch~ : Int32, message~ : String)
}

///|
fn deliver(
  emit : (ConnectionEvent) -> Bool,
  event : ConnectionEvent,
) -> Unit raise {
  guard emit(event) else { raise ConsumerOverflow }
}

///|
priv suberror ConsumerOverflow

///|
fn retry_ceiling(attempt : Int32) -> Int32 {
  let mut delay = 500
  for i = 0; i < attempt && delay < 30000; i = i + 1 {
    delay = Int32::min(delay * 2, 30000)
  }
  delay
}

///|
fn retry_delay(attempt : Int32) -> Int32 raise {
  guard @env.rand(2) is Some(bytes) else {
    raise HostClientError("OS entropy unavailable for SSH reconnect")
  }
  let sample = bytes[0].to_int() * 256 + bytes[1].to_int()
  sample % (retry_ceiling(attempt) + 1)
}

///|
/// Own the SSH scope until cancelled by the window. The only retry is a new
/// connection; no request is replayed. Each initialize resets the backoff and
/// every attempt gets a new epoch. Identity replacement stops retries.
pub async fn Connection::run(
  self : Connection,
  emit~ : (ConnectionEvent) -> Bool,
) -> Unit {
  guard !self.running else {
    raise HostClientError("window connection is already running")
  }
  self.running = true
  defer {
    self.running = false
    self.client = None
  }
  let mut attempt = 0
  for ;; {
    self.epoch = fresh_connection_epoch()
    let epoch = self.epoch
    deliver(emit, Connecting(epoch~))
    let config = {
      ..self.host.config,
      expected_server_id: self.host.server_id,
    }
    let error = with_client(config, client => {
      // Another window may have completed initialize since config was read.
      self.host.pin(client.identity)
      self.client = Some(client)
      defer {
        self.client = None
      }
      attempt = 0
      deliver(emit, Connected(epoch~, identity=client.identity))
      for ;; {
        let value = client.next_notification()
        deliver(emit, Notification(epoch~, value~))
      }
    }) catch {
      error => error
    }
    match error {
      IdentityChanged(message) => {
        deliver(emit, IdentityBlocked(epoch~, message~))
        return
      }
      ConsumerOverflow =>
        raise HostClientError(
          "window notification consumer overflow; resync required",
        )
      _ => {
        let retry_ms = retry_delay(attempt)
        deliver(emit, Disconnected(epoch~, message="\{error}", retry_ms~))
        attempt = Int32::min(attempt + 1, 6)
        @async.sleep(retry_ms)
      }
    }
  }
}

///|
/// The frontend supplies the epoch from its latest Connected event. It cannot
/// accidentally send an old view's action through a replacement connection.
pub async fn Connection::request(
  self : Connection,
  epoch~ : Int32,
  method_ : String,
  params : Json,
) -> Json {
  guard self.epoch == epoch && self.client is Some(client) else {
    raise Unsent("window working-host connection changed or is unavailable")
  }
  let result = client.request(method_, params)
  guard self.epoch == epoch &&
    self.client is Some(current) &&
    physical_equal(current, client) else {
    raise Unknown(
      "reply belongs to a retired working-host connection; reconcile durable state",
    )
  }
  result
}

///|
pub impl ToJson for ConnectionEvent with fn to_json(self) {
  match self {
    Connecting(epoch~) => { "kind": "connecting", "epoch": epoch }
    Connected(epoch~, identity~) =>
      { "kind": "connected", "epoch": epoch, "identity": identity }
    Notification(epoch~, value~) =>
      { "kind": "notification", "epoch": epoch, "value": value }
    Disconnected(epoch~, message~, retry_ms~) =>
      {
        "kind": "disconnected",
        "epoch": epoch,
        "message": message,
        "retry_ms": retry_ms,
      }
    IdentityBlocked(epoch~, message~) =>
      { "kind": "identity_blocked", "epoch": epoch, "message": message }
  }
}

///|
pub extend ConnectionEvent with ToJson::{to_json}

///|
/// Retire only the connection that owned an uncertain connection-scoped
/// operation. A late cancellation must never close its replacement epoch.
pub fn Connection::invalidate(self : Connection, epoch~ : Int32) -> Unit {
  if self.epoch == epoch && self.client is Some(client) {
    client.close(
      reason="SSH connection retired after an uncertain login operation",
    )
  }
}

///|
/// Epochs also fence replacement Connection objects in a multi-host window.
/// Recreating one route must never make a queued reply from its predecessor
/// look current just because both objects started at their first attempt.
let next_connection_epoch : Ref[Int32] = Ref(0)

///|
fn fresh_connection_epoch() -> Int32 raise {
  guard next_connection_epoch.val < 2147483647 else {
    raise HostClientError("connection epoch exhausted")
  }
  next_connection_epoch.val += 1
  next_connection_epoch.val
}
