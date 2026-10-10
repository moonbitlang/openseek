///|
priv suberror BrowserCaptureError {
  BrowserCaptureError(String)
} derive(Debug)

///|
/// Own the port configuration before CEF starts. The marker handshake below
/// also verifies the browser instance if another process wins the bind race.
async fn prepare_debugging() -> Int {
  let configured = @env.get_env_var("PROTON_REMOTE_DEBUGGING_PORT")
  if configured is Some(value) && value != "0" && !value.trim().is_empty() {
    let port = @string.parse_int(value.trim())
    guard port >= 1024 && port <= 65535 else {
      raise BrowserCaptureError("Invalid PROTON_REMOTE_DEBUGGING_PORT")
    }
    port
  } else {
    let reservation = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    let port = reservation.addr.port()
    reservation.close()
    @env.set_env_var("PROTON_REMOTE_DEBUGGING_PORT", port.to_string())
    port
  }
}

///|
/// Close every rejected or interrupted candidate. A matching connection is
/// immediately adopted by the discovery scope before its timeout exits.
async fn connect_target(
  target : @cdp.Target,
  key_json : String,
) -> @cdp.Connection? {
  // A target can disappear between discovery and its WebSocket handshake.
  let connection = target.connect() catch { _ => return None }
  let mut transferred = false
  defer (if !transferred { connection.close() })
  let matched : Bool = connection
    .evaluate("globalThis[\{key_json}] === true")
    .decode_value() catch {
      _ => return None
    }
  guard matched else { return None }
  transferred = true
  Some(connection)
}

///|
/// Use a native browser view's CDP connection for one operation. The callback
/// must not retain the connection: it closes on return, failure, or cancellation.
/// Initialize BrowserViews before starting CEF; a window must be attached here.
pub async fn[T] BrowserViews::with_cdp(
  self : BrowserViews,
  id : Int,
  f : async (@cdp.Connection) -> T,
) -> T {
  let view = self.view(id)
  let marker = @uuid.mint()
  let key_json = ("__seekmoon_cdp_" + marker).to_json().stringify()
  view.eval(
    "Object.defineProperty(globalThis, \{key_json}, {value:true, configurable:true});",
  )
  defer (view.eval("delete globalThis[\{key_json}]") catch { _ => () })
  with_cdp_targets(self.debug_port, key_json, connection => {
    // Once matched, the marker has no further purpose during the operation.
    view.eval("delete globalThis[\{key_json}]")
    f(connection)
  })
}

///|
/// Own discovery and callback together. Adoption happens inside the timeout so
/// cancellation during timeout-scope teardown cannot strand a connection.
async fn[T] with_cdp_targets(
  port : Int,
  key_json : String,
  f : async (@cdp.Connection) -> T,
) -> T {
  let mut owned : @cdp.Connection? = None
  defer (if owned is Some(connection) { connection.close() })
  let connection = @async.with_timeout(10000, () => {
    // Native eval is asynchronous; retry while the view processes the marker.
    for _ in 0..<20 {
      for target in @cdp.list_targets(port) {
        guard target.kind == "page" else { continue }
        if connect_target(target, key_json) is Some(connection) {
          owned = Some(connection)
          return connection
        }
      }
      @async.sleep(50)
    }
    raise BrowserCaptureError(
      "Could not find this browser tab. Reload it and try again.",
    )
  })
  f(connection)
}
