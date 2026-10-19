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
        transport: Http,
        target: "http://127.0.0.1:4321/mcp",
        state: Connected([
          { name: "mcp__seekmoon__browser_open", description: "Open a page", },
        ]),
      },
      {
        name: "docs",
        transport: Http,
        target: "https://example.com/mcp",
        state: Failed("connection refused"),
      },
    ],
  }
  let reply : @protocol.McpStatusReply = Running(status)
  let decoded : @protocol.McpStatusReply = @json.from_json(reply.to_json())
  @debug.assert_eq(decoded, reply)
  let expected : Json = { "engine": "running", "status": status.to_json() }
  assert_true(reply.to_json() == expected)
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
