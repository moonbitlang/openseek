// Host-side LSP backing the editor side-panel — hover tooltips and the
// composer's `#` symbol search. A conversation's workspace may hold the module
// at its root (`<cwd>/moon.mod`) or, just as often, a project the agent created
// one level down (`<cwd>/<project>/moon.mod`); moon-lsp does not discover nested
// modules, so the host finds them and spawns one `moon-lsp --stdio` rooted at
// each. Hover routes by the file's absolute path — workspace, then deepest
// module root; symbol search resolves its conversation's workspace and fans
// out to that workspace's servers. Everything is best-effort — no module yet,
// a failed spawn, a server error, or a non-text file all just yield nothing.
//
// Servers live in one global pool keyed by module root, so conversations
// sharing a project share its servers. Roots are re-detected on each request:
// a project created mid conversation is picked up, one whose module moved is
// retired, and the pool caps at MaxLspServers by retiring the least recently
// used. A moon-lsp process must outlive the individual request that first
// needs it, so — mirroring the engine pump — it is owned by the long-lived
// task group of the `connect` op, not a per-request one: `ensure_servers`
// hands each spawn to that group's LSP pump over a queue and waits for the
// server back. Retiring a server closes the host's stdin end (EOF, so
// moon-lsp exits) and cancels the process; dropping the `connect` group tears
// every server down with it.

///|
/// The largest number of pooled `moon-lsp` servers. A workspace rarely holds
/// more than a couple of modules; the cap only matters across many
/// conversations or a pathological tree (a folder of sample projects), where
/// the most recently used roots win the slots.
const MaxLspServers = 6

///|
/// The most symbol rows a search returns, across all of a conversation's
/// servers — enough to fill the menu, bounded so a short query can't flood it.
const MaxSymbolResults = 50

///|
/// One language server rooted at a single module directory.
priv struct LspWorkspace {
  session : @lsp.Session
  // The module directory moon-lsp is rooted at — an ancestor of the files it
  // answers for, and the key that decides whether a re-detected layout still
  // wants this server.
  root : String
  // The moon-lsp process, owned by the connect op's task group. Retiring this
  // server cancels it; the connect group tears it down on disconnect.
  process : @process.Process
  // The host's ends of the server's pipes. Closing the stdin end EOFs moon-lsp
  // so it exits when this server is retired.
  stdin : @process.WriteToProcess
  stdout : @process.ReadFromProcess
  // Last text synced per file uri, so an unchanged file is not re-sent.
  synced : Map[String, String]
}

///|
/// Lazily-started `moon-lsp` instances in one global pool keyed by module
/// root — conversations sharing a project share its servers.
priv struct LspManager {
  // The engine executable, anchoring the bundled-toolchain lookup for `moon-lsp`.
  engine : String
  runtime_dir : @path.Path?
  // The resolved `moon-lsp` to spawn, computed once on first use; "" until then.
  mut command : String
  // The child environment for spawning `command`, resolved with it. Set (and
  // passed with `inherit_env=false`) when the command is the bundled moon-lsp,
  // which must not see a shell-exported `MOON_HOME`; `None` for the PATH
  // fallback of a dev run, which inherits the environment as-is.
  mut spawn_env : Map[String, String]?
  servers : Map[String, LspWorkspace]
  // Pool recency, freshest first — the MaxLspServers eviction order.
  order : Array[String]
  // Serializes server reconciliation so two concurrent requests don't spawn two
  // servers for the same root.
  create_lock : @semaphore.Semaphore
  // Spawn requests from per-request ops to the LSP pump, which owns the moon-lsp
  // processes in the `connect` op's long-lived task group.
  commands : @async.Queue[LspCommand]
  // Diagnostics published by any pooled server, tagged with the file's absolute
  // path, awaiting forwarding to the webview by `run_diagnostics_pump`. Bounded
  // and drop-oldest so a diagnostics storm can never outrun the drain and grow
  // without bound.
  diagnostics : @async.Queue[DiagnosticsPush]
  // Set while the pump loop is running; a spawn request is only enqueued when a
  // pump is there to service it.
  mut pump_running : Bool
}

