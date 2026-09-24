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
    let recorded : Array[Int] = []
    for event in result.events() {
      if event.item() is Assistant(message) && message.usage() is Some(usage) {
        recorded.push(usage.total_tokens)
      }
    }
    assert_eq(recorded, [110, 220])
  }
}
