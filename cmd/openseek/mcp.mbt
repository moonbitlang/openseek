// Resolve the configured MCP servers into agent tools. Any problem — no config,
// an unreadable file, malformed JSON, a bad config shape, a server that fails to
// start — yields no tools and is logged, so MCP never breaks a session; the
// engine simply runs with its built-in tools.

///|
/// The client version openseek advertises to MCP servers in the handshake.
const McpClientVersion : String = "0.2.2"

///|
/// The `--mcp-config` path, or "" when unset.
fn mcp_config_path(matches : @argparse.Matches) -> String {
  match matches {
    { values: { "mcp-config": [path, ..], .. }, .. } => path
    _ => ""
  }
}

///|
/// Build the agent tools contributed by the configured MCP servers. `[]` when no
/// config is set or on any failure (logged). The connections' reader/writer
/// tasks run on `scope`'s group.
async fn[X] resolve_mcp_tools(
  matches : @argparse.Matches,
  scope : @agent_runtime.AgentTaskScope[X],
  workspace_root~ : String,
) -> Array[@agent_tool.AgentToolDefinition] {
  let path = mcp_config_path(matches)
  if path == "" {
    return []
  }
  let text = @fs.read_file(path).text() catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      @emit.emit(McpConfigUnreadable(path~, error="\{error}"))
      return []
    }
  }
  let servers = @mcpconfig.decode(@json.parse(text)) catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      @emit.emit(McpConfigInvalid(path~, error="\{error}"))
      return []
    }
  }
  let tools = @mcptools.build(
    scope,
    servers,
    client_name="openseek",
    client_version=McpClientVersion,
    workspace_root~,
  )
  @emit.emit(
    McpToolsRegistered(
      servers=servers.length(),
      tools=tools.length(),
      names=[ for tool in tools => tool.name ],
    ),
  )
  tools
}

///|
/// `openseek mcp` — build the MCP tool registry exactly as a session would
/// (one combined build, so cross-server renames and the global tool budget
/// match a real run) and print it grouped by server, so a user can validate an
/// mcp.json without starting a session. A missing, unreadable, or invalid
/// configuration raises, exiting nonzero — the command is usable as a
/// validation gate. Stdout carries only the summary, so the command never opens
/// the event sink and an event the tool build reports is dropped.
async fn run_mcp_command(matches : @argparse.Matches) -> Unit {
  let path = mcp_config_path(matches)
  if path == "" {
    fail(
      "no MCP configuration: pass --mcp-config <file> (or OPENSEEK_MCP_CONFIG)",
    )
  }
  let workspace_root = prepare_workspace_root(matches, log_created=false)
  // Failure text reaches the terminal via stderr, and both the path and the
  // decoder's error can embed configuration strings: keep them terminal-safe.
  let text = @fs.read_file(path).text() catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      fail(
        "cannot read \{@cli.terminal_safe_line(path, limit=200)}: \{@cli.terminal_safe_line("\{error}", limit=200)}",
      )
  }
  let servers = @mcpconfig.decode(@json.parse(text)) catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      fail(
        "invalid MCP configuration in \{@cli.terminal_safe_line(path, limit=200)}: \{@cli.terminal_safe_line("\{error}", limit=200)}",
      )
  }
  // The path is CLI input: guard it like every other displayed string (a
  // longer cap than the metadata's, so real paths stay identifiable).
  let shown_path = @cli.terminal_safe_line(path, limit=200)
  if servers.is_empty() {
    println("\{shown_path}: no servers configured")
    return
  }
  println("\{shown_path}: \{servers.length()} server(s)")
  @async.with_task_group() <| group => {
    let scope = @agent_runtime.AgentTaskScope(group)
    // One combined, grouped build, exactly as serve/run register tools:
    // cross-server renames and the global tool budget behave as in a real
    // session, and ownership comes from the build itself.
    let labels : Map[String, String] = Map([])
    for server in servers {
      labels[server.name()] = server_label(server)
    }
    for
      entry in @mcptools.build_grouped(
        scope,
        servers,
        client_name="openseek",
        client_version=McpClientVersion,
        workspace_root~,
      ) {
      let (name, tools) = entry
      let label = labels.get(name).unwrap_or("")
      // The name is a config key — arbitrary JSON text — so guard it like the
      // rest of the displayed metadata.
      let name = @cli.terminal_safe_line(name)
      if tools.is_empty() {
        // Neutral: an empty group can be a failed connection, a tools-less
        // (e.g. resources-only) server, or one skipped over the tool budget.
        println("- \{name} (\{label}): no tools registered")
      } else {
        println("- \{name} (\{label}): \{tools.length()} tool(s)")
        for tool in tools {
          // Descriptions are server-controlled: strip control characters so a
          // hostile server cannot inject terminal escape sequences (tool names
          // are already sanitized to the provider alphabet by the bridge).
          println(
            "    \{tool.name} — \{@cli.terminal_safe_line(tool.description)}",
          )
        }
      }
    }
    // The servers spawned above live on this group; returning tears them down.
    group.return_immediately(())
  }
}

///|
/// A display label for a configured server. HTTP endpoints are shown without
/// userinfo or query string — both commonly carry credentials.
fn server_label(server : @mcpconfig.McpServer) -> String {
  match server {
    // Arguments are not echoed: they can carry credentials (`--token …`) and
    // arbitrary control characters. The command plus an argument count
    // identifies the entry without leaking its values.
    Stdio(command~, args~, ..) =>
      if args.is_empty() {
        "stdio: \{@cli.terminal_safe_line(command)}"
      } else {
        "stdio: \{@cli.terminal_safe_line(command)} [\{args.length()} arg(s)]"
      }
    Http(url~, ..) => "http: \{@cli.terminal_safe_line(redact_url(url))}"
  }
}

///|
/// Strip userinfo (`user:pass@`) and the query/fragment from `url`, keeping
/// scheme, host, and path — enough to identify the endpoint without echoing
/// embedded credentials.
fn redact_url(url : String) -> String {
  // Cut at the first `?` or `#`, then locate the authority after the FIRST
  // `://` anywhere — matching the decoder's leniency and staying fail-closed
  // for malformed values like `/https://user:secret@host` — and drop a
  // `userinfo@` that precedes any `/` in what follows. The userinfo arm is
  // start-anchored on purpose: an unanchored lexmatch arm SEARCHES, and would
  // redact an `@` sitting in the path.
  let kept = if url =~ (re"[?#]", before~, after=_) { before } else { url }
  let (prefix, rest) = if kept =~ (re"://", before~, after~) {
    ("\{before}://", after)
  } else {
    ("", kept)
  }
  lexmatch rest {
    re"^[^/@]*@" + (re"(.|\n)*$" as tail) => "\{prefix}\{tail}"
    _ => "\{prefix}\{rest}"
  }
}
