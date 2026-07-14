// Bridge configured MCP servers into the agent's tool registry: connect each
// server, discover its tools, and expose each as a namespaced
// `@agent_tool.AgentToolDefinition` whose executor proxies a `tools/call`.

///|
/// Cap on the characters of a single tool result forwarded to the model, so a
/// large MCP payload cannot blow up the context; the tail is dropped with a note.
const MaxToolOutputChars : Int = 50000

///|
/// The deadline for a connected server to answer `tools/list` (including
/// pagination), so a wedged server delays engine startup instead of hanging it.
pub const DefaultDiscoveryTimeoutMs : Int = 30000

///|
/// The deadline for one proxied `tools/call`: a wedged-but-alive server becomes
/// a tool error instead of parking the turn forever (matching the repo rule that
/// every hang-capable tool call is bounded, like the shell's).
pub const CallTimeoutMs : Int = 120000

///|
/// Cap on one tool's description forwarded to the model — every request carries
/// every description, so a misbehaving server must not inflate the context.
const MaxDescriptionChars : Int = 1024

///|
/// Cap on one tool's serialized `inputSchema`. Every request carries every
/// schema; an oversized one is replaced by the open object schema (the server
/// still validates arguments on its side) rather than poisoning every turn.
const MaxSchemaChars : Int = 16384

///|
/// Cap on the MCP tools accepted across ALL configured servers. Providers
/// accept at most 128 function definitions per request, and the built-ins plus
/// headroom must fit inside that, so the MCP budget is what remains.
const MaxTotalMcpTools : Int = 100

///|
/// Provider function-name cap: DeepSeek/Kimi function names are limited to 64
/// characters of `[A-Za-z0-9_-]`.
const MaxFunctionNameChars : Int = 64

///|
/// The namespaced, provider-safe tool name openseek exposes for `tool` from
/// server `server`: `mcp__<server>__<tool>` with every character outside the
/// provider's `[A-Za-z0-9_-]` function-name alphabet replaced by `-`, capped at
/// 64 characters. The `mcp__` prefix keeps MCP tools from colliding with
/// built-ins, and the server segment keeps two servers' identically named tools
/// distinct. (Uniqueness after sanitization is enforced by `build`.)
pub fn tool_name(server : String, tool : String) -> String {
  cap_name("mcp__\{sanitize_segment(server)}__\{sanitize_segment(tool)}")
}

