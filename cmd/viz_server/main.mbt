///|
/// Read-only web server for the events.jsonl visualizer. Serves the static
/// frontend bundle plus a tiny JSON/raw-file API over a `SessionStore`:
///
/// - `GET /`                                  → the viewer shell (web/index.html)
/// - `GET /viz_app.js`                        → the compiled frontend bundle
/// - `GET /api/sessions`                      → JSON listing across known roots
/// - `GET /api/sessions/<key>`                → `{found, events, header}` envelope
/// - `GET /api/sessions/<key>/events.jsonl`   → raw append-only event log
/// - `GET /api/sessions/<key>/session.json`   → raw header (404 when absent)
///
/// It never writes to the stores, so pointing it at live session roots is safe.
async fn main {
  let matches = cli_command().parse(env=@env.get_env_vars())
  let port = parse_port(value(matches, "port"))
  let host = value(matches, "host").trim().to_owned()
  if host.is_empty() {
    fail("--host or OPENSEEK_VIZ_HOST must not be empty")
  }
  let session_root = value(matches, "session-root").trim().to_owned()
  if session_root.is_empty() {
    fail("--session-root or OPENSEEK_SESSION_ROOT must not be empty")
  }
  let session_root_name = value(matches, "session-root-name").trim().to_owned()
  if session_root_name.is_empty() {
    fail(
      "--session-root-name or OPENSEEK_VIZ_SESSION_ROOT_NAME must not be empty",
    )
  }
  let search_dirs = non_empty_values(matches, "search-dir")
  let web_dir = value(matches, "web-dir")
  let bundle = value(matches, "bundle")
  let module_root = match @env.args() {
    [exe, ..] => module_root_from_exe(exe)
    [] => None
  }
  let shell = shell_candidates(web_dir, module_root)
  let bundle_paths = bundle_candidates(bundle, web_dir, module_root)
  let catalog = session_catalog(session_root, search_dirs, session_root_name)
  let addr = @socket.Addr::parse("\{host}:\{port}") catch {
    _ => fail("invalid --host/--port: \{host}:\{port}")
  }
  println("openseek viz: serving \{catalog.roots.length()} session root(s)")
  for root in catalog.roots {
    println("openseek viz: sessions under '\{root.path}'")
  }
  println("openseek viz: shell from '\{shell[0]}'")
  print_open_urls(host, port)
  let server = @http.Server(addr)
  server.run_forever((request, _body, conn) => {
    handle(request, conn, catalog, shell, bundle_paths)
  })
}

///|
/// Print the URL(s) for reaching the server. When bound to the wildcard
/// `0.0.0.0` (all interfaces), show both the loopback URL for this machine and
/// the discovered LAN URL a remote host can open; a specific bound host prints
/// just that one URL. The LAN line is best-effort — if no external address can
/// be found, say so rather than print a misleading URL.
async fn print_open_urls(host : String, port : Int) -> Unit {
  if host != "0.0.0.0" {
    println("openseek viz: open http://\{host}:\{port}")
    return
  }
  println("openseek viz: open http://127.0.0.1:\{port} (this machine)")
  match local_lan_ip() {
    Some(ip) =>
      println(
        "openseek viz: open http://\{ip}:\{port} (LAN, reachable from other machines)",
      )
    None =>
      println(
        "openseek viz: bound to all interfaces; open this machine's LAN IP from another host",
      )
  }
}

///|
/// Best-effort discovery of this machine's primary LAN IPv4 address, for
/// printing a URL a remote host can open. Opens a UDP socket "connected" to a
/// public address and reads back the local address the OS chose for that route.
/// No packet is sent — a UDP `connect` only fixes the default peer and triggers
/// source-address selection in the kernel routing table — so this works offline
/// as long as a route (e.g. a LAN default gateway) exists. Returns `None` when
/// there is no usable route, or the chosen address is loopback/unspecified and
/// thus not reachable from another host.
async fn local_lan_ip() -> String? {
  let probe = @socket.UdpClient(@socket.Addr::parse("8.8.8.8:53")) catch {
    _ => return None
  }
  let addr = probe.addr
  probe.close()
  // The probe forces an IPv4 route, so the local address is IPv4; bail on the
  // unexpected IPv6 case rather than mis-format it.
  if addr.is_ipv6() {
    return None
  }
  let ip = addr.ip()
  let a = (ip >> 24) & 255
  let b = (ip >> 16) & 255
  let c = (ip >> 8) & 255
  let d = ip & 255
  if a == 127 || ip == 0 {
    return None
  }
  Some("\{a}.\{b}.\{c}.\{d}")
}

