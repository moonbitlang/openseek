///|
async test "multiple MCP files merge before connecting and bad files do not hide valid tools" {
  let directory = @fs.tmpdir(prefix="openseek-mcp-merge-")
  defer @fs.rmdir(directory, recursive=true)
  let first = directory + "/first.json"
  let second = directory + "/second.json"
  let broken = directory + "/broken.json"
  let missing = directory + "/missing.json"
  @emit.open()
  defer @emit.close()
  let discovered : Array[String] = []
  @async.with_timeout(10000, () => {
    @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      group.spawn_bg(no_wait=true, () => {
        server.run_forever(
          (request, body, conn) => {
            let message = @json.parse(body.read_all().text())
            guard message is { "id": id, "method": String(method_), .. } else {
              conn.send_response(202, "Accepted")
              return
            }
            let result : Json = match method_ {
              "server/discover" => {
                discovered.push(request.path)
                {
                  "resultType": "complete",
                  "supportedVersions": ["2026-07-28"],
                  "_meta": {
                    "io.modelcontextprotocol/serverInfo": {
                      "name": "test",
                      "version": "1",
                    },
                  },
                  "capabilities": { "tools": {} },
                }
              }
              "tools/list" =>
                {
                  "tools": [
                    {
                      "name": "echo",
                      "description": "Echo",
                      "inputSchema": { "type": "object" },
                    },
                  ],
                }
              _ => {}
            }
            conn.send_response(200, "OK", extra_headers={
              "Content-Type": "application/json",
            })
            let response : Json = {
              "jsonrpc": "2.0",
              "id": id,
              "result": result,
            }
            conn.write(response.stringify())
          },
          max_connections=8,
          allow_failure=true,
        )
      })
      let base = "http://127.0.0.1:\{server.addr.port()}"
      let earlier : Json = {
        "mcpServers": {
          "seekmoon": { "url": base + "/overridden" },
          "extra": { "url": base + "/extra" },
        },
      }
      let later : Json = {
        "mcpServers": { "seekmoon": { "url": base + "/selected" } },
      }
      @fs.write_file(first, earlier.stringify())
      @fs.write_file(second, later.stringify())
      @fs.write_file(broken, "invalid JSON")
      let mcp = @execution.connect_mcp(
        AgentTaskScope(group),
        [first, broken, missing, second],
        workspace_root=directory,
      )
      let tools = @execution.build_extra_tools(
        mcp,
        model=Deepseek(V4Pro),
        api_key="test",
        api_url=base,
      )
      let events : Array[Json] = []
      while @emit.poll_line() is Some(line) {
        events.push(@json.parse(line))
      }
      assert_eq(
        tools.length(),
        2,
        msg=events.map(event => event.stringify()).join("\n"),
      )
      assert_true(
        events.any(event => {
          event is { "event": "mcp_config_invalid", "path": String(path), .. } &&
          path == broken
        }),
      )
      assert_true(
        events.any(event => {
          event
          is { "event": "mcp_config_unreadable", "path": String(path), .. } &&
          path == missing
        }),
      )
      assert_true(tools.any(tool => tool.name == "mcp__seekmoon__echo"))
      assert_true(tools.any(tool => tool.name == "mcp__extra__echo"))
      assert_eq(discovered.length(), 2)
      assert_true(discovered.contains("/selected"))
      assert_true(discovered.contains("/extra"))
      assert_false(discovered.contains("/overridden"))
      // The status reports every file in order, and the merged servers.
      let status = mcp.status()
      guard status.configs
        is [
          { path: p1, state: Loaded, },
          { path: p2, state: Failed(_), },
          { path: p3, state: Failed(_), },
          { path: p4, state: Loaded, },
        ] else {
        fail("expected each file's outcome in order")
      }
      assert_eq([p1, p2, p3, p4], [first, broken, missing, second])
      guard status.servers
        is [
          { name: "seekmoon", transport: Http, state: Connected(t1), .. },
          { name: "extra", transport: Http, state: Connected(t2), .. },
        ] else {
        fail("expected the merged servers in configuration order")
      }
      assert_eq(t1.map(tool => tool.name), ["mcp__seekmoon__echo"])
      assert_eq(t2.map(tool => tool.name), ["mcp__extra__echo"])
      // Failed inputs alone must not publish a successful registration.
      // In particular, retain the original single-file event contract.
      for paths in [[broken], [broken, missing]] {
        let failed = @execution.connect_mcp(
          AgentTaskScope(group),
          paths,
          workspace_root=directory,
        )
        assert_true(failed.status().servers is [])
        assert_eq(failed.status().configs.length(), paths.length())
        let failed_tools = @execution.build_extra_tools(
          failed,
          model=Deepseek(V4Pro),
          api_key="test",
          api_url=base,
        )
        assert_eq(failed_tools.length(), 0)
        let mut failures = 0
        while @emit.poll_line() is Some(line) {
          let event = @json.parse(line)
          assert_false(event is { "event": "mcp_tools_registered", .. })
          if event
            is { "event": "mcp_config_invalid" | "mcp_config_unreadable", .. } {
            failures += 1
          }
        }
        assert_eq(failures, paths.length())
      }
    })
  })
}

///|
async test "the MCP registry tells its owner when a connected server is lost" {
  @async.with_task_group(group => {
    let dir = @fs.tmpdir(prefix="openseek-mcp-registry-")
    defer @fs.rmdir(dir, recursive=true)
    // Offers one tool, then exits a moment later.
    let brief =
      #|read _
      #|printf '{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"legacy"}}\n'
      #|read _
      #|printf '{"jsonrpc":"2.0","id":2,"result":{"protocolVersion":"2025-11-25"}}\n'
      #|read _
      #|read _
      #|printf '{"jsonrpc":"2.0","id":3,"result":{"tools":[{"name":"ping"}]}}\n'
      #|sleep 1
    let config : Json = {
      "mcpServers": {
        "brief": { "command": "sh", "args": ["-c", Json(brief)] },
      },
    }
    let path = "\{dir}/mcp.json"
    @fs.write_file(path, config.stringify(), create_mode=CreateOrTruncate)
    let registry = @execution.connect_mcp(
      AgentTaskScope(group),
      [path],
      workspace_root=dir,
    )
    // Install, then read: a connection already gone never runs the handler.
    let closed : @async.Queue[Unit] = Queue(kind=Unbounded)
    registry.on_connection_closed(() => {
      ignore(closed.try_put(()) catch { _ => false })
    })
    guard registry.status().servers is [server] else {
      fail("the configured server should be listed")
    }
    assert_eq(server.target, "sh")
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
    guard registry.status().servers is [{ state: Lost(tools), .. }] else {
      fail("a server whose connection closed should be lost")
    }
    assert_eq([ for tool in tools => tool.name ], ["mcp__brief__ping"])
  })
}
