///|
/// A scripted DeepSeek stand-in that keeps a turn alive with `plan` calls
/// whose arguments are invalid — each yields an error tool result, which
/// never resets the staleness cadence — for the first `plan_calls` requests,
/// then answers. The server only records request bodies and scripts responses
/// by request number; all assertions happen in the test body after the run,
/// so a client retry shows up as a hard request-count mismatch instead of
/// silently shifting the cadence.
async fn stale_plan_test_server(
  group : @async.TaskGroup[Unit],
  bodies : Array[String],
  plan_calls~ : Int,
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
        if bodies.length() <= plan_calls {
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
    guard stale_plan_test_server(group, bodies, plan_calls=11) is Some(url) else {
      return
    }
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    let session = @agent_session.Session(
      SessionId("plan-reminder"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope~,
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="do a long task",
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
        bodies[index].contains(@agent_session.PlanReminderPrefix),
        msg="request \{index + 1} must not carry the reminder yet",
      )
    }
    assert_true(
      bodies[10].contains(@agent_session.PlanReminderPrefix),
      msg="request 11 should carry the reminder",
    )
    assert_true(bodies[10].contains("has not been used in this turn"))
    // The reminder is durable exactly once, in its plan-free nag variant.
    let reminders = [
      for event in result.events() if event.item() is Runtime(notice) &&
      notice.content().contains(@agent_session.PlanReminderPrefix) => {
        notice.content()
      }
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
/// A scripted stand-in where request 1 records a valid plan and requests
/// 2..plan_calls keep the turn alive with invalid `plan` calls before the
/// answer. The successful write resets the cadence, so the first reminder
/// fires ten requests later — in request 12 — and re-surfaces the recorded
/// checklist. Assertions live in the test body, as above.
async fn recorded_plan_test_server(
  group : @async.TaskGroup[Unit],
  bodies : Array[String],
  plan_calls~ : Int,
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
        } else if bodies.length() <= plan_calls {
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
    guard recorded_plan_test_server(group, bodies, plan_calls=12) is Some(url) else {
      return
    }
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    let session = @agent_session.Session(
      SessionId("plan-reminder-checklist"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope~,
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="do a long task",
      append_item=(session, item) => session.append(item),
      max_steps=20,
      api_url=url,
    )
    // Exactly 13 requests: the plan write, 11 more tool-call steps, the
    // finishing answer.
    assert_eq(bodies.length(), 13)
    assert_false(
      bodies[10].contains(@agent_session.PlanReminderPrefix),
      msg="the successful plan write must delay the reminder past request 11",
    )
    assert_true(
      bodies[11].contains(@agent_session.PlanReminderPrefix),
      msg="request 12 should carry the reminder",
    )
    assert_true(bodies[11].contains("Current plan:"))
    assert_true(bodies[11].contains("1. [in_progress] fix the parser"))
    let reminders = [
      for event in result.events() if event.item() is Runtime(notice) &&
      notice.content().contains(@agent_session.PlanReminderPrefix) => {
        notice.content()
      }
    ]
    assert_eq(reminders.length(), 1)
    assert_true(reminders[0].contains("1. [in_progress] fix the parser"))
  }
}

///|
/// Occurrences of the reminder marker in one request body. Bodies carry the
/// whole conversation, so a reminder injected once keeps appearing in every
/// later request — "did it fire again" is a count on the newest body, not an
/// absence check on it.
fn reminder_count(body : String) -> Int {
  body.split(@agent_session.PlanReminderPrefix).collect().length() - 1
}

///|
/// The no-plan nudge is capped at once per turn: a turn that stays plan-silent
/// long enough for a second window (request 21 would re-fire under a pure
/// 10/10 cadence) still gets exactly one reminder — repeating "consider
/// recording a plan" that the model already declined once is pure noise.
async test "the no-plan nag fires at most once per turn" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard stale_plan_test_server(group, bodies, plan_calls=23) is Some(url) else {
      return
    }
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    let session = @agent_session.Session(
      SessionId("plan-nag-once"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope~,
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="do a long task",
      append_item=(session, item) => session.append(item),
      max_steps=30,
      api_url=url,
    )
    // Exactly 24 requests: 23 tool-call steps plus the finishing answer.
    assert_eq(bodies.length(), 24)
    for index in 0..<10 {
      assert_eq(
        reminder_count(bodies[index]),
        0,
        msg="request \{index + 1} must not carry the reminder yet",
      )
    }
    assert_eq(
      reminder_count(bodies[10]),
      1,
      msg="request 11 should carry the only reminder",
    )
    // A pure 10/10 cadence would inject a second nag in request 21; the
    // once-per-turn cap suppresses it, so the final request still carries
    // exactly one reminder in its history.
    assert_eq(
      reminder_count(bodies[23]),
      1,
      msg="no later request may gain a second no-plan nag",
    )
    let reminders = [
      for event in result.events() if event.item() is Runtime(notice) &&
      notice.content().contains(@agent_session.PlanReminderPrefix) => {
        notice.content()
      }
    ]
    assert_eq(reminders.length(), 1)
    assert_true(reminders[0].contains("has not been used in this turn"))
  }
}

///|
/// The checklist variant is exempt from the once-per-turn cap: a recorded
/// plan left stale keeps re-surfacing on the 10/10 cadence — request 12 and
/// again request 22 — because it repeats real state, not declined advice.
async test "a stale recorded plan re-nags on the ten-request cadence" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard recorded_plan_test_server(group, bodies, plan_calls=22) is Some(url) else {
      return
    }
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    let session = @agent_session.Session(
      SessionId("plan-renag-checklist"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope~,
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="do a long task",
      append_item=(session, item) => session.append(item),
      max_steps=30,
      api_url=url,
    )
    // Exactly 23 requests: the plan write, 21 more tool-call steps, the
    // finishing answer.
    assert_eq(bodies.length(), 23)
    assert_eq(
      reminder_count(bodies[10]),
      0,
      msg="the plan write must delay the first reminder past request 11",
    )
    assert_eq(
      reminder_count(bodies[11]),
      1,
      msg="request 12 should carry the first checklist reminder",
    )
    // The second re-nag lands exactly ten requests later: still one reminder
    // in request 21's history, two from request 22 on.
    assert_eq(
      reminder_count(bodies[20]),
      1,
      msg="request 21 sits inside the ten-request window",
    )
    assert_eq(
      reminder_count(bodies[21]),
      2,
      msg="request 22 should carry the second checklist reminder",
    )
    let reminders = [
      for event in result.events() if event.item() is Runtime(notice) &&
      notice.content().contains(@agent_session.PlanReminderPrefix) => {
        notice.content()
      }
    ]
    assert_eq(reminders.length(), 2)
    assert_true(reminders[0].contains("1. [in_progress] fix the parser"))
    assert_true(reminders[1].contains("1. [in_progress] fix the parser"))
  }
}
