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
      McpServerFailed(server="playwright", error="npx: command not found"),
      session=Some("desktop-test"),
    ),
    test_model(),
  )
  guard reported.notifications.last() is Some(toast) else {
    fail("the failure should be reported")
  }
  assert_true(toast.message.contains("playwright"))
  assert_true(toast.message.has_suffix("npx: command not found"))
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
      McpConfigFailed(
        path="/home/.openseek/mcp.json",
        error="configuration is missing an `mcpServers` object",
      ),
      session=Some("desktop-test"),
    ),
    test_model(),
  )
  guard reported.notifications.last() is Some(toast) else {
    fail("the failure should be reported")
  }
  assert_true(toast.message.contains("/home/.openseek/mcp.json"))
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
      McpToolsDropped(server="playwright", limit=100),
      session=Some("desktop-test"),
    ),
    test_model(),
  )
  guard reported.notifications.last() is Some(toast) else {
    fail("the dropped tools should be reported")
  }
  assert_true(toast.message.contains("playwright"))
  assert_true(toast.message.contains("100"))
}

///|
test "opening Settings asks the current conversation's engine for its MCP state" {
  let dispatch = test_dispatch()
  let model = test_model()
  guard model.mcp_subject() is Conversation(current) else {
    fail("the test model has a conversation on screen")
  }
  let (_, opened) = update(dispatch, OpenSetup, model)
  assert_true(opened.screen is Settings)
  assert_true(opened.mcp.phase is Checking)
  assert_true(opened.mcp.conversation == Some(current))
  // The answer is routed back into the panel.
  let (_, answered) = update(
    dispatch,
    Mcp(Checked(serial=opened.mcp.serial, Ok(Stopped))),
    opened,
  )
  assert_true(answered.mcp.phase is Loaded(Stopped))
  // Still about that conversation while Settings covers it.
  assert_true(answered.mcp_subject() is Conversation(shown) && shown == current)
}

///|
test "Settings opened over a Codex conversation does not ask an OpenSeek engine" {
  let dispatch = test_dispatch()
  // The last OpenSeek conversation stays loaded behind the Codex screen, but
  // Codex takes its servers from its own configuration.
  let model = { ..test_model(), screen: Codex, }
  assert_true(model.active_conversation() is Some(_))
  assert_true(model.mcp_subject() is CodexConversation)
  let (_, opened) = update(dispatch, OpenSetup, model)
  assert_true(opened.mcp.phase is Unchecked)
  assert_true(opened.mcp.conversation is None)
  assert_true(opened.mcp_subject() is CodexConversation)
}

///|
test "an engine's MCP report tells the panel showing its conversation to read again" {
  let dispatch = test_dispatch()
  let model = test_model()
  guard model.mcp_subject() is Conversation(current) else {
    fail("the test model has a conversation on screen")
  }
  // The report itself is the host's to keep; the page only learns that the
  // session has a newer one.
  guard engine_msg({
      run_id: None,
      session: current.session,
      event: McpStatus(status={ configs: [], servers: [], }),
    })
    is Some(McpChanged(session)) else {
    fail("the report should reach the page as a change to read")
  }
  assert_eq(session, current.session)
  // Before Settings has opened there is nothing to keep current.
  let (_, untouched) = update_dev(dispatch, McpChanged(session), model)
  assert_true(untouched.mcp == model.mcp)
  let (_, opened) = update(dispatch, OpenSetup, model)
  let (_, answered) = update(
    dispatch,
    Mcp(Checked(serial=opened.mcp.serial, Ok(Connecting))),
    opened,
  )
  // The engine was still connecting when asked; its report asks again, with
  // the last answer left on show.
  let (_, reported) = update_dev(dispatch, McpChanged(session), answered)
  assert_true(reported.mcp.phase is Reloading(Connecting))
  assert_true(reported.mcp.serial != answered.mcp.serial)
  // Another session's engine is not this panel's business.
  let (_, other) = update_dev(dispatch, McpChanged("another-session"), answered)
  assert_true(other.mcp == answered.mcp)
}

///|
test "a reconnected device has the panel read its conversation again" {
  let dispatch = test_dispatch()
  let (_, opened) = update(dispatch, OpenSetup, test_model())
  let (_, answered) = update(
    dispatch,
    Mcp(Checked(serial=opened.mcp.serial, Ok(Connecting))),
    opened,
  )
  // A report sent while the connection was down is not replayed, so the
  // panel cannot know whether what it shows is still so.
  let (_, reconnected) = update_dev(dispatch, BridgeReady, answered)
  assert_true(reconnected.mcp.phase is Reloading(Connecting))
  assert_true(reconnected.mcp.serial != answered.mcp.serial)
}
