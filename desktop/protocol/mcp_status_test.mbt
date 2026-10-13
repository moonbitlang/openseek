///|
test "an MCP status reply carries the engine's own report unchanged" {
  let status : @wire.McpStatus = Configured(path="/home/.openseek/mcp.json", servers=[
    {
      name: "playwright",
      transport: Stdio,
      target: "npx",
      state: Connected([
        {
          name: "mcp__playwright__browser_click",
          description: "Perform click on a web page",
        },
      ]),
    },
    {
      name: "docs",
      transport: Http,
      target: "https://example.com/mcp",
      state: Failed("connection refused"),
    },
  ])
  let reply : @protocol.McpStatusReply = {
    config_path: "/home/.openseek/mcp.json",
    engine: Running(status),
  }
  let decoded : @protocol.McpStatusReply = @json.from_json(reply.to_json())
  @debug.assert_eq(decoded, reply)
  let expected : Json = {
    "config_path": "/home/.openseek/mcp.json",
    "engine": "running",
    "status": status.to_json(),
  }
  assert_true(reply.to_json() == expected)
}

///|
test "a conversation without an engine is its own MCP status answer" {
  let reply : @protocol.McpStatusReply = {
    config_path: "/home/.openseek/mcp.json",
    engine: NotRunning,
  }
  json_inspect(reply.to_json(), content={
    "config_path": "/home/.openseek/mcp.json",
    "engine": "stopped",
  })
  let decoded : @protocol.McpStatusReply = @json.from_json(reply.to_json())
  @debug.assert_eq(decoded, reply)
  let payload : @protocol.McpStatusPayload = @json.from_json({
    "session": "s-1",
  })
  assert_eq(payload.session, "s-1")
}

///|
test "an engine that has not reported yet is neither stopped nor unconfigured" {
  let reply : @protocol.McpStatusReply = {
    config_path: "/home/.openseek/mcp.json",
    engine: Connecting,
  }
  json_inspect(reply.to_json(), content={
    "config_path": "/home/.openseek/mcp.json",
    "engine": "connecting",
  })
  let decoded : @protocol.McpStatusReply = @json.from_json(reply.to_json())
  @debug.assert_eq(decoded, reply)
}

///|
test "a malformed MCP status reply is refused, not guessed" {
  fn refused(json : Json) -> Bool {
    let _ : @protocol.McpStatusReply = @json.from_json(json) catch {
      _ => return true
    }
    false
  }

  // A running engine always carries its status; an unknown state is not
  // read as "stopped".
  assert_true(refused({ "config_path": "/p", "engine": "running" }))
  assert_true(refused({ "config_path": "/p", "engine": "starting" }))
  assert_true(refused({ "engine": "stopped" }))
}
