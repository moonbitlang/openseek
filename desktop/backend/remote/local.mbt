// The development console: a `.dev` build serves its own frontend bundle on
// plain `http://127.0.0.1:<port>/` to the system browser, answering the
// console's account routes for the one machine it is — `/v1/auth/me`, a
// `/v1/devices` roster naming this host as device `host`, and
// `/v1/devices/host/ws` upgraded into the JSON-RPC connection a relayed
// browser gets (docs/remote-protocol.md). The page is the same bundle and
// document the window loads, so a browser here runs the console exactly as
// it would against the relay, with the relay out of the loop. The window
// itself never uses this origin; it stays on the proton bridge.
//
// The session cookie is the capability boundary: the launch token minted at
// bind time rides the entry URL (`/?device=host&token=…`), the document
// response to that URL sets the cookie, and every account route and the
// WebSocket require it. The URL stays complete in the address bar rather
// than redirecting the token away, so it can be reopened, reloaded, or
// pasted into another browser for as long as this launch lasts. The session
// is that launch, not an account: the page's sign-out returns it to the
// gate and its sign-in returns it to the console, and neither moves the
// token, which only ever appears in the entry URL. A present `Origin`
// header must be our own origin, which keeps foreign web pages (whose
// browsers always send one) out even though they can reach loopback.
// Release builds never open this port.
//
// Browsers key cookies by host, not port, so the session cookie also
// reaches any other server on 127.0.0.1 the developer browses to while it
// exists. That is inherent to loopback cookies and shared by every local
// development tool that uses one; a recipient would have to be a listener
// that is not already running as the user (a container's forwarded port,
// another account's service), and this development-only surface does not
// defend against that.

///|
/// The loopback HTTP+WebSocket listener owning the development console's
/// origin. Bound before the API state exists so the state can carry the
/// entry URL; served once the state does.
pub struct LocalConsole {
  server : @http.Server
  token : String
  // Browsers key cookies by host, not port, so two development hosts on
  // one machine must not share a cookie name: each names its session after
  // its own port.
  cookie_name : String
  // How the roster names this machine.
  name : String
}

///|
/// The roster id under which this host lists itself. Not `local`: the browser
/// bundle keeps that id for the window's own inert channel, and a relay id is
/// `d_…`, so this one collides with neither.
pub const LocalConsoleDevice = "host"

///|
/// Bind the loopback listener on `port`. When that port is taken (another
/// development host, an unrelated program), a fresh ephemeral port keeps the
/// console usable; the Settings page shows whichever origin was bound.
pub async fn LocalConsole::bind(port~ : Int) -> LocalConsole {
  guard @entropy.random_hex(32) is Some(token) else {
    // No OS entropy is a hard failure, never weak randomness.
    raise @host.HostError("no OS entropy available for the console token")
  }
  let server = @http.Server(
    @socket.Addr::parse("127.0.0.1:\{port}"),
    reuse_addr=true,
  ) catch {
    error => {
      @xlog.warn(category="transport") <?
        {
          "event": "console_port_unavailable",
          "port": port,
          "error": "\{error}",
          "message": "the development console port is taken; this launch serves the console on an ephemeral port",
        }
      Server(@socket.Addr::parse("127.0.0.1:0"), reuse_addr=true)
    }
  }
  let name = match @platform.machine_hostname() {
    Some(hostname) => hostname
    None => "This device"
  }
  {
    server,
    token,
    cookie_name: "seekmoon_session_\{server.addr.port()}",
    name,
  }
}

///|
pub fn LocalConsole::port(self : LocalConsole) -> Int {
  self.server.addr.port()
}

///|
/// The console's origin, which is also the only `Origin` its routes accept.
pub fn LocalConsole::origin(self : LocalConsole) -> String {
  "http://127.0.0.1:\{self.port()}"
}

///|
/// The URL a browser opens: the console page pinned to this host, with the
/// token that makes its document response set the session cookie.
pub fn LocalConsole::entry_url(self : LocalConsole) -> String {
  "\{self.origin()}/?device=\{LocalConsoleDevice}&token=\{self.token}"
}

///|
/// Accept and serve connections for the app's lifetime. Files come from
/// `root`, with `/` resolving to `entry` inside it — the directory and
/// document the window itself loads. Each connection is its own task: a
/// static fetch answers one request and closes, while an upgraded WebSocket
/// lives as one client actor until the page goes away.
pub async fn LocalConsole::run(
  self : LocalConsole,
  state : @api.ApiState,
  root~ : String,
  entry~ : String,
) -> Unit {
  defer self.server.close()
  @async.with_task_group(group => {
    for ;; {
      let (conn, _) = self.server.accept()
      group.spawn_bg(allow_failure=true, () => {
        self.handle(state, conn, root~, entry~)
      })
    }
  })
}