///|
/// A request to the LSP pump: spawn a `moon-lsp` server rooted at the given
/// directory into the pump's task group, delivering the started server (or
/// `None` on failure) back over the queue.
priv enum LspCommand {
  SpawnWorkspace(@path.Path, @async.Queue[LspWorkspace?])
}

///|
fn new_lsp_manager(engine : String, runtime_dir? : @path.Path) -> LspManager {
  {
    engine,
    runtime_dir,
    command: "",
    spawn_env: None,
    servers: {},
    order: [],
    create_lock: Semaphore(1, initial_value=1),
    commands: Queue(kind=Unbounded),
    diagnostics: Queue(kind=DiscardOldest(256)),
    pump_running: false,
  }
}

///|
/// The LSP host loop: runs inside the `connect` op's task group for the app's
/// lifetime, servicing spawn requests so each `moon-lsp` is owned by that
/// long-lived group rather than the per-request task that first needed it.
/// Returns only when the group is torn down (webview disconnect), which cancels
/// every server it started.
async fn[G] run_lsp_pump(
  group : @async.TaskGroup[G],
  manager : LspManager,
) -> Unit {
  manager.pump_running = true
  defer {
    manager.pump_running = false
    // The group teardown cancels the pooled processes themselves.
    manager.servers.clear()
    manager.order.clear()
  }
  for ;; {
    match manager.commands.get() {
      SpawnWorkspace(root, ack) =>
        ack.put(spawn_workspace(group, manager, root))
    }
  }
}

///|
/// The `moon-lsp` command to spawn, resolved once and cached. Prefer the binary
/// inside the bundled MoonBit toolchain (a packaged app), so hover works when
/// the app is launched normally with no `moon-lsp` on PATH; fall back to
/// `moon-lsp` on PATH for a dev run with no bundle. Resolution is serialized by
/// the caller's `create_lock`, so the cached write needs no lock of its own.
async fn moon_lsp_command(manager : LspManager) -> String {
  if !manager.command.is_empty() {
    return manager.command
  }
  let command = if @moonbit.bundled_moon_lsp(
      manager.engine,
      runtime_dir?=manager.runtime_dir,
    )
    is Some(path) {
    // The bundled binary must not run against a `MOON_HOME` the launching
    // shell exported — sanitize the child environment the way the engine
    // spawn does, with the bundled bin dir on the path variable.
    manager.spawn_env = Some(@moonbit.bundled_tool_env(path.dirname()))
    path.to_string()
  } else {
    "moon-lsp"
  }
  manager.command = command
  command
}

///|
/// Route hover by the file's absolute path — the workspace it belongs to,
/// then the deepest module root within it. The path is the whole address:
/// no session is involved, so the viewer can ask about any attached file.
async fn lsp_hover_op(
  manager : LspManager,
  payload : LspHoverPayload,
) -> LspHoverReply {
  guard @engine.attached_workspace_dir(payload.path) is Some(dir) else {
    raise HostError("path is outside every attached workspace")
  }
  let file : @path.Path = Path(payload.path)
  let file = file.normalize()
  let servers = ensure_servers(manager, dir)
  guard server_for_file(servers, file.to_string()) is Some(workspace) else {
    return no_hover()
  }
  guard read_text(file) is Some(text) else { return no_hover() }
  let uri = @uri.file_uri(file.to_string())
  // Re-sync only when the file's text actually changed since the last hover.
  if !(workspace.synced.get(uri) is Some(synced) && synced == text) {
    workspace.session.sync_document(uri~, language_id="moonbit", text~)
    workspace.synced.set(uri, text)
  }
  parse_hover(
    workspace.session.hover(
      uri~,
      line=payload.line,
      character=payload.character,
    ),
  )
}