///|
/// Replace every character outside the provider function-name alphabet with `-`.
fn sanitize_segment(segment : String) -> String {
  let out = StringBuilder()
  for ch in segment {
    if (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_' ||
      ch == '-' {
      out.write_char(ch)
    } else {
      out.write_char('-')
    }
  }
  out.to_string()
}

///|
/// Truncate `name` to at most `limit` characters (all-ASCII by construction).
fn cap_name(name : String, limit? : Int = MaxFunctionNameChars) -> String {
  if name.length() <= limit {
    name
  } else {
    name[:limit].to_owned()
  }
}

///|
/// A name not yet in `seen`: `name` itself, or the first `<base>-N` variant that
/// fits the provider cap. Sanitization and capping can make two distinct MCP
/// tools collide; suffixing keeps both callable instead of dropping one.
fn uniquify(seen : Map[String, Unit], name : String) -> String {
  if !seen.contains(name) {
    return name
  }
  for i = 2; ; i = i + 1 {
    let suffix = "-\{i}"
    let candidate = cap_name(name, limit=MaxFunctionNameChars - suffix.length()) +
      suffix
    if !seen.contains(candidate) {
      return candidate
    }
  }
}

///|
/// Discover `client`'s tools and wrap each as a namespaced agent tool. Raises if
/// the server's `tools/list` fails.
pub async fn tools_for_client(
  server : String,
  client : @mcp.McpClient,
) -> Array[@agent_tool.AgentToolDefinition] {
  // Skip exact repeats of one raw name (a misbehaving server aliasing one
  // method) so they cannot eat the tool budget; `build`'s suffixing stays
  // reserved for *distinct* names that collide after sanitization.
  let seen_raw : Map[String, Unit] = Map([])
  let bridged = []
  for tool in client.list_tools() {
    if seen_raw.contains(tool.name) {
      @xlog.warn() <?
        { "event": "mcp_tool_duplicate", "server": server, "tool": tool.name }
      continue
    }
    seen_raw[tool.name] = ()
    bridged.push(bridge_tool(server, client, tool))
  }
  bridged
}

///|
/// Connect every configured server and collect their tools. A server that fails
/// to start, handshake, or list its tools is logged and skipped — it never fails
/// the whole build. Duplicate namespaced names (a misbehaving server repeating a
/// tool) are skipped so the registry cannot be poisoned. The connections' reader/
/// writer tasks run on `scope`'s group and live until it ends.
pub async fn[X] build(
  scope : @agent_runtime.AgentTaskScope[X],
  servers : Array[@config.McpServer],
  client_name~ : String,
  client_version~ : String,
  workspace_root? : String,
  discovery_timeout_ms? : Int = DefaultDiscoveryTimeoutMs,
) -> Array[@agent_tool.AgentToolDefinition] {
  let tools = []
  for
    entry in build_grouped(
      scope,
      servers,
      client_name~,
      client_version~,
      workspace_root?,
      discovery_timeout_ms~,
    ) {
    let (_, contributed) = entry
    for tool in contributed {
      tools.push(tool)
    }
  }
  tools
}

///|
/// Like `build`, grouped by server in config order — each entry pairs the
/// server's name with the tools it contributed after cross-server
/// uniquification and the global budget, so a diagnostic can attribute the
/// registry without reconstructing ownership from names. Flattening the groups
/// yields exactly `build`'s registry.
pub async fn[X] build_grouped(
  scope : @agent_runtime.AgentTaskScope[X],
  servers : Array[@config.McpServer],
  client_name~ : String,
  client_version~ : String,
  workspace_root? : String,
  discovery_timeout_ms? : Int = DefaultDiscoveryTimeoutMs,
) -> Array[(String, Array[@agent_tool.AgentToolDefinition])] {
  let groups : Array[(String, Array[@agent_tool.AgentToolDefinition])] = []
  let mut total = 0
  let seen : Map[String, Unit] = Map([])
  for server in servers {
    let mine : Array[@agent_tool.AgentToolDefinition] = []
    groups.push((server.name(), mine))
    // Budget exhausted: don't launch servers whose tools could not register.
    if total >= MaxTotalMcpTools {
      @xlog.warn() <?
        { "event": "mcp_server_skipped_over_cap", "server": server.name() }
      continue
    }
    let discovered = connect_server(
      scope,
      server,
      client_name~,
      client_version~,
      workspace_root?,
      discovery_timeout_ms~,
    )
    for tool in discovered {
      // The provider accepts at most 128 function definitions per request; the
      // MCP budget leaves room for the built-ins. Beyond it, drop with a log.
      if total >= MaxTotalMcpTools {
        @xlog.warn() <?
          {
            "event": "mcp_tools_capped",
            "server": server.name(),
            "kept": MaxTotalMcpTools,
          }
        break
      }
      // Sanitization/capping can make two distinct MCP tools collide; keep both
      // callable under suffixed names rather than dropping one.
      let name = uniquify(seen, tool.name)
      if name != tool.name {
        @xlog.warn() <?
          { "event": "mcp_tool_renamed", "from": tool.name, "to": name }
      }
      seen[name] = ()
      total = total + 1
      mine.push(
        @agent_tool.AgentToolDefinition(
          name~,
          description=tool.description,
          schema=tool.schema,
          execute=tool.execute,
        ),
      )
    }
  }
  groups
}

///|
/// Connect one server and return its bridged tools, or `[]` on any failure
/// (logged) — including discovery outrunning `discovery_timeout_ms`, so a
/// server that handshakes but never answers `tools/list` cannot hang the
/// engine's startup. Cancellation propagates.
async fn[X] connect_server(
  scope : @agent_runtime.AgentTaskScope[X],
  server : @config.McpServer,
  client_name~ : String,
  client_version~ : String,
  workspace_root? : String,
  discovery_timeout_ms~ : Int,
) -> Array[@agent_tool.AgentToolDefinition] {
  let name = server.name()
  // A connected server, normalized across transports: the initialized client
  // plus its idempotent teardown.
  let connection : (@mcp.McpClient, () -> Unit)? = try {
    match server {
      // A stdio server runs in the agent's workspace, not openseek's invocation
      // directory, so cwd-sensitive servers and relative args target the same
      // tree the built-in tools do.
      @config.Stdio(command~, args~, env~, ..) =>
        @stdio.connect(
          scope.group(),
          command~,
          args~,
          env~,
          cwd?=workspace_root,
          client_name~,
          client_version~,
        ).map(conn => (conn.client(), () => conn.shutdown()))
      @config.Http(url~, headers~, ..) =>
        @streamhttp.connect(
          scope.group(),
          url~,
          headers~,
          client_name~,
          client_version~,
        ).map(conn => (conn.client(), () => conn.shutdown()))
    }
  } catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      @xlog.warn() <?
        { "event": "mcp_connect_failed", "server": name, "error": "\{error}" }
      return []
    }
  }
  guard connection is Some((client, shutdown)) else {
    @xlog.warn() <? { "event": "mcp_connect_failed", "server": name }
    return []
  }
  let discovered = @async.with_timeout_opt(discovery_timeout_ms, () => {
    tools_for_client(name, client)
  }) catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      @xlog.warn() <?
        {
          "event": "mcp_list_tools_failed",
          "server": name,
          "error": "\{error}",
        }
      shutdown()
      return []
    }
  }
  guard discovered is Some(discovered) else {
    @xlog.warn() <? { "event": "mcp_list_tools_timeout", "server": name }
    shutdown()
    return []
  }
  // A server with nothing to offer is useless for the rest of the session:
  // release its process and tasks instead of holding them on the scope.
  if discovered.is_empty() {
    @xlog.warn() <? { "event": "mcp_no_tools", "server": name }
    shutdown()
  }
  discovered
}

