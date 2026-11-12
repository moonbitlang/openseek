// Connect configured MCP servers and keep what each offers: the catalog that
// scripts search and call through the tools SDK's `mcp` package. Nothing here
// becomes an agent tool; the host routes calls by server and tool name.

///|
/// Cap on a single tool result's JSON-encoded length, so a large MCP payload
/// cannot blow up the context. Results reach scripts through the MCP host,
/// whose replies are limited to 64K characters once serialized (`mcp/host`
/// replaces a larger reply with an error after the call already ran).
/// Bounding the escaped text below that, with room for the reply envelope and
/// the truncation note, keeps every accepted result deliverable; the tail is
/// dropped with a note.
const MaxToolOutputChars : Int32 = 60000

///|
/// The deadline for a connected server to answer `tools/list` (including
/// pagination), so a wedged server delays the script that reached it instead
/// of hanging it.
const DefaultDiscoveryTimeoutMs : Int32 = 30000

///|
/// The deadline for one proxied `tools/call`: a wedged-but-alive server becomes
/// a tool error instead of parking the turn forever (matching the repo rule that
/// every hang-capable tool call is bounded, like the shell's).
const CallTimeoutMs : Int32 = 120000

///|
/// How long a script's call or search waits for a server that is still
/// connecting. A server may never settle (a headers helper waiting on the
/// user has no deadline), so the wait is bounded. A call's wait counts
/// against its `CallTimeoutMs`, which keeps every reply within the SDK's
/// 125-second request deadline; a listing request waits for nothing else,
/// so a search's wait alone stays within it.
const ConnectWaitMs : Int32 = 60000

///|
/// Cap on one tool's description in the catalog, so a misbehaving server
/// cannot crowd the pages a script renders.
const MaxDescriptionChars : Int32 = 1024

///|
/// Cap on one serialized schema in the catalog. With the other caps it bounds
/// an item well below an MCP host reply, which carries at least one whole
/// item.
const MaxSchemaChars : Int32 = 16384

///|
/// Cap on a server's instructions or error in the catalog.
const MaxServerTextChars : Int32 = 4000

///|
/// What connecting one configured server came to.
pub enum Connection {
  /// Connected and offering tools, through this client. The client stays open
  /// for as long as the scope lives, so it also says whether the connection
  /// has been lost since.
  Live(@mcp.McpClient)
  /// Connected, offered no tools, and was released.
  NoTools
  /// It could not be started, reached, or asked for its tools; the text says
  /// which and why.
  Failed(String)
}

///|
/// One configured server with what connecting to it came to, the instructions
/// it sent, and the tools it offers under its own names (empty unless the
/// connection is `Live`).
pub struct ServerEntry {
  server : @config.McpServer
  connection : Connection
  instructions : String?
  tools : Array[@mcp.McpTool]
}

///|
/// One configured server and the task that connects it in the background (see
/// `start`), whose result is what connecting came to. It has no task until a
/// script first reaches it.
pub struct Server {
  config : @config.McpServer
  priv mut connecting : @async.Task[ServerEntry]?
  priv connect : () -> @async.Task[ServerEntry]
}

///|
/// The configured servers, in config order, each connecting in a task of its
/// own on `scope`'s group once a script first reaches it (see `settle` and
/// `Server::call`); none connects here. A server that never settles (a stuck
/// headers helper, say) holds back only its own task, which ends with the
/// group. Every failure
/// a task returns is also reported as the event it always was. The
/// connections' reader/writer tasks run on `scope`'s group and live until it
/// ends. `on_change` runs each time what `try_wait` reads may have changed — a
/// server started connecting or settled, or a connected server's connection
/// closed — and must not block.
pub fn start(
  scope : @agent_runtime.AgentTaskScope,
  servers : Array[@config.McpServer],
  client_name~ : String,
  client_version~ : String,
  workspace_root? : String,
  discovery_timeout_ms~ : Int32 = DefaultDiscoveryTimeoutMs,
  on_change? : () -> Unit,
) -> Array[Server] {
  servers.map(server => {
    config: server,
    connecting: None,
    connect: () => {
      let task = scope
        .group()
        .spawn(no_wait=true, () => {
          let entry = connect_server(
            scope,
            server,
            client_name~,
            client_version~,
            workspace_root?,
            discovery_timeout_ms~,
          )
          if on_change is Some(on_change) {
            // The close handler goes on first, so a connection that closes
            // from here on reports itself, and one already closed shows as
            // lost.
            if entry.connection is Live(client) {
              client.set_close_handler(on_change)
            }
            on_change()
          }
          entry
        })
      if on_change is Some(on_change) {
        on_change()
      }
      task
    },
  })
}

