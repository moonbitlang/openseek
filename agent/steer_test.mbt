///|
/// A one-request DeepSeek stand-in for steering tests: asserts the request
/// carries both the original task and the steered text as user messages, then
/// streams a plain content answer so the turn finishes without tool calls.
async fn steer_test_server(group : @async.TaskGroup[Unit]) -> String? {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
    error => {
      let message = "\{error}"
      if message.contains("Operation not permitted") {
        println("local TCP bind unavailable; skipping steer test: \{message}")
        return None
      }
      raise error
    }
  }
  group.spawn_bg(no_wait=true) <| () => {
    server.run_forever(
      (request, body, conn) => {
        assert_eq(request.path, "/chat/completions")
        let request_body = body.read_all().text()
        assert_true(request_body.contains("do the task"))
        assert_true(request_body.contains("also rename the file"))
        // The prebuilt registry reached the request: the standard tools ride
        // along even though the caller, not the turn, constructed them.
        assert_true(request_body.contains("\"name\":\"moon_check\""))
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        conn.write("data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\n")
        conn.write("data: [DONE]\n\n")
      },
      max_connections=1,
    )
  }
  Some("http://127.0.0.1:\{server.addr.port()}/chat/completions")
}

///|
async test "queued steering is folded in at the next step boundary" {
  @async.with_task_group() <| group => {
    guard steer_test_server(group) is Some(url) else { return }
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    // Steer before the turn starts: the loop drains the steering queue at
    // its first step boundary, so the steered text must reach the model
    // alongside the task (the mock server asserts both are in the body).
    @agent.steer(runtime, "also rename the file")
    let session = @agent_session.Session(
      SessionId("steer-test"),
      system_prompt="system",
    )
    // The registry is built once by the caller, the way a serve-mode engine
    // shares it across turns.
    let tools = @agent.build_tools(runtime, scope)
    let result = @agent.run_turn_in_scope(
      runtime,
      scope,
      "test-key",
      V4Flash,
      session,
      "do the task",
      append_item=(session, item) => session.append(item),
      max_steps=2,
      api_url=url,
      tools~,
    )
    // The steered text is durably part of the conversation: task, steer,
    // then the finished terminal.
    let events = result.events()
    assert_eq(events.length(), 3)
    guard events[0].item() is User(task) else { fail("expected task event") }
    assert_eq(task.content(), "do the task")
    guard events[1].item() is User(steer) else { fail("expected steer event") }
    assert_eq(steer.content(), "also rename the file")
    guard events[2].item() is Terminal(Finished(answer)) else {
      fail("expected finished terminal")
    }
    assert_eq(answer, "ok")
  }
}

///|
async test "blank steering input is dropped at the boundary" {
  @async.with_task_group() <| group => {
    guard steer_test_server(group) is Some(url) else { return }
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    @agent.steer(runtime, "   ")
    @agent.steer(runtime, "also rename the file")
    let session = @agent_session.Session(
      SessionId("steer-blank"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime,
      scope,
      "test-key",
      V4Flash,
      session,
      "do the task",
      append_item=(session, item) => session.append(item),
      max_steps=2,
      api_url=url,
    )
    // The blank steer left no trace; only the real one was applied.
    assert_eq(result.events().length(), 3)
  }
}
