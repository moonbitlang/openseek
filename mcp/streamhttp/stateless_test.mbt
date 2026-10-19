///|
async fn stateless_reply(
  conn : @http.ServerConnection,
  id : Json,
  result : Json,
) -> Unit {
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json",
    "Mcp-Session-Id": "must-be-ignored",
  })
  conn.write(
    ({ "jsonrpc": "2.0", "id": id, "result": result } : Json).stringify(),
  )
}

///|
async test "stateless HTTP has per-request metadata mirrored headers no initialize and no session DELETE" {
  @async.with_task_group(group => {
    guard bind_test_server("TCP bind unavailable") is Some(server) else {
      return
    }
    let requests : Array[(@http.Request, Json)] = []
    let schema : Json = {
      "type": "object",
      "properties": { "tenant": { "type": "string", "x-mcp-header": "Tenant" } },
    }
    group.spawn_bg(no_wait=true, () => {
      server.run_forever((request, body, conn) => {
        let message = @json.parse(body.read_all().text())
        requests.push((request, message))
        guard message is { "id": id, "method": String(method_), .. } else {
          fail("unexpected notification")
        }
        let result : Json = match method_ {
          "server/discover" =>
            {
              "resultType": "complete",
              "supportedVersions": ["2026-07-28"],
              "capabilities": { "tools": {} },
              "_meta": {
                "io.modelcontextprotocol/serverInfo": {
                  "name": "strict",
                  "version": "1",
                },
              },
            }
          "tools/list" =>
            {
              "resultType": "complete",
              "tools": [
                { "name": "你好", "inputSchema": schema },
                {
                  "name": "invalid",
                  "inputSchema": {
                    "properties": {
                      "x": { "type": "number", "x-mcp-header": "X" },
                    },
                  },
                },
                {
                  "name": "invalid-property-names",
                  "inputSchema": {
                    "propertyNames": {
                      "type": "string",
                      "x-mcp-header": "Tenant",
                    },
                  },
                },
                {
                  "name": "invalid-content-schema",
                  "inputSchema": {
                    "contentSchema": {
                      "type": "string",
                      "x-mcp-header": "Tenant",
                    },
                  },
                },
              ],
            }
          "tools/call" =>
            {
              "resultType": "complete",
              "content": [{ "type": "text", "text": "ok" }],
            }
          _ => fail("stateless connection must not initialize")
        }
        stateless_reply(conn, id, result)
      })
    })
    let connection = @streamhttp.connect(
      group,
      url="http://127.0.0.1:\{server.addr.port()}/mcp",
      headers={
        "Authorization": "Bearer test",
        "mCp-MeThOd": "wrong",
        "Mcp-Name": "wrong",
        "MCP-Session-ID": "wrong",
        "Mcp-Param-Tenant": "wrong",
      },
      client_name="test",
      client_version="1",
    )
    assert_eq(connection.init().protocol_version, "2026-07-28")
    let client = connection.client()
    assert_eq(client.list_tools().map(tool => tool.name), ["你好"])
    assert_eq(
      client
      .call_tool(name="你好", arguments={ "tenant": " padded " })
      .render_text(),
      "ok",
    )
    connection.shutdown()
    @async.sleep(20)
    assert_eq(requests.length(), 3)
    for (request, message) in requests {
      assert_true(request.meth is Post)
      assert_eq(request.headers.get("Mcp-Session-Id"), None)
      assert_eq(request.headers.get("MCP-Protocol-Version"), Some("2026-07-28"))
      assert_eq(request.headers.get("Authorization"), Some("Bearer test"))
      guard message
        is {
          "method": String(method_),
          "params": {
            "_meta": {
              "io.modelcontextprotocol/protocolVersion": "2026-07-28",
              "io.modelcontextprotocol/clientCapabilities": Object(capabilities),
              ..
            },
            ..
          },
          ..
        } else {
        fail("missing request metadata")
      }
      assert_eq(capabilities.length(), 0)
      assert_eq(request.headers.get("Mcp-Method"), Some(method_))
      if method_ == "tools/call" {
        assert_eq(request.headers.get("Mcp-Name"), Some("=?base64?5L2g5aW9?="))
        assert_eq(
          request.headers.get("Mcp-Param-Tenant"),
          Some("=?base64?IHBhZGRlZCA=?="),
        )
      }
    }
  })
}