///|
/// The task connecting this server, started now if it has not been.
fn Server::task(self : Server) -> @async.Task[ServerEntry] {
  match self.connecting {
    Some(task) => task
    None => {
      let task = (self.connect)()
      self.connecting = Some(task)
      task
    }
  }
}

///|
/// Whether this server has started connecting, which it does when a script
/// first reaches it.
pub fn Server::started(self : Server) -> Bool {
  self.connecting is Some(_)
}

///|
/// What connecting this server came to, or `None` while it has not started or
/// is still connecting, as `Task::try_wait` reads its task — except that a
/// task cancelled with its group, which only happens as the engine shuts down,
/// reads as `None` rather than raising.
pub fn Server::try_wait(self : Server) -> ServerEntry? {
  guard self.connecting is Some(task) else { return None }
  task.try_wait() catch {
    _ => None
  }
}

///|
/// What connecting this server comes to, starting it first if it has not
/// started. Cancellation propagates.
pub async fn Server::settled(self : Server) -> ServerEntry {
  self.task().wait()
}

///|
/// What connecting this server came to, starting it first if it has not
/// started, and waiting up to `timeout_ms` for it to settle: `None` when it is
/// still connecting by then.
async fn Server::wait(self : Server, timeout_ms~ : Int32) -> ServerEntry? {
  let task = self.task()
  @async.with_timeout_opt(timeout_ms, () => task.wait())
}

///|
/// Wait until the servers a search needs have settled: the one named
/// `server`, or every server when none is named (one not configured needs
/// nothing), starting any of them that has not started. The wait ends after
/// `timeout_ms` whatever is left; a server still connecting then is listed as
/// such.
pub async fn settle(
  servers : Array[Server],
  server? : String,
  timeout_ms~ : Int32 = ConnectWaitMs,
) -> Unit {
  let waiting = servers.filter(configured => {
    match server {
      Some(name) => name == configured.config.name()
      None => true
    }
  })
  let tasks = waiting.map(configured => configured.task())
  ignore(
    @async.with_timeout_opt(timeout_ms, () => {
      for task in tasks {
        ignore(task.wait())
      }
    }),
  )
}

///|
/// Call `tool` of this server, as `ServerEntry::call` does, once it has
/// settled, starting it first if it has not started. A
/// server still connecting is waited for up to `wait_ms`, and is an
/// error result saying so when it has not settled by then. The wait counts
/// against the call's deadline.
pub async fn Server::call(
  self : Server,
  tool : String,
  arguments : Json,
  wait_ms~ : Int32 = ConnectWaitMs,
) -> @agent_tool.ToolAction {
  let started = @async.now()
  guard self.wait(timeout_ms=wait_ms) is Some(entry) else {
    let (message, _) = cap_serialized(
      "MCP server `\{self.config.name()}` is still connecting after \{wait_ms / 1000}s; try again later",
      MaxToolOutputChars,
    )
    @agent_tool.respond(message, is_error=true)
  }
  let waited = (@async.now() - started).to_int()
  entry.call(tool, arguments, timeout_ms=CallTimeoutMs - waited)
}

///|
/// Call `tool` of this server. A server that is not connected, or that does
/// not offer `tool`, is an error result naming what went wrong; so is a call
/// the server fails, loses the connection on, or does not answer within
/// `timeout_ms`.
pub async fn ServerEntry::call(
  self : ServerEntry,
  tool : String,
  arguments : Json,
  timeout_ms~ : Int32 = CallTimeoutMs,
) -> @agent_tool.ToolAction {
  let server = self.server.name()
  match self.connection {
    Live(client) if self.tools.iter().any(offered => offered.name == tool) =>
      call_tool(client, tool, arguments, timeout_ms~)
    Live(_) => {
      let (message, _) = cap_serialized(
        "MCP server `\{server}` has no tool `\{tool}`; find its tools with `@mcp.search(server=\{Json(server).stringify()})`",
        MaxToolOutputChars,
      )
      @agent_tool.respond(message, is_error=true)
    }
    NoTools =>
      @agent_tool.respond(
        "MCP server `\{server}` offers no tools",
        is_error=true,
      )
    Failed(error) => {
      let (message, _) = cap_serialized(
        "MCP server `\{server}` is unavailable: \{error}",
        MaxToolOutputChars,
      )
      @agent_tool.respond(message, is_error=true)
    }
  }
}

