///|
/// Read-only web server for the session-file visualizer. Serves the static
/// frontend bundle plus a tiny JSON/raw-file API over discovered session
/// `.jsonl` files:
///
/// - `GET /`                                  → the viewer shell (web/index.html)
/// - `GET /viz_app.js`                        → the compiled frontend bundle
/// - `GET /api/sessions`                      → JSON listing across known roots
/// - `GET /api/sessions/<key>`                → `{found, events, events_bytes}` envelope
/// - `GET /api/sessions/<key>/openseek_session-<id>.jsonl` → raw session file (header line + events)
///
/// It never writes to the stores, so pointing it at live session roots is safe.
/// Session discovery is intentionally file-oriented: only
/// `openseek_session-*.jsonl` files are listed, so `.DS_Store`, lock files, and
/// malformed/husk directories do not show up as sessions.
async fn main {
  let matches = cli_command().parse(env=@env.get_env_vars())
  let port = parse_port(@cli.value(matches, "port"))
  let host = @cli.require_non_empty(
    matches, "host", "--host or OPENSEEK_VIZ_HOST must not be empty",
  )
  let session_root = @cli.require_non_empty(
    matches, "session-root", "--session-root or OPENSEEK_SESSION_ROOT must not be empty",
  )
  let session_root_name = @cli.require_non_empty(
    matches, "session-root-name", "--session-root-name or OPENSEEK_VIZ_SESSION_ROOT_NAME must not be empty",
  )
  // Keep main's fix (f26def11): an explicit --session-root drops the default
  // cwd scan. effective_search_dirs encodes that; do not revert to a bare
  // non_empty_values(matches, "search-dir").
  let search_dirs = effective_search_dirs(matches)
  let web_dir = @cli.value(matches, "web-dir")
  let bundle = @cli.value(matches, "bundle")
  let module_root = match @env.args() {
    [exe, ..] => module_root_from_exe(exe)
    [] => None
  }
  let shell = shell_candidates(web_dir, module_root)
  let bundle_paths = bundle_candidates(bundle, web_dir, module_root)
  let catalog = session_catalog(session_root, search_dirs, session_root_name)
  // Export mode: freeze the sessions the server would serve into one standalone
  // HTML and exit, rather than run_forever. The exported file is decoupled from
  // this server and from the current parser — it carries its own bundle + data.
  let export_path = @cli.value(matches, "export")
  if export_path != "" {
    let rows = catalog.rows()
    let html = build_export_html(rows, shell, bundle_paths)
    @fs.write_file(export_path, html, create_mode=CreateOrTruncate)
    println(
      "openseek viz: wrote standalone export '\{export_path}' (\{rows.length()} session(s), \{html.length()} chars)",
    )
    return
  }
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
let sessions_dir_name : String = "sessions"

///|
let session_file_prefix : String = "openseek_session-"

///|
let session_file_suffix : String = ".jsonl"

///|
fn session_file_name(id : String) -> String {
  "\{session_file_prefix}\{id}\{session_file_suffix}"
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
/// matching file, or an opaque key returned by `/api/sessions`. Both segments
/// are percent-decoded — ids containing URL-reserved characters (spaces, `?`,
/// `#`) must decode in both positions to resolve the right session. The
/// resolved path always comes from the catalog scan, never from the URL file
/// segment.
async fn session_path_reply(catalog : SessionCatalog, rest : String) -> Reply {
  let (key, file) = match rest.split_once("/") {
    None => (percent_decode(rest), None)
    Some((key, file)) =>
      (percent_decode("\{key}"), Some(percent_decode("\{file}")))
  }
  let row = match catalog.lookup(key) {
    Some(found) => found
    None => return text_reply(404, "Not Found", "session file not found")
  }
  guard valid_session_id(row.id) else {
    return text_reply(400, "Bad Request", "invalid session id")
  }
  match file {
    None => session_envelope_reply(row.path)
    Some(name) if name == session_file_name(row.id) =>
      asset_reply(row.path, "application/x-ndjson; charset=utf-8")
    Some(other) =>
      text_reply(404, "Not Found", "no such session file: \{other}")
  }
}

///|
/// Mirror the session-store id validation enough for URL handling. File scan
/// paths are catalog-derived, but a legacy bare-id URL still needs an id check.
fn valid_session_id(value : String) -> Bool {
  value != "" &&
  !value.contains("/") &&
  !value.contains("\\") &&
  !value.contains("\u{0}") &&
  value != "." &&
  value != ".."
}

///|
/// Serve one session as a single JSON envelope:
/// `{ "found": Bool, "events": String, "events_bytes": Number }`.
///
/// The frontend's HTTP client (`rabbita/http`) resolves any completed response
/// as success regardless of status code, so absence and content must be encoded
/// in the body rather than signalled by 404. `events` is the raw session-file
/// text — the header line followed by event lines — which the frontend parser
/// splits apart itself.
async fn session_envelope_reply(path : String) -> Reply {
  json_reply(session_envelope_body(path))
}

///|
/// The `{found, events, events_bytes}` payload for one session, factored out of
/// `session_envelope_reply` so the standalone exporter can bake the exact same
/// body the live server would return into the embedded data map.
async fn session_envelope_body(path : String) -> Json {
  if !@fs.exists(path) {
    return { "found": false }
  }
  {
    "found": true,
    "events": read_text_lossy(path),
    "events_bytes": Json::number(file_size(path).to_double()),
  }
}

///|
async fn session_list_reply(catalog : SessionCatalog) -> Reply {
  json_reply(session_list_json(catalog.rows()))
}

///|
/// The `/api/sessions` listing as JSON, shared by the live route and the
/// standalone exporter so both encode the sidebar rows identically.
fn session_list_json(rows : Array[SessionListRow]) -> Json {
  rows.map(row => row.to_json()).to_json()
}

///|
/// Assemble a single self-contained HTML file: the viewer shell with the
/// compiled frontend bundle inlined and every API response the server would
/// serve — the `/api/sessions` listing plus one envelope per session — baked
/// into a `window.__OPENSEEK_DATA__` map, keyed by request path. The frontend's
/// transport checks that map before hitting the network, so the exported file
/// renders every session offline, with no server and no dependence on the
/// current parser: the bundle that understands these logs ships alongside them.
async fn build_export_html(
  rows : Array[SessionListRow],
  shell : Array[String],
  bundle : Array[String],
) -> String {
  let shell_html = read_first_existing(
    shell, "index.html shell (build with `moon build` or pass --web-dir)",
  )
  let bundle_js = read_first_existing(
    bundle, "viz_app.js bundle (build with `moon build` or pass --bundle)",
  )
  // Bake the two live endpoints the frontend fetches: the sidebar listing and
  // one envelope per session, keyed exactly as the frontend requests them.
  let data : Map[String, Json] = Map([])
  data["/api/sessions"] = Json::string(session_list_json(rows).stringify())
  for row in rows {
    data["/api/sessions/\{row.key}"] = Json::string(
      session_envelope_body(row.path).stringify(),
    )
  }
  // Escape every `<` in the data to its JSON unicode escape so no `<!--`,
  // `<script`, or `</script` in session text can drive HTML's script-data
  // tokenizer out of the inline block — the `<!--`+`<script` double-escape trap
  // would otherwise swallow the following bundle and blank the page. The escape
  // decodes back to `<` in the JS/JSON parser, so the data round-trips unchanged.
  let blob = escape_json_for_html(data.to_json().stringify())
  let bundle_inline = escape_script_close(bundle_js)
  let scripts = "<script>window.__OPENSEEK_DATA__ = \{blob};</script>\n<script>\n\{bundle_inline}\n</script>"
  let marker = "<script src=\"/viz_app.js\"></script>"
  match shell_html.split_once(marker) {
    Some((before, after)) => "\{before}\{scripts}\{after}"
    None =>
      fail(
        "index.html shell is missing the \{marker} tag; cannot inline the bundle",
      )
  }
}

///|
/// Read the first existing candidate as text, or fail naming what was missing.
async fn read_first_existing(
  candidates : Array[String],
  what : String,
) -> String {
  for candidate in candidates {
    if candidate != "" && @fs.exists(candidate) {
      return read_text_lossy(candidate)
    }
  }
  fail("could not locate \{what}")
}

///|
/// Rewrite every `<` in a stringified JSON payload to its `<` escape, so an
/// inline `<script>…</script>` data block carrying it cannot be pushed out of
/// HTML's script-data state. Every state transition there begins with `<`, so
/// escaping `<` alone defeats `<!--`, `<script`, and `</script` (including the
/// `<!--`+`<script` double-escape trap). The escape decodes back to `<` in the
/// JS/JSON parser, so the embedded data is unchanged. A `<` only ever appears
/// inside a string value here (keys and structure have none), so this is safe.
fn escape_json_for_html(json : String) -> String {
  let builder = StringBuilder()
  for c in json {
    if c == '<' {
      builder <+ "\\u003c"
    } else {
      builder.write_char(c)
    }
  }
  builder.to_string()
}

///|
/// Neutralise any literal `</script` in inlined JavaScript so it cannot close
/// the enclosing `<script>` block early. The match is case-insensitive because
/// an HTML parser closes the tag on `</script` in any letter case; a backslash
/// after `<` yields `<\/script`, the same token to a JS parser (a backslash
/// before `/` is a no-op outside a regex/string, and legal inside both), so the
/// bundle's behaviour is unchanged.
fn escape_script_close(js : String) -> String {
  let chars = js.to_array()
  let builder = StringBuilder()
  let n = chars.length()
  let mut i = 0
  while i < n {
    if chars[i] == '<' && is_script_close_tail(chars, i + 1) {
      builder <+ "<\\/"
      i += 2
    } else {
      builder.write_char(chars[i])
      i += 1
    }
  }
  builder.to_string()
}

///|
/// Whether `chars[at..]` begins with `/script` case-insensitively — the tail of
/// a `</script` close tag once the leading `<` has matched. HTML matches the tag
/// name in any case, so `</SCRIPT` and `</Script` must be caught too.
fn is_script_close_tail(chars : Array[Char], at : Int) -> Bool {
  let tail = ['/', 's', 'c', 'r', 'i', 'p', 't']
  guard at + tail.length() <= chars.length() else { return false }
  for k in 0..<tail.length() {
    let actual = chars[at + k]
    let want = tail[k]
    // Uppercase of an ASCII letter is its lowercase minus 32; `/` has no case.
    let matches = actual == want ||
      (want >= 'a' && want <= 'z' && actual.to_int() == want.to_int() - 32)
    if !matches {
      return false
    }
  }
  true
}

///|
priv struct SessionRoot {
  path : String
  scan_path : String
  label : String
  recursive : Bool
  // Whether this root is a discovered marker store (its directory is named like
  // the root marker, e.g. `.openseek`) rather than a direct directory/file of
  // copied JSONL logs. The sidebar uses this to decide whether the path's last
  // segment is a marker to strip when grouping by directory.
  is_marker : Bool
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
  path : String
  last_active : Int64?
  last_active_nanoseconds : Int
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
        if a.last_active_nanoseconds == b.last_active_nanoseconds {
          compare_session_list_row_labels(a, b)
        } else if a.last_active_nanoseconds > b.last_active_nanoseconds {
          -1
        } else {
          1
        }
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
  let roots : Array[SessionRoot] = []
  // Serve the explicit --session-root directly when it is a store, a directory
  // of copied `openseek_session-*.jsonl` files, or a single matching file.
  for root in session_root_sources(session_root, session_root_name) {
    roots.push(root)
  }
  // Scan the --session-root only when it is a container, so nested stores under
  // a container root and standalone copied-log directories are surfaced the same
  // way search-dir trees are. A direct store root is already served above; do
  // not recurse into its `sessions/<id>` directories as copied-log roots.
  let scan_dirs = if is_session_store(session_root, session_root_name) {
    search_dirs
  } else {
    [session_root, ..search_dirs]
  }
  for root in discover_session_roots(scan_dirs, session_root_name) {
    roots.push(root)
  }
  let roots = unique_roots(roots)
  { roots, }
}

///|
async fn discover_session_roots(
  search_dirs : Array[String],
  session_root_name : String,
) -> Array[SessionRoot] {
  let roots : Array[SessionRoot] = []
  for dir in search_dirs {
    scan_session_roots(dir, session_root_name, roots)
  }
  roots
}

///|
async fn scan_session_roots(
  dir : String,
  session_root_name : String,
  roots : Array[SessionRoot],
) -> Unit {
  guard is_directory(dir) else {
    if is_session_jsonl_file(dir) {
      roots.push(jsonl_collection_root(dir))
    }
    return
  }
  if path_tail(dir) == session_root_name {
    if contains_direct_session_file(dir) {
      roots.push(jsonl_collection_root(dir))
    }
    roots.push(store_root(dir, session_root_name))
    return
  }
  let direct = join_path(dir, session_root_name)
  if is_directory(direct) {
    roots.push(store_root(direct, session_root_name))
  }
  if contains_direct_session_file(dir) {
    roots.push(jsonl_collection_root(dir))
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
async fn is_regular_file(path : String) -> Bool {
  (@fs.kind(path, follow_symlink=false) catch { _ => return false }) == Regular
}

///|
/// Whether `path` is itself a session store (servable directly) rather than a
/// container to scan: it is named like the root marker (e.g. `.openseek`), or it
/// already holds a `sessions/` directory.
async fn is_session_store(path : String, session_root_name : String) -> Bool {
  path_tail(path) == session_root_name ||
  is_directory(join_path(path, sessions_dir_name))
}

///|
async fn session_root_sources(
  path : String,
  session_root_name : String,
) -> Array[SessionRoot] {
  let roots : Array[SessionRoot] = []
  if is_session_jsonl_source(path) {
    roots.push(jsonl_collection_root(path))
  }
  if is_session_store(path, session_root_name) {
    roots.push(store_root(path, session_root_name))
  }
  roots
}

///|
fn store_root(path : String, session_root_name : String) -> SessionRoot {
  {
    path,
    scan_path: join_path(path, sessions_dir_name),
    label: root_label(path),
    recursive: true,
    is_marker: path_tail(path) == session_root_name,
  }
}

///|
fn jsonl_collection_root(path : String) -> SessionRoot {
  {
    path,
    scan_path: path,
    label: root_label(path),
    recursive: false,
    is_marker: false,
  }
}

///|
async fn is_session_jsonl_source(path : String) -> Bool {
  is_session_jsonl_file(path) || contains_direct_session_file(path)
}

///|
async fn is_session_jsonl_file(path : String) -> Bool {
  is_regular_file(path) && session_id_from_file_name(path_tail(path)) is Some(_)
}

///|
async fn contains_direct_session_file(dir : String) -> Bool {
  guard is_directory(dir) else { return false }
  let names = @fs.readdir(dir, sort=true) catch { _ => return false }
  for name in names {
    let child = join_path(dir, name)
    if session_id_from_file_name(name) is Some(_) && is_regular_file(child) {
      return true
    }
  }
  false
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
fn should_skip_session_file_scan_dir(name : String) -> Bool {
  name == ".git" ||
  name == "node_modules" ||
  name == ".mooncakes" ||
  name == "_build"
}

///|
let first_prompt_scan_limit : Int = 50

///|
async fn unique_roots(roots : Array[SessionRoot]) -> Array[SessionRoot] {
  let seen : Array[String] = []
  let unique : Array[SessionRoot] = []
  for root in roots {
    let key = @fs.realpath(root.scan_path) catch { _ => root.scan_path }
    if !seen.contains(key) {
      seen.push(key)
      unique.push(root)
    }
  }
  unique
}

///|
async fn first_prompt_in_log(path : String) -> String {
  let file = @fs.open(path, mode=ReadOnly) catch { _ => return "" }
  defer file.close()
  let _ = file.read_until("\n") catch { _ => return "" }
  for _ in 0..<first_prompt_scan_limit {
    let next = file.read_until("\n") catch { _ => return "" }
    guard next is Some(line) else { break }
    if line.trim().is_empty() {
      continue
    }
    let event : @agent_session.SessionEvent = @json.from_json(@json.parse(line)) catch {
      _ => return ""
    }
    if event.item() is User(message) {
      return message.content()
    }
  }
  ""
}

///|
async fn SessionCatalog::rows(self : SessionCatalog) -> Array[SessionListRow] {
  let rows : Array[SessionListRow] = []
  for root in self.roots {
    for path in session_files_under(root.scan_path, root.recursive) {
      match session_id_from_file_name(path_tail(path)) {
        Some(id) => {
          let (last_active, last_active_nanoseconds) = session_file_stamp(path)
          rows.push({
            key: stable_session_key(path),
            id,
            root: root.path,
            root_label: root.label,
            is_marker: root.is_marker,
            path,
            last_active,
            last_active_nanoseconds,
            first_prompt: first_prompt_in_log(path),
          })
        }
        None => ()
      }
    }
  }
  rows.sort_by(compare_session_list_rows)
  rows
}

///|
async fn session_files_under(path : String, recursive : Bool) -> Array[String] {
  let files : Array[String] = []
  collect_session_files(path, files, recursive)
  files.sort()
  files
}

///|
async fn collect_session_files(
  path : String,
  files : Array[String],
  recursive : Bool,
) -> Unit {
  let kind = @fs.kind(path, follow_symlink=false) catch { _ => return }
  match kind {
    Regular =>
      if session_id_from_file_name(path_tail(path)) is Some(_) {
        files.push(path)
      }
    Directory => {
      let names = @fs.readdir(path, sort=true) catch { _ => return }
      for name in names {
        if should_skip_session_file_scan_dir(name) {
          continue
        }
        let child = join_path(path, name)
        let child_kind = @fs.kind(child, follow_symlink=false) catch {
          _ => continue
        }
        match child_kind {
          Regular =>
            if session_id_from_file_name(name) is Some(_) {
              files.push(child)
            }
          Directory =>
            if recursive {
              collect_session_files(child, files, recursive)
            }
          _ => ()
        }
      }
    }
    _ => ()
  }
}

///|
fn stable_session_key(path : String) -> String {
  let builder = StringBuilder()
  builder <+ "file-"
  for byte in @utf8.encode(path) {
    let value = byte.to_int()
    if value < 16 {
      builder <+ "0"
    }
    builder <+ "\{value.to_string(radix=16)}"
  }
  builder.to_string()
}

///|
fn session_id_from_file_name(name : String) -> String? {
  guard name.has_prefix(session_file_prefix) &&
    name.has_suffix(session_file_suffix) else {
    return None
  }
  let id = name[session_file_prefix.length():name.length() -
  session_file_suffix.length()].to_owned()
  if valid_session_id(id) {
    Some(id)
  } else {
    None
  }
}

///|
async fn session_file_stamp(path : String) -> (Int64?, Int) {
  let stamp = @fs.mtime(path) catch { _ => return (None, 0) }
  let (seconds, nanoseconds) = stamp
  (Some(seconds), nanoseconds)
}

///|
async fn SessionCatalog::lookup(
  self : SessionCatalog,
  key : String,
) -> SessionListRow? {
  let rows = self.rows()
  for row in rows {
    if row.key == key {
      return Some(row)
    }
  }
  for row in rows {
    if row.id == key {
      return Some(row)
    }
  }
  None
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
    Some(index) => trimmed[index + 1:].to_owned()
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
/// live session file can be torn mid-codepoint by a concurrent append; strict
/// decoding would 500 the whole fetch, hiding the valid prefix. Lossy decoding
/// keeps that prefix, and the torn final line then fails to parse client-side
/// and is reported as a benign truncated tail.
async fn read_text_lossy(path : String) -> String {
  @utf8.decode_lossy(@fs.read_file(path).binary())
}

///|
async fn file_size(path : String) -> Int64 {
  let file = @fs.open(path, mode=ReadOnly) catch { _ => return 0L }
  defer file.close()
  file.size() catch {
    _ => 0L
  }
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
    about="Read-only web server for the OpenSeek session visualizer.",
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
        about="Directory to scan recursively for session roots; repeat to scan several trees. The default '.' scan is skipped when --session-root is given explicitly.",
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
      OptionArg(
        "export",
        long="export",
        env="OPENSEEK_VIZ_EXPORT",
        default_values=[""],
        about="Write a self-contained standalone HTML (all discovered sessions embedded, no server needed) to this path and exit, instead of serving.",
      ),
    ],
  )
}

///|
/// The directories to scan recursively for session roots. An explicit
/// `--session-root` (flag or env) narrows serving to that root, so the
/// default `.` scan is dropped — pointing the server at another project's
/// sessions must not also pull in whatever tree it was started from. An
/// explicit `--search-dir` always wins: giving both flags means "that root,
/// plus these scans".
fn effective_search_dirs(matches : @argparse.Matches) -> Array[String] {
  if explicitly_provided(matches, "session-root") &&
    !explicitly_provided(matches, "search-dir") {
    []
  } else {
    non_empty_values(matches, "search-dir")
  }
}

///|
/// Whether the user supplied `name` on the command line or via its
/// environment variable, rather than the built-in default filling it in.
fn explicitly_provided(matches : @argparse.Matches, name : String) -> Bool {
  matches.sources.get(name) is (Some(Argv) | Some(Env))
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