///|
async test "modern HTTP errors and authentication failures never trigger legacy initialization" {
  for
    (status, code) in [
      (400, -32020),
      (400, -32021),
      (400, -32022),
      (404, -32601),
      (401, -32600),
      (503, -32603),
    ] {
    @async.with_task_group(group => {
      guard bind_test_server("TCP bind unavailable") is Some(server) else {
        return
      }
      let methods : Array[String] = []
      group.spawn_bg(no_wait=true, () => {
        server.run_forever((_, body, conn) => {
          let message = @json.parse(body.read_all().text())
          guard message is { "id": id, "method": String(method_), .. } else {
            fail("missing request")
          }
          methods.push(method_)
          conn.send_response(status, "Rejected", extra_headers={
            "Content-Type": "application/json",
          })
          conn.write(
            (
              {
                "jsonrpc": "2.0",
                "id": id,
                "error": { "code": Json(code), "message": "rejected" },
              } : Json).stringify(),
          )
        })
      })
      try
        @streamhttp.connect(
          group,
          url="http://127.0.0.1:\{server.addr.port()}/mcp",
          client_name="test",
          client_version="1",
        )
      catch {
        _ => ()
      } noraise {
        _ => fail("expected rejected discovery")
      }
      assert_eq(methods, ["server/discover"])
    })
  }
}

///|
async test "HTTP legacy fallback preserves session handshake after plain 400" {
  @async.with_task_group(group => {
    guard mock_mcp_endpoint(group) is Some((url, seen)) else { return }
    let connection = @streamhttp.connect(
      group,
      url~,
      client_name="test",
      client_version="1",
    )
    defer connection.shutdown()
    assert_eq(connection.init().protocol_version, "2025-11-25")
    connection.client().list_tools() |> ignore
    assert_eq(seen.session_id, "session-123")
  })
}

///|
async test "cancelling a modern HTTP call closes its stream while another call completes" {
  @async.with_task_group(group => {
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    let started : @async.Queue[Unit] = Queue(kind=Unbounded)
    let disconnected : @async.Queue[Unit] = Queue(kind=Unbounded)
    let methods : Array[String] = []
    group.spawn_bg(no_wait=true, () => {
      server.run_forever((tcp, _) => {
        let conn = @http.ServerConnection::new(tcp)
        defer conn.close()
        let _ = conn.read_request()
        let message = @json.parse(conn.read_all().text())
        guard message is { "id": id, "method": String(method_), .. } else {
          fail("unexpected notification POST")
        }
        methods.push(method_)
        if method_ == "server/discover" {
          stateless_reply(conn, id, {
            "resultType": "complete",
            "supportedVersions": ["2026-07-28"],
            "capabilities": {},
          })
        } else if method_ == "tools/list" {
          stateless_reply(conn, id, { "resultType": "complete", "tools": [] })
        } else if message is { "params": { "name": "wait", .. }, .. } {
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          conn.write(": waiting\n\n")
          conn.flush()
          started.put(())
          tcp.read_some() |> ignore
          disconnected.put(())
        } else {
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          // A forbidden peer request must not cause a response POST.
          conn.write(
            "data: {\"jsonrpc\":\"2.0\",\"id\":\"peer\",\"method\":\"ping\"}\n\n",
          )
          let reply : Json = {
            "jsonrpc": "2.0",
            "id": id,
            "result": {
              "resultType": "complete",
              "content": [{ "type": "text", "text": "done" }],
            },
          }
          conn.write("data: \{reply.stringify()}\n\n")
        }
        conn.end_response()
      })
    })
    let connection = @streamhttp.connect(
      group,
      url="http://127.0.0.1:\{server.addr.port()}/mcp",
      client_name="test",
      client_version="1",
    )
    defer connection.shutdown()
    let pending = group.spawn(() => {
      connection.client().call_tool(name="wait", arguments={})
    })
    @async.with_timeout(1000, () => started.get())
    assert_eq(
      connection.client().call_tool(name="fast", arguments={}).render_text(),
      "done",
    )
    pending.cancel()
    @async.with_timeout(1000, () => disconnected.get())
    assert_eq(methods, [
      "server/discover", "tools/list", "tools/call", "tools/call",
    ])
  })
}
