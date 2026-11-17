///|
async test "direct dispatch uses the host identity and tool groups" {
  let dispatcher = @mcp.Dispatcher(test_tools(), version="direct-test")
  let initialized = dispatcher.dispatch(
    request(1, "initialize", { "protocolVersion": "2025-11-25" }),
    session="host-session",
  )
  assert_true(
    initialized
    is Some(
      { "result": { "serverInfo": { "version": "direct-test", .. }, .. }, .. },
    ),
  )
  let listed = dispatcher.dispatch(
    request(2, "tools/list", {}),
    session="host-session",
    groups=["browser"],
  )
  assert_true(
    listed
    is Some(
      { "result": { "tools": [{ "name": "browser_get_text", .. }], .. }, .. },
    ),
  )
  let called = dispatcher.dispatch(
    request(3, "tools/call", {
      "name": "browser_get_text",
      "arguments": { "session": "forged-session" },
    }),
    session="host-session",
    groups=["browser"],
  )
  assert_true(
    called
    is Some(
      {
        "result": {
          "content": [
            { "text": "host-session {\"session\":\"forged-session\"}", .. },
          ],
          "isError": false,
          ..
        },
        ..
      },
    ),
  )
  let excluded = dispatcher.dispatch(
    request(4, "tools/call", { "name": "echo" }),
    session="host-session",
    groups=["browser"],
  )
  assert_true(excluded is Some({ "error": { "code": -32602, .. }, .. }))
}

///|
async test "HTTP and direct dispatch share later tool registrations" {
  with_server(server => {
    let dispatcher = server.dispatcher()
    server.add_tools([
      {
        name: "added",
        description: "A host-owned handler registered after transport setup.",
        input_schema: { "type": "object" },
        call: call => [Text(call.session)],
      },
    ])
    let direct = dispatcher.dispatch(
      request(1, "tools/call", { "name": "added" }),
      session="shared-session",
    )
    let (status, http) = post(
      grant(server, "shared-session"),
      request(1, "tools/call", { "name": "added" }),
    )
    assert_eq(status, 200)
    assert_eq(direct, http)
  })
}

///|
async test "direct dispatch validates stateless metadata without HTTP headers" {
  let dispatcher = @mcp.Dispatcher([], version="test")
  let discovered = dispatcher.dispatch(
    request(1, "server/discover", stateless_params()),
    session="host-session",
  )
  assert_true(
    discovered is Some({ "result": { "resultType": "complete", .. }, .. }),
  )
  let unsupported = dispatcher.dispatch(
    request(2, "server/discover", stateless_params(version="2099-01-01")),
    session="host-session",
  )
  assert_true(unsupported is Some({ "error": { "code": -32022, .. }, .. }))
  let missing_capabilities = dispatcher.dispatch(
    request(3, "server/discover", {
      "_meta": { "io.modelcontextprotocol/protocolVersion": "2026-07-28" },
    }),
    session="host-session",
  )
  assert_true(
    missing_capabilities is Some({ "error": { "code": -32602, .. }, .. }),
  )
}
