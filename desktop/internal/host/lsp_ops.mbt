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
// Servers live in one app-lifetime pool actor keyed by module root, so
// conversations sharing a project share its servers. Roots are re-detected on
// each request: a project created mid conversation is picked up, one whose
// module moved is retired, and the pool caps at MaxLspServers by retiring the
// least recently used. Each pooled root is a child `LspServerActor` that owns
// its moon-lsp process, stdio, session, and synced-document state.

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
/// One request handled by a single language-server actor. Each variant owns
/// the concrete reply queue its caller expects; raw LSP JSON never crosses
/// this actor boundary.
priv enum LspServerCommand {
  Hover(String, String, Int, Int, @async.Queue[LspHoverReply])
  Open(String, String, @async.Queue[LspDiagnosticsReply])
  Symbols(String, String, @async.Queue[WorkspaceSymbolsReply])
}

///|
/// The typed result produced inside the actor after decoding one LSP reply.
priv enum LspServerResult {
  HoverResult(LspHoverReply)
  OpenResult(LspDiagnosticsReply)
  SymbolsResult(WorkspaceSymbolsReply)
}

///|
priv enum LspServerInput {
  ServerCommand(LspServerCommand)
  StopServer
}

///|
priv enum LspServerOutcome {
  ServerCompleted(LspServerResult)
  ServerStopped
}

///|
/// The handle for one module-root actor. Only immutable identity and control
/// channels leave `run`; process/session/document state stays inside it.
priv struct LspServerActor {
  root : String
  inbox : @async.Queue[LspServerCommand]
  stop : @async.Queue[Unit]
  started : @async.Queue[Bool]
  closed : Ref[Bool]
}

///|
/// Resources and mutable protocol state owned by `LspServerActor::run`.
priv struct LspServerRuntime {
  session : @lsp.Session
  process : @process.Process
  stdin : @process.WriteToProcess
  stdout : @process.ReadFromProcess
  synced : Map[String, String]
}

///|
priv struct LspSpawnConfig {
  command : String
  env : Map[String, String]?
}

///|
priv enum LspPoolCommand {
  Reconcile(String, Array[String], @async.Queue[Unit])
  Acquire(String, @async.Queue[LspServerActor?])
  Spawned(String, LspServerActor?)
  Evict(Array[String], @async.Queue[Unit])
}

///|
/// External handle for the app-lifetime LSP pool actor. The diagnostics queue
/// is a separate bounded output lane; all pool mutations go through `inbox`.
priv struct LspPoolActor {
  engine : String
  runtime_dir : @path.Path?
  inbox : @async.Queue[LspPoolCommand]
  diagnostics : @async.Queue[DiagnosticsPush]
}

///|
/// Mutable state local to `LspPoolActor::run`.
priv struct LspPoolState {
  mut spawn_config : LspSpawnConfig?
  servers : Map[String, LspServerActor]
  order : Array[String]
  pending : Map[String, Array[@async.Queue[LspServerActor?]]]
}

///|
fn LspPoolActor::new(
  engine : String,
  runtime_dir? : @path.Path,
) -> LspPoolActor {
  {
    engine,
    runtime_dir,
    inbox: Queue(kind=Blocking(64)),
    diagnostics: Queue(kind=DiscardOldest(256)),
  }
}

///|
fn LspServerActor::new(root : String) -> LspServerActor {
  {
    root,
    inbox: Queue(kind=Blocking(32)),
    stop: Queue(kind=DiscardOldest(1)),
    started: Queue(kind=Blocking(1)),
    closed: Ref(false),
  }
}

///|
async fn LspPoolActor::run(self : LspPoolActor) -> Unit {
  let state = LspPoolState::{
    spawn_config: None,
    servers: Map([]),
    order: [],
    pending: Map([]),
  }
  defer {
    state.stop_all()
    state.fail_pending_spawns()
    while (self.inbox.try_get() catch { _ => None }) is Some(command) {
      command.cancel()
    }
    self.inbox.close()
  }
  @async.with_task_group(group => {
    for ;; {
      match self.inbox.get() {
        Reconcile(dir, roots, reply) => {
          state.reconcile(dir, roots)
          ignore(reply.try_put(()) catch { _ => false })
        }
        Acquire(root, reply) => state.acquire(self, group, root, reply)
        Spawned(root, server) => state.finish_spawn(root, server)
        Evict(keep, reply) => {
          state.evict(keep)
          ignore(reply.try_put(()) catch { _ => false })
        }
      }
    }
  })
}