///|
/// Sync the file the editor just opened into its server so the server analyzes
/// it and begins publishing diagnostics, and return whatever it has already
/// reported. Routes by absolute path exactly like `hover`. Best-effort: no
/// workspace, no server, or a non-text file yields no diagnostics. Later
/// changes arrive as `diagnostics` events.
async fn lsp_open_op(
  manager : LspManager,
  payload : LspOpenPayload,
) -> LspDiagnosticsReply {
  guard @engine.attached_workspace_dir(payload.path) is Some(dir) else {
    raise HostError("path is outside every attached workspace")
  }
  let file : @path.Path = Path(payload.path)
  let file = file.normalize()
  let servers = ensure_servers(manager, dir)
  guard server_for_file(servers, file.to_string()) is Some(workspace) else {
    return { diagnostics: [] }
  }
  guard read_text(file) is Some(text) else { return { diagnostics: [] } }
  let uri = @uri.file_uri(file.to_string())
  // Re-sync only when the file's text actually changed since the last request.
  if !(workspace.synced.get(uri) is Some(synced) && synced == text) {
    workspace.session.sync_document(uri~, language_id="moonbit", text~)
    workspace.synced.set(uri, text)
  }
  { diagnostics: workspace.session.diagnostics_for(uri~).unwrap_or([]) }
}

///|
/// Forward published diagnostics to the webview. Runs in the connect op's task
/// group alongside the LSP pump for the app's lifetime: each server's handler
/// enqueues onto `manager.diagnostics`, and this loop emits them as
/// `diagnostics` events. Returns only when the group is torn down.
async fn run_diagnostics_pump(
  manager : LspManager,
  emit : async (DiagnosticsPush) -> Unit,
) -> Unit {
  for ;; {
    emit(manager.diagnostics.get())
  }
}

///|
/// Search the conversation's workspace symbol index for `query`. Resolves the
/// workspace from the session, ensures its server is running, asks moon-lsp for
/// `workspace/symbol`, and flattens the result into workspace-relative rows.
/// Best-effort: an empty query, a missing workspace, a dead server, or nothing
/// indexed all yield no symbols.
async fn workspace_symbols_op(
  manager : LspManager,
  payload : WorkspaceSymbolsPayload,
) -> WorkspaceSymbolsReply {
  // An empty query is valid — it asks the server for every symbol, which backs
  // the bare `#` menu (capped like any other result).
  guard @engine.resolve_in_workspace(
      payload.session,
      "",
      workspace?=payload.workspace,
    )
    is Some(dir) else {
    return { symbols: [] }
  }
  let workspace_dir = dir.to_string()
  let symbols : Array[SymbolItem] = []
  // Fan the query across every module's server and merge, relativizing each
  // result against the conversation workspace (the common ancestor) so rows
  // from `<cwd>/a` and `<cwd>/b` come back as `a/...` and `b/...`. Sequential
  // is fine for the usual one or two servers.
  for workspace in ensure_servers(manager, dir) {
    if symbols.length() >= MaxSymbolResults {
      break
    }
    let reply = parse_symbols(
      workspace.session.workspace_symbols(query=payload.query),
      workspace_dir,
    )
    for symbol in reply.symbols {
      if symbols.length() >= MaxSymbolResults {
        break
      }
      symbols.push(symbol)
    }
  }
  { symbols, }
}

///|
/// Flatten a `workspace/symbol` result (an array of `SymbolInformation`) into
/// the flat reply the front-end consumes, relativizing each location's path
/// against the workspace and capping the count. A row missing a name or
/// location is skipped; an unrecognized shape yields no symbols.
fn parse_symbols(raw : Json?, workspace_dir : String) -> WorkspaceSymbolsReply {
  guard raw is Some(Array(items)) else { return { symbols: [] } }
  let symbols : Array[SymbolItem] = []
  for item in items {
    // A small cap keeps the menu usable and the reply bounded; moon-lsp can
    // return far more for a short query.
    if symbols.length() >= MaxSymbolResults {
      break
    }
    guard item is Object(fields) else { continue }
    guard fields.get("name") is Some(String(name)) && !name.is_empty() else {
      continue
    }
    guard fields.get("location") is Some(Object(location)) &&
      location.get("uri") is Some(String(uri)) else {
      continue
    }
    symbols.push({
      name,
      kind: @jsonx.json_int(fields, "kind"),
      container: @jsonx.json_text(fields, "containerName"),
      path: workspace_relative(uri, workspace_dir),
      range: symbol_range(location),
    })
  }
  { symbols, }
}

