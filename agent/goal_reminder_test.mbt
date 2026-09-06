///|
/// A scripted DeepSeek stand-in for goal-reminder cadence tests: the first
/// `probe_calls` requests answer with a `probe` tool call (keeping the turn
/// alive), the next request answers. Bodies are recorded; all assertions
/// happen in the test after the run, so a client retry shows up as a hard
/// request-count mismatch instead of silently shifting the cadence.
async fn goal_test_server(
  group : @async.TaskGroup[Unit],
  bodies : Array[String],
  probe_calls~ : Int,
) -> String? {
  guard bind_test_server(
      "local TCP bind unavailable; skipping goal reminder test",
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
        if bodies.length() <= probe_calls {
          conn.write(
            "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_\{bodies.length()}\",\"function\":{\"name\":\"probe\",\"arguments\":\"{}\"}}]}}]}\n\n",
          )
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
fn goal_probe_tools() -> @agent_tool.Tools raise {
  Tools([
    AgentToolDefinition(
      name="probe",
      description="Probe tool.",
      schema=JsonSchema({ "type": "object" }),
      execute=Sync(_args => @agent_tool.respond("probe-result")),
    ),
  ])
}

///|
fn goal_set_marker(text : String) -> @agent_session.SessionItem {
  Runtime(RuntimeNotice("\{@agent_session.GoalPrefix}\n\{text}"))
}

///|
fn count_reminders(body : String) -> Int {
  body.split("[goal reminder]").count() - 1
}

///|
async test "a standing goal from a prior turn is re-surfaced at turn start" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard goal_test_server(group, bodies, probe_calls=0) is Some(url) else {
      return
    }
    let session = @agent_session.Session(
        SessionId("goal-turn-start"),
        system_prompt="system",
      )
      .append(goal_set_marker("GOAL-MARKER port the decoder"))
      .append(User(UserMessage("earlier task")))
      .append(Terminal(Finished("earlier answer")))
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="next chunk",
      append_item=(session, item) => session.append(item),
      max_steps=3,
      api_url=url,
      tools=goal_probe_tools(),
    )
    // Two rounds: the answer, then the once-per-turn goal check's follow-up.
    assert_eq(bodies.length(), 2)
    assert_true(bodies[0].contains(@agent_session.GoalReminderPrefix))
    assert_true(bodies[0].contains("GOAL-MARKER port the decoder"))
    assert_true(bodies[1].contains(@agent_session.GoalCheckPrefix))
    // Durable exactly once, after the task.
    let reminders = [
      for event in result.events() if event.item() is Runtime(notice) &&
      notice.content().has_prefix(@agent_session.GoalReminderPrefix) => notice
    ]
    assert_eq(reminders.length(), 1)
  }
}

///|
async test "a freshly set goal is not double-announced" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard goal_test_server(group, bodies, probe_calls=0) is Some(url) else {
      return
    }
    // The idle /goal set appends the marker, then the prompt appends the
    // task: the marker is not the last event, but no model response follows
    // it, so the marker itself still rides the first request.
    let session = @agent_session.Session(
        SessionId("goal-fresh-set"),
        system_prompt="system",
      )
      .append(User(UserMessage("earlier task")))
      .append(Terminal(Finished("earlier answer")))
      .append(goal_set_marker("GOAL-MARKER fresh objective"))
    let _ = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="get started",
      append_item=(session, item) => session.append(item),
      max_steps=3,
      api_url=url,
      tools=goal_probe_tools(),
    )
    // Two rounds: the goal check still fires for a fresh goal; only the
    // duplicate turn-start reminder is suppressed.
    assert_eq(bodies.length(), 2)
    assert_true(bodies[0].contains("GOAL-MARKER fresh objective"))
    assert_false(bodies[0].contains(@agent_session.GoalReminderPrefix))
    assert_false(bodies[1].contains(@agent_session.GoalReminderPrefix))
  }
}

///|
async test "a long turn is reminded exactly once, at the start" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard goal_test_server(group, bodies, probe_calls=31) is Some(url) else {
      return
    }
    let session = @agent_session.Session(
        SessionId("goal-cadence"),
        system_prompt="system",
      )
      .append(goal_set_marker("GOAL-MARKER long objective"))
      .append(Terminal(Finished("earlier answer")))
    let _ = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="keep going",
      append_item=(session, item) => session.append(item),
      max_steps=40,
      api_url=url,
      tools=goal_probe_tools(),
    )
    // 31 probe rounds, the first final answer, then the goal check's
    // follow-up round.
    assert_eq(bodies.length(), 33)
    // Once per turn: the turn-start reminder in request 1 and NO mid-turn
    // re-reminders — turns are context-bounded now, so the reminder never
    // leaves the model's context, and the finish check (visible in the
    // final round) is the enforcement point.
    assert_eq(count_reminders(bodies[0]), 1)
    assert_eq(count_reminders(bodies[29]), 1)
    assert_eq(count_reminders(bodies[30]), 1)
    assert_eq(count_reminders(bodies[32]), 1)
  }
}

///|
async test "a goal steered in mid-turn is announced once, not reminded" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard goal_test_server(group, bodies, probe_calls=1) is Some(url) else {
      return
    }
    let runtime = @agent_runtime.AgentRuntime()
    runtime.queue_steer(
      Notice("\{@agent_session.GoalPrefix}\nGOAL-MARKER steered"),
    )
    let session = @agent_session.Session(
      SessionId("goal-steered"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="start",
      append_item=(session, item) => session.append(item),
      max_steps=4,
      api_url=url,
      tools=goal_probe_tools(),
    )
    // Probe round, first final answer, goal-check follow-up.
    assert_eq(bodies.length(), 3)
    assert_true(bodies[0].contains("GOAL-MARKER steered"))
    for body in bodies {
      assert_false(body.contains(@agent_session.GoalReminderPrefix))
    }
    guard result.current_goal() is Some(goal) else {
      fail("expected the steered goal to be durable")
    }
    assert_eq(goal.text(), "GOAL-MARKER steered")
  }
}

///|
async test "a cleared goal produces no reminders" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard goal_test_server(group, bodies, probe_calls=0) is Some(url) else {
      return
    }
    let session = @agent_session.Session(
        SessionId("goal-cleared"),
        system_prompt="system",
      )
      .append(goal_set_marker("GOAL-MARKER stale"))
      .append(Terminal(Finished("earlier answer")))
      .append(Runtime(RuntimeNotice(@agent_session.GoalClearedNotice)))
    let _ = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="just answer",
      append_item=(session, item) => session.append(item),
      max_steps=2,
      api_url=url,
      tools=goal_probe_tools(),
    )
    assert_eq(bodies.length(), 1)
    assert_false(bodies[0].contains(@agent_session.GoalReminderPrefix))
  }
}
