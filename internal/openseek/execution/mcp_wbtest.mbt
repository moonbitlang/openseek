///|
async test "the MCP registry says how the engine was configured and what came of it" {
  @async.with_task_group(group => {
    let scope = @agent_runtime.AgentTaskScope(group)
    let dir = @fs.tmpdir(prefix="openseek-mcp-registry-")
    defer @fs.rmdir(dir, recursive=true)
    // No `--mcp-config`: nothing was configured, and there are no tools.
    let unconfigured = connect_mcp(scope, workspace_root=dir)
    assert_true(unconfigured.status() is NotConfigured)
    assert_true(unconfigured.tools().is_empty())
    // A file the engine cannot use is its own state, with the error.
    let path = "\{dir}/mcp.json"
    guard connect_mcp(scope, workspace_root=dir, config_path=path).status()
      is ConfigFailed(path=missing, ..) else {
      fail("a missing file should fail to load")
    }
    assert_eq(missing, path)
    @fs.write_file(path, "{\"servers\": {}}", create_mode=CreateOrTruncate)
    guard connect_mcp(scope, workspace_root=dir, config_path=path).status()
      is ConfigFailed(error~, ..) else {
      fail("a file without `mcpServers` should fail to load")
    }
    assert_true(error.contains("mcpServers"))
    // A configured server that cannot start is listed with why, by its
    // command and never its arguments.
    @fs.write_file(
      path,
      (
        #|{"mcpServers": {"bad": {"command": "openseek-no-such-mcp-server-xyz", "args": ["--token", "secret"]}}}
      ),
      create_mode=CreateOrTruncate,
    )
    let loaded = connect_mcp(scope, workspace_root=dir, config_path=path)
    guard loaded.status() is Configured(path=config, servers=[server]) else {
      fail("the configured server should be listed")
    }
    assert_eq(config, path)
    assert_eq(server.name, "bad")
    assert_true(server.transport is Stdio)
    assert_eq(server.target, "openseek-no-such-mcp-server-xyz")
    assert_true(server.state is Failed(_))
    assert_true(loaded.tools().is_empty())
  })
}

///|
async test "the MCP registry tells its owner when a connected server is lost" {
  @async.with_task_group(group => {
    let scope = @agent_runtime.AgentTaskScope(group)
    let dir = @fs.tmpdir(prefix="openseek-mcp-registry-")
    defer @fs.rmdir(dir, recursive=true)
    // Offers one tool, then exits a moment later.
    let brief =
      #|read _
      #|printf '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25"}}\n'
      #|read _
      #|read _
      #|printf '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"ping"}]}}\n'
      #|sleep 1
    let config : Json = {
      "mcpServers": {
        "brief": { "command": "sh", "args": ["-c", Json(brief)] },
      },
    }
    let path = "\{dir}/mcp.json"
    @fs.write_file(path, config.stringify(), create_mode=CreateOrTruncate)
    let registry = connect_mcp(scope, workspace_root=dir, config_path=path)
    // Install, then read: a connection already gone never runs the handler.
    let closed : @async.Queue[Unit] = Queue(kind=Unbounded)
    registry.on_connection_closed(() => {
      ignore(closed.try_put(()) catch { _ => false })
    })
    guard registry.status() is Configured(servers=[server], ..) else {
      fail("the configured server should be listed")
    }
    match server.state {
      // Spawning is forbidden in this sandbox: skip.
      Failed(_) => {
        println("skipped: cannot spawn sh")
        return
      }
      Connected(tools) => {
        assert_eq([ for tool in tools => tool.name ], ["mcp__brief__ping"])
        @async.with_timeout(10000, () => closed.get())
      }
      _ => ()
    }
    // The tools stay registered with the model, so a lost server still lists
    // them — that is what tells it from one that never connected.
    guard registry.status()
      is Configured(servers=[{ state: Lost(tools), .. }], ..) else {
      fail("a server whose connection closed should be lost")
    }
    assert_eq([ for tool in tools => tool.name ], ["mcp__brief__ping"])
  })
}