///|
/// The catalog as scripts download it: each server, then its tools, in
/// configuration order. A server is `{"server", "instructions"?, "error"?}`,
/// with `error` when it failed to connect or its connection was lost; a tool
/// is `{"server", "tool": {"name", "description", "input_schema",
/// "output_schema"?}}`. Server-supplied parts are capped so any one item fits
/// an MCP host reply: descriptions, instructions, and errors are cut and marked, an
/// arguments schema that is not an object or is oversized becomes the open
/// object schema (the server still validates its arguments), and an oversized
/// result schema is dropped, since it only helps whoever reads `data`. A
/// server still connecting is listed as unavailable, saying so, until it
/// settles, and so is one that connects on demand and has not started.
pub fn catalog_items(servers : Array[Server]) -> Array[Json] {
  let items : Array[Json] = []
  for configured in servers {
    let server = configured.config.name()
    let fields : Map[String, Json] = { "server": Json(server) }
    let settled = configured.try_wait()
    let error = match settled {
      None if !configured.started() =>
        Some(
          "not connected yet; search it by name, `@mcp.search(server=\{Json(server).stringify()})`, to connect it",
        )
      None => Some("still connecting; search again from a later script")
      Some({ connection: Failed(error), .. }) => Some(error)
      Some({ connection: Live(client), .. }) if client.is_closed() =>
        Some("the connection was lost")
      Some(_) => None
    }
    match error {
      Some(error) =>
        fields["error"] = Json(cut(error, MaxServerTextChars, marked=true))
      None =>
        if settled is Some({ instructions: Some(instructions), .. }) &&
          !instructions.is_blank() {
          fields["instructions"] = Json(
            cut(instructions.trim().to_owned(), MaxServerTextChars, marked=true),
          )
        }
    }
    items.push(Json::object(fields))
    guard error is None && settled is Some(entry) else { continue }
    for tool in entry.tools {
      let record : Map[String, Json] = {
        "name": Json(tool.name),
        "description": Json(
          cut(tool.description, MaxDescriptionChars, marked=true),
        ),
        "input_schema": if tool.input_schema is Object(_) &&
          tool.input_schema.stringify().length() <= MaxSchemaChars {
          tool.input_schema
        } else {
          { "type": "object" }
        },
      }
      if tool.output_schema is Some(output) &&
        output.stringify().length() <= MaxSchemaChars {
        record["output_schema"] = output
      }
      items.push({ "server": Json(server), "tool": Json::object(record) })
    }
  }
  items
}

///|
/// `text` cut to `limit` whole characters, ending in `…` when `marked` and
/// anything was dropped.
fn cut(text : String, limit : Int32, marked~ : Bool) -> String {
  let (kept, truncated) = cap_chars(text, limit)
  if truncated && marked {
    "\{kept}…"
  } else {
    kept
  }
}

///|
/// Connect one server and return what that came to with the instructions it
/// sent and its tools — no tools on any failure (reported as an event),
/// including discovery outrunning `discovery_timeout_ms`, so a server that
/// handshakes but never answers `tools/list` cannot hang the script waiting
/// for it.
/// Cancellation propagates.
async fn connect_server(
  scope : @agent_runtime.AgentTaskScope,
  server : @config.McpServer,
  client_name~ : String,
  client_version~ : String,
  workspace_root? : String,
  discovery_timeout_ms~ : Int32,
) -> ServerEntry {
  let name = server.name()
  fn unavailable(connection : Connection) -> ServerEntry {
    { server, connection, instructions: None, tools: [], }
  }

  // A connected server, normalized across transports: the initialized client
  // and its initialization result; closing the client tears the transport
  // (and, for stdio, the process) down.
  let (client, init) : (@mcp.McpClient, @mcp.InitializeResult) = try {
    match server {
      // A stdio server runs in the agent's workspace, not openseek's invocation
      // directory, so cwd-sensitive servers and relative args target the same
      // tree the built-in tools do.
      Stdio(command~, args~, env~, ..) => {
        let connection = @stdio.connect(
          scope.group(),
          command~,
          args~,
          env~,
          cwd?=workspace_root,
          client_name~,
          client_version~,
        )
        (connection.client(), connection.init())
      }
      Http(url~, headers~, headers_helper~, ..) => {
        // Resolve configuration before connecting. The transport receives only
        // ordinary headers; helper output overrides static keys regardless of case.
        let resolved : Map[String, String] = Map([])
        for name, value in headers {
          resolved[name.to_lower()] = value
        }
        if headers_helper is Some(helper) {
          for name, value in @headers_helper.run(helper, cwd?=workspace_root) {
            resolved[name.to_lower()] = value
          }
        }
        let connection = @streamhttp.connect(
          scope.group(),
          url~,
          headers=resolved,
          client_name~,
          client_version~,
        )
        (connection.client(), connection.init())
      }
    }
  } catch {
    error => {
      let error = "\{error}"
      @emit.emit(McpConnectFailed(server=name, error~))
      return unavailable(Failed(error))
    }
  }
  let discovered = try {
    errdefer client.close()
    @async.with_timeout(discovery_timeout_ms, () => discover(name, client))
  } catch {
    @async.TimeoutError => {
      @emit.emit(McpListToolsTimeout(server=name))
      return unavailable(Failed("timed out listing its tools"))
    }
    error => {
      let error = "\{error}"
      @emit.emit(McpListToolsFailed(server=name, error~))
      return unavailable(Failed("listing its tools failed: \{error}"))
    }
  }
  // A server with nothing to offer is useless for the rest of the session:
  // release its process and tasks instead of holding them on the scope.
  if discovered.is_empty() {
    @emit.emit(McpNoTools(server=name))
    client.close()
    return unavailable(NoTools)
  }
  {
    server,
    connection: Live(client),
    instructions: init.instructions,
    tools: discovered,
  }
}