///|
/// A symbol's zero-based `location.range`, or an all-zeros range when the
/// location carries none (some servers return a bare `uri`).
fn symbol_range(location : Map[String, Json]) -> SymbolRange {
  guard location.get("range")
    is Some(
      Object(
        {
          "start": Object(
            { "line": Number(line, ..), "character": Number(col, ..), .. }
          ),
          "end": Object(
            {
              "line": Number(end_line, ..),
              "character": Number(end_col, ..),
              ..
            }
          ),
          ..
        }
      )
    ) else {
    return { start: { line: 0, col: 0 }, end: { line: 0, col: 0 } }
  }
  {
    start: { line: line.to_int(), col: col.to_int() },
    end: { line: end_line.to_int(), col: end_col.to_int() },
  }
}

///|
/// Turn an absolute `file:` URI into a path relative to `workspace_dir`. A URI
/// already inside the workspace loses the directory prefix; one that is not (the
/// server should not return such, but be safe) keeps its absolute path.
fn workspace_relative(uri : String, workspace_dir : String) -> String {
  let path = @uri.file_uri_path(uri)
  match @pathx.relative_to(path, root=workspace_dir) {
    Some(relative) => relative
    None => path
  }
}

///|
/// The pooled servers answering for `dir`'s module roots: a live pooled root
/// is reused (two conversations on the same project share one moon-lsp), a
/// missing or dead one spawns via the pump, a pooled server under `dir` whose
/// module vanished retires, and the pool caps at MaxLspServers by retiring the
/// least recently used. Empty when the directory holds no module yet — the
/// caller waits rather than rooting a server at a non-project directory.
async fn ensure_servers(
  manager : LspManager,
  dir : @path.Path,
) -> Array[LspWorkspace] {
  // A conversation's directory is created on its first run; before then
  // there is nothing to analyze.
  guard @fs.exists(dir.to_string()) else { return [] }
  let roots = lsp_roots(dir)
  manager.create_lock.acquire()
  defer manager.create_lock.release()
  // Retire pooled servers rooted under `dir` whose module is gone — the
  // per-request re-detection that picks up mid-conversation layout changes.
  let stale : Array[String] = []
  for root, _ in manager.servers {
    if @pathx.contains(dir.to_string(), root) && !roots_contains(roots, root) {
      stale.push(root)
    }
  }
  for root in stale {
    retire_server(manager, root)
  }
  // Reuse or spawn — via the pump, so a new process is owned by the connect
  // op's task group and outlives this request. With no pump running (the
  // webview never called `connect`) there is nothing to analyze against
  // anyway, so skip rather than block on a spawn no one will service.
  let live : Array[LspWorkspace] = []
  for root in roots {
    let key = root.to_string()
    if manager.servers.get(key) is Some(server) {
      // A pooled server whose transport already ended (moon-lsp crashed or
      // exited) would answer nothing forever — retire it and fall through to
      // spawn a fresh one.
      if !server.session.is_closed() {
        touch_server(manager, key)
        live.push(server)
        continue
      }
      retire_server(manager, key)
    }
    guard manager.pump_running else { continue }
    let ack : @async.Queue[LspWorkspace?] = Queue(kind=Unbounded)
    manager.commands.put(SpawnWorkspace(root, ack))
    guard ack.get() is Some(server) else { continue }
    manager.servers.set(key, server)
    manager.order.insert(0, key)
    live.push(server)
  }
  evict_over_cap(manager, keep=live)
  live
}

///|
/// Move a pooled root to the front of the recency order.
fn touch_server(manager : LspManager, root : String) -> Unit {
  if manager.order.search(root) is Some(index) {
    manager.order.remove(index) |> ignore
  }
  manager.order.insert(0, root)
}

///|
/// Close and forget a pooled server.
fn retire_server(manager : LspManager, root : String) -> Unit {
  guard manager.servers.get(root) is Some(server) else { return }
  close_workspace(server)
  manager.servers.remove(root)
  if manager.order.search(root) is Some(index) {
    manager.order.remove(index) |> ignore
  }
}

///|
/// Retire the least recently used pooled servers until the pool fits the
/// cap, never touching the ones the current request is about to use.
fn evict_over_cap(manager : LspManager, keep~ : Array[LspWorkspace]) -> Unit {
  for root in manager.order.copy().rev() {
    if manager.servers.length() <= MaxLspServers {
      break
    }
    if keep.iter().any(server => server.root == root) {
      continue
    }
    retire_server(manager, root)
  }
}

