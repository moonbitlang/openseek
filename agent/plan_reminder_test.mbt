///|
/// The durable plan-reminder notices recorded in `result`, in order.
fn plan_reminders(result : @agent_session.Session) -> Array[String] {
  [
    for event in result.events() if event.item() is Runtime(notice) &&
    notice.content().contains(@agent_session.PlanReminderPrefix) => {
      notice.content()
    }
  ]
}

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
  guard bind_test_server(
      "local TCP bind unavailable; skipping plan reminder test",
    )
    is Some(server) else {
    return None
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
async test "a plan-silent turn gets one staleness reminder after the cadence" {
  @async.with_task_group() <| group => {
    let cadence = @agent.plan_reminder_after_steps
    let bodies : Array[String] = []
    guard stale_plan_test_server(group, bodies, plan_calls=cadence + 1)
      is Some(url) else {
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
      max_steps=cadence + 10,
      api_url=url,
    )
    // Exactly cadence+2 requests: cadence+1 tool-call steps plus the
    // finishing answer. A retry would inflate the count and fail here
    // rather than skew the cadence assertions below.
    assert_eq(bodies.length(), cadence + 2)
    for index in 0..<cadence {
      assert_false(
        bodies[index].contains(@agent_session.PlanReminderPrefix),
        msg="request \{index + 1} must not carry the reminder yet",
      )
    }
    assert_true(
      bodies[cadence].contains(@agent_session.PlanReminderPrefix),
      msg="request \{cadence + 1} should carry the reminder",
    )
    assert_true(bodies[cadence].contains("has not been used in this turn"))
    // The reminder is durable exactly once, in its plan-free nag variant.
    let reminders = plan_reminders(result)
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
/// fires a full cadence window later and re-surfaces the recorded
/// checklist. Assertions live in the test body, as above.
async fn recorded_plan_test_server(
  group : @async.TaskGroup[Unit],
  bodies : Array[String],
  plan_calls~ : Int,
) -> String? {
  guard bind_test_server(
      "local TCP bind unavailable; skipping plan reminder test",
    )
    is Some(server) else {
    return None
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
    let cadence = @agent.plan_reminder_after_steps
    let bodies : Array[String] = []
    guard recorded_plan_test_server(group, bodies, plan_calls=cadence + 2)
      is Some(url) else {
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
      max_steps=cadence + 10,
      api_url=url,
    )
    // Exactly cadence+3 requests: the plan write, cadence+1 more tool-call
    // steps, the finishing answer.
    assert_eq(bodies.length(), cadence + 3)
    assert_false(
      bodies[cadence].contains(@agent_session.PlanReminderPrefix),
      msg="the successful plan write must delay the reminder one request further",
    )
    assert_true(
      bodies[cadence + 1].contains(@agent_session.PlanReminderPrefix),
      msg="request \{cadence + 2} should carry the reminder",
    )
    assert_true(bodies[cadence + 1].contains("Current plan:"))
    assert_true(bodies[cadence + 1].contains("1. [in_progress] fix the parser"))
    let reminders = plan_reminders(result)
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
/// long enough for a second window still gets exactly one reminder —
/// repeating "consider recording a plan" that the model already declined
/// once is pure noise.
async test "the no-plan nag fires at most once per turn" {
  @async.with_task_group() <| group => {
    let cadence = @agent.plan_reminder_after_steps
    let bodies : Array[String] = []
    guard stale_plan_test_server(group, bodies, plan_calls=2 * cadence + 3)
      is Some(url) else {
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
      max_steps=2 * cadence + 10,
      api_url=url,
    )
    // Exactly 2*cadence+4 requests: 2*cadence+3 tool-call steps plus the
    // finishing answer.
    assert_eq(bodies.length(), 2 * cadence + 4)
    for index in 0..<cadence {
      assert_eq(
        reminder_count(bodies[index]),
        0,
        msg="request \{index + 1} must not carry the reminder yet",
      )
    }
    assert_eq(
      reminder_count(bodies[cadence]),
      1,
      msg="request \{cadence + 1} should carry the only reminder",
    )
    // A pure repeating cadence would inject a second nag one window later;
    // the once-per-turn cap suppresses it, so the final request still
    // carries exactly one reminder in its history.
    assert_eq(
      reminder_count(bodies[2 * cadence + 3]),
      1,
      msg="no later request may gain a second no-plan nag",
    )
    let reminders = plan_reminders(result)
    assert_eq(reminders.length(), 1)
    assert_true(reminders[0].contains("has not been used in this turn"))
  }
}

///|
/// The checklist variant is exempt from the once-per-turn cap: a recorded
/// plan left stale keeps re-surfacing once per cadence window, because it
/// repeats real state, not declined advice.
async test "a stale recorded plan re-nags on the request cadence" {
  @async.with_task_group() <| group => {
    let cadence = @agent.plan_reminder_after_steps
    let bodies : Array[String] = []
    guard recorded_plan_test_server(group, bodies, plan_calls=2 * cadence + 2)
      is Some(url) else {
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
      max_steps=2 * cadence + 10,
      api_url=url,
    )
    // Exactly 2*cadence+3 requests: the plan write, 2*cadence+1 more
    // tool-call steps, the finishing answer.
    assert_eq(bodies.length(), 2 * cadence + 3)
    assert_eq(
      reminder_count(bodies[cadence]),
      0,
      msg="the plan write must delay the first reminder one request further",
    )
    assert_eq(
      reminder_count(bodies[cadence + 1]),
      1,
      msg="request \{cadence + 2} should carry the first checklist reminder",
    )
    // The second re-nag lands exactly one cadence window later: still one
    // reminder just inside the window, two from the boundary on.
    assert_eq(
      reminder_count(bodies[2 * cadence]),
      1,
      msg="request \{2 * cadence + 1} sits inside the cadence window",
    )
    assert_eq(
      reminder_count(bodies[2 * cadence + 1]),
      2,
      msg="request \{2 * cadence + 2} should carry the second checklist reminder",
    )
    let reminders = plan_reminders(result)
    assert_eq(reminders.length(), 2)
    assert_true(reminders[0].contains("1. [in_progress] fix the parser"))
    assert_true(reminders[1].contains("1. [in_progress] fix the parser"))
  }
}