///|
/// A fully-computed HTTP reply. Building it does no socket I/O, so the single
/// send in `handle` is the only place a response is written — there is no way to
/// start a second response (which would panic `send_response`).
struct Reply {
  code : Int
  reason : String
  content_type : String
  body : String
}

///|
/// Handle one request: compute the reply (catching any failure as a 500), then
/// send it exactly once. A failure during the send — e.g. the client closed the
/// connection mid-body — is swallowed: the response was already started, so
/// retrying would double-send. `run_forever` keeps serving other connections.
async fn handle(
  request : @http.Request,
  conn : @http.ServerConnection,
  catalog : SessionCatalog,
  shell : Array[String],
  bundle : Array[String],
) -> Unit {
  let reply = build_reply(request, catalog, shell, bundle) catch {
    error => text_reply(500, "Internal Server Error", "error: \{error}")
  }
  send_reply(conn, reply) catch {
    // The send already started, so a mid-body failure (client hung up) must not
    // trigger a second send_response. Swallow it; run_forever keeps serving.
    _ => ()
  }
}

///|
async fn send_reply(conn : @http.ServerConnection, reply : Reply) -> Unit {
  conn.send_response(reply.code, reply.reason, extra_headers={
    "Content-Type": reply.content_type,
  })
  conn.write_string(reply.body)
  conn.end_response()
}

///|
async fn build_reply(
  request : @http.Request,
  catalog : SessionCatalog,
  shell : Array[String],
  bundle : Array[String],
) -> Reply {
  guard request.meth is Get else {
    return text_reply(405, "Method Not Allowed", "only GET is supported")
  }
  let path = strip_query(request.path)
  match path {
    "/" | "/index.html" =>
      search_reply(
        shell, "text/html; charset=utf-8", "index.html not found; pass --web-dir or run from the openseek checkout",
      )
    "/viz_app.js" =>
      search_reply(
        bundle, "text/javascript; charset=utf-8", "viz_app.js not found; build it with: moon build",
      )
    "/api/sessions" => session_list_reply(catalog)
    _ =>
      match path.strip_prefix("/api/sessions/") {
        Some(rest) => session_path_reply(catalog, "\{rest}")
        None => text_reply(404, "Not Found", "no route for \{path}")
      }
  }
}

///|
/// Resolve `<key>` (envelope) or `<key>/<file>` (raw) after the
/// `/api/sessions/` route prefix. A key is either legacy `<id>` for the first
/// root, or `<root>|<id>` for a discovered root. The segment is percent-decoded, so ids containing
/// URL-reserved characters (spaces, `?`, `#`) still resolve to the right
/// session. The store's own id validation rejects path separators and `..`, so
/// a crafted id cannot escape the session directory.
async fn session_path_reply(catalog : SessionCatalog, rest : String) -> Reply {
  let (key, file) = match rest.split_once("/") {
    None => (percent_decode(rest), None)
    Some((key, file)) => (percent_decode("\{key}"), Some("\{file}"))
  }
  let (root, id_value) = match catalog.lookup(key) {
    Some(found) => found
    None => return text_reply(404, "Not Found", "session root not found")
  }
  // Validate the id ourselves so a malformed request is a 400, not a 500 from
  // the store's path-building assertion. These are the store's own id rules.
  guard valid_session_id(id_value) else {
    return text_reply(400, "Bad Request", "invalid session id")
  }
  let id = @agent_session.SessionId(id_value)
  match file {
    None => session_envelope_reply(root.store, id)
    Some("events.jsonl") =>
      asset_reply(
        root.store.event_log_file(id),
        "application/x-ndjson; charset=utf-8",
      )
    Some("session.json") =>
      asset_reply(root.store.header_file(id), "application/json; charset=utf-8")
    Some(other) =>
      text_reply(404, "Not Found", "no such session file: \{other}")
  }
}

///|
/// Mirror `SessionStore`'s id validation so a bad URL id is rejected as a client
/// error before any store path is built (which would otherwise raise → 500).
fn valid_session_id(value : String) -> Bool {
  value != "" &&
  !value.contains("/") &&
  !value.contains("\\") &&
  value != "." &&
  value != ".."
}

