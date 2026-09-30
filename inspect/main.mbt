///|
/// Read-only web server for the session-file visualizer. Serves the static
/// frontend bundle plus a tiny JSON/raw-file API over discovered session
/// `.jsonl` files:
///
/// - `GET /`                                  → the viewer shell (web/index.html)
/// - `GET /viz_app.js`                        → the compiled frontend bundle
/// - `GET /api/sessions`                      → JSON listing across known roots
/// - `GET /api/sessions/<key>`                → `{found, events, events_bytes}` envelope
///   (`?known_bytes=N` answers `{found, unchanged, events_bytes}` while the log
///   is still N bytes, so a `--watch` viewer can poll cheaply)
/// - `GET /api/sessions/<key>/openseek_session-<id>.jsonl` → raw session file (header line + events)
/// - `GET /api/info`                          → `{server, version, identity}`, so a
///   second `inspect` can tell whether a busy port already serves its sessions
///
/// The shell and bundle come from disk when running from a checkout (or when
/// `--web-dir`/`--bundle` name them), and otherwise from the copies built into a
/// published binary (`generated_assets.mbt`), so `moonx moonbitlang/inspect`
/// needs no files beside it.
///
/// It never writes to the stores, so pointing it at live session roots is safe.
/// Session discovery is intentionally file-oriented: only
/// `openseek_session-*.jsonl` files are listed, so `.DS_Store`, lock files, and
/// malformed/husk directories do not show up as sessions.
priv struct VizConfig {
  port : Int
  host : String
  session_root : String
  session_root_name : String
  search_dirs : Array[String]
  web_dir : String
  // Whether `--web-dir` (or its env) was given, rather than the `web` default.
  // Only an explicit directory is searched when running outside a checkout.
  web_dir_explicit : Bool
  bundle : String
  export_path : String
  export_session : String
  // `--watch`: the served viewer re-checks the open session and the list.
  watch : Bool
  // `--ensure`: find or start the one loopback, token-protected server for
  // these sessions (see ensure.mbt).
  ensure : Bool
  // Whether `--port` (or its env) was given; `--ensure` otherwise derives one.
  port_explicit : Bool
  // Exit after this many minutes without a request; 0 never exits.
  idle_minutes : Int
}

///|
fn viz_config_from_matches(matches : @argparse.Matches) -> VizConfig raise {
  let (
    port,
    host,
    session_root,
    session_root_name,
    web_dir,
    bundle,
    export_path,
    export_session,
    idle_exit,
  ) = match matches {
    {
      values: {
        "port": [port, ..],
        "host": [host, ..],
        "session-root": [session_root, ..],
        "session-root-name": [session_root_name, ..],
        "web-dir": [web_dir, ..],
        "bundle": [bundle, ..],
        "export": [export_path, ..],
        "export-session": [export_session, ..],
        "idle-exit": [idle_exit, ..],
        ..
      },
      ..
    } =>
      (
        port, host, session_root, session_root_name, web_dir, bundle, export_path,
        export_session, idle_exit,
      )
    _ => fail("missing parsed visualizer defaults")
  }
  guard export_session.is_blank() || !export_path.is_blank() else {
    fail("--export-session requires --export")
  }
  let ensure = matches.flags.get("ensure") is Some(true)
  let host = host.trim()
  guard !host.is_empty() else {
    fail("--host or OPENSEEK_VIZ_HOST must not be empty")
  }
  let session_root = session_root.trim()
  guard !session_root.is_empty() else {
    fail("--session-root must not be empty")
  }
  let session_root_name = session_root_name.trim()
  guard !session_root_name.is_empty() else {
    fail(
      "--session-root-name or OPENSEEK_VIZ_SESSION_ROOT_NAME must not be empty",
    )
  }
  {
    port: parse_port(port),
    host: "\{host}",
    session_root: "\{session_root}",
    session_root_name: "\{session_root_name}",
    search_dirs: effective_search_dirs(matches),
    web_dir,
    web_dir_explicit: !(matches.sources.get("web-dir") is (Some(Default) | None)),
    bundle,
    export_path,
    export_session: export_session.trim().to_owned(),
    watch: matches.flags.get("watch") is Some(true),
    ensure,
    port_explicit: !(matches.sources.get("port") is (Some(Default) | None)),
    idle_minutes: match idle_exit.trim() {
      // Unset: an `--ensure` server is a shared background helper, so it goes
      // away on its own; a server someone started by hand runs until stopped.
      "" => if ensure { 60 } else { 0 }
      text =>
        @string.parse_int(text) catch {
          _ =>
            fail("--idle-exit must be a whole number of minutes, got: \{text}")
        }
    },
  }
}

