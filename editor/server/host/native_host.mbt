///|
/// Native filesystem host for the reference remote server.
struct NativeServerHost {
  poll_interval_ms : Int
}

///|
/// Creates the native host with the default file-watch polling interval.
fn new_native_server_host() -> NativeServerHost {
  { poll_interval_ms: 500, }
}

///|
/// Creates the native host with a clamped polling interval.
fn native_server_host_with_poll_interval(
  poll_interval_ms : Int,
) -> NativeServerHost {
  { poll_interval_ms: poll_interval_ms.max(10), }
}

///|
async fn read_native_text_file(
  root : String,
  path : @workspace.SourcePath,
) -> @server.ServerHostReadResult {
  let target = workspace_file_path(root, path)
  match validate_native_file(root, target) {
    Some(error) => ServerHostReadError(error.0, error.1)
    None =>
      match try_read_text_file(root, path) {
        Some(content) => ServerHostReadOk(content)
        None => ServerHostReadError(Unavailable, "Unable to read source file.")
      }
  }
}

///|
/// Resolves exactly one directory level: a non-recursive `readdir` that
/// reuses `skip_workspace_entry` filtering and mints each child's
/// `readonly-remote://workspace/<path>` URI with unresolved children.
async fn read_native_directory(
  root : String,
  relative : String,
) -> @server.ServerHostResolveResult {
  let normalized_root = normalize_host_path(root)
  let dir_path = if relative == "" {
    normalized_root
  } else {
    "\{normalized_root}/\{relative}"
  }
  if !@fs.exists(dir_path) {
    return ServerHostResolveError(FileNotFound, "Directory does not exist.")
  }
  let root_real = realpath_or_normalized(normalized_root)
  let dir_real = realpath_or_normalized(dir_path)
  if !is_under_root(root_real, dir_real) {
    return ServerHostResolveError(
      InvalidUri,
      "Directory path escapes the workspace root.",
    )
  }
  match (Some(@fs.kind(dir_real)) catch { _ => None }) {
    Some(Directory) => ()
    _ =>
      return ServerHostResolveError(
        FileNotADirectory,
        "Path is not a directory.",
      )
  }
  let names = Some(@fs.readdir(dir_path, include_hidden=true, sort=true)) catch {
    _ => None
  }
  guard names is Some(names) else {
    return ServerHostResolveError(Unavailable, "Unable to read directory.")
  }
  let children : Array[@workspace.WorkspaceStat] = []
  for name in names {
    let path = if relative is "" { name } else { "\{relative}/\{name}" }
    guard !skip_workspace_entry(path~, name~) else { continue }
    let disk_kind = Some(@fs.kind("\{dir_path}/\{name}")) catch { _ => None }
    match (disk_kind, @server.remote_document_uri(path)) {
      (Some(Directory), Some(uri)) =>
        children.push({ uri, name, kind: Directory, children: None, })
      (Some(Regular), Some(uri)) =>
        children.push({ uri, name, kind: File, children: None, })
      _ => ()
    }
  }
  ServerHostResolveOk(children)
}

///|
async fn poll_native_file_watch(
  root : String,
  path : @workspace.SourcePath,
  poll_interval_ms : Int,
  disposed : Ref[Bool],
  listener : async (@workspace.FileChangeType) -> Unit,
) -> Unit {
  let target = workspace_file_path(root, path)
  let mut previous = native_file_signature(target)
  while !disposed.val {
    @async.sleep(poll_interval_ms)
    let next = native_file_signature(target)
    if next != previous {
      let change_type : @workspace.FileChangeType = if next == "missing" {
        Deleted
      } else {
        Changed
      }
      listener(change_type) catch {
        _ => ()
      }
      previous = next
    }
  }
}

///|
async fn native_file_signature(path : String) -> String {
  let exists = Some(@fs.exists(path)) catch { _ => None }
  if exists != Some(true) {
    return "missing"
  }
  match (Some(@fs.mtime(path)) catch { _ => None }) {
    Some((seconds, nanos)) => "exists:\{seconds}:\{nanos}"
    None => "missing"
  }
}