///|
/// One request, classified by route. Everything the console page fetches
/// from the relay's origin exists here too, answered for this one machine.
priv enum Route {
  // `GET /?…token=…`: the entry document, whose response sets the session.
  Entry(String)
  AuthMe
  Devices
  // The gate's sign-in link (`GET /v1/auth/login`) and the page's sign-out
  // (`POST /v1/auth/logout`): the console page leaves and comes back, while
  // the session stays with the launch.
  Login
  Logout
  // The protocol WebSocket for device `host`.
  DeviceSocket
  Static(String)
  Unknown
  MethodNotAllowed
}

///|
fn route(meth : @http.RequestMethod, path : String, entry~ : String) -> Route {
  let (route, query) = split_path_query(path)
  match (meth, route) {
    (Get, "/") if query_param(query, "token") is Some(token) => Entry(token)
    (Get, "/v1/auth/me") => AuthMe
    (Get, "/v1/devices") => Devices
    (Get, "/v1/auth/login") => Login
    (Post, "/v1/auth/logout") => Logout
    (Get, socket) if socket == "/v1/devices/\{LocalConsoleDevice}/ws" =>
      DeviceSocket
    (Get, _) =>
      match static_asset_route(route, entry~) {
        Some(relative) => Static(relative)
        None => Unknown
      }
    _ => MethodNotAllowed
  }
}

///|
async fn LocalConsole::handle(
  self : LocalConsole,
  state : @api.ApiState,
  conn : @http.ServerConnection,
  root~ : String,
  entry~ : String,
) -> Unit {
  defer conn.close()
  let request = conn.read_request()
  let route = route(request.meth, request.path, entry~)
  // The account routes and the socket are the session's; the page and its
  // files are not, since the entry document is what grants the session.
  let needs_session = route is AuthMe ||
    route is Devices ||
    route is DeviceSocket ||
    route is Logout
  if needs_session && !self.session_authorized(request) {
    respond_status(conn, 401, "Unauthorized")
    return
  }
  match route {
    Entry(token) =>
      if token == self.token {
        // The document itself carries the session: every load of the entry
        // URL renews the cookie, so the URL remains a working capability.
        serve_static(
          root,
          entry,
          conn,
          cookie=Cookie(
            self.cookie_name,
            self.token,
            path="/",
            http_only=true,
            extensions=["SameSite=Strict"],
          ),
        )
      } else {
        respond_status(conn, 403, "Forbidden")
      }
    // No account stands behind the local console, so it has no avatar; the
    // field is absent rather than empty.
    AuthMe => respond_json(conn, { "login": "local" })
    Devices =>
      respond_json(conn, {
        "devices": [
          { "id": LocalConsoleDevice, "name": self.name, "online": true },
        ],
      })
    DeviceSocket =>
      if request.headers.get("upgrade") is Some(upgrade) &&
        upgrade.to_lower() == "websocket" {
        serve_ws(state, request, conn)
      } else {
        respond_status(conn, 400, "Bad Request")
      }
    // Sign-out sends the page to its gate; the session stays with the
    // launch, so nothing is cleared. Redirecting the gate's sign-in to the
    // token-bearing entry URL would hand the token to any local client that
    // asked, so it returns to the page as it is: the cookie, still present,
    // signs it back in.
    Login => respond_redirect(conn, "/?device=\{LocalConsoleDevice}")
    Logout => respond_status(conn, 204, "No Content")
    Static(relative) => serve_static(root, relative, conn)
    Unknown => respond_status(conn, 404, "Not Found")
    MethodNotAllowed => respond_status(conn, 405, "Method Not Allowed")
  }
}

///|
/// Whether a request carries the session and comes from our own origin (or
/// none — a non-browser debugging client has no `Origin`; the cookie remains
/// its capability).
fn LocalConsole::session_authorized(
  self : LocalConsole,
  request : @http.Request,
) -> Bool {
  session_authorized(
    request.headers.get("cookie"),
    request.headers.get("origin"),
    cookie=self.cookie_name,
    token=self.token,
    origin=self.origin(),
  )
}

///|
fn session_authorized(
  cookie_header : String?,
  request_origin : String?,
  cookie~ : String,
  token~ : String,
  origin~ : String,
) -> Bool {
  guard cookie_header is Some(cookies) &&
    cookie_value(cookies, cookie) == Some(token) else {
    return false
  }
  match request_origin {
    None => true
    Some(request_origin) => request_origin == origin
  }
}

