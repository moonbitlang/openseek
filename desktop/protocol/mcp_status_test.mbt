///|
test "an MCP status reply carries the engine's own report unchanged" {
  let status : @wire.McpStatus = {
    configs: [
      { path: "/run/host-mcp.json", state: Loaded, },
      { path: "/home/.openseek/mcp.json", state: Loaded, },
    ],
    servers: [
      {
        name: "seekmoon",
        source: "/run/host-mcp.json",
        transport: Http,
        target: "http://127.0.0.1:4321/mcp",
        state: Connected([
          { name: "mcp__seekmoon__browser_open", description: "Open a page", },
        ]),
      },
      {
        name: "docs",
        source: "/home/.openseek/mcp.json",
        transport: Http,
        target: "https://example.com/mcp",
        state: Failed("connection refused"),
      },
    ],
  }
  let reply : @protocol.McpStatusReply = Running(
    status~,
    builtin_config=Some("/run/host-mcp.json"),
  )
  let decoded : @protocol.McpStatusReply = @json.from_json(reply.to_json())
  @debug.assert_eq(decoded, reply)
  let expected : Json = {
    "engine": "running",
    "status": status.to_json(),
    "builtin_config": "/run/host-mcp.json",
  }
  assert_true(reply.to_json() == expected)
  // A host without its own tool server hands the engine no file of its own.
  let plain : @protocol.McpStatusReply = Running(status~, builtin_config=None)
  assert_true(
    plain.to_json() == { "engine": "running", "status": status.to_json() },
  )
  let decoded : @protocol.McpStatusReply = @json.from_json(plain.to_json())
  @debug.assert_eq(decoded, plain)
}

///|
test "a conversation without a reporting engine is its own MCP status answer" {
  for reply in [@protocol.McpStatusReply::Stopped, Connecting] {
    let decoded : @protocol.McpStatusReply = @json.from_json(reply.to_json())
    @debug.assert_eq(decoded, reply)
  }
  assert_true(
    @protocol.McpStatusReply::Stopped.to_json() == { "engine": "stopped" },
  )
  // An engine state this client does not know is refused, not guessed.
  try {
    let _ : @protocol.McpStatusReply = @json.from_json({ "engine": "paused" })
  } catch {
    _ => ()
  } noraise {
    _ => fail("an unknown engine state decoded")
  }
}
