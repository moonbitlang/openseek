///|
async test "prediction preserves the main request prefix and leaves the session intact" {
  let session = @agent_session.Session(
      SessionId("prediction"),
      system_prompt="EXECUTE ALL TOOLS",
    )
    .append(User(UserMessage(Content([Text("修复菜单选择的问题")]))))
    .append(
      Assistant(
        AssistantMessage(
          "",
          tool_calls=[ToolCall(id="t", name="shell", arguments="{}")],
          reasoning_content="Inspect the menu implementation first.",
        ),
      ),
    )
    .append(
      Tool(
        ToolResult(tool_call_id="t", tool_name="shell", content=[
          Text("VERBOSE_TOOL_OUTPUT".repeat(2000)),
        ]),
      ),
    )
    .append(Terminal(Finished("已修复，测试通过。")))
  let tools : Array[@deepseek.ToolDefinition] = [
    ToolDefinition("shell", "Run a shell command", { "type": "object" }),
  ]
  let original_request = @deepseek.encode_chat_request(
    session.chat_messages(),
    tools~,
    thinking=High,
  )
  guard original_request
    is { "messages": Array(original_messages), "tools": original_tools, .. } else {
    fail("missing main request context")
  }
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(
        (_request, body, conn) => {
          let request = @json.parse(body.read_all().text())
          assert_true(
            request
            is {
              "thinking": { "type": "enabled", .. },
              "reasoning_effort": "high",
              ..
            },
          )
          assert_true(request is { "max_tokens": 1024, "stream": false, .. })
          guard request
            is { "messages": Array(messages), "tools": tool_definitions, .. } else {
            fail("expected inherited context")
          }
          assert_false(request is { "response_format": _, .. })
          assert_eq(tool_definitions, original_tools)
          assert_eq(messages.length(), original_messages.length() + 1)
          for index in 0..<original_messages.length() {
            assert_eq(messages[index], original_messages[index])
          }
          assert_true(
            messages.last()
            is Some({ "role": "user", "content": String(prompt), .. }) &&
            prompt.contains("Predict the single message"),
          )
          let reply : Json = {
            "choices": [
              { "message": { "content": "{\"text\":\"提交这个修复\"}" } },
            ],
            "usage": {
              "prompt_tokens": 40,
              "completion_tokens": 8,
              "total_tokens": 48,
              "prompt_cache_hit_tokens": 32,
              "prompt_cache_miss_tokens": 8,
            },
          }
          conn.send_response(200, "OK")
          conn.write_string(reply.stringify())
          conn.end_response()
        },
        max_connections=1,
      )
    })
    let client = @client.Client(
      api_key="fixture",
      thinking=High,
      retry_attempts=1,
      api_url="http://127.0.0.1:\{server.addr.port()}/chat/completions",
    )
    guard @prediction.generate(client, session, tools~)
      is Completed(text~, usage~) else {
      fail("missing prediction")
    }
    assert_eq(text, Some("提交这个修复"))
    assert_eq(usage.prompt_tokens, 40)
    assert_eq(usage.prompt_cache_hit_tokens, 32)
    assert_eq(usage.prompt_cache_miss_tokens, 8)
    assert_eq(
      @deepseek.encode_chat_request(
        session.chat_messages(),
        tools~,
        thinking=High,
      ),
      original_request,
    )
    assert_eq(session.last_sequence(), 4)
  })
}

///|
async test "empty context skips without contacting the provider" {
  let client = @client.Client(
    api_key="unused",
    api_url="http://127.0.0.1:1",
    retry_attempts=1,
  )
  let empty = @agent_session.Session(SessionId("empty"), system_prompt="system")
  assert_true(@prediction.generate(client, empty, tools=[]) is Skipped)
}

///|
async test "uncertain predictions are absent and malformed model output stays an error" {
  let session = @agent_session.Session(
      SessionId("output"),
      system_prompt="system",
    )
    .append(User(UserMessage(Content([Text("Finish the fix")]))))
    .append(Terminal(Finished("Done")))
  let responses = [
    "{\"text\":null}", "{\"text\":\"\"}", "{\"text\":\"first\\nsecond\"}", "{\"text\":42}",
    "not json",
  ]
  let mut index = 0
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true, () => {
      server.run_forever(
        (_request, body, conn) => {
          ignore(body.read_all())
          let content = responses[index]
          index += 1
          let reply : Json = {
            "choices": [{ "message": { "content": content } }],
            "usage": {
              "prompt_tokens": 10,
              "completion_tokens": 5,
              "total_tokens": 15,
            },
          }
          conn.send_response(200, "OK")
          conn.write_string(reply.stringify())
          conn.end_response()
        },
        max_connections=1,
      )
    })
    let client = @client.Client(
      api_key="fixture",
      thinking=No,
      retry_attempts=1,
      api_url="http://127.0.0.1:\{server.addr.port()}/chat/completions",
    )
    guard @prediction.generate(client, session, tools=[])
      is Completed(text=None, usage~) else {
      fail("expected a completed prediction without a suggestion")
    }
    assert_eq(usage.prompt_tokens, 10)
    assert_eq(usage.completion_tokens, 5)
    for _ in 1..<responses.length() {
      let failed = try @prediction.generate(client, session, tools=[]) catch {
        _ => true
      } noraise {
        _ => false
      }
      assert_true(failed)
    }
  })
  assert_eq(index, responses.length())
}
