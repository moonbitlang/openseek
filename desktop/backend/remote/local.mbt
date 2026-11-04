// The development console: a `.dev` build serves its own frontend bundle on
// plain `http://127.0.0.1:<port>/` to the system browser, answering the
// console's account routes for the one machine it is — `/v1/auth/me`,
// independent browser account login via `/v2/auth/login` and `/cb`,
// `/v1/devices` roster naming this host as device `host`, and
// `/v1/devices/host/ws` upgraded into the JSON-RPC connection a relayed
// browser gets (docs/remote-protocol.md). The page is the same bundle and
// document the window loads, so a browser here runs the console exactly as
// it would against the relay, with the relay out of the loop. The window
// itself never uses this origin; it stays on the proton bridge.
//
// Local access needs no launch token or browser cookie. A bookmark or a new
// browser can open the same stable URL directly. The listener binds only to
// loopback; Host must name that bound address, and a present Origin must be
// our own. Together these keep unrelated web origins out, including a domain
// rebound to loopback. Release builds never open this port.

///|
/// The loopback HTTP+WebSocket listener owning the development console's
/// origin. Bound before the API state exists so the state can carry the
/// entry URL; served once the state does.
pub struct LocalConsole {
  server : @http.Server
  // How the roster names this machine.
  name : String
  priv account_origin : String
  priv sign_in : @browser_signin.Flow
}

///|
/// The roster id under which this host lists itself. Not `local`: the browser
/// bundle keeps that id for the window's own inert channel, and a relay id is
/// `d_…`, so this one collides with neither.
const LocalConsoleDevice = "host"

///|
/// The port this console is bound on. Private: consumers read the bound
/// address through `origin()`, the exported accessor.
fn LocalConsole::port(self : LocalConsole) -> Int32 {
  self.server.addr.port()
}

///|
/// One request, classified by route. Everything the console page fetches
/// from the relay's origin exists here too, answered for this one machine.
priv enum Route {
  Home
  AuthMe
  AccountLogin
  AccountCallback
  AccountLogout
  Devices
  // Compatibility routes for the shared console's account controls.
  Login
  Logout
  // The protocol WebSocket for device `host`.
  DeviceSocket
  ApplicationPage
  Static(String)
  Unknown
  MethodNotAllowed
}

