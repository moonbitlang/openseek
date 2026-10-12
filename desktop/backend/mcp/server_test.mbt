///|
/// What an engine holds after reading the config its conversation was
/// granted: where the server is, and the header that lets it in.
priv struct Grant {
  url : String
  authorization : String
}

///|
/// Read a grant back out of an engine config, the way an engine would.
async fn read_grant(config : @pathx.Path) -> Grant {
  guard @json.parse(@fsx.read_text(config))
    is {
      "mcpServers": {
        "seekmoon": {
          "url": String(url),
          "headers": { "Authorization": String(authorization), .. },
          ..
        },
        ..
      },
      ..
    } else {
    fail("the engine config names no seekmoon server")
  }
  { url, authorization, }
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
  ]
}

///|
/// Serve the test tools for the duration of `body`.
async fn with_server(body : async (@mcp.Server) -> Unit) -> Unit {
  let dir = @pathx.Path(@fs.tmpdir(prefix="openseek-mcp-server-"))
  let server = @mcp.Server(test_tools(), version="1.2.3", config_dir=dir)
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => server.run())
    body(server)
  })
}

///|
/// POST one JSON-RPC message, returning the status and the reply body when
/// there is one.
async fn post(grant : Grant, message : Json, origin? : String) -> (Int, Json?) {
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
fn request(id : Int, method_ : String, params : Json) -> Json {
  {
    "jsonrpc": "2.0",
    "id": id.to_json(),
    "method": method_.to_json(),
    "params": params,
  }
}

///|
async test "the engine's own MCP client lists and calls this server's tools" {
  with_server(server => {
    let grant = read_grant(server.engine_config(session="s-interop"))
    @async.with_task_group(group => {
      let connection = @streamhttp.connect(
        group,
        url=grant.url,
        headers={ "Authorization": grant.authorization },
        client_name="openseek",
        client_version="test",
      )
      defer connection.shutdown()
      assert_eq(connection.init().server_name, "seekmoon")
      assert_eq(connection.init().server_version, "1.2.3")
      let client = connection.client()
      assert_eq(client.list_tools().map(tool => tool.name), ["echo", "broken"])
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
async test "a token names its conversation, and a conversation keeps its token" {
  with_server(server => {
    let first = read_grant(server.engine_config(session="s-one"))
    let again = read_grant(server.engine_config(session="s-one"))
    let other = read_grant(server.engine_config(session="s-two"))
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
    let grant = read_grant(server.engine_config(session="s-version"))
    let initialize = (version : String) => {
      request(1, "initialize", {
        "protocolVersion": version.to_json(),
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
    let grant = read_grant(server.engine_config(session="s-errors"))
    let code = (reply : (Int, Json?)) => {
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
    let grant = read_grant(server.engine_config(session="s-notify"))
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
    let grant = read_grant(server.engine_config(session="s-auth"))
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
    let grant = read_grant(server.engine_config(session="s-parse"))
    let (response, body) = @http.post(grant.url, "{not json", headers={
      "Authorization": grant.authorization,
    })
    assert_eq(response.code, 400)
    assert_true(
      body.json() is { "error": { "code": Number(-32700, ..), .. }, .. },
    )
  })
}

///|
async test "the engine config keeps the user's servers beside this one" {
  with_server(server => {
    let dir = @pathx.Path(@fs.tmpdir(prefix="openseek-mcp-inherited-"))
    let theirs = dir.join("mcp.json")
    @fsx.write_text(
      theirs,
      (
        {
          "mcpServers": {
            "codex": { "command": "codex", "args": ["mcp-server"] },
            "seekmoon": { "url": "http://example.invalid/" },
          },
          "note": "kept",
        } : Json).stringify(),
    )
    let config = server.engine_config(session="s-merge", inherited=theirs)
    let grant = read_grant(config)
    guard @json.parse(@fsx.read_text(config))
      is { "mcpServers": Object(servers), "note": String(note), .. } else {
      fail("the merged config lost its shape")
    }
    assert_eq(note, "kept")
    assert_eq(servers.keys().to_array(), ["codex", "seekmoon"])
    // The entry under this server's name is this server's, whatever the
    // user's file had there.
    assert_true(grant.url.has_prefix("http://127.0.0.1:"))
  })
}

///|
async test "an unreadable user config costs only the user's servers" {
  with_server(server => {
    let dir = @pathx.Path(@fs.tmpdir(prefix="openseek-mcp-broken-"))
    let broken = dir.join("mcp.json")
    @fsx.write_text(broken, "{not json")
    for inherited in [broken, dir.join("absent.json")] {
      let config = server.engine_config(session="s-broken", inherited~)
      guard @json.parse(@fsx.read_text(config))
        is { "mcpServers": Object(servers), .. } else {
        fail("no config was written")
      }
      assert_eq(servers.keys().to_array(), ["seekmoon"])
    }
  })
}