///|
/// Serve one session as a single JSON envelope:
/// `{ "found": Bool, "events": String, "header": Json|null }`.
///
/// The frontend's HTTP client (`rabbita/http`) resolves any completed response
/// as success regardless of status code, so absence and content must be encoded
/// in the body rather than signalled by 404. `events` is the raw `events.jsonl`
/// text; `header` is the parsed `session.json` or `null` when it is absent.
async fn session_envelope_reply(
  store : @store.SessionStore,
  id : @agent_session.SessionId,
) -> Reply {
  let events_path = store.event_log_file(id)
  let header_path = store.header_file(id)
  let events_exists = @fs.exists(events_path)
  let header_exists = @fs.exists(header_path)
  // A session with only a header (e.g. a crash between the first header write
  // and the empty-log write) is still loadable — `SessionStore::load` treats a
  // missing log as empty — and `listings()` can surface it, so treat either
  // file existing as found rather than reporting a listed session as missing.
  if !events_exists && !header_exists {
    return json_reply({ "found": false })
  }
  let events_text = if events_exists {
    read_text_lossy(events_path)
  } else {
    ""
  }
  let header : Json = if header_exists {
    @json.parse(read_text_lossy(header_path)) catch {
      _ => Json::null()
    }
  } else {
    Json::null()
  }
  json_reply({ "found": true, "events": events_text, "header": header })
}

///|
async fn session_list_reply(catalog : SessionCatalog) -> Reply {
  let rows : Array[SessionListRow] = []
  for root in catalog.roots {
    for listing in root.store.listings() {
      let id = listing.id().value()
      rows.push({
        key: session_key(root.key, id),
        id,
        root: root.path,
        root_label: root.label,
        is_marker: root.is_marker,
        last_active: listing.last_active_unix_seconds(),
        first_prompt: listing.first_prompt(),
      })
    }
  }
  rows.sort_by(compare_session_list_rows)
  json_reply(Array::map(rows, row => row.to_json()).to_json())
}

///|
priv struct SessionRoot {
  key : String
  path : String
  label : String
  // Whether this root is a discovered marker store (its directory is named like
  // the root marker, e.g. `.openseek`) rather than a direct store the user
  // pointed `--session-root` at. The sidebar uses this to decide whether the
  // path's last segment is a marker to strip when grouping by directory.
  is_marker : Bool
  store : @store.SessionStore
}

///|
priv struct SessionCatalog {
  roots : Array[SessionRoot]
}

///|
priv struct SessionListRow {
  key : String
  id : String
  root : String
  root_label : String
  is_marker : Bool
  last_active : Int64?
  first_prompt : String
}

///|
fn SessionListRow::to_json(self : SessionListRow) -> Json {
  let last_active : Json = match self.last_active {
    Some(seconds) => Json::number(seconds.to_double())
    None => Json::null()
  }
  {
    "key": self.key,
    "id": self.id,
    "root": self.root,
    "root_label": self.root_label,
    "is_marker": self.is_marker,
    "last_active": last_active,
    "first_prompt": self.first_prompt,
  }
}

///|
fn compare_session_list_rows(a : SessionListRow, b : SessionListRow) -> Int {
  match (a.last_active, b.last_active) {
    (Some(a_time), Some(b_time)) =>
      if a_time == b_time {
        compare_session_list_row_labels(a, b)
      } else if a_time > b_time {
        -1
      } else {
        1
      }
    (Some(_), None) => -1
    (None, Some(_)) => 1
    (None, None) => compare_session_list_row_labels(a, b)
  }
}

///|
fn compare_session_list_row_labels(
  a : SessionListRow,
  b : SessionListRow,
) -> Int {
  let root_order = a.root_label.compare(b.root_label)
  if root_order != 0 {
    root_order
  } else {
    a.id.compare(b.id)
  }
}

///|
async fn session_catalog(
  session_root : String,
  search_dirs : Array[String],
  session_root_name : String,
) -> SessionCatalog {
  let paths : Array[String] = []
  // Serve the explicit --session-root directly only when it is actually a store
  // (named like the root marker, or holding a `sessions/` directory). Otherwise
  // it is a container — e.g. a directory of best-of-N run workspaces, each with
  // its own nested store — and announcing it as a root would list zero sessions.
  if is_session_store(session_root, session_root_name) {
    paths.push(session_root)
  }
  // Scan the --session-root as well as the --search-dirs, so nested stores under
  // a container root are surfaced the same way search-dir trees are.
  let scan_dirs = [session_root]
  for dir in search_dirs {
    scan_dirs.push(dir)
  }
  for root in discover_session_roots(scan_dirs, session_root_name) {
    paths.push(root)
  }
  let unique = unique_paths(paths)
  let roots : Array[SessionRoot] = []
  for index, path in unique {
    roots.push({
      key: index.to_string(),
      path,
      label: root_label(path),
      is_marker: path_tail(path) == session_root_name,
      store: @store.SessionStore(path),
    })
  }
  { roots, }
}