///|
/// The tools `client` offers, in listing order, without exact repeats of one
/// name (a misbehaving server aliasing one method), which are reported and
/// skipped. Raises if the server's `tools/list` fails.
pub async fn discover(
  server : String,
  client : @mcp.McpClient,
) -> Array[@mcp.McpTool] {
  let seen : Set[String] = Set([])
  let tools = []
  for tool in client.list_tools() {
    if seen.contains(tool.name) {
      @emit.emit(McpToolDuplicate(server~, tool=tool.name))
      continue
    }
    seen.add(tool.name)
    tools.push(tool)
  }
  tools
}

///|
/// Proxy a tool call to the MCP server and map the result into a tool action:
/// the rendered text as content, image content as image input (the same way
/// `read_image` returns it), and any `structuredContent` as data.
/// A JSON-RPC / transport failure, and a call the server does not answer
/// within `timeout_ms`, becomes an error response; a tool-level failure is
/// surfaced via `is_error`.
pub async fn call_tool(
  client : @mcp.McpClient,
  tool : String,
  args : Json,
  timeout_ms~ : Int32 = CallTimeoutMs,
) -> @agent_tool.ToolAction {
  let outcome = @async.with_timeout_opt(timeout_ms, () => {
    client.call_tool(name=tool, arguments=args)
  }) catch {
    error => {
      // The assembled text carries server-supplied strings (the tool name and
      // error message): cap the whole response so it cannot bypass the
      // context-size protection.
      let (message, _) = cap_serialized(
        "MCP tool `\{tool}` call failed: \{error}",
        MaxToolOutputChars,
      )
      return @agent_tool.respond(message, is_error=true)
    }
  }
  guard outcome is Some(result) else {
    let (message, _) = cap_serialized(
      "MCP tool `\{tool}` timed out after \{timeout_ms / 1000}s",
      MaxToolOutputChars,
    )
    return @agent_tool.respond(message, is_error=true)
  }
  // The text is what a script prints for the model, so it keeps the budget. A
  // structured result also rides along as `data`, but only whole and beside
  // the text: the text renders it too, so leaving it out loses nothing a
  // reader could not find.
  let rendered = result.render()
  let (content, truncated) = cap_serialized(rendered.text, MaxToolOutputChars)
  let text = if truncated {
    "\{content}\n<system>truncated=true shown_chars=\{content.char_length()} max_output_chars=\{MaxToolOutputChars}</system>"
  } else {
    content
  }
  let data = result.structured_content.filter(value => {
    Json(text).stringify().length() + value.stringify().length() <=
    MaxToolOutputChars
  })
  @agent_tool.respond(
    text,
    images=rendered.images,
    is_error=result.is_error,
    brief=@agent_tool.brief_line(text),
    data?,
  )
}

///|
/// Truncate `text` to its longest prefix of whole characters whose JSON string
/// encoding is at most `limit` characters long, reporting whether anything was
/// dropped. Escaping (quotes, backslashes, control characters) can make the
/// encoding several times longer than the text, so the cut is searched against
/// the real encoding rather than estimated.
fn cap_serialized(text : String, limit : Int32) -> (String, Bool) {
  fn fits(prefix : String) -> Bool {
    Json(prefix).stringify().length() <= limit
  }

  if fits(text) {
    return (text, false)
  }
  // A longer prefix never encodes shorter, so the kept length is monotone.
  let mut fitting = 0
  let mut too_long = text.char_length()
  while too_long - fitting > 1 {
    let middle = fitting + (too_long - fitting) / 2
    if fits(cap_chars(text, middle).0) {
      fitting = middle
    } else {
      too_long = middle
    }
  }
  (cap_chars(text, fitting).0, true)
}

///|
/// Truncate `text` to at most `limit` whole characters (never splitting a
/// surrogate pair), reporting whether anything was dropped.
fn cap_chars(text : String, limit : Int32) -> (String, Bool) {
  let kept = StringBuilder()
  for ch in text; count = 0 {
    if count >= limit {
      return (kept.to_string(), true)
    }
    kept.write_char(ch)
    continue count + 1
  }
  (kept.to_string(), false)
}
