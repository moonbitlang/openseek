///|
fn goal_tool_call_payload(arguments : String) -> String {
  (
    {
      "choices": [
        {
          "delta": {
            "tool_calls": [
              {
                "index": 0,
                "id": "call_goal",
                "type": "function",
                "function": { "name": "goal", "arguments": arguments },
              },
            ],
          },
        },
      ],
    } : Json).stringify()
}

///|
fn goal_tools_with_probe() -> @agent_tool.Tools raise {
  Tools([@goal.definition(), probe_definition()])
}

///|
async test "goal met defers the tombstone to a batch-safe boundary" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    // One batch: goal(met) followed by probe — the tombstone must not split
    // the batch on replay.
    let met_and_probe =
      #|{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_goal","function":{"name":"goal","arguments":"{\"status\":\"met\"}"}},{"index":1,"id":"call_probe","function":{"name":"probe","arguments":"{}"}}]}}]}
    guard goal_check_test_server(group, bodies, [
        met_and_probe,
        final_answer_payload("wrapped up"),
      ])
      is Some(url) else {
      return
    }
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=answered_goal_session("goal-tool-met"),
      task="finish the objective",
      append_item=(session, item) => session.append(item),
      max_steps=3,
      api_url=url,
      tools=goal_tools_with_probe(),
    )
    // No finish check (met disarmed it) and no third round.
    assert_eq(bodies.length(), 2)
    assert_false(bodies[1].contains(@agent_session.GoalCheckPrefix))
    // Durable order: both batch results precede the tombstone, which
    // precedes the terminal — replay stays protocol-valid.
    let mut goal_seq = 0
    let mut probe_seq = 0
    let mut tombstone_seq = 0
    let mut terminal_seq = 0
    for event in result.events() {
      match event.item() {
        Tool(tool_result) if tool_result.tool_call_id() == "call_goal" => {
          assert_false(tool_result.is_error())
          assert_true(tool_result.content().contains("met"))
          goal_seq = event.sequence()
        }
        Tool(tool_result) if tool_result.tool_call_id() == "call_probe" => {
          assert_eq(tool_result.content(), "probe-result")
          probe_seq = event.sequence()
        }
        Runtime(notice) if notice.content() == @agent_session.GoalClearedNotice =>
          tombstone_seq = event.sequence()
        Terminal(Finished(_)) => terminal_seq = event.sequence()
        _ => ()
      }
    }
    assert_true(0 < goal_seq)
    assert_true(goal_seq < probe_seq)
    assert_true(probe_seq < tombstone_seq)
    assert_true(tombstone_seq < terminal_seq)
    // The goal is durably gone and replay synthesizes nothing.
    assert_true(result.current_goal() is None)
    for message in result.chat_messages() {
      assert_false(message.content.contains("previous agent process exited"))
    }
  }
}

///|
async test "goal met in the final batch flushes before the terminal" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard goal_check_test_server(group, bodies, [
        goal_tool_call_payload("{\"status\":\"met\"}"),
        final_answer_payload("all done"),
      ])
      is Some(url) else {
      return
    }
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=answered_goal_session("goal-tool-met-final"),
      task="finish the objective",
      append_item=(session, item) => session.append(item),
      max_steps=3,
      api_url=url,
      tools=goal_tools_with_probe(),
    )
    assert_eq(bodies.length(), 2)
    let events = result.events()
    guard events.peek() is Some(last) && last.item() is Terminal(Finished(_)) else {
      fail("expected finished terminal")
    }
    assert_true(result.current_goal() is None)
  }
}

///|
async test "goal continuing stands in for the finish check" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard goal_check_test_server(group, bodies, [
        goal_tool_call_payload(
          "{\"status\":\"continuing\",\"remaining\":\"the parser is half done\"}",
        ),
        final_answer_payload("pausing here"),
      ])
      is Some(url) else {
      return
    }
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=answered_goal_session("goal-tool-continuing"),
      task="do a slice",
      append_item=(session, item) => session.append(item),
      max_steps=3,
      api_url=url,
      tools=goal_tools_with_probe(),
    )
    // The structured continuing answer replaces the goal check: the final
    // answer ends the turn in two rounds, and the goal still stands.
    assert_eq(bodies.length(), 2)
    assert_false(bodies[1].contains(@agent_session.GoalCheckPrefix))
    guard result.current_goal() is Some(goal) else {
      fail("expected the goal to keep standing")
    }
    assert_true(goal.text().contains("GOAL-MARKER"))
  }
}

///|
async test "goal calls without a standing goal or remaining are errors" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard goal_check_test_server(group, bodies, [
        goal_tool_call_payload("{\"status\":\"met\"}"),
        goal_tool_call_payload("{\"status\":\"continuing\"}"),
        final_answer_payload("ok"),
      ])
      is Some(url) else {
      return
    }
    // No goal marker anywhere in this session.
    let session = @agent_session.Session(
      SessionId("goal-tool-errors"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="try the goal tool",
      append_item=(session, item) => session.append(item),
      max_steps=4,
      api_url=url,
      tools=goal_tools_with_probe(),
    )
    let errors = [
      for event in result.events() if event.item() is Tool(tool_result) &&
      tool_result.is_error() => tool_result
    ]
    assert_eq(errors.length(), 2)
    assert_true(errors[0].content().contains("no standing goal"))
    assert_true(errors[1].content().contains("remaining"))
    // No tombstone was ever appended.
    for event in result.events() {
      if event.item() is Runtime(notice) {
        assert_false(notice.content() == @agent_session.GoalClearedNotice)
      }
    }
  }
}

///|
async test "goal met flushes its tombstone on non-finish terminals" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    // The turn's only step calls goal(met); max_steps=1 exhausts without
    // ever reaching finish_turn.
    guard goal_check_test_server(group, bodies, [
        goal_tool_call_payload("{\"status\":\"met\"}"),
      ])
      is Some(url) else {
      return
    }
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=answered_goal_session("goal-tool-max-steps"),
      task="finish the objective",
      append_item=(session, item) => session.append(item),
      max_steps=1,
      api_url=url,
      tools=goal_tools_with_probe(),
    )
    let events = result.events()
    guard events.peek() is Some(last) && last.item() is Terminal(Failed(_)) else {
      fail("expected max-steps failure terminal")
    }
    // The durable clear landed before the terminal: the next turn must not
    // resurrect a goal the tool result says was met.
    assert_true(result.current_goal() is None)
  }
}

///|
async test "the goal check names the goal tool when registered" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard goal_check_test_server(group, bodies, [
        final_answer_payload("premature"),
        final_answer_payload("done"),
      ])
      is Some(url) else {
      return
    }
    let _ = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=answered_goal_session("goal-tool-check-text"),
      task="do the next chunk",
      append_item=(session, item) => session.append(item),
      max_steps=3,
      api_url=url,
      tools=goal_tools_with_probe(),
    )
    assert_eq(bodies.length(), 2)
    assert_true(bodies[1].contains(@agent_session.GoalCheckPrefix))
    assert_true(bodies[1].contains("calling the goal tool"))
  }
}