///|
/// One cookie's value out of a `Cookie` request header. The session value is
/// plain hex, so nothing needs decoding.
fn cookie_value(header : String, name : String) -> String? {
  for pair in header.split(";") {
    let pair = pair.trim()
    if pair.find("=") is Some(index) && pair[:index].to_owned() == name {
      return Some(pair[index + 1:].to_owned())
    }
  }
  None
}

///|
/// The same client actor a relayed browser gets, on a socket this host
/// accepted instead of dialled.
async fn serve_ws(
  state : @api.ApiState,
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  let ws = @websocket.from_http_server(request, conn)
  defer ws.close()
  WsClientActor(state).serve(ws) catch {
    // The page reloading or the tab closing mid-frame is routine.
    _ => ()
  }
}

///|
/// One bundled file; the entry document additionally carries the session
/// cookie when the request presented the token.
async fn serve_static(
  root : String,
  relative : String,
  conn : @http.ServerConnection,
  cookie? : @http.Cookie,
) -> Unit {
  // Only an absent file is 404; an unreadable one is the bundle being broken,
  // which the log names and the browser sees as a server failure.
  let body = @fs.read_file("\{root}/\{relative}").binary() catch {
    @os_error.OSError(_) as os_error if os_error.is_ENOENT() => {
      respond_status(conn, 404, "Not Found")
      return
    }
    error => {
      @xlog.error(category="transport") <?
        {
          "event": "console_asset_unreadable",
          "path": relative,
          "error": "\{error}",
        }
      respond_status(conn, 500, "Internal Server Error")
      return
    }
  }
  conn.send_response(
    200,
    "OK",
    extra_headers={
      "Content-Type": content_type(relative),
      "Content-Length": body.length().to_string(),
      // A development bundle changes in place between launches; make every
      // load revalidate rather than trust a stale browser cache.
      "Cache-Control": "no-cache",
      "Connection": "close",
    },
    cookies=match cookie {
      Some(cookie) => [cookie]
      None => []
    },
  )
  conn.write(body)
  conn.end_response()
}

///|
async fn respond_json(conn : @http.ServerConnection, body : Json) -> Unit {
  let text = body.stringify()
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json",
    "Content-Length": @utf8.encode(text).length().to_string(),
    "Cache-Control": "no-store",
    "Connection": "close",
  })
  conn.write(text)
  conn.end_response()
}

///|
async fn respond_redirect(
  conn : @http.ServerConnection,
  location : String,
) -> Unit {
  conn.send_response(302, "Found", extra_headers={
    "Location": location,
    "Content-Length": "0",
    "Connection": "close",
  })
  conn.end_response()
}

///|
async fn respond_status(
  conn : @http.ServerConnection,
  code : Int,
  reason : String,
) -> Unit {
  conn.send_response(code, reason, extra_headers={
    "Content-Length": "0",
    "Connection": "close",
  })
  conn.end_response()
}

///|
/// Map a request path onto a bundled file: `/` is the entry document, and
/// only plain visible names resolve — no empty, dotted, or parent segments,
/// and no backslash or colon, which Windows would read as a separator or a
/// drive/stream marker inside what this split treats as one segment.
/// Everything else 404s without touching the filesystem.
fn static_asset_route(path : String, entry~ : String) -> String? {
  guard path.strip_prefix("/") is Some(rest) else { return None }
  if rest.is_empty() {
    return Some(entry)
  }
  for segment in rest.split("/") {
    if segment.is_empty() ||
      segment.has_prefix(".") ||
      segment.contains("\\") ||
      segment.contains(":") {
      return None
    }
  }
  Some(rest.to_owned())
}

///|
fn content_type(name : String) -> String {
  let extension = match name.rev_find(".") {
    Some(index) => name[index + 1:].to_owned()
    None => ""
  }
  match extension {
    "html" => "text/html; charset=utf-8"
    "js" | "mjs" => "text/javascript; charset=utf-8"
    "css" => "text/css; charset=utf-8"
    "json" | "map" => "application/json"
    "svg" => "image/svg+xml"
    "png" => "image/png"
    "ico" => "image/x-icon"
    "ttf" => "font/ttf"
    "woff" => "font/woff"
    "woff2" => "font/woff2"
    "wasm" => "application/wasm"
    "txt" => "text/plain; charset=utf-8"
    _ => "application/octet-stream"
  }
}

///|
fn split_path_query(path : String) -> (String, String) {
  match path.find("?") {
    Some(index) => (path[:index].to_owned(), path[index + 1:].to_owned())
    None => (path, "")
  }
}