///|
async fn LspPoolState::resolve_spawn_config(
  self : LspPoolState,
  actor : LspPoolActor,
) -> LspSpawnConfig {
  if self.spawn_config is Some(config) {
    return config
  }
  let config = if @moonbit.bundled_moon_lsp(
      actor.engine,
      runtime_dir?=actor.runtime_dir,
    )
    is Some(path) {
    {
      command: path.to_string(),
      env: Some(@moonbit.bundled_tool_env(path.dirname())),
    }
  } else {
    { command: "moon-lsp", env: None }
  }
  self.spawn_config = Some(config)
  config
}

///|
async fn LspPoolActor::reconcile(
  self : LspPoolActor,
  dir : String,
  roots : Array[String],
) -> Unit {
  let reply : @async.Queue[Unit] = Queue(kind=Blocking(1))
  self.inbox.put(Reconcile(dir, roots, reply)) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return
  }
  reply.get() catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
}

///|
async fn LspPoolActor::acquire(
  self : LspPoolActor,
  root : String,
) -> LspServerActor? {
  let reply : @async.Queue[LspServerActor?] = Queue(kind=Blocking(1))
  self.inbox.put(Acquire(root, reply)) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  reply.get() catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }
}

///|
async fn LspPoolActor::evict(self : LspPoolActor, keep : Array[String]) -> Unit {
  let reply : @async.Queue[Unit] = Queue(kind=Blocking(1))
  self.inbox.put(Evict(keep, reply)) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return
  }
  reply.get() catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
}

///|
/// Forward the pool's bounded diagnostics output for the app lifetime.
async fn LspPoolActor::forward_diagnostics(
  self : LspPoolActor,
  emit : async (DiagnosticsPush) -> Unit,
) -> Unit {
  for ;; {
    emit(self.diagnostics.get())
  }
}

///|
fn LspPoolState::reconcile(
  self : LspPoolState,
  dir : String,
  roots : Array[String],
) -> Unit {
  let stale : Array[String] = []
  for root, _ in self.servers {
    if @pathx.contains(dir, root) && roots.search(root) is None {
      stale.push(root)
    }
  }
  for root in stale {
    self.retire(root)
  }
}

///|
async fn[G] LspPoolState::acquire(
  self : LspPoolState,
  actor : LspPoolActor,
  group : @async.TaskGroup[G],
  root : String,
  reply : @async.Queue[LspServerActor?],
) -> Unit {
  if self.servers.get(root) is Some(server) {
    if !server.closed.val {
      self.touch(root)
      ignore(reply.try_put(Some(server)) catch { _ => false })
      return
    }
    self.retire(root)
  }
  if self.pending.get(root) is Some(waiters) {
    waiters.push(reply)
    return
  }
  self.pending.set(root, [reply])
  let config = self.resolve_spawn_config(actor)
  let server = LspServerActor::new(root)
  group.spawn_bg(allow_failure=true, () => server.run(config, actor.diagnostics))
  group.spawn_bg(allow_failure=true, () => {
    let started = server.started.get() catch {
      error if @async.is_being_cancelled() => raise error
      _ => false
    }
    actor.inbox.put(Spawned(root, if started { Some(server) } else { None }))
  })
}

///|
fn LspPoolState::finish_spawn(
  self : LspPoolState,
  root : String,
  candidate : LspServerActor?,
) -> Unit {
  let waiters = self.pending.get(root).unwrap_or([])
  self.pending.remove(root)
  guard !waiters.is_empty() else {
    if candidate is Some(server) {
      server.stop()
    }
    return
  }
  let server = match candidate {
    Some(server) if !server.closed.val => {
      self.servers.set(root, server)
      self.touch(root)
      Some(server)
    }
    Some(server) => {
      server.stop()
      None
    }
    None => None
  }
  for reply in waiters {
    ignore(reply.try_put(server) catch { _ => false })
  }
}

///|
fn LspPoolState::touch(self : LspPoolState, root : String) -> Unit {
  if self.order.search(root) is Some(index) {
    self.order.remove(index) |> ignore
  }
  self.order.insert(0, root)
}

///|
fn LspPoolState::retire(self : LspPoolState, root : String) -> Unit {
  guard self.servers.get(root) is Some(server) else { return }
  server.stop()
  self.servers.remove(root)
  if self.order.search(root) is Some(index) {
    self.order.remove(index) |> ignore
  }
}

