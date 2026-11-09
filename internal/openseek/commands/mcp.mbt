///|
/// `openseek mcp` — connect the configured MCP servers exactly as a session
/// would and print what each came to, with its tools under their own names, so
/// a user can validate an mcp.json without starting a session. A missing,
/// unreadable, or invalid configuration raises, exiting nonzero — the command
/// is usable as a validation gate. Stdout carries only the summary, so the command never opens
/// the event sink and an event the tool build reports is dropped.
pub async fn run_mcp_command(matches : @argparse.Matches) -> Unit {
  let paths = @options.mcp_config_paths(matches)
  guard !paths.is_empty() else {
    fail(
      "no MCP configuration: pass --mcp-config <file> (or OPENSEEK_MCP_CONFIG)",
    )
  }
  let workspace_root = @setup.prepare_workspace_root(matches, log_created=false)
  // The path is CLI input: guard it like every other displayed string (a
  // longer cap than the metadata's, so real paths stay identifiable).
  let configs : Array[Array[@mcpconfig.McpServer]] = []
  for path in paths {
    let shown_path = @cli.terminal_safe_line(path, limit=200)
    // This command is a validation gate: a bad file exits nonzero, unlike
    // run/serve, which report the file and continue with the remaining ones.
    let text = @fs.read_file(path).text() catch {
      error =>
        fail(
          "cannot read \{shown_path}: \{@cli.terminal_safe_line("\{error}", limit=200)}",
        )
    }
    let servers = @mcpconfig.decode(@json.parse(text), env=@env.get_env_vars()) catch {
      error =>
        fail(
          "invalid MCP configuration in \{shown_path}: \{@cli.terminal_safe_line("\{error}", limit=200)}",
        )
    }
    configs.push(servers)
  }
  let servers = @mcpconfig.merge(configs)
  let shown_path = paths
    .map(path => @cli.terminal_safe_line(path, limit=200))
    .join(", ")
  if servers.is_empty() {
    println("\{shown_path}: no servers configured")
    return
  }
  println("\{shown_path}: \{servers.length()} server(s)")
  @async.with_task_group() <| group => {
    let scope = @agent_runtime.AgentTaskScope(group)
    // Connect exactly as serve/run do, so what is printed is what a script's
    // `@mcp.search` would find.
    let entries = @mcptools.connect(
      scope,
      servers,
      client_name="openseek",
      client_version=@execution.McpClientVersion,
      workspace_root~,
    )
    for entry in entries {
      let label = server_label(entry.server)
      // The name is a config key — arbitrary JSON text — so guard it like the
      // rest of the displayed metadata.
      let name = @cli.terminal_safe_line(entry.server.name())
      match entry.connection {
        Failed(error) =>
          println(
            "- \{name} (\{label}): unavailable: \{@cli.terminal_safe_line(error, limit=200)}",
          )
        NoTools => println("- \{name} (\{label}): no tools")
        Live(_) => {
          println("- \{name} (\{label}): \{entry.tools.length()} tool(s)")
          for tool in entry.tools {
            // Names and descriptions are server-controlled: strip control
            // characters so a hostile server cannot inject terminal escape
            // sequences.
            println(
              "    \{@cli.terminal_safe_line(tool.name)} — \{@cli.terminal_safe_line(tool.description)}",
            )
          }
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
    Http(..) => "http: \{@cli.terminal_safe_line(server.target())}"
  }
}