///|
async fn main {
  let matches = cli_command().parse(env=@env.get_env_vars())
  let config = viz_config_from_matches(matches)
  // Keep main's fix (f26def11): an explicit --session-root drops the default
  // cwd scan. effective_search_dirs encodes that; do not revert to a bare
  // non_empty_values(matches, "search-dir").
  let module_root = match @env.args() {
    [exe, ..] => module_root_from_exe(exe)
    [] => None
  }
  let shell = shell_candidates(
    config.web_dir,
    module_root,
    web_dir_explicit=config.web_dir_explicit,
  )
  let bundle_paths = bundle_candidates(
    config.bundle,
    config.web_dir,
    module_root,
    web_dir_explicit=config.web_dir_explicit,
  )
  // `--ensure` keys everything on the session root's real path and keeps its
  // record there, so the root must exist before either is computed; a missing
  // relative `.openseek` would otherwise hash the same in every project.
  if config.ensure {
    @fs.mkdir(config.session_root, recursive=true, allow_exist=true)
  }
  let catalog = session_catalog(
    config.session_root,
    config.search_dirs,
    config.session_root_name,
  )
  // Export mode: freeze the sessions the server would serve into one standalone
  // HTML and exit, rather than run_forever. The exported file is decoupled from
  // this server and from the current parser — it carries its own bundle + data.
  if config.export_path != "" {
    let rows = catalog.rows()
    // --export-session scopes the freeze to one parent and its subagent
    // children — one run, one tidy file — instead of every session the
    // scan found.
    let rows = if config.export_session == "" {
      rows
    } else {
      let scoped = rows.filter(row => {
        in_export_scope(row.id, config.export_session)
      })
      guard scoped.any(row => row.id == config.export_session) else {
        fail(
          "openseek viz: no session '\{config.export_session}' in the scanned roots",
        )
      }
      scoped
    }
    let bundle = resolve_bundle(bundle_paths)
    guard bundle.text() is Some(bundle_js) else {
      fail(
        "could not locate the viz_app.js bundle (build with `moon build cmd/viz_app --target js` or pass --bundle)",
      )
    }
    guard resolve_shell(shell).text() is Some(shell_html) else {
      fail("could not locate index.html shell (pass --web-dir)")
    }
    let html = build_export_html(rows, shell_html, bundle_js)
    @fs.write_file(config.export_path, html, create_mode=CreateOrTruncate)
    // Name the embedded bundle: a stale artifact silently shadowing a
    // fresh build is invisible in the output file, but not in this line.
    println(
      "openseek viz: wrote standalone export '\{config.export_path}' (\{rows.length()} session(s), \{html.length()} chars; bundle: \{bundle.describe()})",
    )
    return
  }
  let identity = server_identity(config.session_root, config.search_dirs)
  let assets : ViewerAssets = {
    shell,
    bundle: bundle_paths,
    watch: config.watch,
    identity,
  }
  if config.ensure {
    ensure_main(config, catalog, assets)
    return
  }
  let addr = @socket.Addr::parse("\{config.host}:\{config.port}") catch {
    _ => fail("invalid --host/--port: \{config.host}:\{config.port}")
  }
  let server = @http.Server(addr, reuse_addr=true) catch {
    @os_error.OSError(_) as error => {
      // The port is taken. If an `inspect` for these same sessions holds it,
      // point at that one rather than fail: starting a second is never wanted.
      let probe_host = if config.host == "0.0.0.0" {
        "127.0.0.1"
      } else {
        config.host
      }
      if probe_inspect(probe_host, config.port, identity) {
        println(
          "openseek viz: already serving these sessions at http://\{probe_host}:\{config.port}",
        )
        return
      }
      raise error
    }
    error => raise error
  }
  print_serving(catalog, assets)
  print_open_urls(config.host, config.port)
  serve(server, catalog, assets, idle_ms=idle_ms(config.idle_minutes))
}

