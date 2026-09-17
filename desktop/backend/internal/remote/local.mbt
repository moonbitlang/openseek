// The local transport: the desktop window's own loopback origin. The host
// serves the frontend bundle over plain `http://127.0.0.1:<port>/` and
// upgrades `/ws` into exactly the JSON-RPC connection a relayed browser gets
// (docs/remote-protocol.md), plus the window-only methods — so the window
// and a remote page share one client path end to end. The WebSocket is the
// capability boundary: it requires the launch token minted for the window's
// entry URL, and a present `Origin` header must be our own origin, which
// keeps foreign web pages (whose browsers always send one) out even though
// they can reach loopback.
//
// The port is fixed — the build's default unless `--port` / OPENSEEK_PORT names
// another (see `main`) — rather than ephemeral, because the origin is the
// key to the page's localStorage: a port that changed on every launch would
// reset every UI preference with it.

///|
/// The loopback HTTP+WebSocket server owning the window's origin.
struct LocalServer {
  state : @api.ApiState
  // The directory the page's files are served from and the document `/`
  // resolves to inside it.
  root : String
  entry : String
  token : String
  // The window-only methods every loopback connection serves beside the
  // shared catalog.
  window_endpoints : Array[@endpoint.Endpoint]
  // Runs when a page attaches (its WebSocket handshake was accepted): the
  // previous page's native views must not survive its replacement.
  on_page_attached : () -> Unit
  server : @http.Server
}

///|
/// Bind the loopback listener on the configured port. When that port is
/// taken (another instance, an unrelated program), a fresh ephemeral port
/// keeps the app usable at the cost of one launch's UI preferences — the
/// fixed origin's storage stays intact for the next launch that gets it.
pub async fn LocalServer::start(
  state : @api.ApiState,
  root~ : String,
  entry~ : String,
  token~ : String,
  window_endpoints~ : Array[@endpoint.Endpoint],
  on_page_attached~ : () -> Unit,
  port~ : Int,
) -> LocalServer {
  let server = @http.Server(
    @socket.Addr::parse("127.0.0.1:\{port}"),
    reuse_addr=true,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      @xlog.warn(category="transport") <?
        {
          "event": "loopback_port_unavailable",
          "port": port,
          "error": "\{error}",
          "message": "the fixed loopback port is taken; this launch runs on an ephemeral origin and UI preferences will not carry over",
        }
      Server(@socket.Addr::parse("127.0.0.1:0"), reuse_addr=true)
    }
  }
  { state, root, entry, token, window_endpoints, on_page_attached, server, }
}

///|
pub fn LocalServer::port(self : LocalServer) -> Int {
  self.server.addr.port()
}

///|
/// The page's origin, which is also the only `Origin` its WebSocket accepts.
pub fn LocalServer::origin(self : LocalServer) -> String {
  "http://127.0.0.1:\{self.port()}"
}

///|
/// The URL the window loads. The token rides the entry query string; the
/// page hands it back on its WebSocket dial.
pub fn LocalServer::entry_url(self : LocalServer) -> String {
  "\{self.origin()}/?token=\{self.token}"
}

///|
/// Accept and serve connections for the app's lifetime. Each connection is
/// its own task: a static fetch answers one request and closes, while an
/// upgraded WebSocket lives as one client actor until the page goes away.
pub async fn LocalServer::run(self : LocalServer) -> Unit {
  defer self.server.close()
  @async.with_task_group(group => {
    for ;; {
      let (conn, _) = self.server.accept()
      group.spawn_bg(allow_failure=true, () => self.handle(conn))
    }
  })
}

///|
async fn LocalServer::handle(
  self : LocalServer,
  conn : @http.ServerConnection,
) -> Unit {
  defer conn.close()
  let request = conn.read_request()
  if request.headers.get("upgrade") is Some(upgrade) &&
    upgrade.to_lower() == "websocket" {
    self.serve_ws(request, conn)
  } else {
    self.serve_static(request, conn)
  }
}

