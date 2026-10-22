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
/// pagination), so a wedged server delays engine startup instead of hanging it.
const DefaultDiscoveryTimeoutMs : Int32 = 30000

///|
/// The deadline for one proxied `tools/call`: a wedged-but-alive server becomes
/// a tool error instead of parking the turn forever (matching the repo rule that
/// every hang-capable tool call is bounded, like the shell's).
const CallTimeoutMs : Int32 = 120000

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
/// Connect every configured server, in config order, and keep the outcome of
/// each beside the tools it offers. Every failure it returns is also reported
/// as the event it always was. The connections' reader/writer tasks run on
/// `scope`'s group and live until it ends.
pub async fn[X] connect(
  scope : @agent_runtime.AgentTaskScope[X],
  servers : Array[@config.McpServer],
  client_name~ : String,
  client_version~ : String,
  workspace_root? : String,
  discovery_timeout_ms~ : Int32 = DefaultDiscoveryTimeoutMs,
) -> Array[ServerEntry] {
  let entries : Array[ServerEntry] = []
  for server in servers {
    let (connection, instructions, tools) = connect_server(
      scope,
      server,
      client_name~,
      client_version~,
      workspace_root?,
      discovery_timeout_ms~,
    )
    entries.push({ server, connection, instructions, tools, })
  }
  entries
}

///|
/// Call `tool` of this server. A server that is not connected, or that does
/// not offer `tool`, is an error result naming what went wrong; so is a call
/// the server fails, times out, or loses the connection on.
pub async fn ServerEntry::call(
  self : ServerEntry,
  tool : String,
  arguments : Json,
) -> @agent_tool.ToolAction {
  let server = self.server.name()
  match self.connection {
    Live(client) if self.tools.iter().any(offered => offered.name == tool) =>
      call_tool(client, tool, arguments)
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
/// result schema is dropped, since it only helps whoever reads `data`.
pub fn catalog_items(entries : Array[ServerEntry]) -> Array[Json] {
  let items : Array[Json] = []
  for entry in entries {
    let server = entry.server.name()
    let fields : Map[String, Json] = { "server": Json(server) }
    let error = match entry.connection {
      Failed(error) => Some(error)
      Live(client) if client.is_closed() => Some("the connection was lost")
      Live(_) | NoTools => None
    }
    match error {
      Some(error) =>
        fields["error"] = Json(cut(error, MaxServerTextChars, marked=true))
      None =>
        if entry.instructions is Some(instructions) && !instructions.is_blank() {
          fields["instructions"] = Json(
            cut(instructions.trim().to_owned(), MaxServerTextChars, marked=true),
          )
        }
    }
    items.push(Json::object(fields))
    guard error is None else { continue }
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
/// handshakes but never answers `tools/list` cannot hang the engine's startup.
/// Cancellation propagates.
async fn[X] connect_server(
  scope : @agent_runtime.AgentTaskScope[X],
  server : @config.McpServer,
  client_name~ : String,
  client_version~ : String,
  workspace_root? : String,
  discovery_timeout_ms~ : Int32,
) -> (Connection, String?, Array[@mcp.McpTool]) {
  let name = server.name()
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
      Http(url~, headers~, ..) => {
        let connection = @streamhttp.connect(
          scope.group(),
          url~,
          headers~,
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
      return (Failed(error), None, [])
    }
  }
  let discovered = try {
    errdefer client.close()
    @async.with_timeout(discovery_timeout_ms, () => discover(name, client))
  } catch {
    @async.TimeoutError => {
      @emit.emit(McpListToolsTimeout(server=name))
      return (Failed("timed out listing its tools"), None, [])
    }
    error => {
      let error = "\{error}"
      @emit.emit(McpListToolsFailed(server=name, error~))
      return (Failed("listing its tools failed: \{error}"), None, [])
    }
  }
  // A server with nothing to offer is useless for the rest of the session:
  // release its process and tasks instead of holding them on the scope.
  if discovered.is_empty() {
    @emit.emit(McpNoTools(server=name))
    client.close()
    return (NoTools, None, [])
  }
  (Live(client), init.instructions, discovered)
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
/// A JSON-RPC / transport failure becomes an error response; a tool-level
/// failure is surfaced via `is_error`.
pub async fn call_tool(
  client : @mcp.McpClient,
  tool : String,
  args : Json,
) -> @agent_tool.ToolAction {
  let outcome = @async.with_timeout_opt(CallTimeoutMs, () => {
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
      "MCP tool `\{tool}` timed out after \{CallTimeoutMs / 1000}s",
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