///|
/// One coherent native-file observation used by semantic providers. Text is
/// normalized exactly as a TextModel snapshot, while the signature remains the
/// provider revision exposed on the wire.
priv struct NativeDiskSnapshot {
  signature : String
  text : String
  normalized_text : String
} derive(Eq)

///|
/// Reads a validated file only when its signature stays stable across the
/// read. Callers that run external tools re-read this snapshot afterwards.
async fn read_native_disk_snapshot(
  root : String,
  path : @workspace.SourcePath,
) -> NativeDiskSnapshot? {
  let target = workspace_file_path(root, path)
  guard validate_native_file(root, target) is None else { return None }
  let before = native_file_signature(target)
  guard before != "missing" else { return None }
  guard (Some(@fs.read_file(target)) catch { _ => None }) is Some(data) else {
    return None
  }
  guard (Some(data.text()) catch { _ => None }) is Some(text) else {
    return None
  }
  guard !text.contains("\u{0}") else { return None }
  let after = native_file_signature(target)
  guard before == after else { return None }
  Some({
    signature: after,
    text,
    normalized_text: @model.TextSnapshot(text).get_value(),
  })
}

///|
async fn validate_native_file(
  root : String,
  target : String,
) -> (@workspace.FileSystemProviderErrorCode, String)? {
  let root_real = realpath_or_normalized(root)
  let exists = Some(@fs.exists(target)) catch { _ => None }
  if exists != Some(true) {
    return Some((FileNotFound, "Source file does not exist."))
  }
  let target_real = realpath_or_normalized(target)
  if !is_under_root(root_real, target_real) {
    return Some((InvalidUri, "Source path escapes the workspace root."))
  }
  match (Some(@fs.kind(target_real)) catch { _ => None }) {
    Some(Directory) => Some((IsDirectory, "Source path is a directory."))
    Some(Regular) => None
    Some(_) => Some((InvalidData, "Source path is not a regular text file."))
    None => Some((Unavailable, "Unable to inspect source file."))
  }
}

///|
async fn try_read_text_file(
  root : String,
  path : @workspace.SourcePath,
) -> @workspace.DocumentContent? {
  match read_native_disk_snapshot(root, path) {
    Some(snapshot) => {
      let display_name = path.display_name()
      Some(
        DocumentContent(
          snapshot.text,
          display_name~,
          language_id=@workspace.infer_language_id(display_name),
          revision=snapshot.signature,
        ),
      )
    }
    None => None
  }
}

///|
async fn realpath_or_normalized(path : String) -> String {
  match (Some(@fs.realpath(path)) catch { _ => None }) {
    Some(real) => normalize_host_path(real)
    None => normalize_host_path(path)
  }
}

///|
fn workspace_file_path(root : String, path : @workspace.SourcePath) -> String {
  "\{normalize_host_path(root)}/\{path.to_string()}"
}

///|
fn normalize_host_path(path : String) -> String {
  let normalized = path.replace_all(old="\\", new="/")
  if normalized.has_suffix("/") && normalized.length() > 1 {
    normalized[0:normalized.length() - 1].to_owned()
  } else {
    normalized
  }
}

///|
fn is_under_root(root : String, target : String) -> Bool {
  target == root || target.has_prefix("\{root}/")
}

///|
fn skip_workspace_entry(path~ : String, name~ : String) -> Bool {
  name == ".git" ||
  name == "_build" ||
  name == ".mooncakes" ||
  name == "node_modules" ||
  path == "web/generated" ||
  path == "web/dist"
}

///|
/// Live protocol websocket outboxes, keyed by session id. Server-initiated
/// pushes (diagnostics) broadcast one encoded frame to every session.
priv struct ProtocolSessions {
  next_session_id : Ref[Int]
  outboxes : Map[Int, @aqueue.Queue[String]]
}

///|
fn ProtocolSessions::ProtocolSessions() -> ProtocolSessions {
  { next_session_id: Ref(0), outboxes: {}, }
}

///|
fn ProtocolSessions::attach(
  self : ProtocolSessions,
  outbox : @aqueue.Queue[String],
) -> Int {
  self.next_session_id.val += 1
  self.outboxes.set(self.next_session_id.val, outbox)
  self.next_session_id.val
}

