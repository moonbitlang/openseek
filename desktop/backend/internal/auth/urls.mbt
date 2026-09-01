// URL derivations shared by the sign-in flow, the relay actor,
// and the status shape. The server origin itself comes from the engine
// settings' server selection (or the environment override) — this package
// only derives from it.

///|
/// The control-WebSocket URL a host dials to register with `server_url`'s
/// relay: `https` becomes `wss` (`http` → `ws` for local development).
pub fn tunnel_url(server_url : String) -> String {
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
/// The browser console URL for a device registered at `server_url`. A packaged
/// Desktop opens the Browser bundle published from the same release, so its UI
/// and host messages come from one build. Development has no published bundle
/// and therefore uses the server-selected console instead.
pub fn device_url(
  server_url : String,
  device : String,
  app_version~ : String,
) -> String {
  let origin = match server_url.strip_suffix("/") {
    Some(origin) => origin.to_owned()
    None => server_url
  }
  if app_version == "development" {
    "\{origin}/console/?device=\{device}"
  } else {
    "\{origin}/console/releases/v\{app_version}/index.html?device=\{device}"
  }
}

///|
/// The server origin implied by a full tunnel URL — the status shape's
/// `server_url` when the connector runs from the environment override,
/// whose `OPENSEEK_RELAY_URL` is the `ws(s)` URL, not the origin.
pub fn origin_from_relay_url(relay_url : String) -> String {
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
