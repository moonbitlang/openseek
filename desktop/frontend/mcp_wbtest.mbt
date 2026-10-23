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
      @wire.McpConfigInvalid(
        path="/home/.openseek/mcp.json",
        error="configuration is missing an `mcpServers` object",
      ),
      session="desktop-test",
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
      @wire.McpToolsCapped(server="playwright", kept=100),
      session="desktop-test",
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
fn current_key(model : Model) -> @interop.ConversationKey {
  { channel: Local, session: model.active_session, }
}

///|
test "showing the overview asks the engine of the conversation on screen" {
  let dispatch = test_dispatch()
  let model = test_model()
  // Hidden, the overview describes nothing and asks nothing.
  assert_true(model.overview_conversation() is None)
  let (_, shown) = update(dispatch, ToggleOverview, model)
  assert_true(shown.overview_open)
  assert_true(shown.overview_conversation() == Some(current_key(model)))
  assert_true(shown.mcp.phase is Checking)
  assert_true(shown.mcp.conversation == Some(current_key(model)))
  // The answer is routed back into the connectors card.
  let (_, answered) = update(
    dispatch,
    Mcp(Checked(serial=shown.mcp.serial, Ok(Stopped))),
    shown,
  )
  assert_true(answered.mcp.phase is Loaded(Stopped))
  // Hiding asks nothing and keeps the answer.
  let (_, hidden) = update(dispatch, ToggleOverview, answered)
  assert_false(hidden.overview_open)
  assert_true(hidden.mcp == answered.mcp)
  // Showing it again asks again, with the last answer on show meanwhile:
  // what the engine holds changes on its own.
  let (_, again) = update(dispatch, ToggleOverview, hidden)
  assert_true(again.mcp.phase is Reloading(Stopped))
  assert_true(again.mcp.serial != answered.mcp.serial)
}

///|
test "the overview stays shown across conversations and asks about each" {
  let dispatch = test_dispatch()
  let (_, shown) = update(dispatch, ToggleOverview, test_model())
  let (_, answered) = update(
    dispatch,
    Mcp(Checked(serial=shown.mcp.serial, Ok(Connecting))),
    shown,
  )
  let second = empty_conversation(
    @interop.ChannelId::Local,
    "second-session",
    @interop.ChannelId::Local.test_project(),
  )
  let (_, switched) = update(dispatch, OpenSession(Local, "second-session"), {
    ..answered,
    conversations: [..answered.conversations, second],
  })
  assert_eq(switched.active_session, "second-session")
  assert_true(switched.overview_open)
  assert_true(
    switched.mcp.conversation ==
    Some({ channel: Local, session: "second-session", }),
  )
  assert_true(switched.mcp.phase is Checking)
  // Settings has no conversation to describe: nothing is asked, and the
  // overview is still on when the conversation comes back.
  let (_, settings) = update(dispatch, OpenSetup, switched)
  assert_true(settings.overview_open)
  assert_true(settings.overview_conversation() is None)
  assert_true(settings.mcp == switched.mcp)
}

///|
test "an engine's MCP report tells the overview showing its conversation to read again" {
  let dispatch = test_dispatch()
  let model = test_model()
  let current = current_key(model)
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
  // Before the overview has shown there is nothing to keep current.
  let (_, untouched) = update_dev(dispatch, McpChanged(session), model)
  assert_true(untouched.mcp == model.mcp)
  let (_, shown) = update(dispatch, ToggleOverview, model)
  let (_, answered) = update(
    dispatch,
    Mcp(Checked(serial=shown.mcp.serial, Ok(Connecting))),
    shown,
  )
  // The engine was still connecting when asked; its report asks again, with
  // the last answer left on show.
  let (_, reported) = update_dev(dispatch, McpChanged(session), answered)
  assert_true(reported.mcp.phase is Reloading(Connecting))
  assert_true(reported.mcp.serial != answered.mcp.serial)
  // Another session's engine is not this overview's business.
  let (_, other) = update_dev(dispatch, McpChanged("another-session"), answered)
  assert_true(other.mcp == answered.mcp)
}

///|
test "a reconnected device has the overview read its conversation again" {
  let dispatch = test_dispatch()
  let (_, shown) = update(dispatch, ToggleOverview, test_model())
  let (_, answered) = update(
    dispatch,
    Mcp(Checked(serial=shown.mcp.serial, Ok(Connecting))),
    shown,
  )
  // A report sent while the connection was down is not replayed, so the
  // overview cannot know whether what it shows is still so.
  let (_, reconnected) = update_dev(dispatch, BridgeReady, answered)
  assert_true(reconnected.mcp.phase is Reloading(Connecting))
  assert_true(reconnected.mcp.serial != answered.mcp.serial)
}

///|
test "the stored overview choice is read back" {
  let (_, shown) = update(test_dispatch(), OverviewLoaded(true), test_model())
  assert_true(shown.overview_open)
  let (_, hidden) = update(test_dispatch(), OverviewLoaded(false), shown)
  assert_false(hidden.overview_open)
}
