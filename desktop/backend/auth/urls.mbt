// URL derivations shared by the sign-in flow, the relay actor,
// and the status shape. The server origin itself comes from the engine
// settings' server selection (or the environment override) — this package
// only derives from it.

///|
/// The control-WebSocket URL a host dials to register with `server_url`'s
/// relay: `https` becomes `wss` (`http` → `ws` for local development).
fn tunnel_url(server_url : String) -> String {
  let origin = match server_url.strip_suffix("/") {
    Some(origin) => origin.to_owned()
    None => server_url
  }
  let ws_origin = if origin.strip_prefix("https://") is Some(rest) {
    "wss://\{rest}"
  } else if origin.strip_prefix("http://") is Some(rest) {
    "ws://\{rest}"
  } else {
    origin
  }
  "\{ws_origin}/v1/tunnel"
}

///|
/// The browser console URL for a device registered at `server_url`: its chat
/// page, served by the relay's one current frontend. A host built for another
/// protocol revision is reported there as unavailable.
fn device_url(server_url : String, device : String) -> String {
  let origin = match server_url.strip_suffix("/") {
    Some(origin) => origin
    None => server_url
  }
  "\{origin}/device/\{@uri.encode_component(device)}/chat"
}

///|
/// The server origin implied by a full tunnel URL — the status shape's
/// `server_url` when the connector runs from the environment override,
/// whose `OPENSEEK_RELAY_URL` is the `ws(s)` URL, not the origin.
fn origin_from_relay_url(relay_url : String) -> String {
  let origin = if relay_url.strip_prefix("wss://") is Some(rest) {
    "https://\{rest}"
  } else if relay_url.strip_prefix("ws://") is Some(rest) {
    "http://\{rest}"
  } else {
    relay_url
  }
  match origin.strip_suffix("/v1/tunnel") {
    Some(base) => base.to_owned()
    None => origin
  }
}
