///|
test "Cloud MCP requests and events round trip without credentials" {
  let answer : @protocol.UserQuestionAnswer = {
    id: "q",
    session: "cloud-a",
    answers: Some({ "plan": "A" }),
  }
  let requests : Array[@protocol.CloudMcpRequest] = [
    Dispatch(account="123", session="cloud-a", message={
      "jsonrpc": "2.0",
      "id": 1,
      "method": "tools/list",
    }),
    Detach(account="123", session="cloud-a"),
    Questions(account="123"),
    Answer(account="123", answer~),
  ]
  for request in requests {
    let json = request.to_json()
    assert_eq((@json.from_json(json) : @protocol.CloudMcpRequest), request)
    assert_false(json.stringify().contains("token"))
  }
  let events : Array[@protocol.CloudMcpEvent] = [
    Questions(account="123", snapshot={ generation: 1, requests: [], }),
    Input(account="123", session="cloud-a", text="answer", id="q-result"),
  ]
  for event in events {
    let notification = @protocol.Notification::CloudMcp(event)
    assert_eq(
      @protocol.Notification::from_wire(
        "cloud.mcp.event",
        notification.params(),
      ),
      Some(notification),
    )
  }
  let browser : @protocol.BrowserEventPayload = CloudOpenRequested(
    account="123",
    request="open",
    session="cloud-a",
    url="https://example.test/",
  )
  assert_eq(
    (@json.from_json(browser.to_json()) : @protocol.BrowserEventPayload),
    browser,
  )
}

///|
test "Cloud MCP malformed actions and incomplete routing are rejected" {
  let malformed : Array[Json] = [
    { "account": "123", "action": "unknown" },
    { "account": "123", "action": "dispatch", "message": {} },
    { "action": "questions" },
    { "account": "123", "action": "answer", "answer": null },
  ]
  for json in malformed {
    let failed = try {
      let _ : @protocol.CloudMcpRequest = @json.from_json(json)
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
}