///|
/// A raw query parameter. Values are compared byte-for-byte — the launch
/// token is plain hex, so nothing needs percent-decoding.
fn query_param(query : String, name : String) -> String? {
  for pair in query.split("&") {
    if pair.find("=") is Some(index) && pair[:index].to_owned() == name {
      return Some(pair[index + 1:].to_owned())
    }
  }
  None
}

///|
test "routes: the entry, the console's account routes, then the bundle" {
  assert_true(
    route(Get, "/?device=host&token=sesame", entry="index.html")
    is Entry("sesame"),
  )
  assert_true(
    route(Get, "/?token=sesame", entry="index.html") is Entry("sesame"),
  )
  assert_true(route(Get, "/", entry="index.html") is Static("index.html"))
  assert_true(
    route(Get, "/?device=host", entry="desktop-dev.html")
    is Static("desktop-dev.html"),
  )
  assert_true(route(Get, "/v1/auth/me", entry="index.html") is AuthMe)
  assert_true(route(Get, "/v1/devices", entry="index.html") is Devices)
  assert_true(route(Post, "/v1/auth/logout", entry="index.html") is Logout)
  assert_true(route(Get, "/v1/auth/login", entry="index.html") is Login)
  assert_true(
    route(Post, "/v1/devices", entry="index.html") is MethodNotAllowed,
  )
  assert_false(route(Get, "/v1/auth/logout", entry="index.html") is Logout)
  assert_true(
    route(Get, "/v1/devices/host/ws", entry="index.html") is DeviceSocket,
  )
  assert_false(
    route(Get, "/v1/devices/d_other/ws", entry="index.html") is DeviceSocket,
  )
  assert_true(
    route(Get, "/frontend.js", entry="index.html") is Static("frontend.js"),
  )
  assert_true(
    route(Get, "/mermaid/chunks/x.mjs", entry="index.html")
    is Static("mermaid/chunks/x.mjs"),
  )
}

///|
test "static routes reject traversal and hidden names" {
  assert_true(static_asset_route("/../secret", entry="index.html") is None)
  assert_true(
    static_asset_route("/fonts/../../etc/passwd", entry="index.html") is None,
  )
  assert_true(static_asset_route("/.hidden", entry="index.html") is None)
  assert_true(static_asset_route("//double", entry="index.html") is None)
  assert_true(static_asset_route("no-slash", entry="index.html") is None)
  // Windows reads these as separators and drive or stream markers.
  assert_true(
    static_asset_route("/safe\\..\\..\\Users\\x\\secret", entry="index.html")
    is None,
  )
  assert_true(static_asset_route("/C:/Users/x", entry="index.html") is None)
  assert_true(
    static_asset_route("/frontend.js:stream", entry="index.html") is None,
  )
}

///|
test "account routes and the socket require the session and our own origin" {
  let cookie = "seekmoon_session"
  let token = "sesame"
  let origin = "http://127.0.0.1:4100"
  let session = "seekmoon_session=sesame"
  assert_true(session_authorized(Some(session), None, cookie~, token~, origin~))
  assert_true(
    session_authorized(Some(session), Some(origin), cookie~, token~, origin~),
  )
  assert_true(
    session_authorized(
      Some("other=1; seekmoon_session=sesame; more=2"),
      Some(origin),
      cookie~,
      token~,
      origin~,
    ),
  )
  assert_false(
    session_authorized(
      Some(session),
      Some("https://evil.example"),
      cookie~,
      token~,
      origin~,
    ),
  )
  assert_false(
    session_authorized(
      Some(session),
      Some("http://127.0.0.1:4101"),
      cookie~,
      token~,
      origin~,
    ),
  )
  assert_false(
    session_authorized(
      Some("seekmoon_session=wrong"),
      None,
      cookie~,
      token~,
      origin~,
    ),
  )
  assert_false(
    session_authorized(Some("other=1"), None, cookie~, token~, origin~),
  )
  assert_false(session_authorized(None, None, cookie~, token~, origin~))
}

///|
test "content types cover the bundled asset set" {
  assert_eq(content_type("index.html"), "text/html; charset=utf-8")
  assert_eq(content_type("frontend.js"), "text/javascript; charset=utf-8")
  assert_eq(
    content_type("mermaid/mermaid.esm.min.mjs"),
    "text/javascript; charset=utf-8",
  )
  assert_eq(content_type("viewer.css"), "text/css; charset=utf-8")
  assert_eq(content_type("codicon.ttf"), "font/ttf")
  assert_eq(content_type("unknown.bin"), "application/octet-stream")
}
