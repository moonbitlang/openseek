///|
async fn tool_batch_test_server(group : @async.TaskGroup[Unit]) -> String? {
  let mut requests = 0
  serve_chat_completions(
    group,
    "local TCP bind unavailable; skipping tool batch test",
    max_connections=2,
    (request, request_body, conn) => {
      requests += 1
      assert_eq(request.path, "/chat/completions")
      conn.send_response(200, "OK", extra_headers={
        "Content-Type": "text/event-stream",
      })
      if requests == 1 {
        assert_true(request_body.contains("\"name\":\"first_test\""))
        assert_true(request_body.contains("\"name\":\"second_test\""))
        conn.write(
          (
            #|data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_first","type":"function","function":{"name":"first_test","arguments":"{}"}},{"index":1,"id":"call_second","type":"function","function":{"name":"second_test","arguments":"{}"}}]}}]}
            #|
            #|
          ),
        )
      } else {
        assert_true(request_body.contains("first-result"))
        assert_true(request_body.contains("second-result"))
        conn.write(
          (
            #|data: {"choices":[{"delta":{"content":"done"}}]}
            #|
            #|
          ),
        )
      }
      conn.write("data: [DONE]\n\n")
    },
  )
}

///|
async test "agent executes each normal tool call in a response batch" {
  @async.with_task_group() <| group => {
    guard tool_batch_test_server(group) is Some(url) else { return }
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    let session = @agent_session.Session(
      SessionId("tool-batch-test"),
      system_prompt="system",
    )
    let mut first_called = false
    let mut second_called = false
    let tools = @agent_tool.Tools([
      AgentToolDefinition(
        name="first_test",
        description="First batch test tool.",
        schema=JsonSchema({ "type": "object" }),
        execute=Sync(_args => {
          first_called = true
          @agent_tool.respond("first-result")
        }),
      ),
      AgentToolDefinition(
        name="second_test",
        description="Second batch test tool.",
        schema=JsonSchema({ "type": "object" }),
        execute=Sync(_args => {
          second_called = true
          @agent_tool.respond("second-result")
        }),
      ),
    ])
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope~,
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="run both tools",
      append_item=(session, item) => session.append(item),
      max_steps=2,
      api_url=url,
      tools~,
    )
    assert_true(first_called)
    assert_true(second_called)
    let events = result.events()
    assert_eq(events.length(), 6)
    assert_true(events[0].item() is User(_))
    guard events[1].item() is Assistant(message) else {
      fail("expected assistant tool-call event")
    }
    assert_eq(message.tool_calls().length(), 2)
    guard events[2].item() is Tool(first_result) else {
      fail("expected first tool result")
    }
    assert_eq(first_result.tool_call_id(), "call_first")
    assert_eq(first_result.content(), "first-result")
    guard events[3].item() is Tool(second_result) else {
      fail("expected second tool result")
    }
    assert_eq(second_result.tool_call_id(), "call_second")
    assert_eq(second_result.content(), "second-result")
    guard events[4].item() is Assistant(final_response) else {
      fail("expected durable final response")
    }
    assert_eq(final_response.content(), "done")
    guard events[5].item() is Terminal(Finished(answer)) else {
      fail("expected finished terminal")
    }
    assert_eq(answer, "done")
  }
}

///|
/// A stand-in that answers every request with a single `tool_name` call
/// (id `call_id`), after checking the request advertised that tool.
async fn one_tool_call_server(
  group : @async.TaskGroup[Unit],
  skip_message : String,
  tool_name~ : String,
  call_id~ : String,
) -> String? {
  serve_chat_completions(group, skip_message, max_connections=1, (
    _request,
    request_body,
    conn,
  ) => {
    assert_true(request_body.contains("\"name\":\"\{tool_name}\""))
    conn.send_response(200, "OK", extra_headers={
      "Content-Type": "text/event-stream",
    })
    conn.write(
      "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"\{call_id}\",\"type\":\"function\",\"function\":{\"name\":\"\{tool_name}\",\"arguments\":\"{}\"}}]}}]}\n\n",
    )
    conn.write("data: [DONE]\n\n")
  })
}

///|
async test "max-step exhaustion preserves continued session state" {
  @async.with_task_group() <| group => {
    guard one_tool_call_server(
        group,
        "local TCP bind unavailable; skipping max-step exhaustion test",
        tool_name="continue_test",
        call_id="call_continue",
      )
      is Some(url) else {
      return
    }
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    let session = @agent_session.Session(
      SessionId("max-step-exhaustion-test"),
      system_prompt="system",
    )
    let tools = @agent_tool.Tools([
      AgentToolDefinition(
        name="continue_test",
        description="Force the agent loop to continue.",
        schema=JsonSchema({ "type": "object" }),
        execute=Sync(_args => @agent_tool.respond("continue-result")),
      ),
    ])
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope~,
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="run one tool then exhaust",
      append_item=(session, item) => session.append(item),
      max_steps=1,
      api_url=url,
      tools~,
    )
    let events = result.events()
    assert_eq(events.length(), 4)
    assert_true(events[0].item() is User(_))
    guard events[1].item() is Assistant(message) else {
      fail("expected assistant tool-call event")
    }
    assert_eq(message.tool_calls().length(), 1)
    guard events[2].item() is Tool(tool_result) else {
      fail("expected tool result")
    }
    assert_eq(tool_result.tool_call_id(), "call_continue")
    assert_eq(tool_result.content(), "continue-result")
    guard events[3].item() is Terminal(Failed(message)) else {
      fail("expected exhausted terminal")
    }
    assert_eq(message, "max steps exhausted")
  }
}

///|
async test "agent failure terminal uses the latest persisted session" {
  @async.with_task_group() <| group => {
    guard one_tool_call_server(
        group,
        "local TCP bind unavailable; skipping append failure test",
        tool_name="ok_test",
        call_id="call_ok",
      )
      is Some(url) else {
      return
    }
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    let initial = @agent_session.Session(
      SessionId("append-failure-test"),
      system_prompt="system",
    )
    let mut persisted = initial
    let mut rejected_tool_result = false
    let tools = @agent_tool.Tools([
      AgentToolDefinition(
        name="ok_test",
        description="Produce a normal response after the assistant tool call.",
        schema=JsonSchema({ "type": "object" }),
        execute=Sync(_args => @agent_tool.respond("ok-result")),
      ),
    ])
    let _ = @agent.run_turn_in_scope(
      runtime~,
      scope~,
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=initial,
      task="run the append failure tool",
      append_item=(session, item) => {
        assert_eq(session.events().length(), persisted.events().length())
        if item is Tool(_) && !rejected_tool_result {
          rejected_tool_result = true
          fail("persist tool result failed")
        }
        let next = session.append(item)
        persisted = next
        next
      },
      max_steps=1,
      api_url=url,
      tools~,
    ) catch {
      error => {
        assert_true("\{error}".contains("persist tool result failed"))
        assert_true(rejected_tool_result)
        let events = persisted.events()
        assert_eq(events.length(), 3)
        assert_true(events[0].item() is User(_))
        guard events[1].item() is Assistant(message) else {
          fail("expected persisted assistant tool call")
        }
        assert_eq(message.tool_calls().length(), 1)
        guard events[2].item() is Terminal(Failed(message)) else {
          fail("expected persisted failure terminal")
        }
        assert_true(message.contains("persist tool result failed"))
        return
      }
    }
    fail("expected append failure")
  }
}