///|
fn LspPoolState::evict(self : LspPoolState, keep : Array[String]) -> Unit {
  for root in self.order.copy().rev() {
    if self.servers.length() <= MaxLspServers {
      break
    }
    if keep.search(root) is Some(_) {
      continue
    }
    self.retire(root)
  }
}

///|
fn LspPoolState::stop_all(self : LspPoolState) -> Unit {
  for _, server in self.servers {
    server.stop()
  }
  self.servers.clear()
  self.order.clear()
}

///|
fn LspPoolState::fail_pending_spawns(self : LspPoolState) -> Unit {
  for _, waiters in self.pending {
    for reply in waiters {
      ignore(reply.try_put(None) catch { _ => false })
    }
  }
  self.pending.clear()
}

///|
fn LspPoolCommand::cancel(self : LspPoolCommand) -> Unit {
  match self {
    Reconcile(_, _, reply) | Evict(_, reply) =>
      ignore(reply.try_put(()) catch { _ => false })
    Acquire(_, reply) => ignore(reply.try_put(None) catch { _ => false })
    Spawned(_, server) => if server is Some(server) { server.stop() }
  }
}

///|
fn LspServerActor::stop(self : LspServerActor) -> Unit {
  ignore(self.stop.try_put(()) catch { _ => false })
}

///|
async fn[T] LspServerActor::call(
  self : LspServerActor,
  command : LspServerCommand,
  reply : @async.Queue[T],
  fallback : T,
) -> T {
  guard !self.closed.val else { return fallback }
  self.inbox.put(command) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return fallback
  }
  reply.get() catch {
    error if @async.is_being_cancelled() => raise error
    _ => fallback
  }
}

///|
async fn LspServerActor::hover(
  self : LspServerActor,
  uri : String,
  text : String,
  line : Int,
  character : Int,
) -> LspHoverReply {
  let reply : @async.Queue[LspHoverReply] = Queue(kind=Blocking(1))
  self.call(Hover(uri, text, line, character, reply), reply, no_hover())
}

///|
async fn LspServerActor::open(
  self : LspServerActor,
  uri : String,
  text : String,
) -> LspDiagnosticsReply {
  let reply : @async.Queue[LspDiagnosticsReply] = Queue(kind=Blocking(1))
  self.call(Open(uri, text, reply), reply, { diagnostics: [] })
}

///|
async fn LspServerActor::symbols(
  self : LspServerActor,
  query : String,
  workspace_dir : String,
) -> WorkspaceSymbolsReply {
  let reply : @async.Queue[WorkspaceSymbolsReply] = Queue(kind=Blocking(1))
  self.call(Symbols(query, workspace_dir, reply), reply, { symbols: [] })
}

///|
fn LspServerCommand::reply(
  self : LspServerCommand,
  result : LspServerResult?,
) -> Unit {
  match (self, result) {
    (Hover(_, _, _, _, reply), Some(HoverResult(value))) =>
      ignore(reply.try_put(value) catch { _ => false })
    (Hover(_, _, _, _, reply), _) =>
      ignore(reply.try_put(no_hover()) catch { _ => false })
    (Open(_, _, reply), Some(OpenResult(value))) =>
      ignore(reply.try_put(value) catch { _ => false })
    (Open(_, _, reply), _) =>
      ignore(reply.try_put({ diagnostics: [] }) catch { _ => false })
    (Symbols(_, _, reply), Some(SymbolsResult(value))) =>
      ignore(reply.try_put(value) catch { _ => false })
    (Symbols(_, _, reply), _) =>
      ignore(reply.try_put({ symbols: [] }) catch { _ => false })
  }
}

///|
/// Own one moon-lsp process and its protocol state until stopped, the
/// transport closes, or the app-lifetime pool is cancelled.
async fn LspServerActor::run(
  self : LspServerActor,
  config : LspSpawnConfig,
  diagnostics : @async.Queue[DiagnosticsPush],
) -> Unit {
  let announced = Ref(false)
  defer {
    if !announced.val {
      ignore(self.started.try_put(false) catch { _ => false })
    }
    self.closed.val = true
    while (self.inbox.try_get() catch { _ => None }) is Some(command) {
      command.reply(None)
    }
    self.inbox.close()
    self.stop.close()
    self.started.close()
  }
  @async.with_task_group(group => {
    self.run_in_group(group, config, diagnostics, announced)
    group.return_immediately(())
  })
}

