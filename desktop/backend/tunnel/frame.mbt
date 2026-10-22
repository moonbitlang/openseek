// The control messages exchanged by the desktop process and openseek-api on
// the long-lived `/v1/tunnel` WebSocket (docs/remote-protocol.md). This package
// only defines their JSON representation: socket ownership, authentication,
// retries, and stream pairing live on their respective sides.
//
// Once `Open` causes the desktop to dial `/v1/tunnel/<stream>`, that data
// WebSocket carries the normal client protocol unchanged. Nothing in this
// package decodes or routes those client messages. See README.md for the full
// connection flow and ownership boundaries.

///|
pub(all) enum Frame {
  /// Desktop → service, the first frame: register this machine. The service
  /// maps the token to a stable device id, so reconnecting keeps the same
  /// browser destination.
  Register(token~ : String, name~ : String)
  /// Service → desktop: registration succeeded; `device` is the public id.
  Registered(device~ : String)
  /// Service → desktop: a browser connected to `/v2/devices/<device>/ws`;
  /// open the matching `/v1/tunnel/<stream>` data WebSocket.
  Open(stream~ : String)
  /// Service → desktop: registration was rejected. The desktop stops using
  /// these credentials and waits for a new sign-in instead of retrying them.
  Fail(message~ : String)
  /// Desktop → service, after `registered`: something the account's
  /// installed consoles should be told about while they are closed. The
  /// service turns it into a Web Push to each of the account's subscriptions.
  Notify(PushEvent)
}

///|
/// The two moments the desktop window raises a system banner for, as the
/// service needs them to build a push: the session names the conversation a
/// notification opens. The text fields are already cut to banner length.
pub(all) enum PushEvent {
  /// A run settled with any status but `cancelled`.
  Finished(session~ : String, status~ : String, answer~ : String?)
  /// A run stopped to ask permission.
  Approval(session~ : String, tool~ : String, detail~ : String)
}

///|
fn PushEvent::to_json(self : PushEvent) -> Json {
  match self {
    Finished(session~, status~, answer~) => {
      let event : Json = {
        "kind": "finished",
        "session": session,
        "status": status,
      }
      if answer is Some(answer) && event is Object(fields) {
        fields["answer"] = Json(answer)
      }
      event
    }
    Approval(session~, tool~, detail~) =>
      { "kind": "approval", "session": session, "tool": tool, "detail": detail }
  }
}

///|
fn PushEvent::from_json(json : Json) -> PushEvent? {
  match json {
    {
      "kind": "finished",
      "session": String(session),
      "status": String(status),
      "answer"? : answer,
      ..
    } =>
      match answer {
        None => Some(Finished(session~, status~, answer=None))
        Some(String(answer)) =>
          Some(Finished(session~, status~, answer=Some(answer)))
        Some(_) => None
      }
    {
      "kind": "approval",
      "session": String(session),
      "tool": String(tool),
      "detail": String(detail),
      ..
    } => Some(Approval(session~, tool~, detail~))
    _ => None
  }
}

///|
pub fn Frame::encode(self : Frame) -> String {
  let frame : Json = match self {
    Register(token~, name~) =>
      { "type": "register", "device_token": token, "name": name }
    Registered(device~) => { "type": "registered", "device": device }
    Open(stream~) => { "type": "open", "stream": stream }
    Fail(message~) => { "type": "fail", "message": message }
    Notify(event) => { "type": "notify", "event": event.to_json() }
  }
  frame.stringify()
}

///|
/// Decode one control frame; None for anything malformed or unknown — the
/// receiving side terminates the current control connection.
pub fn Frame::decode(text : String) -> Frame? {
  let json = @json.parse(text) catch { _ => return None }
  match json {
    {
      "type": "register",
      "device_token": String(token),
      "name": String(name),
      ..
    } => Some(Register(token~, name~))
    { "type": "registered", "device": String(device), .. } =>
      Some(Registered(device~))
    { "type": "open", "stream": String(stream), .. } => Some(Open(stream~))
    { "type": "fail", "message": String(message), .. } => Some(Fail(message~))
    { "type": "notify", "event": event, .. } =>
      PushEvent::from_json(event).map(event => Notify(event))
    _ => None
  }
}
