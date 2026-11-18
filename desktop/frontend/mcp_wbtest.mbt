///|
test "an MCP server that failed while the engine started is reported" {
  let dispatch = test_dispatch()
  // The engine connects its MCP servers before it reads the first prompt and
  // records none of the outcome, so the stream event is the only word a user
  // gets that the tools they configured are missing.
  let (_, reported) = update_dev(
    dispatch,
    Engine(
      None,
      @wire.McpConnectFailed(
        server="playwright",
        error="npx: command not found",
      ),
      session="desktop-test",
    ),
    test_model(),
  )
  guard reported.notifications.last() is Some({ message: Raw(message), .. }) else {
    fail("the failure should be reported")
  }
  assert_true(message.contains("playwright"))
  assert_true(message.has_suffix("npx: command not found"))
}

///|
test "an MCP failure stamped with a run this page has not opened yet still lands" {
  let dispatch = test_dispatch()
  // The host can stamp startup events with the id of the run it is about to
  // open, before this page has heard that the run started. The session stamp
  // is what routes them.
  let (_, reported) = update_dev(
    dispatch,
    Engine(
      Some("r-not-started-here"),
      @wire.McpConfigInvalid(
        path="/home/.openseek/mcp.json",
        error="configuration is missing an `mcpServers` object",
      ),
      session="desktop-test",
    ),
    test_model(),
  )
  guard reported.notifications.last() is Some({ message: Raw(message), .. }) else {
    fail("the failure should be reported")
  }
  assert_true(message.contains("/home/.openseek/mcp.json"))
}

///|
test "a server cut off by the MCP tool limit is reported" {
  let dispatch = test_dispatch()
  // The server connected, so nothing else marks it: without the toast the
  // tools past the limit are simply absent.
  let (_, reported) = update_dev(
    dispatch,
    Engine(
      None,
      @wire.McpToolsCapped(server="playwright", kept=100),
      session="desktop-test",
    ),
    test_model(),
  )
  guard reported.notifications.last() is Some({ message: Raw(message), .. }) else {
    fail("the dropped tools should be reported")
  }
  assert_true(message.contains("playwright"))
  assert_true(message.contains("100"))
}
