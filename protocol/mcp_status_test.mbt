///|
fn tool(name : String) -> @openseek_protocol.McpTool {
  { name, description: "does \{name}", }
}

///|
test "an mcp_status survives the wire with every server state" {
  let status : @openseek_protocol.McpStatus = Configured(
    path="/home/.openseek/mcp.json",
    servers=[
      {
        name: "playwright",
        transport: Stdio,
        target: "npx",
        state: Connected([tool("mcp__playwright__browser_click")]),
      },
      {
        name: "notes",
        transport: Stdio,
        target: "notes-mcp",
        state: Lost([tool("mcp__notes__read")]),
      },
      { name: "quiet", transport: Stdio, target: "quiet", state: NoTools, },
      {
        name: "docs",
        transport: Http,
        target: "https://example.com/mcp",
        state: Failed("connection refused"),
      },
      { name: "late", transport: Stdio, target: "late", state: Skipped, },
    ],
  )
  let event : @openseek_protocol.Event = McpStatus(status~)
  guard @openseek_protocol.parse(event.to_json())
    is Some(McpStatus(status=decoded)) else {
    fail("mcp_status did not decode")
  }
  @debug.assert_eq(decoded, status)
  json_inspect(
    @openseek_protocol.Event::McpStatus(
      status=Configured(path="/p", servers=[
        {
          name: "docs",
          transport: Http,
          target: "https://example.com/mcp",
          state: Failed("connection refused"),
        },
      ]),
    ).to_json(),
    content={
      "event": "mcp_status",
      "status": {
        "config": "loaded",
        "path": "/p",
        "servers": [
          {
            "name": "docs",
            "transport": "http",
            "target": "https://example.com/mcp",
            "state": "failed",
            "error": "connection refused",
          },
        ],
      },
    },
  )
}

///|
test "an engine without a usable MCP configuration says which way" {
  let statuses : Array[@openseek_protocol.McpStatus] = [
    NotConfigured,
    ConfigFailed(
      path="/home/.openseek/mcp.json",
      error="configuration is missing an `mcpServers` object",
    ),
    Configured(path="/home/.openseek/mcp.json", servers=[]),
  ]
  for status in statuses {
    let decoded : @openseek_protocol.McpStatus = @json.from_json(
      status.to_json(),
    )
    @debug.assert_eq(decoded, status)
  }
  json_inspect(@openseek_protocol.McpStatus::NotConfigured.to_json(), content={
    "config": "none",
  })
}

///|
test "a malformed MCP server status is refused, not guessed" {
  fn refused(json : Json) -> Bool {
    let _ : @openseek_protocol.McpServerStatus = @json.from_json(json) catch {
      _ => return true
    }
    false
  }

  fn server(transport : String, state : Json) -> Json {
    guard state is Object(fields) else { return state }
    fields["name"] = "a"
    fields["transport"] = Json(transport)
    fields["target"] = "a"
    Json::object(fields)
  }

  // A server holding tools lists them; holding none is `no_tools`.
  assert_true(refused(server("stdio", { "state": "connected", "tools": [] })))
  assert_true(refused(server("stdio", { "state": "lost" })))
  assert_true(refused(server("stdio", { "state": "failed" })))
  assert_true(refused(server("stdio", { "state": "up" })))
  assert_true(refused(server("pipe", { "state": "skipped" })))
  assert_false(refused(server("stdio", { "state": "skipped" })))
  // An event whose status does not decode is not an event.
  assert_true(
    @openseek_protocol.parse({
      "event": "mcp_status",
      "status": { "config": "loaded", "path": "/p" },
    })
    is None,
  )
}
