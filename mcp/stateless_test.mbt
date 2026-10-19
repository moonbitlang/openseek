///|
fn discovery_result() -> Json {
  {
    "resultType": "complete",
    "supportedVersions": ["2026-07-28"],
    "capabilities": { "tools": {} },
    "_meta": {
      "io.modelcontextprotocol/serverInfo": { "name": "modern", "version": "1" },
    },
  }
}

///|
async test "stateless discovery and every paginated tool request carry metadata without initialize" {
  @async.with_task_group(group => {
    let seen : Array[Json] = []
    let client = fake_client(group, request => {
      seen.push(request)
      let result : Json = match request {
        { "method": "server/discover", .. } => discovery_result()
        { "method": "tools/list", "params": { "cursor": "next", .. }, .. } =>
          { "resultType": "complete", "tools": [] }
        { "method": "tools/list", .. } =>
          { "resultType": "complete", "tools": [], "nextCursor": "next" }
        _ =>
          {
            "resultType": "complete",
            "content": [{ "type": "text", "text": "done" }],
          }
      }
      Some(success(request, result))
    })
    let info = client.discover(client_name="test", client_version="2")
    assert_eq(info.protocol_version, "2026-07-28")
    assert_eq(info.server_name, Some("modern"))
    assert_eq(client.list_tools().length(), 0)
    assert_eq(client.call_tool(name="echo", arguments={}).render_text(), "done")
    assert_eq(seen.map(method_of), [
      "server/discover", "tools/list", "tools/list", "tools/call",
    ])
    for request in seen {
      assert_true(
        request
        is {
          "params": {
            "_meta": {
              "io.modelcontextprotocol/protocolVersion": "2026-07-28",
              "io.modelcontextprotocol/clientCapabilities": { },
              "io.modelcontextprotocol/clientInfo": {
                "name": "test",
                "version": "2",
                ..
              },
              ..
            },
            ..
          },
          ..
        },
      )
    }
  })
}

///|
async test "discovery rejects malformed success and incompatible stateless versions" {
  for
    result in [
      Json::empty_object(),
      { "supportedVersions": ["2099-01-01"], "capabilities": {} },
    ] {
    @async.with_task_group(group => {
      let client = fake_client(
        group,
        answers("server/discover", request => success(request, result)),
      )
      try client.discover(client_name="test", client_version="1") catch {
        @mcp.Protocol(_) => ()
        error => raise error
      } noraise {
        _ => fail("expected invalid discovery to fail")
      }
    })
  }
}

///|
async test "input-required and unknown result types cannot become successful empty tool output" {
  for kind in ["input_required", "unknown"] {
    @async.with_task_group(group => {
      let client = fake_client(group, request => {
        Some(
          success(
            request,
            if method_of(request) == "server/discover" {
              discovery_result()
            } else {
              { "resultType": kind, "inputRequests": { "x": {} } }
            },
          ),
        )
      })
      client.discover(client_name="test", client_version="1") |> ignore
      try client.call_tool(name="echo", arguments={}) catch {
        @mcp.Protocol(_) => ()
        error => raise error
      } noraise {
        _ => fail("expected unsupported result to fail")
      }
    })
  }
}

///|
async test "stateless request cancellation names the outstanding request and preserves the connection" {
  @async.with_task_group(group => {
    let cancelled : @async.Queue[Json] = Queue(kind=Unbounded)
    let client = fake_client(group, request => {
      match method_of(request) {
        "server/discover" => Some(success(request, discovery_result()))
        "notifications/cancelled" => {
          (cancelled.try_put(request) catch { _ => false }) |> ignore
          None
        }
        "tools/list" =>
          Some(success(request, { "resultType": "complete", "tools": [] }))
        _ => None
      }
    })
    client.discover(client_name="test", client_version="1") |> ignore
    assert_true(
      @async.with_timeout_opt(20, () => {
        client.call_tool(name="wait", arguments={})
      })
      is None,
    )
    let notification = @async.with_timeout(1000, () => cancelled.get())
    assert_true(notification is { "params": { "requestId": 2, .. }, .. })
    assert_eq(client.list_tools().length(), 0)
  })
}