///|
fn route(meth : @http.RequestMethod, path : String, entry~ : String) -> Route {
  let (route, _) = split_path_query(path)
  match (meth, route) {
    (Get, "/") => Home
    (Get, path) if @routes.is_application_path(path) => ApplicationPage
    (Get, "/v1/auth/me") => AuthMe
    (Get, "/v2/auth/login") => AccountLogin
    (Get, "/cb") => AccountCallback
    (Post, "/v2/auth/logout") => AccountLogout
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
  // Check the document as well as APIs: a foreign hostname resolving to
  // loopback must not load this frontend under its own origin.
  if !self.request_allowed(request) {
    respond_status(conn, 403, "Forbidden")
    return
  }
  match route {
    Home => {
      let (_, query) = split_path_query(request.path)
      respond_redirect(
        conn,
        "/device/\{LocalConsoleDevice}/chat" +
        (if query.is_empty() { "" } else { "?" + query }),
      )
    }
    // No account stands behind the local console, so it has no avatar; the
    // field is absent rather than empty.
    AuthMe => respond_json(conn, { "login": "local" })
    AccountLogin => {
      let (_, query) = split_path_query(request.path)
      let location = self.sign_in.begin(decoded_query_param(query, "return_to")) catch {
        error => {
          respond_account_page(conn, "\{error}", code=500, html=false)
          return
        }
      }
      respond_redirect(conn, location)
    }
    // The one-time state and PKCE verifier bind the callback to a login
    // started on this console.
    AccountCallback => {
      let (_, query) = split_path_query(request.path)
      match
        self.sign_in.finish(
          decoded_query_param(query, "state"),
          decoded_query_param(query, "code"),
          decoded_query_param(query, "error"),
        ) {
        Ok(html) => respond_account_page(conn, html, code=200, html=true)
        Err((code, message)) =>
          respond_account_page(conn, message, code~, html=false)
      }
    }
    AccountLogout => {
      guard request.headers.get("authorization") is Some(authorization) else {
        respond_status(conn, 401, "Unauthorized")
        return
      }
      let (response, body) = @http.post(
        self.account_origin + "/v2/auth/logout",
        "",
        headers={ "Authorization": authorization },
      ) catch {
        _ => {
          respond_status(conn, 502, "Bad Gateway")
          return
        }
      }
      respond_account_page(conn, body.text(), code=response.code, html=false)
    }
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
    // The local host has no account session to establish or clear. Returning
    // to a local page always restores access.
    Login => {
      let (_, query) = split_path_query(request.path)
      let destination = query_param(query, "return_to").map(value => {
        @uri.decode_component(value)
      })
      let fallback = "/device/\{LocalConsoleDevice}/chat"
      let target = if destination is Some(destination) {
        let (path, query) = split_path_query(destination)
        match @routes.parse(path) {
          Ok(location) if (
              location.device == Some(LocalConsoleDevice) ||
              location.target.is_cloud()
            ) &&
            location.path() is Some(path) =>
            path + (if query.is_empty() { "" } else { "?" + query })
          _ => fallback
        }
      } else {
        fallback
      }
      respond_redirect(conn, target)
    }
    Logout => respond_status(conn, 204, "No Content")
    Static(relative) =>
      serve_static(
        root,
        relative,
        conn,
        local_console_document=relative == entry,
      )
    ApplicationPage =>
      serve_static(root, entry, conn, local_console_document=true)
    Unknown => respond_status(conn, 404, "Not Found")
    MethodNotAllowed => respond_status(conn, 405, "Method Not Allowed")
  }
}

///|
/// Browsers must address this listener directly and use its origin. Local
/// debugging clients and document navigations may omit Origin.
fn LocalConsole::request_allowed(
  self : LocalConsole,
  request : @http.Request,
) -> Bool {
  guard request.headers.get("host") is Some(host) &&
    "http://" + host == self.origin() else {
    return false
  }
  if request.headers.get("origin") is Some(origin) {
    origin == self.origin()
  } else {
    true
  }
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
/// One bundled file, including the application document.
async fn serve_static(
  root : String,
  relative : String,
  conn : @http.ServerConnection,
  local_console_document~ : Bool = false,
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
  // The marker identifies this host independently of its current CSR route.
  // It carries no account credentials and does not change local access.
  let body = if local_console_document {
    let html = @utf8.decode_lossy(body, ignore_bom=true)
    @utf8.encode(
      html.replace_all(
        old="<head>",
        new="<head>\n<meta name=\"seekmoon-local-console\" />",
      ),
    )
  } else {
    body
  }
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": content_type(relative),
    "Content-Length": body.length().to_string(),
    // A development bundle changes in place between launches; make every
    // load revalidate rather than trust a stale browser cache.
    "Cache-Control": "no-cache",
    "Connection": "close",
  })
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
  // The route codec owns pathname validity. This HTTP boundary also protects
  // the query text retained in a login return address from header injection.
  guard !location.any(ch => ch.is_control()) else {
    respond_status(conn, 400, "Bad Request")
    return
  }
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
  code : Int32,
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
  let extension = match name.rev_split_once(".") {
    Some((_, extension)) => extension.to_owned()
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
  match path.split_once("?") {
    Some((path, query)) => (path.to_owned(), query.to_owned())
    None => (path, "")
  }
}

///|
/// A raw query parameter; the caller decodes its value when needed.
fn query_param(query : String, name : String) -> String? {
  for pair in query.split("&") {
    if pair.split_once("=") is Some((key, value)) && key == name {
      return Some(value.to_owned())
    }
  }
  None
}

///|
test "routes: the entry, the console's account routes, then the bundle" {
  assert_true(
    route(Get, "/?device=host&token=sesame", entry="index.html") is Home,
  )
  assert_true(route(Get, "/?token=sesame", entry="index.html") is Home)
  assert_true(route(Get, "/", entry="index.html") is Home)
  assert_true(route(Get, "/?device=host", entry="desktop-dev.html") is Home)
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

///|
test "stable application paths serve the application document" {
  for path in ["/cloud", "/cloud/session/s1"] {
    assert_true(route(Get, path, entry="index.html") is ApplicationPage)
  }
  assert_true(
    route(Get, "/device/host/chat/session/s1", entry="index.html")
    is ApplicationPage,
  )
  assert_true(
    route(Get, "/frontend.js", entry="index.html") is Static("frontend.js"),
  )
}

///|
fn decoded_query_param(query : String, name : String) -> String? {
  query_param(query, name).map(value => @uri.decode_component(value))
}

///|
async fn respond_account_page(
  conn : @http.ServerConnection,
  body : String,
  code~ : Int32,
  html~ : Bool,
) -> Unit {
  conn.send_response(code, "Account", extra_headers={
    "Content-Type": if html {
      "text/html; charset=utf-8"
    } else {
      "text/plain; charset=utf-8"
    },
    "Content-Length": @utf8.encode(body).length().to_string(),
    "Cache-Control": "no-store",
    "Connection": "close",
  })
  conn.write(body)
  conn.end_response()
}