///|
async fn[G] LspServerActor::run_in_group(
  self : LspServerActor,
  group : @async.TaskGroup[G],
  config : LspSpawnConfig,
  diagnostics : @async.Queue[DiagnosticsPush],
  announced : Ref[Bool],
) -> Unit {
  guard self.start_runtime(group, config, diagnostics) is Some(runtime) else {
    ignore(self.started.try_put(false) catch { _ => false })
    announced.val = true
    return
  }
  defer runtime.close()
  ignore(self.started.try_put(true) catch { _ => false })
  announced.val = true
  for ;; {
    match self.next_input() {
      StopServer => return
      ServerCommand(command) => {
        let outcome : LspServerOutcome = @async.any([
          () => ServerCompleted(runtime.execute(command)),
          () => {
            self.stop.get()
            ServerStopped
          },
        ])
        match outcome {
          ServerCompleted(result) => command.reply(Some(result))
          ServerStopped => {
            command.reply(None)
            return
          }
        }
      }
    }
  }
}

///|
async fn LspServerActor::next_input(self : LspServerActor) -> LspServerInput {
  if (self.stop.try_get() catch { _ => None }) is Some(_) {
    return StopServer
  }
  @async.any([
    () => ServerCommand(self.inbox.get()),
    () => {
      self.stop.get()
      StopServer
    },
  ])
}

///|
async fn[G] LspServerActor::start_runtime(
  self : LspServerActor,
  group : @async.TaskGroup[G],
  config : LspSpawnConfig,
  diagnostics : @async.Queue[DiagnosticsPush],
) -> LspServerRuntime? {
  let (child_stdin, stdin_writer) = @process.write_to_process()
  let (stdout_reader, child_stdout) = @process.read_from_process()
  let process = @process.spawn(
    group,
    config.command,
    ["--stdio"],
    extra_env?=config.env,
    inherit_env=config.env is None,
    stdin=child_stdin,
    stdout=child_stdout,
    cwd=self.root,
    no_wait=true,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    _ => {
      stdin_writer.close()
      stdout_reader.close()
      return None
    }
  }
  let client = @jsonrpc.Client::new(
    @lsp.StreamTransport::new(stdout_reader, stdin_writer, label=self.root),
  )
  let session = @lsp.Session::new(client)
  session.on_publish_diagnostics((uri, diags) => {
    (diagnostics.try_put({
      path: @uri.file_uri_path(uri),
      diagnostics: @protocol.LspDiagnostic::array_from_wire(diags),
    }) catch {
      _ => false
    })
    |> ignore
  })
  group.spawn_bg(allow_failure=true, () => {
    client.run_message_pump() catch {
      error if @async.is_being_cancelled() => raise error
      _ => ()
    }
    ignore(self.stop.try_put(()) catch { _ => false })
  })
  session.initialize(root_uri=@uri.file_uri(self.root)) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
  Some({
    session,
    process,
    stdin: stdin_writer,
    stdout: stdout_reader,
    synced: Map([]),
  })
}

///|
async fn LspServerRuntime::execute(
  self : LspServerRuntime,
  command : LspServerCommand,
) -> LspServerResult {
  match command {
    Hover(uri, text, line, character, _) => {
      self.sync(uri, text)
      HoverResult(parse_hover(self.session.hover(uri~, line~, character~)))
    }
    Open(uri, text, _) => {
      self.sync(uri, text)
      let diagnostics = match self.session.diagnostics_for(uri~) {
        Some(raw) => @protocol.LspDiagnostic::array_from_wire(raw)
        None => []
      }
      OpenResult({ diagnostics, })
    }
    Symbols(query, workspace_dir, _) =>
      SymbolsResult(
        parse_symbols(self.session.workspace_symbols(query~), workspace_dir),
      )
  }
}

///|
/// Sync a changed document exactly once before the command that needs it.
async fn LspServerRuntime::sync(
  self : LspServerRuntime,
  uri : String,
  text : String,
) -> Unit {
  guard !(self.synced.get(uri) is Some(synced) && synced == text) else {
    return
  }
  self.session.sync_document(uri~, language_id="moonbit", text~)
  self.synced.set(uri, text)
}

///|
fn LspServerRuntime::close(self : LspServerRuntime) -> Unit {
  self.process.cancel()
  self.stdin.close()
  self.stdout.close()
}

