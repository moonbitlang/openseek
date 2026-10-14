///|
/// What a client holds once its conversation has been granted: where the
/// server is, and the header that lets it in.
priv struct Grant {
  url : String
  authorization : String
}

///|
/// `session`'s grant, read back out of the environment the host would set.
fn grant(server : @mcp.Server, session : String) -> Grant raise {
  let env = server.grant(session)
  guard env.get(@mcp.UrlEnv) is Some(url) &&
    env.get(@mcp.TokenEnv) is Some(token) else {
    fail("a grant names the server and carries a token")
  }
  { url, authorization: "Bearer \{token}", }
}

///|
fn test_tools() -> Array[@mcp.Tool] {
  [
    {
      name: "echo",
      description: "Echo the caller and its arguments.",
      input_schema: { "type": "object" },
      call: call => "\{call.session} \{call.arguments.stringify()}",
    },
    {
      name: "broken",
      description: "Always fails.",
      input_schema: { "type": "object" },
      call: _ => raise @mcp.ToolError("the page is gone; open it again"),
    },
    {
      name: "browser_get_text",
      description: "Read a tab's text.",
      input_schema: {
        "type": "object",
        "properties": {
          "tab": { "type": "integer", "description": "The tab to read." },
          "selector": { "type": "string" },
          "include_hidden": { "type": "boolean" },
          "viewport": { "type": "object" },
        },
        "required": ["tab"],
      },
      call: call => "\{call.session} \{call.arguments.stringify()}",
    },
  ]
}

///|
/// Serve the test tools for the duration of `body`.
async fn with_server(body : async (@mcp.Server) -> Unit) -> Unit {
  let server = @mcp.Server(test_tools(), version="1.2.3")
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => server.run())
    body(server)
  })
}

///|
/// POST one JSON-RPC message, returning the status and the reply body when
/// there is one.
async fn post(
  grant : Grant,
  message : Json,
  origin? : String,
) -> (Int32, Json?) {
  let headers : @http.Headers = {
    "Content-Type": "application/json",
    "Authorization": grant.authorization,
  }
  if origin is Some(origin) {
    headers["Origin"] = origin
  }
  let (response, body) = @http.post(grant.url, message.stringify(), headers~)
  let text = body.text()
  (response.code, if text.is_empty() { None } else { Some(@json.parse(text)) })
}

///|
fn request(id : Int32, method_ : String, params : Json) -> Json {
  {
    "jsonrpc": "2.0",
    "id": Json(id),
    "method": Json(method_),
    "params": params,
  }
}

///|
async test "the engine's own MCP client lists and calls this server's tools" {
  with_server(server => {
    let servers = @mcpconfig.decode(
      {
        "mcpServers": {
          "seekmoon": {
            "url": "${OPENSEEK_DESKTOP_TOOLS_URL}",
            "headers": {
              "Authorization": "Bearer ${OPENSEEK_DESKTOP_TOOLS_TOKEN}",
            },
          },
        },
      },
      env=server.grant("s-interop"),
    )
    guard servers[0] is Http(url~, headers~, ..) else { fail("expected HTTP") }
    @async.with_task_group(group => {
      let connection = @streamhttp.connect(
        group,
        url~,
        headers~,
        client_name="openseek",
        client_version="test",
      )
      defer connection.shutdown()
      assert_eq(connection.init().server_name, "seekmoon")
      assert_eq(connection.init().server_version, "1.2.3")
      let client = connection.client()
      assert_eq(client.list_tools().map(tool => tool.name), [
        "echo", "broken", "browser_get_text",
      ])
      let echoed = client.call_tool(name="echo", arguments={ "tab": 3 })
      assert_false(echoed.is_error)
      assert_eq(echoed.render_text(), "s-interop {\"tab\":3}")
      let failed = client.call_tool(
        name="broken",
        arguments=Json::empty_object(),
      )
      assert_true(failed.is_error)
      assert_eq(failed.render_text(), "the page is gone; open it again")
    })
  })
}

///|
async test "HTTP clients select tool groups for discovery and calls" {
  with_server(server => {
    let grant = grant(server, "s-filtered")
    @async.with_task_group(group => {
      let connection = @streamhttp.connect(
        group,
        url=grant.url,
        headers={
          "Authorization": grant.authorization,
          "X-SeekMoon-Tool-Groups": "browser, broken",
        },
        client_name="openseek",
        client_version="test",
      )
      defer connection.shutdown()
      let client = connection.client()
      assert_eq(client.list_tools().map(tool => tool.name), [
        "broken", "browser_get_text",
      ])
      let result = client.call_tool(name="browser_get_text", arguments={
        "tab": 3,
      })
      assert_eq(result.render_text(), "s-filtered {\"tab\":3}")
      // Use a raw call to check the protocol error for an excluded tool.
      let (response, body) = @http.post(
        grant.url,
        request(9, "tools/call", { "name": "echo" }).stringify(),
        headers={
          "Authorization": grant.authorization,
          "X-SeekMoon-Tool-Groups": "browser, broken",
        },
      )
      assert_eq(response.code, 200)
      assert_true(
        body.json() is { "error": { "code": Number(-32602, ..), .. }, .. },
      )
    })
  })
}