///|
/// The server whose root contains `file`, or `None` when no module does. The
/// deepest matching root wins, so a file inside a nested module is answered by
/// that module's server rather than an ancestor's.
fn server_for_file(
  servers : Array[LspWorkspace],
  file : String,
) -> LspWorkspace? {
  let mut best : LspWorkspace? = None
  for workspace in servers {
    guard @pathx.contains(workspace.root, file) else { continue }
    if best is Some(current) && current.root.length() >= workspace.root.length() {
      continue
    }
    best = Some(workspace)
  }
  best
}

///|
/// Whether `root` is one of the wanted roots.
fn roots_contains(roots : Array[@path.Path], root : String) -> Bool {
  for candidate in roots {
    if candidate.to_string() == root {
      return true
    }
  }
  false
}

///|
/// Retire a server: cancel the process and close the host's pipe ends (the EOF
/// on stdin is moon-lsp's own exit signal; the cancel is the backstop).
fn close_workspace(workspace : LspWorkspace) -> Unit {
  workspace.process.cancel()
  workspace.stdin.close()
  workspace.stdout.close()
}

///|
/// The module directories moon-lsp should be rooted at. The workspace itself
/// when it carries a module/workspace manifest (covering a root project and
/// multi-module `moon.work` workspaces in one server); otherwise its immediate
/// subdirectories that are modules — the common `<cwd>/<project>` layout — one
/// server each. A bounded scan: only the root and its direct children. When
/// more modules than `MaxLspServers` sit side by side, the most recently
/// modified win the slots.
async fn lsp_roots(workspace_dir : @path.Path) -> Array[@path.Path] {
  if manifest_mtime(workspace_dir) is Some(_) {
    return [workspace_dir]
  }
  let names = @fs.readdir(workspace_dir.to_string(), sort=true) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return []
  }
  // Child directories that are modules, paired with their manifest mtime for
  // the recency cut when there are too many.
  let modules : Array[(@path.Path, Int64)] = []
  for name in names {
    let child = workspace_dir.join((name : @path.Path))
    let is_dir = (@fs.kind(child.to_string()) catch {
        error if @async.is_being_cancelled() => raise error
        _ => Unknown
      })
      is Directory
    guard is_dir else { continue }
    guard manifest_mtime(child) is Some(mtime) else { continue }
    modules.push((child, mtime))
  }
  // Drop the oldest until within the cap (rare; usually a handful at most).
  while modules.length() > MaxLspServers {
    let mut oldest = 0
    for index, entry in modules {
      if entry.1 < modules[oldest].1 {
        oldest = index
      }
    }
    modules.remove(oldest) |> ignore
  }
  modules.map(entry => entry.0)
}

///|
/// The newest mtime (in whole seconds) among the module manifests directly in
/// `dir`, or `None` when `dir` holds none — i.e. it is not a module root.
async fn manifest_mtime(dir : @path.Path) -> Int64? {
  let mut newest : Int64? = None
  for name in ["moon.mod", "moon.mod.json", "moon.work"] {
    let path = dir.join((name : @path.Path)).to_string()
    guard @fs.exists(path) else { continue }
    let (seconds, _) = @fs.mtime(path) catch {
      error if @async.is_being_cancelled() => raise error
      _ => continue
    }
    newest = match newest {
      Some(current) => Some(if seconds > current { seconds } else { current })
      None => Some(seconds)
    }
  }
  newest
}