///|
/// Route hover by the file's absolute path — the workspace it belongs to,
/// then the deepest module root within it. The path is the whole address:
/// no session is involved, so the viewer can ask about any attached file.
async fn lsp_hover_op(
  pool : LspPoolActor,
  payload : LspHoverPayload,
) -> LspHoverReply {
  guard @engine.attached_workspace_dir(payload.path) is Some(dir) else {
    raise HostError("path is outside every attached workspace")
  }
  let file : @path.Path = Path(payload.path)
  let file = file.normalize()
  let servers = ensure_servers(pool, dir)
  guard server_for_file(servers, file.to_string()) is Some(server) else {
    return no_hover()
  }
  guard read_text(file) is Some(text) else { return no_hover() }
  let uri = @uri.file_uri(file.to_string())
  server.hover(uri, text, payload.line, payload.character)
}

///|
/// Sync the file the editor just opened into its server so the server analyzes
/// it and begins publishing diagnostics, and return whatever it has already
/// reported. Routes by absolute path exactly like `hover`. Best-effort: no
/// workspace, no server, or a non-text file yields no diagnostics. Later
/// changes arrive as `diagnostics` events.
async fn lsp_open_op(
  pool : LspPoolActor,
  payload : LspOpenPayload,
) -> LspDiagnosticsReply {
  guard @engine.attached_workspace_dir(payload.path) is Some(dir) else {
    raise HostError("path is outside every attached workspace")
  }
  let file : @path.Path = Path(payload.path)
  let file = file.normalize()
  let servers = ensure_servers(pool, dir)
  guard server_for_file(servers, file.to_string()) is Some(server) else {
    return { diagnostics: [] }
  }
  guard read_text(file) is Some(text) else { return { diagnostics: [] } }
  let uri = @uri.file_uri(file.to_string())
  server.open(uri, text)
}

///|
/// Search the conversation's workspace symbol index for `query`. Resolves the
/// workspace from the session, ensures its server is running, asks moon-lsp for
/// `workspace/symbol`, and flattens the result into workspace-relative rows.
/// Best-effort: an empty query, a missing workspace, a dead server, or nothing
/// indexed all yield no symbols.
async fn workspace_symbols_op(
  pool : LspPoolActor,
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
  for server in ensure_servers(pool, dir) {
    if symbols.length() >= MaxSymbolResults {
      break
    }
    let reply = server.symbols(payload.query, workspace_dir)
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
/// missing or dead one spawns as a child actor, a pooled server under `dir` whose
/// module vanished retires, and the pool caps at MaxLspServers by retiring the
/// least recently used. Empty when the directory holds no module yet — the
/// caller waits rather than rooting a server at a non-project directory.
async fn ensure_servers(
  pool : LspPoolActor,
  dir : @path.Path,
) -> Array[LspServerActor] {
  // A conversation's directory is created on its first run; before then
  // there is nothing to analyze.
  guard @fs.exists(dir.to_string()) else { return [] }
  // Directory discovery is deliberately outside the pool actor: filesystem
  // I/O must not block unrelated acquire/retire messages.
  let roots = lsp_roots(dir).map(root => root.to_string())
  pool.reconcile(dir.to_string(), roots)
  let live : Array[LspServerActor] = []
  for root in roots {
    if pool.acquire(root) is Some(server) {
      live.push(server)
    }
  }
  pool.evict(live.map(server => server.root))
  live
}

///|
/// The server whose root contains `file`, or `None` when no module does. The
/// deepest matching root wins, so a file inside a nested module is answered by
/// that module's server rather than an ancestor's.
fn server_for_file(
  servers : Array[LspServerActor],
  file : String,
) -> LspServerActor? {
  let mut best : LspServerActor? = None
  for server in servers {
    guard @pathx.contains(server.root, file) else { continue }
    if best is Some(current) && current.root.length() >= server.root.length() {
      continue
    }
    best = Some(server)
  }
  best
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

///|
test "workspace relative strips the workspace prefix on both separators" {
  assert_eq(workspace_relative("file:///ws/src/a.mbt", "/ws"), "src/a.mbt")
  assert_eq(workspace_relative("file:///ws/a%20b.mbt", "/ws"), "a b.mbt")
  assert_eq(
    workspace_relative("file:///C:/ws/src/a.mbt", "C:\\ws"),
    "src/a.mbt",
  )
  assert_eq(workspace_relative("file:///ws", "/ws"), "")
  assert_eq(workspace_relative("file:///other/a.mbt", "/ws"), "/other/a.mbt")
}