///|
fn ProtocolSessions::detach(self : ProtocolSessions, session : Int) -> Unit {
  self.outboxes.remove(session)
}

///|
fn ProtocolSessions::broadcast(self : ProtocolSessions, raw : String) -> Unit {
  for _session, outbox in self.outboxes {
    enqueue(outbox, raw)
  }
}

///|
/// Broadcasts to every session except one — used for events whose triggering
/// session already received a correlated response.
fn ProtocolSessions::broadcast_except(
  self : ProtocolSessions,
  excluded : Int,
  raw : String,
) -> Unit {
  for session, outbox in self.outboxes {
    if session != excluded {
      enqueue(outbox, raw)
    }
  }
}

///|
/// Enqueues without suspending: the transport and session queues are all
/// unbounded, so `try_put` only fails when a queue was closed at teardown.
fn enqueue(queue : @aqueue.Queue[String], message : String) -> Unit {
  (queue.try_put(message) catch { _ => false }) |> ignore
}

///|
/// Starts the native reference server: static assets over HTTP and the remote
/// workspace protocol over WebSocket. The default listener is loopback-only;
/// `host="0.0.0.0"` opts into every IPv4 interface and LAN URL discovery.
pub async fn run_native_editor_server(
  root : String,
  host? : String = "127.0.0.1",
  port? : Int = 5173,
  asset_dir? : String = "web/dist",
  moon_command? : String = "moon",
  browse_root? : String = "",
  log? : (String) -> Unit = println,
) -> Unit {
  let server_host = NativeServerHost::NativeServerHost()
  let root : Ref[String] = Ref(realpath_or_normalized(root))
  let browse_scope = resolve_browse_scope(browse_root, host)
  let addr = @socket.Addr::parse("\{host}:\{port}")
  let http_server = @http.Server(addr, reuse_addr=true)
  // The diagnostics check runs outlive any single protocol connection, so
  // they run on the server-lifetime task group.
  @async.with_task_group() <| group => {
    let spawn_task = task => {
      group.spawn_bg(task, no_wait=true, allow_failure=true)
    }
    let sessions = ProtocolSessions::ProtocolSessions()
    let workspace = moon_backed_native_workspace(
      root, browse_scope, server_host, moon_command, spawn_task, sessions,
    )
    let network_host = if host == "0.0.0.0" {
      default_route_ipv4_address()
    } else {
      None
    }
    for message in editor_server_listening_messages(host, port, network_host) {
      log(message)
    }
    http_server.run_forever() <| ((request, _body, conn) => {
      handle_native_editor_request(workspace, asset_dir, request, conn)
    })
  }
}

///|
/// An explicit `--browse-root` always wins; otherwise unrestricted browsing
/// is reserved for loopback listeners and disabled on every other bind, so
/// the unauthenticated LAN posture of `just dev` cannot be re-rooted.
async fn resolve_browse_scope(
  browse_root : String,
  host : String,
) -> HostBrowseScope {
  if browse_root != "" {
    BrowseWithin(realpath_or_normalized(browse_root))
  } else if is_loopback_host(host) {
    BrowseHost
  } else {
    BrowseDisabled
  }
}

///|
fn is_loopback_host(host : String) -> Bool {
  host == "localhost" || host == "::1" || host.has_prefix("127.")
}

///|
/// Mutable native workspace state shared by every protocol session: the
/// served root, the browse scope, the base remote server whose sessions
/// share that root, the diagnostics runner, and the live session outboxes.
priv struct NativeWorkspace {
  root : Ref[String]
  browse_scope : HostBrowseScope
  remote_server : @server.RemoteServer
  diagnostics : MoonCheckDiagnostics
  sessions : ProtocolSessions
}

///|
/// Points every consumer of the served root — sessions, language provider,
/// diagnostics — at `real_root` and drops diagnostics state produced for the
/// previous root. Clients react to the `WorkspaceSwitched` packets by closing
/// their documents, which retires the old root's watches.
fn NativeWorkspace::switch_root(
  self : NativeWorkspace,
  real_root : String,
) -> Unit {
  self.root.val = real_root
  self.remote_server.set_workspace_root(real_root)
  self.diagnostics.reset()
}

