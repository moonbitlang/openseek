// Host-side LSP backing the editor side-panel — hover tooltips and the
// composer's `#` symbol search. A conversation's workspace may hold the module
// at its root (`<cwd>/moon.mod`) or, just as often, a project the agent created
// one level down (`<cwd>/<project>/moon.mod`); moon-lsp does not discover nested
// modules, so the host finds them and spawns one `moon-lsp --stdio` rooted at
// each. Hover routes to the server whose root contains the file; symbol search
// fans out to all of them. Everything is best-effort — no module yet, a failed
// spawn, a server error, or a non-text file all just yield nothing.
//
// The set of servers is re-detected on each request, so a project created mid
// conversation is picked up (and one whose module moved is retired): a layout
// change spawns the new roots and closes the gone ones. A moon-lsp process must
// outlive the individual request that first needs it, so — mirroring the engine
// pump — it is owned by the long-lived task group of the `connect` op, not a
// per-request one: `ensure_workspaces` hands each spawn to that group's LSP pump
// over a queue and waits for the server back. Retiring a server closes the
// host's stdin end (EOF, so moon-lsp exits) and cancels the process; dropping
// the `connect` group tears every server down with it.

///|
/// The largest number of `moon-lsp` servers one conversation may run at once.
/// A workspace rarely holds more than a couple of modules; the cap only matters
/// for a pathological tree (a folder of sample projects), where the most
/// recently modified modules win the slots.
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
/// Lazily-started `moon-lsp` instances, keyed by conversation session id — a
/// conversation can run several when its workspace holds several modules.
priv struct LspManager {
  // The engine executable, anchoring the bundled-toolchain lookup for `moon-lsp`.
  engine : String
  runtime_dir : @path.Path?
  // The resolved `moon-lsp` to spawn, computed once on first use; "" until then.
  mut command : String
  workspaces : Map[String, Array[LspWorkspace]]
  // Serializes server reconciliation so two concurrent requests don't spawn two
  // servers for the same root.
  create_lock : @semaphore.Semaphore
  // Spawn requests from per-request ops to the LSP pump, which owns the moon-lsp
  // processes in the `connect` op's long-lived task group.
  commands : @async.Queue[LspCommand]
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
    workspaces: {},
    create_lock: Semaphore(1, initial_value=1),
    commands: Queue(kind=Unbounded),
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
    manager.workspaces.clear()
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
    path.to_string()
  } else {
    "moon-lsp"
  }
  manager.command = command
  command
}

///|
/// Resolve the file under the conversation's workspace, ensure its server is
/// running, sync the file if its text changed, and request hover.
async fn lsp_hover_op(
  manager : LspManager,
  payload : LspHoverPayload,
) -> LspHoverReply {
  guard @engine.resolve_in_workspace(
      payload.session,
      payload.path,
      workspace?=payload.workspace,
    )
    is Some(file) else {
    raise HostError("path is outside the conversation workspace")
  }
  let servers = ensure_workspaces(
    manager,
    payload.session,
    workspace?=payload.workspace,
  )
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
  for
    workspace in ensure_workspaces(
      manager,
      payload.session,
      workspace?=payload.workspace,
    ) {
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
    let kind = match fields.get("kind") {
      Some(Number(value, ..)) => value.to_int()
      _ => 0
    }
    let container = match fields.get("containerName") {
      Some(String(value)) => value
      _ => ""
    }
    symbols.push({
      name,
      kind,
      container,
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
/// server should not return such, but be safe) keeps its absolute path. Both
/// sides compare with forward slashes so a Windows workspace path matches the
/// URI-derived one.
fn workspace_relative(uri : String, workspace_dir : String) -> String {
  let path = @uri.file_uri_path(uri)
  let root = workspace_dir.replace_all(old="\\", new="/")
  let prefix = root + "/"
  if path.has_prefix(prefix) {
    path.view(start_offset=prefix.length()).to_owned()
  } else if path == root {
    ""
  } else {
    path
  }
}

///|
/// The conversation's language servers, reconciled against the workspace's
/// current module layout: a server is spawned for each module that lacks one
/// and retired for each that has gone. Returns the live set (empty when the
/// workspace holds no module yet — the caller waits rather than rooting a
/// server at a non-project directory).
async fn ensure_workspaces(
  manager : LspManager,
  session : String,
  workspace? : String,
) -> Array[LspWorkspace] {
  guard @engine.resolve_in_workspace(session, "", workspace?) is Some(dir) else {
    return []
  }
  // The workspace directory is created on a conversation's first run; before
  // then there is nothing to analyze.
  guard @fs.exists(dir.to_string()) else { return [] }
  let roots = lsp_roots(dir)
  manager.create_lock.acquire()
  defer manager.create_lock.release()
  let existing = match manager.workspaces.get(session) {
    Some(servers) => servers
    None => []
  }
  // Keep the servers whose root is still wanted; close the rest.
  let live : Array[LspWorkspace] = []
  for workspace in existing {
    if roots_contains(roots, workspace.root) {
      live.push(workspace)
    } else {
      close_workspace(workspace)
    }
  }
  // Spawn a server for each newly wanted root — via the pump, so the process is
  // owned by the connect op's task group and outlives this request. With no pump
  // running (the webview never called `connect`) there is nothing to analyze
  // against anyway, so skip rather than block on a spawn no one will service.
  for root in roots {
    if !servers_has_root(live, root.to_string()) && manager.pump_running {
      let ack : @async.Queue[LspWorkspace?] = Queue(kind=Unbounded)
      manager.commands.put(SpawnWorkspace(root, ack))
      if ack.get() is Some(workspace) {
        live.push(workspace)
      }
    }
  }
  manager.workspaces.set(session, live)
  live
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
    guard file == workspace.root || file.has_prefix(workspace.root + "/") else {
      continue
    }
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
/// Whether a live server is already rooted at `root`.
fn servers_has_root(servers : Array[LspWorkspace], root : String) -> Bool {
  for workspace in servers {
    if workspace.root == root {
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