///|
/// Wrap one discovered MCP tool as an agent tool whose executor calls it.
fn bridge_tool(
  server : String,
  client : @mcp.McpClient,
  tool : @mcp.McpTool,
) -> @agent_tool.AgentToolDefinition {
  // Bound the model-facing description: every request carries every tool's
  // description, so an oversized one (including a fallback built from a huge
  // tool/server name) inflates each turn.
  let raw_description = if tool.description == "" {
    "Tool `\{tool.name}` from MCP server `\{server}`."
  } else {
    tool.description
  }
  let (capped, truncated) = cap_chars(raw_description, MaxDescriptionChars)
  let description = if truncated { "\{capped}…" } else { capped }
  // The provider requires `function.parameters` to be a JSON Schema object, and
  // every request carries every schema. A non-object (null/array/...) would
  // poison each turn, and an oversized one blows up the context — normalize
  // both to the open object schema (the server still validates its arguments).
  let schema = if tool.input_schema is Object(_) &&
    tool.input_schema.stringify().length() <= MaxSchemaChars {
    tool.input_schema
  } else {
    { "type": "object" }
  }
  @agent_tool.AgentToolDefinition(
    name=tool_name(server, tool.name),
    description~,
    schema=@agent_tool.JsonSchema(schema),
    execute=@agent_tool.Async(args => call_tool(client, tool.name, args)),
  )
}

///|
/// Proxy a tool call to the MCP server and map the result into a tool action.
/// A JSON-RPC / transport failure becomes an error response (rather than
/// aborting the loop); a tool-level failure is surfaced via `is_error`.
async fn call_tool(
  client : @mcp.McpClient,
  tool : String,
  args : Json,
) -> @agent_tool.ToolAction {
  let outcome = @async.with_timeout_opt(CallTimeoutMs, () => {
    client.call_tool(name=tool, arguments=args)
  }) catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      // The assembled text carries server-supplied strings (the tool name and
      // error message): cap the whole response so it cannot bypass the
      // context-size protection.
      let (message, _) = cap_chars(
        "MCP tool `\{tool}` call failed: \{error}",
        MaxToolOutputChars,
      )
      return @agent_tool.ToolAction::respond(message, is_error=true)
    }
  }
  guard outcome is Some(result) else {
    let (message, _) = cap_chars(
      "MCP tool `\{tool}` timed out after \{CallTimeoutMs / 1000}s",
      MaxToolOutputChars,
    )
    return @agent_tool.ToolAction::respond(message, is_error=true)
  }
  let (content, truncated) = cap_chars(result.render_text(), MaxToolOutputChars)
  let text = if truncated {
    "\{content}\n<system>truncated=true shown_chars=\{MaxToolOutputChars} max_output_chars=\{MaxToolOutputChars}</system>"
  } else {
    content
  }
  @agent_tool.ToolAction::respond(
    text,
    is_error=result.is_error,
    brief=@agent_tool.brief_line(text),
  )
}

///|
/// Truncate `text` to at most `limit` whole characters (never splitting a
/// surrogate pair), reporting whether anything was dropped.
fn cap_chars(text : String, limit : Int) -> (String, Bool) {
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