///|
/// `--ensure`: reuse the server already serving these sessions, or become it.
/// Either way the last startup line is `openseek viz: open <url>`, which is
/// what a caller such as the TUI reads.
async fn ensure_main(
  config : VizConfig,
  catalog : SessionCatalog,
  assets : ViewerAssets,
) -> Unit {
  let ports = if config.port_explicit {
    [config.port]
  } else {
    ensure_ports(assets.identity)
  }
  match ensure_server(config.session_root, assets.identity, ports) {
    Reused(port, token) =>
      println("openseek viz: open \{ensure_url(port, token)} (already running)")
    Started(server, port, token) => {
      print_serving(catalog, assets)
      if config.idle_minutes > 0 {
        println(
          "openseek viz: exits after \{config.idle_minutes} idle minute(s)",
        )
      }
      println("openseek viz: open \{ensure_url(port, token)}")
      serve(
        server,
        catalog,
        assets,
        access={ token, port, },
        idle_ms=idle_ms(config.idle_minutes),
        watch_root=config.session_root,
        on_exit=() => remove_own_record(config.session_root, port, token),
      )
    }
  }
}

///|
async fn print_serving(catalog : SessionCatalog, assets : ViewerAssets) -> Unit {
  println("openseek viz: serving \{catalog.roots.length()} session root(s)")
  for root in catalog.roots {
    println("openseek viz: sessions under '\{root.path}'")
  }
  println("openseek viz: shell from \{resolve_shell(assets.shell).describe()}")
  println(
    "openseek viz: bundle from \{resolve_bundle(assets.bundle).describe()}",
  )
  if assets.watch {
    println(
      "openseek viz: --watch: open sessions refresh every \{watch_interval_ms}ms",
    )
  }
}

///|
/// `--idle-exit` minutes in milliseconds; 0 stays 0 ("never").
fn idle_ms(minutes : Int) -> Int64 {
  minutes.to_int64() * 60_000L
}