///|
async test "a token names its conversation, and a conversation keeps its token" {
  with_server(server => {
    let first = grant(server, "s-one")
    let again = grant(server, "s-one")
    let other = grant(server, "s-two")
    assert_eq(first.authorization, again.authorization)
    assert_true(first.authorization != other.authorization)
    let call = request(1, "tools/call", { "name": "echo" })
    guard post(first, call)
      is (
        200,
        Some({ "result": { "content": [{ "text": String(one), .. }], .. }, .. }),
      ) else {
      fail("s-one's call was not answered")
    }
    guard post(other, call)
      is (
        200,
        Some({ "result": { "content": [{ "text": String(two), .. }], .. }, .. }),
      ) else {
      fail("s-two's call was not answered")
    }
    assert_eq(one, "s-one {}")
    assert_eq(two, "s-two {}")
  })
}

///|
async test "initialize answers a supported version in kind and any other with the latest" {
  with_server(server => {
    let grant = grant(server, "s-version")
    let initialize = (version : String) => {
      request(1, "initialize", {
        "protocolVersion": Json(version),
        "capabilities": Json::empty_object(),
        "clientInfo": { "name": "test", "version": "0" },
      })
    }
    guard post(grant, initialize("2025-03-26"))
      is (200, Some({ "result": { "protocolVersion": String(kept), .. }, .. })) else {
      fail("initialize was not answered")
    }
    assert_eq(kept, "2025-03-26")
    guard post(grant, initialize("1999-01-01"))
      is (200, Some({ "result": { "protocolVersion": String(latest), .. }, .. })
      ) else {
      fail("initialize was not answered")
    }
    assert_eq(latest, "2025-11-25")
  })
}

///|
async test "protocol errors are JSON-RPC errors, not tool results" {
  with_server(server => {
    let grant = grant(server, "s-errors")
    let code = (reply : (Int32, Json?)) => {
      match reply {
        (200, Some({ "error": { "code": Number(code, ..), .. }, .. })) =>
          Some(code.to_int())
        _ => None
      }
    }
    assert_eq(
      code(post(grant, request(1, "tools/call", { "name": "missing" }))),
      Some(-32602),
    )
    assert_eq(
      code(post(grant, request(2, "tools/call", Json::empty_object()))),
      Some(-32602),
    )
    assert_eq(
      code(post(grant, request(3, "resources/list", Json::empty_object()))),
      Some(-32601),
    )
    assert_eq(code(post(grant, [1, 2, 3])), Some(-32600))
  })
}

///|
async test "a notification is accepted without a reply" {
  with_server(server => {
    let grant = grant(server, "s-notify")
    let notification : Json = {
      "jsonrpc": "2.0",
      "method": "notifications/initialized",
      "params": Json::empty_object(),
    }
    assert_true(post(grant, notification) is (202, None))
  })
}

///|
async test "requests without a granted token, or from a web origin, are refused" {
  with_server(server => {
    let grant = grant(server, "s-auth")
    let ping = request(1, "ping", Json::empty_object())
    assert_true(post(grant, ping) is (200, Some(_)))
    assert_true(
      post({ ..grant, authorization: "Bearer not-a-token", }, ping)
      is (401, None),
    )
    assert_true(post({ ..grant, authorization: "", }, ping) is (401, None))
    // A page an agent opened can reach loopback; holding a token must not be
    // enough for it.
    assert_true(post(grant, ping, origin="https://example.com") is (403, None))
    assert_true(post({ ..grant, url: grant.url + "x", }, ping) is (404, None))
    let (response, _) = @http.get(grant.url, headers={
      "Authorization": grant.authorization,
    })
    assert_eq(response.code, 405)
  })
}

///|
async test "a body that is not JSON is a parse error" {
  with_server(server => {
    let grant = grant(server, "s-parse")
    let (response, body) = @http.post(grant.url, "{not json", headers={
      "Authorization": grant.authorization,
    })
    assert_eq(response.code, 400)
    assert_true(
      body.json() is { "error": { "code": Number(-32700, ..), .. }, .. },
    )
  })
}