///|
async fn discover_session_roots(
  search_dirs : Array[String],
  session_root_name : String,
) -> Array[String] {
  let roots : Array[String] = []
  for dir in search_dirs {
    scan_session_roots(dir, session_root_name, roots)
  }
  roots
}

///|
async fn scan_session_roots(
  dir : String,
  session_root_name : String,
  roots : Array[String],
) -> Unit {
  guard is_directory(dir) else { return }
  if path_tail(dir) == session_root_name {
    roots.push(dir)
    return
  }
  let direct = join_path(dir, session_root_name)
  if is_directory(direct) {
    roots.push(direct)
  }
  let names = @fs.readdir(dir, sort=true) catch { _ => return }
  for name in names {
    if should_skip_scan_dir(name, session_root_name) {
      continue
    }
    let child = join_path(dir, name)
    if is_directory(child) {
      scan_session_roots(child, session_root_name, roots)
    }
  }
}

///|
async fn is_directory(path : String) -> Bool {
  (@fs.kind(path, follow_symlink=false) catch { _ => return false }) ==
  Directory
}

///|
/// Whether `path` is itself a session store (servable directly) rather than a
/// container to scan: it is named like the root marker (e.g. `.openseek`), or it
/// already holds a `sessions/` directory.
async fn is_session_store(path : String, session_root_name : String) -> Bool {
  path_tail(path) == session_root_name ||
  is_directory(join_path(path, "sessions"))
}

///|
fn should_skip_scan_dir(name : String, session_root_name : String) -> Bool {
  name == session_root_name ||
  name == ".git" ||
  name == "node_modules" ||
  name == ".mooncakes" ||
  name == "_build"
}

///|
async fn unique_paths(paths : Array[String]) -> Array[String] {
  let seen : Array[String] = []
  let unique : Array[String] = []
  for path in paths {
    let key = @fs.realpath(path) catch { _ => path }
    if !seen.contains(key) {
      seen.push(key)
      unique.push(path)
    }
  }
  unique
}

///|
fn session_key(root_key : String, id : String) -> String {
  "\{root_key}|\{id}"
}

///|
fn SessionCatalog::lookup(
  self : SessionCatalog,
  key : String,
) -> (SessionRoot, String)? {
  match key.split_once("|") {
    Some((root_key, id)) => {
      let root_key = "\{root_key}"
      for root in self.roots {
        if root.key == root_key {
          return Some((root, "\{id}"))
        }
      }
      None
    }
    None =>
      match self.roots {
        [root, ..] => Some((root, key))
        [] => None
      }
  }
}

///|
fn root_label(path : String) -> String {
  let trimmed = trim_trailing_path_separators(path)
  if trimmed.is_empty() {
    path
  } else {
    trimmed
  }
}

///|
fn path_tail(path : String) -> String {
  let trimmed = trim_trailing_path_separators(path)
  match last_path_separator(trimmed) {
    Some(index) => slice_from(trimmed, index + 1)
    None => trimmed
  }
}

///|
fn last_path_separator(path : String) -> Int? {
  match (path.rev_find("/"), path.rev_find("\\")) {
    (Some(a), Some(b)) => Some(if a > b { a } else { b })
    (Some(a), None) => Some(a)
    (None, Some(b)) => Some(b)
    (None, None) => None
  }
}

///|
fn trim_trailing_path_separators(path : String) -> String {
  let mut result = path
  while result.length() > 1 &&
        (result.has_suffix("/") || result.has_suffix("\\")) {
    result = result[:result.length() - 1].to_owned()
  }
  result
}

///|
fn join_path(parent : String, child : String) -> String {
  if parent.is_empty() || parent.has_suffix("/") || parent.has_suffix("\\") {
    "\{parent}\{child}"
  } else {
    "\{parent}/\{child}"
  }
}

