///|
pub struct Target {
  kind : String
  priv debugger_url : String?
  priv port : Int
}

///|
/// Discover targets on a local Chromium debugging endpoint. The host still
/// owns port allocation and the association between native views and targets.
pub async fn list_targets(port : Int) -> Array[Target] {
  let (_, body) = @http.get("http://127.0.0.1:\{port}/json/list")
  let json = @json.parse(body.text())
  guard json is Array(targets) else {
    raise Protocol("Invalid CDP target list")
  }
  targets.map(target => {
    kind: required(target, "type"),
    port,
    debugger_url: optional(target, "webSocketDebuggerUrl"),
  })
}

///|
/// Connect to this discovered target. The endpoint must belong to the local
/// debugging service that supplied it; missing endpoints are not connectable.
pub async fn Target::connect(self : Target) -> Connection {
  guard self.debugger_url is Some(url) else {
    raise Protocol("CDP target has no debugger endpoint")
  }
  guard url.has_prefix("ws://127.0.0.1:\{self.port}/devtools/") ||
    url.has_prefix("ws://localhost:\{self.port}/devtools/") else {
    raise Protocol(
      "CDP target endpoint does not belong to its debugging service",
    )
  }
  connect(url)
}