///|
/// Spawn `moon-lsp` rooted at the module directory `root` into `group` and run
/// the initialize handshake. `None` if the process could not start. Called only
/// from the pump, whose `group` owns the process for the app's lifetime.
async fn[G] spawn_workspace(
  group : @async.TaskGroup[G],
  manager : LspManager,
  root : @path.Path,
) -> LspWorkspace? {
  let directory = root.to_string()
  let command = moon_lsp_command(manager)
  let (child_stdin, stdin_writer) = @process.write_to_process()
  let (stdout_reader, child_stdout) = @process.read_from_process()
  // `no_wait`: the group cancels the server at teardown rather than waiting for
  // an exit that only comes once its stdin is closed.
  let process = @process.spawn(
    group,
    command,
    ["--stdio"],
    extra_env?=manager.spawn_env,
    inherit_env=manager.spawn_env is None,
    stdin=child_stdin,
    stdout=child_stdout,
    cwd=directory,
    no_wait=true,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  let client = @jsonrpc.Client::new(
    @lsp.StreamTransport::new(stdout_reader, stdin_writer, label=directory),
  )
  let session_object = @lsp.Session::new(client)
  // Forward the server's diagnostics to the webview, keyed by the file's
  // absolute path (the model URI's address) — no session, since a pooled server
  // is shared across conversations and the path is the whole address. The
  // handler runs on the client's reader task, so it only enqueues.
  session_object.on_publish_diagnostics((uri, diags) => {
    (manager.diagnostics.try_put({
      path: @uri.file_uri_path(uri),
      diagnostics: diags,
    }) catch {
      _ => false
    })
    |> ignore
  })
  // A standing reader in the pump's group, so the server's `publishDiagnostics`
  // notifications are read as they arrive — not only while a hover/symbol
  // request happens to be in flight. It shares routing with those requests, so
  // their replies still reach them; it ends when the transport closes.
  group.spawn_bg(allow_failure=true, () => client.run_message_pump())
  // A failed handshake is non-fatal: later requests simply return nothing.
  session_object.initialize(root_uri=@uri.file_uri(directory)) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
  Some({
    session: session_object,
    root: directory,
    process,
    stdin: stdin_writer,
    stdout: stdout_reader,
    synced: {},
  })
}

///|
/// Read a workspace file as text. `None` for an unreadable or non-UTF-8 (binary)
/// file, which has no meaningful hover anyway.
async fn read_text(file : @path.Path) -> String? {
  let data = @fs.read_file(file.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  Some(data.text()) catch {
    _ => None
  }
}

///|
/// An empty hover reply — "nothing to show here".
fn no_hover() -> LspHoverReply {
  {
    value: "",
    markdown: false,
    has_range: false,
    start_line: 0,
    start_character: 0,
    end_line: 0,
    end_character: 0,
  }
}

///|
/// Normalize an LSP hover result into the flat reply the front-end consumes.
/// `None`, an empty value, or an unrecognized shape all collapse to `no_hover`.
fn parse_hover(hover : Json?) -> LspHoverReply {
  guard hover is Some(json) else { return no_hover() }
  let (value, markdown) = parse_contents(json)
  guard !value.is_empty() else { return no_hover() }
  match parse_range(json) {
    Some((start_line, start_character, end_line, end_character)) =>
      {
        value,
        markdown,
        has_range: true,
        start_line,
        start_character,
        end_line,
        end_character,
      }
    None =>
      {
        value,
        markdown,
        has_range: false,
        start_line: 0,
        start_character: 0,
        end_line: 0,
        end_character: 0,
      }
  }
}

///|
/// Extract the hover text and whether it is markdown from an LSP `Hover`'s
/// `contents`, which may be a `MarkupContent`, a `MarkedString` (plain or
/// `{language, value}`), or an array of those.
fn parse_contents(hover : Json) -> (String, Bool) {
  guard hover is { "contents": contents, .. } else { return ("", false) }
  match contents {
    { "kind": String(kind), "value": String(value), .. } =>
      (value, kind == "markdown")
    { "value": String(value), .. } => (value, false)
    String(value) => (value, false)
    [first, ..] =>
      match first {
        { "value": String(value), .. } => (value, false)
        String(value) => (value, false)
        _ => ("", false)
      }
    _ => ("", false)
  }
}

///|
/// Extract the hover's optional range (the symbol the tooltip describes).
fn parse_range(hover : Json) -> (Int, Int, Int, Int)? {
  guard hover
    is {
      "range": {
        "start": {
          "line": Number(start_line, ..),
          "character": Number(start_character, ..),
          ..
        },
        "end": {
          "line": Number(end_line, ..),
          "character": Number(end_character, ..),
          ..
        },
        ..
      },
      ..
    } else {
    return None
  }
  Some(
    (
      start_line.to_int(),
      start_character.to_int(),
      end_line.to_int(),
      end_character.to_int(),
    ),
  )
}