///|
/// Builds the moon-backed remote server and wires the push path that keeps
/// diagnostics live without any client pulling (the `publishDiagnostics` →
/// marker-service flow of VS Code): every cached document snapshot (open or
/// watch update) schedules a `moon check` run, and each run broadcasts its
/// per-file diagnostics to every connected session as `Diagnostics` push
/// packets.
fn moon_backed_native_workspace(
  root : Ref[String],
  browse_scope : HostBrowseScope,
  host : &@server.ServerHost,
  moon_command : String,
  spawn_task : (async () -> Unit) -> Unit,
  sessions : ProtocolSessions,
) -> NativeWorkspace {
  let provider = MoonWorkspaceLanguageProvider(root, moon_command~)
  let remote_server = @server.RemoteServer::with_language_providers(
    root.val,
    host,
    provider,
    provider,
    provider,
    provider,
  )
  let diagnostics = MoonCheckDiagnostics(
    root,
    (uri, revision, file_diagnostics) => {
      sessions.broadcast(
        diagnostics_push_packet(uri, revision, file_diagnostics),
      )
    },
    moon_command~,
  )
  remote_server.set_document_sync_listener(
    Some(document => {
      diagnostics.note_document(document)
      diagnostics.schedule(spawn_task)
    }),
  )
  { root, browse_scope, remote_server, diagnostics, sessions, }
}

///|
fn diagnostics_push_packet(
  uri : @base_common.Uri,
  revision : String,
  diagnostics : Array[@language.Diagnostic],
) -> String {
  @remote_protocol.ServerPacket::Diagnostics({ uri, revision, diagnostics, })
  .to_json()
  .stringify()
}

///|
async fn handle_native_editor_request(
  workspace : NativeWorkspace,
  asset_dir : String,
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  if request.path == "/protocol" {
    handle_protocol_connection(workspace, request, conn)
  } else {
    serve_static_route(asset_dir, request, conn)
  }
}

///|
async fn handle_protocol_connection(
  workspace : NativeWorkspace,
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  let session_server = workspace.remote_server.new_session()
  let ws = @websocket.from_http_server(request, conn)
  defer ws.close()
  // Watch tasks emit packets concurrently with request handling, and the
  // websocket connection rejects interleaved sends; one writer task owns
  // the socket and everything else enqueues outbound frames.
  let outbox : @aqueue.Queue[String] = Queue(kind=Unbounded)
  let session = workspace.sessions.attach(outbox)
  defer workspace.sessions.detach(session)
  // Announce the served workspace first: a client that reconnected across a
  // switch reconciles against this instead of keeping the old root's editor
  // state; clients already on this root treat it as a no-op.
  enqueue(outbox, workspace_announce_packet(workspace))
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      for ;; {
        ws.send_text(outbox.get())
      }
    })
    let spawn_watch = task => {
      group.spawn_bg(task, no_wait=true, allow_failure=true)
    }
    try {
      for ;; {
        let message = ws.recv()
        match message.kind {
          Text => {
            let raw = message.read_all().text()
            handle_protocol_message(
              workspace, session_server, session, outbox, raw, spawn_watch,
            )
          }
          Binary => ignore(message.read_all().binary())
        }
      }
    } catch {
      @websocket.ConnectionClosed(_, _) => ()
      _ => ()
    }
    session_server.dispose_watches()
  }
}

///|
/// Dispatches one wire message. Host filesystem packets (repository browsing
/// and workspace switching) are host-level state changes and never reach the
/// per-session policy server.
async fn handle_protocol_message(
  workspace : NativeWorkspace,
  session_server : @server.RemoteServer,
  session : Int,
  outbox : @aqueue.Queue[String],
  raw : String,
  spawn_watch : (async () -> Unit) -> Unit,
) -> Unit {
  match @remote_protocol.decode_client_packet(raw) {
    DecodedClientPacket(ListHostDirectory(request)) =>
      outbox.put(list_host_directory_packet(workspace, request))
    DecodedClientPacket(SwitchWorkspace(request)) =>
      switch_workspace_packets(workspace, session, outbox, request)
    DecodedClientPacket(packet) => {
      let responses = session_server.handle_client_packet(
        packet,
        packet => outbox.put(packet.to_json().stringify()),
        spawn_watch,
      )
      for packet in responses {
        outbox.put(packet.to_json().stringify())
      }
    }
    ClientPacketDecodeError(error) =>
      outbox.put(@remote_protocol.RemoteError(error).to_json().stringify())
  }
}

