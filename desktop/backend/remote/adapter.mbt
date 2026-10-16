///|
/// Transport type erasure happens after the service/desktop endpoint has
/// already paired a typed command and its handler. The registry is not rebuilt.
pub(all) struct RequestHandler {
  name : String
  invoke : async (Json) -> Json
}

///|
/// Working-host events have a typed delivery profile. A desktop/relay host
/// can additionally supply its own auth/update events without adding them to
/// the service protocol.
pub(all) enum Notification {
  Host(@protocol.HostNotification)
  Other(String, Json)
}

///|
pub fn Notification::from_host(
  event : @protocol.HostNotification,
) -> Notification {
  Host(event)
}

///|
pub fn Notification::other(method_ : String, params : Json) -> Notification {
  Other(method_, params)
}

///|
fn Notification::wire_name(self : Notification) -> String {
  match self {
    Host(event) => event.wire_name()
    Other(name, _) => name
  }
}

///|
fn Notification::params(self : Notification) -> Json {
  match self {
    Host(event) => event.params()
    Other(_, params) => params
  }
}

///|
fn Notification::profile(self : Notification) -> Notification? {
  match self {
    Host(event) => notification_for_client(event).map(event => Host(event))
    Other(_, _) => Some(self)
  }
}
