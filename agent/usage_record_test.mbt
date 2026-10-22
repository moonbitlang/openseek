///|
async test "each provider response's usage is recorded on its assistant item" {
  @async.with_task_group() <| group => {
    let mut requests = 0
    guard serve_chat_completions(
        group,
        "local TCP bind unavailable; skipping usage record test",
        max_connections=2,
        (_request, _body, conn) => {
          requests += 1
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          if requests == 1 {
            conn.write(
              (
                #|data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"probe","arguments":"{}"}}]}}],"usage":{"prompt_tokens":100,"completion_tokens":10,"total_tokens":110,"prompt_cache_hit_tokens":60,"prompt_cache_miss_tokens":40}}
                #|
                #|
              ),
            )
          } else {
            conn.write(
              (
                #|data: {"choices":[{"delta":{"content":"done"}}],"usage":{"prompt_tokens":200,"completion_tokens":20,"total_tokens":220,"prompt_cache_hit_tokens":150,"prompt_cache_miss_tokens":50}}
                #|
                #|
              ),
            )
          }
          conn.write("data: [DONE]\n\n")
        },
      )
      is Some(url) else {
      return
    }
    let tools = @agent_tool.Tools([
      AgentToolDefinition(
        name="probe",
        description="Probe tool.",
        schema=JsonSchema({ "type": "object" }),
        execute=Sync(_args => @agent_tool.respond("ok")),
      ),
    ])
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=Session(SessionId("usage"), system_prompt="s"),
      content=Content([Text("go")]),
      append_item=(session, item) => session.append(item),
      max_steps=2,
      api_url=url,
      tools~,
    )
    // One usage per response, on the item that first records it: the
    // tool-call step and the final answer.
    let recorded : Array[Int32] = []
    for event in result.events() {
      if event.item() is Assistant(message) && message.usage() is Some(usage) {
        recorded.push(usage.total_tokens)
      }
    }
    assert_eq(recorded, [110, 220])
    assert_eq(result.usage_records().map(record => record.call), [1, 2])
    assert_eq(
      result.usage_records().map(record => record.report.total_tokens),
      [Some(110), Some(220)],
    )
    assert_eq(result.supplemental_usage().length(), 0)
  }
}

///|
async test "failed streaming attempts and successful response share call identity without double counting" {
  @async.with_task_group() <| group => {
    let hits = Ref(0)
    guard serve_chat_completions(
        group,
        "local TCP bind unavailable; skipping usage test",
        max_connections=2,
        (_request, _body, conn) => {
          hits.val += 1
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          if hits.val == 1 {
            conn.write(
              "data: {\"id\":\"first\",\"usage\":{\"total_tokens\":13}}\n\n",
            )
          } else {
            conn.write(
              "data: {\"id\":\"second\",\"choices\":[{\"delta\":{\"content\":\"done\"}}],\"usage\":{\"total_tokens\":0}}\n\ndata: [DONE]\n\n",
            )
          }
        },
      )
      is Some(url) else {
      return
    }
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=Session(SessionId("parent-sr-3"), system_prompt="s"),
      content=Content([Text("go")]),
      append_item=(session, item) => session.append(item),
      tools=Tools([]),
      api_url=url,
      retry_attempts=2,
      retry_backoff_ms=1,
    )
    let records = result.usage_records()
    assert_eq(records.length(), 2)
    assert_eq(records.map(record => record.session_id), [
      "parent-sr-3", "parent-sr-3",
    ])
    assert_eq(records.map(record => record.call), [1, 1])
    assert_eq(records.map(record => record.attempt), [1, 2])
    assert_eq(records.map(record => record.outcome), ["failed", "completed"])
    assert_eq(records.map(record => record.report.total_tokens), [
      Some(13),
      Some(0),
    ])
    assert_eq(result.supplemental_usage().length(), 1)
    assert_eq(
      result.events().iter().filter(event => event.is_agent_step()).count(),
      1,
    )
  }
}

///|
async test "reported usage survives a later assistant append failure" {
  @async.with_task_group() <| group => {
    guard serve_chat_completions(
        group,
        "local TCP bind unavailable; skipping usage test",
        max_connections=1,
        (_request, _body, conn) => {
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          conn.write(
            "data: {\"choices\":[{\"delta\":{\"content\":\"done\"}}],\"usage\":{\"total_tokens\":17}}\n\ndata: [DONE]\n\n",
          )
        },
      )
      is Some(url) else {
      return
    }
    let initial = @agent_session.Session(
      SessionId("append-fails"),
      system_prompt="s",
    )
    let persisted = Ref(initial)
    let failed = try {
      ignore(
        @agent.run_turn_in_scope(
          runtime=AgentRuntime(),
          scope=AgentTaskScope(group),
          api_key="test-key",
          model=Deepseek(V4Flash),
          session=initial,
          content=Content([Text("go")]),
          tools=Tools([]),
          api_url=url,
          append_item=(session, item) => {
            if item is Assistant(_) {
              fail("synthetic assistant append failure")
            }
            let next = session.append(item)
            persisted.val = next
            next
          },
          append_usage=(session, record) => {
            let next = session.append_usage(record)
            persisted.val = next
            next
          },
        ),
      )
      false
    } catch {
      _ => true
    }
    assert_true(failed)
    assert_eq(persisted.val.usage_records().length(), 1)
    assert_eq(persisted.val.usage_records()[0].report.total_tokens, Some(17))
    assert_true(
      persisted.val.last_terminal() is Some(Failed(message)) &&
      message.contains("synthetic assistant append failure"),
    )
  }
}

///|
async test "auto-compaction records usage before summary validation" {
  for summary in ["", "checkpoint"] {
    @async.with_task_group() <| group => {
      guard auto_compact_test_server(group, request => {
          if is_checkpoint_request(request) {
            Body({
              "choices": [{ "message": { "content": summary } }],
              "usage": { "total_tokens": 29 },
            })
          } else {
            Sse(sse_final_with_reasoning("done", "", 900_000))
          }
        })
        is Some(url) else {
        return
      }
      let result = @agent.run_turn_in_scope(
        runtime=AgentRuntime(),
        scope=AgentTaskScope(group),
        api_key="test-key",
        model=Deepseek(V4Flash),
        session=Session(SessionId("auto-usage"), system_prompt="s"),
        content=Content([Text("go")]),
        append_item=(session, item) => session.append(item),
        tools=Tools([]),
        api_url=url,
      )
      let records = result.usage_records()
      assert_eq(records.length(), 2)
      assert_eq(records.map(record => record.purpose), [
        "agent", "auto_compaction",
      ])
      assert_eq(records.map(record => record.call), [1, 2])
      assert_eq(records[1].report.total_tokens, Some(29))
      assert_eq(
        result
        .events()
        .iter()
        .filter(event => event.item() is Summary(_))
        .count(),
        if summary == "" {
          0
        } else {
          1
        },
      )
    }
  }
}