///|
/// The OpenSeek checkout root derived from this executable's own path, or
/// `None` for a binary living outside a moon build tree.
///
/// `moon run` keeps the invoking shell's working directory — which is how a
/// user serving another project's sessions (`moon run ../openseek/cmd/...`)
/// ends up with CWD-relative asset defaults pointing at the wrong tree. But
/// the binary itself always sits at
/// `<root>/_build/<target>/<profile>/build/cmd/viz_server/...`, so everything
/// before the `_build` component locates the checkout and its assets,
/// wherever the server was started from.
fn module_root_from_exe(exe : String) -> String? {
  match exe.split_once("/_build/") {
    Some((root, _)) => Some("\{root}")
    None =>
      if exe.strip_prefix("_build/") is Some(_) {
        Some(".")
      } else {
        None
      }
  }
}

///|
/// Where to look for the viewer shell, in order: the configured `--web-dir`
/// (CWD-relative by default, preserving in-checkout behavior), then the
/// checkout's own `web/` derived from the executable path, so running from
/// another project's directory needs no flags.
fn shell_candidates(web_dir : String, module_root : String?) -> Array[String] {
  let candidates = ["\{web_dir}/index.html"]
  if module_root is Some(root) {
    candidates.push("\{root}/web/index.html")
  }
  candidates
}

///|
/// Where to look for the compiled frontend bundle, in order: an explicit
/// `--bundle` path, `<web-dir>/viz_app.js`, moon's release and debug outputs
/// for the standalone frontend module, legacy in-module frontend build outputs,
/// then the same paths under the executable-derived checkout root. This lets
/// `moon build` followed by `moon run --target native cmd/viz_server` work
/// with no copy step — from any directory.
fn bundle_candidates(
  bundle : String,
  web_dir : String,
  module_root : String?,
) -> Array[String] {
  let candidates = [
    bundle,
    "\{web_dir}/viz_app.js",
    "_build/js/release/build/bobzhang/openseek-viz-app/openseek-viz-app.js",
    "_build/js/debug/build/bobzhang/openseek-viz-app/openseek-viz-app.js",
    "_build/js/release/build/cmd/viz_app/viz_app.js",
    "_build/js/debug/build/cmd/viz_app/viz_app.js",
  ]
  if module_root is Some(root) {
    candidates.push("\{root}/web/viz_app.js")
    candidates.push(
      "\{root}/_build/js/release/build/bobzhang/openseek-viz-app/openseek-viz-app.js",
    )
    candidates.push(
      "\{root}/_build/js/debug/build/bobzhang/openseek-viz-app/openseek-viz-app.js",
    )
    candidates.push("\{root}/_build/js/release/build/cmd/viz_app/viz_app.js")
    candidates.push("\{root}/_build/js/debug/build/cmd/viz_app/viz_app.js")
  }
  candidates
}

///|
/// Serve the first existing candidate file, or a 404 carrying `missing` so
/// the error names the fix rather than just the failure.
async fn search_reply(
  candidates : Array[String],
  content_type : String,
  missing : String,
) -> Reply {
  for candidate in candidates {
    if candidate != "" && @fs.exists(candidate) {
      return asset_reply(candidate, content_type)
    }
  }
  text_reply(404, "Not Found", missing)
}

///|
/// Read a file into a reply, or a 404 reply when it does not exist.
async fn asset_reply(path : String, content_type : String) -> Reply {
  if !@fs.exists(path) {
    return text_reply(404, "Not Found", "missing file: \{path}")
  }
  { code: 200, reason: "OK", content_type, body: read_text_lossy(path) }
}

///|
/// Read a file as text, decoding invalid UTF-8 lossily rather than raising. A
/// live `events.jsonl` can be torn mid-codepoint by a concurrent append; strict
/// decoding would 500 the whole fetch, hiding the valid prefix. Lossy decoding
/// keeps that prefix, and the torn final line then fails to parse client-side
/// and is reported as a benign truncated tail.
async fn read_text_lossy(path : String) -> String {
  @utf8.decode_lossy(@fs.read_file(path).binary())
}

///|
fn json_reply(body : Json) -> Reply {
  {
    code: 200,
    reason: "OK",
    content_type: "application/json; charset=utf-8",
    body: body.stringify(),
  }
}

///|
fn text_reply(code : Int, reason : String, message : String) -> Reply {
  { code, reason, content_type: "text/plain; charset=utf-8", body: message }
}

