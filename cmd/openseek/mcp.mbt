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
      @xlog.warn() <?
        { "event": "mcp_config_unreadable", "path": path, "error": "\{error}" }
      return []
    }
  }
  let servers = @mcpconfig.decode(@json.parse(text)) catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      @xlog.warn() <?
        { "event": "mcp_config_invalid", "path": path, "error": "\{error}" }
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
  @xlog.info() <?
    {
      "event": "mcp_tools_registered",
      "servers": servers.length(),
      "tools": tools.length(),
      "names": [
        for tool in tools => Json::string(tool.name)
      ],
    }
  tools
}

///|
/// `openseek mcp` — build the MCP tool registry exactly as a session would
/// (one combined build, so cross-server renames and the global tool budget
/// match a real run) and print it grouped by server, so a user can validate an
/// mcp.json without starting a session. A missing, unreadable, or invalid
/// configuration raises, exiting nonzero — the command is usable as a
/// validation gate. Logs are discarded: stdout carries only the summary.
async fn run_mcp_command(matches : @argparse.Matches) -> Unit {
  @xlog.global().set_handler(DiscardLog::{  })
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
        "cannot read \{terminal_safe_line(path, limit=200)}: \{terminal_safe_line("\{error}", limit=200)}",
      )
  }
  let servers = @mcpconfig.decode(@json.parse(text)) catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      fail(
        "invalid MCP configuration in \{terminal_safe_line(path, limit=200)}: \{terminal_safe_line("\{error}", limit=200)}",
      )
  }
  // The path is CLI input: guard it like every other displayed string (a
  // longer cap than the metadata's, so real paths stay identifiable).
  let shown_path = terminal_safe_line(path, limit=200)
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
      let name = terminal_safe_line(name)
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
            "    \{tool.name} — \{terminal_safe_line(tool.description)}",
          )
        }
      }
    }
    // The servers spawned above live on this group; returning tears them down.
    group.return_immediately(())
  }
}

///|
/// Collapse untrusted text to one terminal-safe line: whitespace runs become a
/// single space, C0/C1 controls and DEL are dropped (ESC, CSI, OSC and friends
/// render as terminal commands, not text — same rule as the sessions listing's
/// prompt labels), and anything past 72 characters is elided with `…`.
fn terminal_safe_line(text : String, limit? : Int = 72) -> String {
  let out = StringBuilder()
  for ch in text.trim(); last_was_space = false, count = 0 {
    if count >= limit {
      out.write_char('…')
      break
    }
    if ch is (' ' | '\t' | '\n' | '\r') {
      if !last_was_space {
        out.write_char(' ')
        continue true, count + 1
      }
      continue true, count
    } else if ch.to_int() < 0x20 ||
      ch.to_int() == 0x7F ||
      (ch.to_int() >= 0x80 && ch.to_int() <= 0x9F) {
      continue last_was_space, count
    } else {
      out.write_char(ch)
      continue false, count + 1
    }
  }
  out.to_string()
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
        "stdio: \{terminal_safe_line(command)}"
      } else {
        "stdio: \{terminal_safe_line(command)} [\{args.length()} arg(s)]"
      }
    Http(url~, ..) => "http: \{terminal_safe_line(redact_url(url))}"
  }
}

///|
/// Strip userinfo (`user:pass@`) and the query/fragment from `url`, keeping
/// scheme, host, and path — enough to identify the endpoint without echoing
/// embedded credentials.
fn redact_url(url : String) -> String {
  let cut_query = match url.find("?") {
    Some(q) => url[:q].to_owned()
    None => url
  }
  let cut_fragment = match cut_query.find("#") {
    Some(h) => cut_query[:h].to_owned()
    None => cut_query
  }
  // The authority starts after `://` when a scheme is present, else at the
  // string's start — a schemeless `user:pass@host/…` (which the decoder
  // accepts) must be redacted too.
  let host_start = match cut_fragment.find("://") {
    Some(scheme_end) => scheme_end + 3
    None => 0
  }
  let authority_end = match cut_fragment[host_start:].find("/") {
    Some(slash) => host_start + slash
    None => cut_fragment.length()
  }
  match cut_fragment[host_start:authority_end].find("@") {
    Some(at) =>
      cut_fragment[:host_start].to_owned() +
      cut_fragment[host_start + at + 1:].to_owned()
    None => cut_fragment
  }
}
