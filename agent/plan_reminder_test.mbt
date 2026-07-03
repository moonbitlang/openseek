///|
/// A scripted DeepSeek stand-in that keeps a turn alive with `plan` calls
/// whose arguments are invalid — each yields an error tool result, which
/// never resets the staleness cadence. The server only records request
/// bodies and scripts responses by request number; all assertions happen in
/// the test body after the run, so a client retry shows up as a hard
/// request-count mismatch instead of silently shifting the cadence.
async fn stale_plan_test_server(
  group : @async.TaskGroup[Unit],
  bodies : Array[String],
) -> String? {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
    error => {
      let message = "\{error}"
      if message.contains("Operation not permitted") {
        println("local TCP bind unavailable; skipping plan reminder test")
        return None
      }
      raise error
    }
  }
  group.spawn_bg(no_wait=true) <| () => {
    server.run_forever(
      (_request, body, conn) => {
        bodies.push(body.read_all().text())
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        if bodies.length() <= 11 {
          conn.write(
            (
              #|data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_plan","function":{"name":"plan","arguments":"{\"steps\":[{\"title\":\"step\",\"status\":\"doing\"}]}"}}]}}]}
            ),
          )
          conn.write("\n\n")
        } else {
          conn.write(
            "data: {\"choices\":[{\"delta\":{\"content\":\"done\"}}]}\n\n",
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
async test "a plan-silent turn gets one staleness reminder after ten requests" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard stale_plan_test_server(group, bodies) is Some(url) else { return }
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    let session = @agent_session.Session(
      SessionId("plan-reminder"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime,
      scope,
      "test-key",
      V4Flash,
      session,
      "do a long task",
      append_item=(session, item) => session.append(item),
      max_steps=20,
      api_url=url,
    )
    // Exactly 12 requests: 11 tool-call steps plus the finishing answer. A
    // retry would inflate the count and fail here rather than skew the
    // cadence assertions below.
    assert_eq(bodies.length(), 12)
    for index in 0..<10 {
      assert_false(
        bodies[index].contains("[plan reminder]"),
        msg="request \{index + 1} must not carry the reminder yet",
      )
    }
    assert_true(
      bodies[10].contains("[plan reminder]"),
      msg="request 11 should carry the reminder",
    )
    assert_true(bodies[10].contains("has not been used in this turn"))
    // The reminder is durable exactly once, in its plan-free nag variant.
    let reminders = [
      for event in result.events() if event.item() is Runtime(notice) &&
      notice.content().contains("[plan reminder]") => notice.content()
    ]
    assert_eq(reminders.length(), 1)
    assert_true(reminders[0].contains("has not been used in this turn"))
    guard result.events().peek() is Some(last) &&
      last.item() is Terminal(Finished(answer)) else {
      fail("expected finished terminal")
    }
    assert_eq(answer, "done")
  }
}

///|
/// A scripted stand-in where request 1 records a valid plan. The successful
/// write resets the cadence, so the reminder fires ten requests later — in
/// request 12 — and re-surfaces the recorded checklist. Assertions live in
/// the test body, as above.
async fn recorded_plan_test_server(
  group : @async.TaskGroup[Unit],
  bodies : Array[String],
) -> String? {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
    error => {
      let message = "\{error}"
      if message.contains("Operation not permitted") {
        println("local TCP bind unavailable; skipping plan reminder test")
        return None
      }
      raise error
    }
  }
  group.spawn_bg(no_wait=true) <| () => {
    server.run_forever(
      (_request, body, conn) => {
        bodies.push(body.read_all().text())
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        if bodies.length() == 1 {
          conn.write(
            (
              #|data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_plan","function":{"name":"plan","arguments":"{\"steps\":[{\"title\":\"fix the parser\",\"status\":\"in_progress\"}]}"}}]}}]}
            ),
          )
          conn.write("\n\n")
        } else if bodies.length() <= 12 {
          conn.write(
            (
              #|data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_plan","function":{"name":"plan","arguments":"{\"steps\":[{\"title\":\"step\",\"status\":\"doing\"}]}"}}]}}]}
            ),
          )
          conn.write("\n\n")
        } else {
          conn.write(
            "data: {\"choices\":[{\"delta\":{\"content\":\"done\"}}]}\n\n",
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
async test "a recorded plan delays the reminder and is re-surfaced by it" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard recorded_plan_test_server(group, bodies) is Some(url) else { return }
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    let session = @agent_session.Session(
      SessionId("plan-reminder-checklist"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime,
      scope,
      "test-key",
      V4Flash,
      session,
      "do a long task",
      append_item=(session, item) => session.append(item),
      max_steps=20,
      api_url=url,
    )
    // Exactly 13 requests: the plan write, 11 more tool-call steps, the
    // finishing answer.
    assert_eq(bodies.length(), 13)
    assert_false(
      bodies[10].contains("[plan reminder]"),
      msg="the successful plan write must delay the reminder past request 11",
    )
    assert_true(
      bodies[11].contains("[plan reminder]"),
      msg="request 12 should carry the reminder",
    )
    assert_true(bodies[11].contains("Current plan:"))
    assert_true(bodies[11].contains("1. [in_progress] fix the parser"))
    let reminders = [
      for event in result.events() if event.item() is Runtime(notice) &&
      notice.content().contains("[plan reminder]") => notice.content()
    ]
    assert_eq(reminders.length(), 1)
    assert_true(reminders[0].contains("1. [in_progress] fix the parser"))
  }
}