///|
async fn serve_static_route(
  asset_dir : String,
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  guard request.meth is Get else {
    serve_not_found(conn)
    return
  }
  match static_route(request.path) {
    Some((file_name, content_type)) =>
      serve_static_file(conn, "\{asset_dir}/\{file_name}", content_type)
    None => serve_not_found(conn)
  }
}

///|
async fn serve_static_file(
  conn : @http.ServerConnection,
  file_path : String,
  content_type : String,
) -> Unit {
  if !@fs.exists(file_path) {
    serve_not_found(conn)
    return
  }
  let content = Some(@fs.read_file(file_path).binary()) catch { _ => None }
  match content {
    Some(content) => {
      conn.send_response(200, "OK", extra_headers={
        "Content-Type": content_type,
        "Content-Length": content.length().to_string(),
      })
      write_static_response_body(conn, content)
      conn.end_response()
    }
    None => serve_not_found(conn)
  }
}

///|
async fn write_static_response_body(
  conn : @http.ServerConnection,
  content : Bytes,
) -> Unit {
  let chunk_size = 16384
  for start = 0; start < content.length(); {
    let end = (start + chunk_size).min(content.length())
    conn.write(content[start:end])
    continue end
  }
}

///|
async fn serve_not_found(conn : @http.ServerConnection) -> Unit {
  let body = "Not found"
  conn
  ..send_response(404, "Not Found", extra_headers={
    "Content-Type": "text/plain; charset=utf-8",
    "Content-Length": body.length().to_string(),
  })
  ..write_string(body)
  .end_response()
}

///|
fn static_route(path : String) -> (String, String)? {
  let path = strip_query(path)
  match path {
    "/" | "/index.html" => Some(("index.html", "text/html; charset=utf-8"))
    "/embed.html" => Some(("embed.html", "text/html; charset=utf-8"))
    "/style.css" => Some(("style.css", "text/css; charset=utf-8"))
    "/codicon.ttf" => Some(("codicon.ttf", "font/ttf"))
    "/editor.mjs" => Some(("editor.mjs", "text/javascript; charset=utf-8"))
    "/embed.mjs" => Some(("embed.mjs", "text/javascript; charset=utf-8"))
    "/browser-tests/runner.html" =>
      Some(("browser-tests/runner.html", "text/html; charset=utf-8"))
    "/browser-tests/runner.mjs" =>
      Some(("browser-tests/runner.mjs", "text/javascript; charset=utf-8"))
    "/browser-tests/runner.mjs.map" =>
      Some(("browser-tests/runner.mjs.map", "application/json; charset=utf-8"))
    _ => mermaid_static_route(path)
  }
}

///|
/// Keep the server's static surface closed while allowing Mermaid's
/// content-hashed ESM chunks to change on a deliberate version bump.
fn mermaid_static_route(path : String) -> (String, String)? {
  if path == "/mermaid/mermaid.esm.min.mjs" {
    return Some(
      ("mermaid/mermaid.esm.min.mjs", "text/javascript; charset=utf-8"),
    )
  }
  if path == "/mermaid/LICENSE" {
    return Some(("mermaid/LICENSE", "text/plain; charset=utf-8"))
  }
  let prefix = "/mermaid/chunks/mermaid.esm.min/"
  guard path.has_prefix(prefix) && path.has_suffix(".mjs") else { return None }
  let name = path[prefix.length():]
  guard !name.is_empty() &&
    name
    .iter()
    .all(char => {
      char.is_ascii_alphabetic() ||
      char.is_ascii_digit() ||
      char == '-' ||
      char == '_' ||
      char == '.'
    }) else {
    return None
  }
  Some((path[1:].to_owned(), "text/javascript; charset=utf-8"))
}

///|
fn strip_query(path : String) -> String {
  match path.find("?") {
    Some(index) => path[0:index].to_owned()
    None => path
  }
}
