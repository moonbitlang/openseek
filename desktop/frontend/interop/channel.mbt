// Which engine host a request is for. Every feature package names its
// channel in `bridge_request(channel, op, payload)`; the channel picks the
// transport while method names and payloads stay identical either way
// (docs/remote-protocol.md).

///|
/// One engine host the page can talk to. `Local` is the page's own host —
/// the injected proton bridge in the desktop window; `Remote(id)` is a
/// stable named target. Today browser remotes are relay devices reached over
/// WebSocket; the identity deliberately does not encode that transport so a
/// another remote target can use the same channel shape.
pub(all) enum ChannelId {
  Local
  Remote(String)
} derive(Debug, Eq, Hash)

///|
/// One conversation on one engine host. Session ids are only meaningful
/// inside their channel: two independent hosts may both contain `s1`, and
/// their state and async replies must remain distinct throughout the client.
/// This is a frontend identity only; neither the remote wire nor persistence
/// serializes this struct.
pub(all) struct ConversationKey {
  channel : ChannelId
  session : String
} derive(Debug, Eq, Hash)

///|
/// The authority used by app-owned resource URIs for this channel. The
/// authority is an identity, not a network endpoint: `remote.<id>` stays
/// stable if the target's transport changes.
pub fn ChannelId::uri_authority(self : ChannelId) -> String {
  match self {
    Local => "local"
    Remote(id) => "remote.\{id}"
  }
}

///|
/// Decode an app-owned URI authority. Unknown authorities and an empty remote
/// id are rejected so a foreign URI can never fall back to the local host.
pub fn ChannelId::from_uri_authority(authority : String) -> ChannelId? {
  if authority == "local" {
    Some(Local)
  } else if authority.strip_prefix("remote.") is Some(id) && !id.is_empty() {
    Some(Remote(id.to_owned()))
  } else {
    None
  }
}

///|
/// The channel this page is born with: the desktop webview talks to its
/// local host. `None` in a browser — the console at `/` holds no channel
/// until it fetches the device roster and connects each device.
pub fn page_channel() -> ChannelId? {
  if openseek_api() is Some(_) {
    Some(Local)
  } else {
    None
  }
}
