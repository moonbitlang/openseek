///|
fn stateless_params(version~ : String = "2026-07-28") -> Json {
  {
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": version,
      "io.modelcontextprotocol/clientCapabilities": {},
      "io.modelcontextprotocol/clientInfo": { "name": "test", "version": "1" },
    },
  }
}

///|
async fn modern_post(
  grant : Grant,
  method_ : String,
  params : Json,
  headers~ : @http.Headers = {},
) -> (Int32, Json) {
  let all : @http.Headers = {
    "Authorization": grant.authorization,
    "Content-Type": "application/json",
    "MCP-Protocol-Version": "2026-07-28",
    "Mcp-Method": method_,
  }
  for key, value in headers {
    all[key] = value
  }
  let (response, body) = @http.post(
    grant.url,
    request(1, method_, params).stringify(),
    headers=all,
  )
  assert_eq(response.headers.get("Mcp-Session-Id"), None)
  (response.code, body.json())
}

///|
async test "host serves a stateless tool call before discovery and interleaves legacy requests" {
  with_server(server => {
    let first = grant(server, "one")
    let second = grant(server, "two")
    guard stateless_params() is Object(params) else { fail("params") }
    params["name"] = "echo"
    params["arguments"] = {}
    let (status, answer) = modern_post(first, "tools/call", Json(params), headers={
      "Mcp-Name": "echo",
      "Mcp-Session-Id": "ignored",
    })
    assert_eq(status, 200)
    assert_true(
      answer
      is {
        "result": {
          "resultType": "complete",
          "content": [{ "text": "one {}", .. }],
          ..
        },
        ..
      },
    )
    let (_, discovery) = modern_post(
      second,
      "server/discover",
      stateless_params(),
    )
    assert_true(
      discovery
      is {
        "result": {
          "resultType": "complete",
          "supportedVersions": ["2026-07-28"],
          "_meta": {
            "io.modelcontextprotocol/serverInfo": {
              "name": "seekmoon",
              "version": "1.2.3",
              ..
            },
            ..
          },
          ..
        },
        ..
      },
    )
    let (_, legacy) = post(
      second,
      request(2, "initialize", { "protocolVersion": "2025-11-25" }),
    )
    assert_true(
      legacy is Some({ "result": { "protocolVersion": "2025-11-25", .. }, .. }),
    )
    let (_, again) = modern_post(second, "tools/call", Json(params), headers={
      "Mcp-Name": "echo",
    })
    assert_true(
      again is { "result": { "content": [{ "text": "two {}", .. }], .. }, .. },
    )
  })
}

///|
async test "host rejects modern version and header mismatches independently on every request" {
  with_server(server => {
    let grant = grant(server, "test")
    for
      headers in [
        ({ "Mcp-Method": "tools/call" } : @http.Headers),
        { "MCP-Protocol-Version": "2025-11-25" },
      ] {
      let (status, error) = modern_post(
        grant,
        "server/discover",
        stateless_params(),
        headers~,
      )
      assert_eq(status, 400)
      assert_true(error is { "error": { "code": -32020, .. }, .. })
    }
    let (status, error) = modern_post(
      grant,
      "server/discover",
      stateless_params(version="2099-01-01"),
      headers={ "MCP-Protocol-Version": "2099-01-01" },
    )
    assert_eq(status, 400)
    assert_true(
      error
      is {
        "error": {
          "code": -32022,
          "data": { "supported": ["2026-07-28"], .. },
          ..
        },
        ..
      },
    )
    let (status, error) = modern_post(grant, "unknown", stateless_params())
    assert_eq(status, 404)
    assert_true(error is { "error": { "code": -32601, .. }, .. })
    let (status, error) = modern_post(grant, "initialize", stateless_params())
    assert_eq(status, 404)
    assert_true(error is { "error": { "code": -32601, .. }, .. })
    let (status, error) = modern_post(grant, "tools/list", {})
    assert_eq(status, 400)
    assert_true(error is { "error": { "code": -32020, .. }, .. })
  })
}

///|
async test "host validates encoded tool names and mirrored parameters before executing handlers" {
  let server = @mcp.Server(
    [
      {
        name: "你好",
        description: "Echo tenant",
        input_schema: {
          "type": "object",
          "properties": {
            "tenant": { "type": "string", "x-mcp-header": "Tenant" },
          },
        },
        call: call => [Text(call.session)],
      },
    ],
    version="test",
  )
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => server.run())
    let grant = grant(server, "caller")
    guard stateless_params() is Object(params) else { fail("params") }
    params["name"] = "你好"
    params["arguments"] = { "tenant": "你好" }
    let (status, answer) = modern_post(grant, "tools/call", Json(params), headers={
      "Mcp-Name": "=?base64?5L2g5aW9?=",
      "Mcp-Param-Tenant": "=?base64?5L2g5aW9?=",
    })
    assert_eq(status, 200)
    assert_true(
      answer is { "result": { "content": [{ "text": "caller", .. }], .. }, .. },
    )
    let (status, error) = modern_post(grant, "tools/call", Json(params), headers={
      "Mcp-Name": "=?base64?5L2g5aW9?=",
    })
    assert_eq(status, 400)
    assert_true(error is { "error": { "code": -32020, .. }, .. })
  })
}

///|
async test "host rejects recognized headers for absent and null arguments" {
  let calls : Array[Json] = []
  let server = @mcp.Server(
    [
      {
        name: "echo",
        description: "Echo tenant",
        input_schema: {
          "type": "object",
          "properties": {
            "tenant": { "type": "string", "x-mcp-header": "Tenant" },
          },
        },
        call: call => {
          calls.push(call.arguments)
          [Text("called")]
        },
      },
    ],
    version="test",
  )
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => server.run())
    let grant = grant(server, "caller")
    guard stateless_params() is Object(params) else { fail("params") }
    params["name"] = "echo"
    for arguments in [Json::empty_object(), { "tenant": null }] {
      params["arguments"] = arguments
      for value in ["other-tenant", "=?base64?!!!?="] {
        let (status, answer) = modern_post(grant, "tools/call", Json(params), headers={
          "Mcp-Name": "echo",
          "mCp-PaRaM-tEnAnT": value,
        })
        assert_eq(status, 400)
        assert_true(answer is { "error": { "code": -32020, .. }, .. })
        assert_eq(calls.length(), 0)
      }
    }
    // Omitted recognized headers and unknown headers remain valid.
    let (status, _) = modern_post(grant, "tools/call", Json(params), headers={
      "Mcp-Name": "echo",
      "Mcp-Param-Unknown": "ignored",
    })
    assert_eq(status, 200)
    assert_eq(calls.length(), 1)
  })
}

///|
async test "HTTP client discovers header schemas before a direct tool call" {
  let server = @mcp.Server(
    [
      {
        name: "echo",
        description: "Echo tenant",
        input_schema: {
          "type": "object",
          "properties": {
            "tenant": { "type": "string", "x-mcp-header": "Tenant" },
          },
        },
        call: _ => [Text("ok")],
      },
    ],
    version="test",
  )
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => server.run())
    let grant = grant(server, "caller")
    let connection = @streamhttp.connect(
      group,
      url=grant.url,
      headers={ "Authorization": grant.authorization },
      client_name="test",
      client_version="1",
    )
    defer connection.shutdown()
    let result = connection
      .client()
      .call_tool(name="echo", arguments={ "tenant": "a" })
    assert_eq(result.render_text(), "ok")
  })
}
