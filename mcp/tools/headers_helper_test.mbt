// Use pinned MoonBit CLI tools through moonx so these process tests also
// run on Windows without depending on a host shell or Unix utilities.

///|
async test "HTTP helpers resolve once before connect and leave configuration unchanged" {
  let dir = @fs.tmpdir(prefix="mcp-headers-")
  defer @fs.rmdir(dir, recursive=true)
  // Spaces and shell syntax in the filename must survive argv unchanged.
  let filename = "headers $(never-execute); literal.json"
  let path = dir + "/" + filename
  @fs.write_file(
    dir + "/helper.sh",
    "moonx cli/cat@0.1.0 -\necho run >> invocations\nmoonx cli/cat@0.1.0 \"$1\"\n",
  )
  @fs.write_file(
    path, "{\"Authorization\":\"Bearer first\",\"MCP-Protocol-Version\":\"wrong\"}",
  )
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
      error if "\{error}".contains("Operation not permitted") => {
        println("local TCP bind unavailable; skipping headers helper test")
        return
      }
      error => raise error
    }
    let seen : Array[@http.Headers] = []
    group.spawn_bg(no_wait=true, () => {
      server.run_forever((request, body, conn) => {
        seen.push(request.headers)
        let message = @json.parse(body.read_all().text())
        guard message is { "id": id, "method": String(method_), .. } else {
          fail("expected a stateless request")
        }
        let result : Json = match method_ {
          "server/discover" =>
            {
              "resultType": "complete",
              "supportedVersions": ["2026-07-28"],
              "capabilities": { "tools": {} },
              "_meta": {
                "io.modelcontextprotocol/serverInfo": {
                  "name": "helper-test",
                  "version": "1",
                },
              },
            }
          "tools/list" =>
            {
              "resultType": "complete",
              "tools": [{ "name": "ping", "inputSchema": { "type": "object" } }],
            }
          "tools/call" =>
            {
              "resultType": "complete",
              "content": [{ "type": "text", "text": "pong" }],
            }
          _ => fail("unexpected method \{method_}")
        }
        respond_json(conn, id, result)
      })
    })
    let scope = @agent_runtime.AgentTaskScope(group)
    let servers = @config.decode({
      "mcpServers": {
        "remote": {
          "url": "http://127.0.0.1:\{server.addr.port()}/mcp",
          "headers": { "authorization": "static", "X-Static": "preserved" },
          "headersHelper": [
            "moonx",
            "cli/sh@0.1.1",
            "helper.sh",
            Json(filename),
          ],
        },
      },
    })
    guard servers is [Http(headers=configured_headers, ..)] else {
      fail("expected an HTTP configuration")
    }
    let entries = connect_all(
      scope,
      servers,
      client_name="test",
      client_version="1",
      workspace_root=dir,
    )
    guard entries is [{ connection: Live(first), .. } as entry] else {
      fail("expected a connected server")
    }
    assert_eq(@fs.read_file(dir + "/invocations").text(), "run\n")
    assert_true(!seen.is_empty())
    // Existing clients retain their resolved map, even after helper output changes.
    @fs.write_file(
      path,
      "{\"authorization\":\"Bearer second\"}",
      create_mode=CreateOrTruncate,
    )
    guard entry.call("ping", {}) is Respond(output) else {
      fail("expected a tool response")
    }
    assert_false(output.is_error)
    assert_eq(output.content, "pong")
    for headers in seen {
      assert_eq(headers.get("Authorization"), Some("Bearer first"))
      assert_eq(headers.get("X-Static"), Some("preserved"))
      assert_eq(headers.get("MCP-Protocol-Version"), Some("2026-07-28"))
    }
    first.close()
    assert_eq(@fs.read_file(dir + "/invocations").text(), "run\n")
    seen.clear()
    let entries = connect_all(
      scope,
      servers,
      client_name="test",
      client_version="1",
      workspace_root=dir,
    )
    guard entries is [{ connection: Live(second), .. }] else {
      fail("expected a new connected server")
    }
    assert_true(!seen.is_empty())
    for headers in seen {
      assert_eq(headers.get("Authorization"), Some("Bearer second"))
      assert_eq(headers.get("X-Static"), Some("preserved"))
    }
    second.close()
    assert_eq(@fs.read_file(dir + "/invocations").text(), "run\nrun\n")
    assert_eq(configured_headers, {
      "authorization": "static",
      "X-Static": "preserved",
    })
  })
}