///|
/// The path without any `?query` suffix.
fn strip_query(path : String) -> String {
  match path.split_once("?") {
    Some((path, _)) => "\{path}"
    None => path
  }
}

///|
/// Code-unit slice `s[start:]` as an owned `String`.
fn slice_from(s : String, start : Int) -> String {
  s[start:].to_owned()
}

///|
/// Percent-decode a URL path segment (`%XX` → byte), assembling the decoded
/// bytes and interpreting them as UTF-8. Non-`%` characters pass through as
/// their own UTF-8 bytes. `+` is left as-is (it is literal in path segments).
/// A malformed `%` escape is left verbatim, and undecodable bytes fall back to
/// the original string.
fn percent_decode(s : String) -> String {
  let chars = s.to_array()
  let bytes : Array[Byte] = []
  for i = 0 {
    match chars[i:] {
      [] => break
      // A complete %XX escape needs two hex digits after the percent: the
      // view pattern checks the remaining length, the guard checks the
      // digits, and a truncated or malformed escape falls through to the
      // verbatim arm.
      ['%', high, low, ..] if hex_val(high) is Some(h) &&
        hex_val(low) is Some(l) => {
        bytes.push(((h * 16 + l) & 0xff).to_byte())
        continue i + 3
      }
      [c, ..] => {
        for byte in @utf8.encode(c.to_string()) {
          bytes.push(byte)
        }
        continue i + 1
      }
    }
  }
  @utf8.decode(Bytes::from_array(bytes)) catch {
    _ => s
  }
}

///|
fn hex_val(c : Char) -> Int? {
  match c {
    '0'..='9' => Some(c.to_int() - '0')
    'a'..='f' => Some(c.to_int() - 'a' + 10)
    'A'..='F' => Some(c.to_int() - 'A' + 10)
    _ => None
  }
}

///|
fn cli_command() -> @argparse.Command {
  Command(
    "openseek-viz",
    about="Read-only web server for the OpenSeek events.jsonl visualizer.",
    options=[
      OptionArg(
        "port",
        long="port",
        env="OPENSEEK_VIZ_PORT",
        default_values=["8080"],
        about="TCP port to listen on.",
      ),
      OptionArg(
        "host",
        long="host",
        env="OPENSEEK_VIZ_HOST",
        default_values=["0.0.0.0"],
        about="Interface address to bind. 0.0.0.0 (default) listens on all interfaces and is reachable from other machines; 127.0.0.1 restricts to this machine.",
      ),
      OptionArg(
        "session-root",
        long="session-root",
        env="OPENSEEK_SESSION_ROOT",
        default_values=[".openseek"],
        about="Compatibility session root to serve in addition to discovered roots.",
      ),
      OptionArg(
        "search-dir",
        long="search-dir",
        env="OPENSEEK_VIZ_SEARCH_DIR",
        action=Append,
        default_values=["."],
        about="Directory to scan recursively for session roots; repeat to scan several trees.",
      ),
      OptionArg(
        "session-root-name",
        long="session-root-name",
        env="OPENSEEK_VIZ_SESSION_ROOT_NAME",
        default_values=[".openseek"],
        about="Directory name treated as an OpenSeek session root during recursive scan.",
      ),
      OptionArg(
        "web-dir",
        long="web-dir",
        env="OPENSEEK_VIZ_WEB_DIR",
        default_values=["web"],
        about="Directory holding the index.html shell.",
      ),
      OptionArg(
        "bundle",
        long="bundle",
        env="OPENSEEK_VIZ_BUNDLE",
        default_values=[""],
        about="Path to the compiled viz_app.js; defaults to auto-locating the moon build output.",
      ),
    ],
  )
}

///|
fn value(matches : @argparse.Matches, name : String) -> String raise {
  match matches.values.get(name) {
    Some([value]) => value
    Some(values) if values.length() > 0 => values[0]
    _ => fail("missing parsed argument: \{name}")
  }
}

///|
fn non_empty_values(
  matches : @argparse.Matches,
  name : String,
) -> Array[String] {
  match matches.values.get(name) {
    Some(values) =>
      [
        for value in values if !value.trim().is_empty() => {
          value.trim().to_owned()
        }
      ]
    None => []
  }
}

///|
fn parse_port(text : String) -> Int raise {
  @string.parse_int(text) catch {
    _ => fail("--port or OPENSEEK_VIZ_PORT must be an integer, got: \{text}")
  }
}
