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
/// A two-request stand-in for the override path: while handling the first
/// request it steers the running turn, then answers content-only — which
/// without the pending steer would have finished the turn. The second
/// request must carry the steer and gets the real final answer.
async fn override_test_server(
  group : @async.TaskGroup[Unit],
  runtime : @agent_runtime.AgentRuntime,
) -> String? {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
    error => {
      let message = "\{error}"
      if message.contains("Operation not permitted") {
        println("local TCP bind unavailable; skipping override test")
        return None
      }
      raise error
    }
  }
  let mut requests = 0
  group.spawn_bg(no_wait=true) <| () => {
    server.run_forever(
      (_request, body, conn) => {
        requests += 1
        let request_body = body.read_all().text()
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        if requests == 1 {
          // The steer arrives while this "final" call is in flight.
          @agent.steer(runtime, "actually, make it rhyme")
          conn.write(
            "data: {\"choices\":[{\"delta\":{\"content\":\"draft answer\"}}]}\n\n",
          )
        } else {
          assert_true(request_body.contains("actually, make it rhyme"))
          assert_true(request_body.contains("draft answer"))
          conn.write(
            "data: {\"choices\":[{\"delta\":{\"content\":\"rhymed answer\"}}]}\n\n",
          )
        }
        conn.write("data: [DONE]\n\n")
      },
      max_connections=2,
    )
  }
  Some("http://127.0.0.1:\{server.addr.port()}/chat/completions")
}

///|
async test "a steer racing the final call keeps the turn alive" {
  @async.with_task_group() <| group => {
    let runtime = @agent_runtime.AgentRuntime()
    guard override_test_server(group, runtime) is Some(url) else { return }
    let scope = @agent_runtime.AgentTaskScope(group)
    let session = @agent_session.Session(
      SessionId("steer-override"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime,
      scope,
      "test-key",
      V4Flash,
      session,
      "write a poem",
      append_item=(session, item) => session.append(item),
      max_steps=3,
      api_url=url,
    )
    // User input beat the model's completion: the draft stayed an ordinary
    // assistant message, the steer follows it, and the turn finished on the
    // second answer.
    let events = result.events()
    assert_eq(events.length(), 4)
    assert_true(events[0].item() is User(_))
    guard events[1].item() is Assistant(draft) else {
      fail("expected the draft as an assistant message")
    }
    assert_eq(draft.content(), "draft answer")
    guard events[2].item() is User(steer) else { fail("expected steer event") }
    assert_eq(steer.content(), "actually, make it rhyme")
    guard events[3].item() is Terminal(Finished(answer)) else {
      fail("expected finished terminal")
    }
    assert_eq(answer, "rhymed answer")
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