///|
async fn LocalServer::serve_ws(
  self : LocalServer,
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  guard ws_authorized(
    request.path,
    request.headers.get("origin"),
    token=self.token,
    origin=self.origin(),
  ) else {
    respond_status(conn, 403, "Forbidden")
    return
  }
  let ws = @websocket.from_http_server(request, conn)
  defer ws.close()
  (self.on_page_attached)()
  WsClientActor::loopback(self.state, self.window_endpoints).serve(ws) catch {
    error if @async.is_being_cancelled() => raise error
    // The page reloading or the window closing mid-frame is routine.
    _ => ()
  }
}

///|
/// Whether a WebSocket handshake may become a client connection: the `/ws`
/// route presenting the launch token, from our own origin (or none — a
/// non-browser debugging client has no `Origin`; the token remains its
/// capability).
fn ws_authorized(
  path : String,
  request_origin : String?,
  token~ : String,
  origin~ : String,
) -> Bool {
  let (route, query) = split_path_query(path)
  guard route == "/ws" && query_param(query, "token") == Some(token) else {
    return false
  }
  match request_origin {
    None => true
    Some(request_origin) => request_origin == origin
  }
}

///|
async fn LocalServer::serve_static(
  self : LocalServer,
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  guard request.meth is Get else {
    respond_status(conn, 405, "Method Not Allowed")
    return
  }
  let (route, _) = split_path_query(request.path)
  guard static_asset_route(route, entry=self.entry) is Some(relative) else {
    respond_status(conn, 404, "Not Found")
    return
  }
  let body = @fs.read_file("\{self.root}/\{relative}").binary() catch {
    error if @async.is_being_cancelled() => raise error
    _ => {
      respond_status(conn, 404, "Not Found")
      return
    }
  }
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": content_type(relative),
    "Content-Length": body.length().to_string(),
    // The bundle changes in place on self-update; make every launch
    // revalidate rather than trust a stale webview cache.
    "Cache-Control": "no-cache",
    "Connection": "close",
  })
  conn.write(body)
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
/// only plain visible names (no empty, dotted, or parent segments) resolve —
/// everything else 404s without touching the filesystem.
fn static_asset_route(path : String, entry~ : String) -> String? {
  guard path.strip_prefix("/") is Some(rest) else { return None }
  if rest.is_empty() {
    return Some(entry)
  }
  for segment in rest.split("/") {
    if segment.is_empty() || segment.has_prefix(".") {
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
test "static routes map the entry and reject traversal" {
  assert_eq(static_asset_route("/", entry="index.html"), Some("index.html"))
  assert_eq(
    static_asset_route("/", entry="desktop-dev.html"),
    Some("desktop-dev.html"),
  )
  assert_eq(
    static_asset_route("/frontend.js", entry="index.html"),
    Some("frontend.js"),
  )
  assert_eq(
    static_asset_route("/fonts/GeistMono-Variable.woff2", entry="index.html"),
    Some("fonts/GeistMono-Variable.woff2"),
  )
  assert_true(static_asset_route("/../secret", entry="index.html") is None)
  assert_true(
    static_asset_route("/fonts/../../etc/passwd", entry="index.html") is None,
  )
  assert_true(static_asset_route("/.hidden", entry="index.html") is None)
  assert_true(static_asset_route("//double", entry="index.html") is None)
  assert_true(static_asset_route("no-slash", entry="index.html") is None)
}

///|
test "websocket handshakes require the token and our own origin" {
  let token = "sesame"
  let origin = "http://127.0.0.1:4100"
  assert_true(ws_authorized("/ws?token=sesame", None, token~, origin~))
  assert_true(ws_authorized("/ws?token=sesame", Some(origin), token~, origin~))
  assert_false(
    ws_authorized(
      "/ws?token=sesame",
      Some("https://evil.example"),
      token~,
      origin~,
    ),
  )
  assert_false(
    ws_authorized(
      "/ws?token=sesame",
      Some("http://127.0.0.1:4101"),
      token~,
      origin~,
    ),
  )
  assert_false(ws_authorized("/ws?token=wrong", None, token~, origin~))
  assert_false(ws_authorized("/ws", None, token~, origin~))
  assert_false(ws_authorized("/other?token=sesame", None, token~, origin~))
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
  assert_eq(content_type("fonts/GeistMono-Variable.woff2"), "font/woff2")
  assert_eq(content_type("unknown.bin"), "application/octet-stream")
}
