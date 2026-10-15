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
  let initialized : Array[String] = []
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
              "initialize" => {
                initialized.push(request.path)
                {
                  "protocolVersion": "2025-11-25",
                  "serverInfo": { "name": "test", "version": "1" },
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
      let tools = @execution.build_extra_tools(
        AgentTaskScope(group),
        model=Deepseek(V4Pro),
        api_key="test",
        api_url=base,
        workspace_root=directory,
        mcp_config_paths=[first, broken, missing, second],
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
      assert_eq(initialized.length(), 2)
      assert_true(initialized.contains("/selected"))
      assert_true(initialized.contains("/extra"))
      assert_false(initialized.contains("/overridden"))
      // Failed inputs alone must not publish a successful registration.
      // In particular, retain the original single-file event contract.
      for paths in [[broken], [broken, missing]] {
        let failed_tools = @execution.build_extra_tools(
          AgentTaskScope(group),
          model=Deepseek(V4Pro),
          api_key="test",
          api_url=base,
          workspace_root=directory,
          mcp_config_paths=paths,
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