///|
/// Serve until stopped; or, with a positive `idle_ms`, until that long passes
/// with no request (a watching browser tab counts, since it asks every
/// second); or, with `watch_root`, until that directory is deleted, so a
/// server started for a temporary session root does not outlive it. Then
/// `on_exit` runs and the server shuts down.
async fn serve(
  server : @http.Server,
  catalog : SessionCatalog,
  assets : ViewerAssets,
  access? : Guard,
  idle_ms~ : Int64,
  watch_root? : String,
  root_check_ms? : Int = 10_000,
  on_exit? : async () -> Unit = () => (),
) -> Unit {
  let last_request = Ref(@async.now())
  @async.with_task_group(group => {
    if idle_ms > 0L || watch_root is Some(_) {
      group.spawn_bg(no_wait=true) <| () => {
        let mut check_every = 30_000
        if idle_ms > 0L && idle_ms < check_every.to_int64() {
          check_every = idle_ms.to_int()
        }
        if watch_root is Some(_) && root_check_ms < check_every {
          check_every = root_check_ms
        }
        while true {
          @async.sleep(check_every)
          let reason = match watch_root {
            Some(root) if !(@fs.exists(root) catch { _ => true }) =>
              Some("session root '\{root}' is gone")
            _ =>
              if idle_ms > 0L && @async.now() - last_request.val >= idle_ms {
                Some("idle for \{idle_ms / 60_000L} minute(s)")
              } else {
                None
              }
          }
          if reason is Some(why) {
            println("openseek viz: \{why}; exiting")
            on_exit()
            group.return_immediately(())
          }
        }
      }
    }
    server.run_forever((request, _body, conn) => {
      last_request.val = @async.now()
      handle(request, conn, catalog, assets, access?)
    })
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
/// Where the viewer's own files come from, plus whether to serve it in watch
/// mode. Candidates are resolved per request, so a frontend rebuilt while the
/// server runs is picked up on reload.
priv struct ViewerAssets {
  shell : Array[String]
  bundle : Array[String]
  watch : Bool
  // What this server serves (`server_identity`), for `/api/info`.
  identity : String
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
  assets : ViewerAssets,
  access? : Guard,
) -> Unit {
  // An `--ensure` server answers only its own loopback name and its token;
  // `/api/info` stays open so another `inspect` can recognise it.
  let path = strip_query(request.path)
  let (reply, set_cookie) = match access {
    Some(access) if path != "/api/info" =>
      if !access.host_allowed(request.headers) {
        (text_reply(403, "Forbidden", "unexpected Host header"), None)
      } else if !access.authorized(request.path, request.headers) {
        (
          text_reply(
            403, "Forbidden", "missing or wrong token: open the URL `inspect --ensure` printed",
          ),
          None,
        )
      } else {
        // Opening the printed `?t=` URL leaves the token in a cookie, so the
        // page's own requests for the bundle and the session API get through.
        let cookie = if query_param(request.path, "t") is Some(_) {
          Some(access.cookie())
        } else {
          None
        }
        (build_reply_or_500(request, catalog, assets), cookie)
      }
    _ => (build_reply_or_500(request, catalog, assets), None)
  }
  send_reply(conn, reply, set_cookie?) catch {
    // The send already started, so a mid-body failure (client hung up) must not
    // trigger a second send_response. Swallow it; run_forever keeps serving.
    _ => ()
  }
}

///|
async fn build_reply_or_500(
  request : @http.Request,
  catalog : SessionCatalog,
  assets : ViewerAssets,
) -> Reply {
  build_reply(request, catalog, assets) catch {
    error => text_reply(500, "Internal Server Error", "error: \{error}")
  }
}

///|
async fn send_reply(
  conn : @http.ServerConnection,
  reply : Reply,
  set_cookie? : String,
) -> Unit {
  let headers : Map[@http.CaseInsensitiveString, String] = {
    "Content-Type": reply.content_type,
  }
  if set_cookie is Some(cookie) {
    headers.set(@http.CaseInsensitiveString("Set-Cookie"), cookie)
  }
  conn.send_response(reply.code, reply.reason, extra_headers=headers)
  conn.write_string(reply.body)
  conn.end_response()
}

///|
async fn build_reply(
  request : @http.Request,
  catalog : SessionCatalog,
  assets : ViewerAssets,
) -> Reply {
  guard request.meth is Get else {
    return text_reply(405, "Method Not Allowed", "only GET is supported")
  }
  let path = strip_query(request.path)
  match path {
    "/" | "/index.html" =>
      match resolve_shell(assets.shell).text() {
        Some(html) =>
          {
            code: 200,
            reason: "OK",
            content_type: "text/html; charset=utf-8",
            body: if assets.watch {
              shell_with_watch(html, watch_interval_ms)
            } else {
              html
            },
          }
        None =>
          text_reply(
            404, "Not Found", "index.html not found; pass --web-dir or run from the openseek checkout",
          )
      }
    "/viz_app.js" =>
      match resolve_bundle(assets.bundle).text() {
        Some(js) =>
          {
            code: 200,
            reason: "OK",
            content_type: "text/javascript; charset=utf-8",
            body: js,
          }
        None =>
          text_reply(
            404, "Not Found", "viz_app.js not found; build it with: moon build",
          )
      }
    "/api/sessions" => session_list_reply(catalog)
    "/api/info" => info_reply(assets.identity)
    _ =>
      match path.strip_prefix("/api/sessions/") {
        Some(rest) =>
          session_path_reply(
            catalog,
            "\{rest}",
            known_bytes?=known_bytes_param(request.path),
          )
        None => text_reply(404, "Not Found", "no route for \{path}")
      }
  }
}

///|
/// Resolve `<key>` (envelope) or `<key>/<file>` (raw) after the
/// `/api/sessions/` route prefix. A key is either legacy `<id>` for the first
/// matching file, or an opaque key returned by `/api/sessions`. Both segments
/// are percent-decoded — ids containing URL-reserved characters (spaces, `?`,
/// `#`) must decode in both positions to resolve the right session. `+` stays
/// literal, as it is in a path segment, and malformed escapes stay verbatim. The
/// resolved path always comes from the catalog scan, never from the URL file
/// segment.
async fn session_path_reply(
  catalog : SessionCatalog,
  rest : String,
  known_bytes? : Int64,
) -> Reply {
  let (key, file) = match rest.split_once("/") {
    None => (@percent.decode_lossy(rest), None)
    Some((key, file)) =>
      (@percent.decode_lossy(key), Some(@percent.decode_lossy(file)))
  }
  let row = match catalog.lookup(key) {
    Some(found) => found
    None => return text_reply(404, "Not Found", "session file not found")
  }
  guard valid_session_id(row.id) else {
    return text_reply(400, "Bad Request", "invalid session id")
  }
  match file {
    None => session_envelope_reply(row.path, known_bytes?)
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
/// splits apart itself. `events_bytes` is the byte length of exactly that text,
/// read once, so it can never claim bytes the reply does not carry.
///
/// With `known_bytes` (a watching viewer's current size), a log that has not
/// changed size answers `{ "found": true, "unchanged": true, "events_bytes" }`
/// instead of resending the whole file. Session logs are append-only between
/// compactions, and a compaction rewrites the file to a different size.
async fn session_envelope_reply(path : String, known_bytes? : Int64) -> Reply {
  if !@fs.exists(path) {
    return json_reply({ "found": false })
  }
  if known_bytes is Some(known) && file_size(path) == known {
    return json_reply({
      "found": true,
      "unchanged": true,
      "events_bytes": Json(known.to_double()),
    })
  }
  let bytes = @fs.read_file(path).binary()
  json_reply({
    "found": true,
    "events": @utf8.decode_lossy(bytes),
    "events_bytes": Json(bytes.length().to_double()),
  })
}

///|
async fn session_list_reply(catalog : SessionCatalog) -> Reply {
  json_reply(catalog.rows().map(row => row.to_json()).to_json())
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
  shell_html : String,
  bundle_js : String,
) -> String {
  let sessions : Array[@viz_export.Session] = []
  for row in rows {
    sessions.push(
      Session(
        key=row.key,
        id=row.id,
        root=row.root,
        root_label=row.root_label,
        is_marker=row.is_marker,
        last_active=row.last_active.map(seconds => seconds.to_double()),
        first_prompt=row.first_prompt,
        events=read_text_lossy(row.path),
      ),
    )
  }
  @viz_export.StandaloneExport(shell_html, bundle_js).render(sessions)
}

///|
/// The bundle to serve/embed: an explicit `--bundle` (the first candidate,
/// blank when unset) wins outright when it exists; otherwise the FRESHEST
/// existing candidate by mtime — not the first. List order once let an
/// 11-day-old `release` artifact silently shadow a fresh `debug` build,
/// shipping a stale frontend into an export; for build outputs, recency is
/// the signal that matters. Ties keep candidate order.
async fn locate_bundle(candidates : Array[String]) -> String? {
  guard candidates is [explicit, .. rest] else { return None }
  if explicit != "" {
    if @fs.exists(explicit) {
      return Some(explicit)
    }
    // An explicitly requested bundle that is missing must not silently
    // become a different one: say so, then fall back to auto-location.
    println(
      "openseek viz: warning: --bundle '\{explicit}' does not exist; auto-locating instead",
    )
  }
  let mut best : (String, Int64, Int)? = None
  for candidate in rest {
    if candidate == "" || !@fs.exists(candidate) {
      continue
    }
    guard file_mtime(candidate) is Some((seconds, nanoseconds)) else {
      continue
    }
    let newer = match best {
      None => true
      Some((_, best_seconds, best_nanoseconds)) =>
        seconds > best_seconds ||
        (seconds == best_seconds && nanoseconds > best_nanoseconds)
    }
    if newer {
      best = Some((candidate, seconds, nanoseconds))
    }
  }
  best.map(entry => entry.0)
}

///|
async fn file_mtime(path : String) -> (Int64, Int)? {
  let file = @fs.open(path, mode=ReadOnly) catch { _ => return None }
  defer file.close()
  let stamp = file.mtime() catch { _ => return None }
  Some(stamp)
}

///|
/// The first non-empty candidate path that names an existing file, or `None`.
/// Used for the SHELL (a curated file, where list order is the intent);
/// the bundle resolves by recency via `locate_bundle` instead.
async fn first_existing(candidates : Array[String]) -> String? {
  for candidate in candidates {
    if candidate != "" && @fs.exists(candidate) {
      return Some(candidate)
    }
  }
  None
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
    Some(seconds) => Json(seconds.to_double())
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
    (Some(a_time), Some(b_time)) => {
      // Most recently active first: compare b to a for a descending order.
      let by_time = b_time.compare(a_time)
      if by_time != 0 {
        return by_time
      }
      let by_nanoseconds = b.last_active_nanoseconds.compare(
        a.last_active_nanoseconds,
      )
      if by_nanoseconds != 0 {
        return by_nanoseconds
      }
      compare_session_list_row_labels(a, b)
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
  // Scan the --session-root only when it is a container, so nested stores under
  // a container root and standalone copied-log directories are surfaced the same
  // way search-dir trees are. A direct store root is already served via
  // `session_root_sources`; do not recurse into its `sessions/<id>` directories
  // as copied-log roots.
  let scan_dirs = if is_session_store(session_root, session_root_name) {
    search_dirs
  } else {
    [session_root, ..search_dirs]
  }
  let roots = unique_roots(
    [
      // Serve the explicit --session-root directly when it is a store, a directory
      // of copied `openseek_session-*.jsonl` files, or a single matching file.
      ..session_root_sources(session_root, session_root_name),
      ..discover_session_roots(scan_dirs, session_root_name),
    ],
  )
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
  name == session_root_name || should_skip_session_file_scan_dir(name)
}

///|
fn should_skip_session_file_scan_dir(name : String) -> Bool {
  name is (".git" | "node_modules" | ".mooncakes" | "_build")
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
    if line.is_blank() {
      continue
    }
    let event : @agent_session.SessionEvent = @json.from_json(@json.parse(line)) catch {
      _ => return ""
    }
    if event.item() is User(message) {
      let content = message.content()
      let text = content.text()
      return if text.is_blank() && !content.is_text_only() {
        "[Image]"
      } else {
        text
      }
    }
  }
  ""
}

///|
async fn SessionCatalog::rows(self : SessionCatalog) -> Array[SessionListRow] {
  let rows : Array[SessionListRow] = []
  for root in self.roots {
    for path in session_files_under(root.scan_path, root.recursive) {
      guard session_id_from_file_name(path_tail(path)) is Some(id) else {
        continue
      }
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
  guard name.strip_prefix(session_file_prefix) is Some(rest) &&
    rest.strip_suffix(session_file_suffix) is Some(id) else {
    return None
  }
  let id = id.to_owned()
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
  match rows.iter().find_first(row => row.key == key) {
    Some(row) => Some(row)
    None => rows.iter().find_first(row => row.id == key)
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
  if trimmed =~ (re"^(.|\n)*[/\\]", after~) {
    after.to_owned()
  } else {
    trimmed
  }
}

///|
fn trim_trailing_path_separators(path : String) -> String {
  let trimmed = for view = path[:] {
    match view {
      // Always keep at least one character, so "/" stays "/".
      [.. rest, '/' | '\\'] if !rest.is_empty() => continue rest
      _ => break view
    }
  }
  if trimmed.length() == path.length() {
    path
  } else {
    trimmed.to_owned()
  }
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
/// `<root>/_build/<target>/<profile>/build/moonbitlang/inspect/...`, so everything
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
///
/// Outside a checkout (`module_root` is `None`, e.g. under `moonx`) only an
/// explicit `--web-dir` is searched: the default `web/` would otherwise pick up
/// whatever unrelated `web/index.html` the current project has, instead of the
/// shell built into the binary.
fn shell_candidates(
  web_dir : String,
  module_root : String?,
  web_dir_explicit~ : Bool,
) -> Array[String] {
  let candidates = []
  if web_dir_explicit || module_root is Some(_) {
    candidates.push("\{web_dir}/index.html")
  }
  if module_root is Some(root) {
    candidates.push("\{root}/web/index.html")
  }
  candidates
}

///|
/// Where to look for the compiled frontend bundle. Element 0 is the
/// explicit `--bundle` path (blank when unset) — the one position that
/// matters, since `locate_bundle` resolves the rest by mtime, not list
/// order: `<web-dir>/viz_app.js`, moon's release and debug outputs for the
/// standalone frontend module, and the same paths under the
/// executable-derived checkout root. This lets `moon build cmd/viz_app
/// --target js` followed by `moon run inspect` work with no copy step —
/// from any directory.
///
/// Outside a checkout only an explicit `--bundle` or `--web-dir` is searched,
/// as for the shell: the CWD-relative build outputs belong to a checkout, and
/// the binary carries its own bundle.
fn bundle_candidates(
  bundle : String,
  web_dir : String,
  module_root : String?,
  web_dir_explicit~ : Bool,
) -> Array[String] {
  let build_outputs = [
    "_build/js/release/build/moonbitlang/openseek-viz-app/openseek-viz-app.js", "_build/js/debug/build/moonbitlang/openseek-viz-app/openseek-viz-app.js",
  ]
  let candidates = [bundle]
  if web_dir_explicit || module_root is Some(_) {
    candidates.push("\{web_dir}/viz_app.js")
  }
  if module_root is Some(_) {
    candidates.append(build_outputs)
  }
  if module_root is Some(root) {
    candidates.push("\{root}/web/viz_app.js")
    for path in build_outputs {
      candidates.push("\{root}/\{path}")
    }
  }
  candidates
}

///|
/// Read a file into a reply, or a 404 reply when it does not exist.
async fn asset_reply(path : String, content_type : String) -> Reply {
  if !@fs.exists(path) {
    return text_reply(404, "Not Found", "missing file: \{path}")
  }
  { code: 200, reason: "OK", content_type, body: read_text_lossy(path), }
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
  { code, reason, content_type: "text/plain; charset=utf-8", body: message, }
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
fn cli_command() -> @argparse.Command {
  Command(
    "openseek-viz",
    about="Read-only web server for the OpenSeek session visualizer.",
    flags=[
      FlagArg(
        "watch",
        long="watch",
        env="OPENSEEK_VIZ_WATCH",
        about="Keep the browser live: the open session and the session list refresh as their logs grow.",
      ),
      FlagArg(
        "ensure",
        long="ensure",
        env="OPENSEEK_VIZ_ENSURE",
        about="Find or start the one server for these sessions: reuse a running one, otherwise serve on loopback at a port derived from --session-root, behind a token, exiting after --idle-exit minutes. Prints `openseek viz: open <url>` either way.",
      ),
    ],
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
        "idle-exit",
        long="idle-exit",
        env="OPENSEEK_VIZ_IDLE_EXIT",
        default_values=[""],
        about="Exit after this many minutes without a request; 0 never exits. Defaults to 60 with --ensure, otherwise never.",
      ),
      OptionArg(
        "export",
        long="export",
        env="OPENSEEK_VIZ_EXPORT",
        default_values=[""],
        about="Write a self-contained standalone HTML (all discovered sessions embedded, no server needed) to this path and exit, instead of serving.",
      ),
      OptionArg(
        "export-session",
        long="export-session",
        env="OPENSEEK_VIZ_EXPORT_SESSION",
        default_values=[""],
        about="Scope --export to this session id plus its subagent children (<id>-sr-N) instead of every discovered session.",
      ),
    ],
  )
}

///|
/// Whether a session belongs to a scoped export: the target itself or one
/// of its `<target>-sr-N` subagent children — the naming contract the
/// subrun runner derives child session ids by, matched one level deep,
/// like the substrate spawns them.
fn in_export_scope(id : String, target : String) -> Bool {
  if id == target {
    return true
  }
  guard id.strip_prefix("\{target}-sr-") is Some(digits) else { return false }
  !digits.is_empty() && digits.all(c => c.is_ascii_digit())
}

///|
test "in_export_scope keeps the parent and exactly its own children" {
  assert_true(in_export_scope("run", "run"))
  assert_true(in_export_scope("run-sr-1", "run"))
  assert_true(in_export_scope("run-sr-12", "run"))
  // Another parent's child, a lookalike prefix, a non-numeric suffix, and
  // a grandchild-shaped id all stay out of scope.
  assert_false(in_export_scope("run2-sr-1", "run"))
  assert_false(in_export_scope("run-sr-", "run"))
  assert_false(in_export_scope("run-sr-x", "run"))
  assert_false(in_export_scope("run-sr-1-sr-2", "run"))
  assert_true(in_export_scope("run-sr-1-sr-2", "run-sr-1"))
}

///|
/// The directories to scan recursively for session roots. An explicit
/// `--session-root` narrows serving to that root, so the
/// default `.` scan is dropped — pointing the server at another project's
/// sessions must not also pull in whatever tree it was started from. An
/// explicit `--search-dir` always wins: giving both flags means "that root,
/// plus these scans".
fn effective_search_dirs(matches : @argparse.Matches) -> Array[String] {
  match matches {
    {
      values: { "search-dir": _, .. },
      sources: { "session-root": Argv, "search-dir": Default, .. },
      ..
    } => []
    { values: { "search-dir": values, .. }, .. } =>
      [
        for value in values if !value.is_blank() => value.trim().to_owned()
      ]
    _ => []
  }
}

///|
fn parse_port(text : String) -> Int raise {
  @string.parse_int(text) catch {
    _ => fail("--port or OPENSEEK_VIZ_PORT must be an integer, got: \{text}")
  }
}

///|
async test "locate_bundle prefers the freshest artifact; explicit wins" {
  let root = @fs.tmpdir(prefix="openseek-viz-bundle-")
  let old_path = "\{root}/old.js"
  let new_path = "\{root}/new.js"
  @fs.write_file(old_path, "old", create_mode=CreateOrTruncate)
  // Written after a settling delay, so strictly newer even on filesystems with
  // coarse timestamp granularity (CI containers are not always APFS).
  @async.sleep(20)
  @fs.write_file(new_path, "new", create_mode=CreateOrTruncate)
  // No explicit bundle: recency beats candidate order.
  assert_eq(locate_bundle(["", old_path, new_path]), Some(new_path))
  assert_eq(locate_bundle(["", new_path, old_path]), Some(new_path))
  // An explicit --bundle wins outright, even when older.
  assert_eq(locate_bundle([old_path, new_path]), Some(old_path))
  // Missing candidates are skipped; nothing existing is None.
  assert_eq(locate_bundle(["", "\{root}/absent.js", old_path]), Some(old_path))
  assert_eq(locate_bundle(["", "\{root}/absent.js"]), None)
  @fs.rmdir(root, recursive=true)
}
