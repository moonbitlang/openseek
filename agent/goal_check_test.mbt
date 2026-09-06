///|
/// Scripted stand-in for goal-check tests: responses come from a queue of
/// SSE payload lines, bodies are recorded, assertions happen after the run.
async fn goal_check_test_server(
  group : @async.TaskGroup[Unit],
  bodies : Array[String],
  responses : Array[String],
) -> String? {
  guard bind_test_server("local TCP bind unavailable; skipping goal check test")
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
        conn.write("data: \{responses[bodies.length() - 1]}\n\n")
        conn.write("data: [DONE]\n\n")
      },
      max_connections=2,
    )
  }
  Some("http://127.0.0.1:\{server.addr.port()}/chat/completions")
}

///|
/// Ceiling-aware variant: streaming responses (with fabricated usage) come
/// from the queue; the checkpoint summary call — the only non-streaming
/// request, recognizable by its prompt — gets a plain JSON body.
async fn goal_ceiling_test_server(
  group : @async.TaskGroup[Unit],
  bodies : Array[String],
  checkpoint_bodies : Array[String],
  responses : Array[String],
) -> String? {
  guard bind_test_server("local TCP bind unavailable; skipping goal check test")
    is Some(server) else {
    return None
  }
  group.spawn_bg(no_wait=true) <| () => {
    server.run_forever(
      (_request, body, conn) => {
        let text = body.read_all().text()
        if text.contains("CONTEXT CHECKPOINT COMPACTION") {
          checkpoint_bodies.push(text)
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          conn.write(
            "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"GOAL-CEILING-SUMMARY\"}}]}",
          )
        } else {
          bodies.push(text)
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          conn.write("data: \{responses[bodies.length() - 1]}\n\n")
          conn.write("data: [DONE]\n\n")
        }
      },
      max_connections=4,
    )
  }
  Some("http://127.0.0.1:\{server.addr.port()}/chat/completions")
}

///|
fn pressured_final_payload(content : String, total_tokens : Int) -> String {
  "{\"choices\":[{\"delta\":{\"content\":\"\{content}\"}}],\"usage\":{\"prompt_tokens\":\{total_tokens - 1000},\"completion_tokens\":1000,\"total_tokens\":\{total_tokens}}}"
}

///|
fn final_answer_payload(content : String) -> String {
  "{\"choices\":[{\"delta\":{\"content\":\"\{content}\"}}]}"
}

///|
/// A session with an answered standing goal, so the turn-start reminder and
/// the finish check are both armed.
fn answered_goal_session(id : String) -> @agent_session.Session {
  @agent_session.Session(SessionId(id), system_prompt="system")
  .append(
    Runtime(
      RuntimeNotice("\{@agent_session.GoalPrefix}\nGOAL-MARKER big objective"),
    ),
  )
  .append(Terminal(Finished("earlier answer")))
}

///|
async test "a finish attempt with a standing goal gets one goal check" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard goal_check_test_server(group, bodies, [
        final_answer_payload("premature answer"),
        // Repeating the attempted answer is deliberate: durable ownership,
        // not text inequality, must prove that the check caused another step.
        final_answer_payload("premature answer"),
      ])
      is Some(url) else {
      return
    }
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=answered_goal_session("goal-check-final"),
      task="do the next chunk",
      append_item=(session, item) => session.append(item),
      max_steps=3,
      api_url=url,
      tools=goal_probe_tools(),
    )
    // Exactly two model rounds: the premature finish, then the post-check
    // finish. The check itself never re-fires (once per turn).
    assert_eq(bodies.length(), 2)
    assert_false(bodies[0].contains(@agent_session.GoalCheckPrefix))
    assert_true(bodies[1].contains(@agent_session.GoalCheckPrefix))
    assert_true(bodies[1].contains("premature answer"))
    let events = result.events()
    guard events.peek() is Some(last) &&
      last.item() is Terminal(Finished(answer)) else {
      fail("expected finished terminal")
    }
    assert_eq(answer, "premature answer")
    let checks = [
      for event in events if event.item() is Runtime(notice) &&
      notice.content().has_prefix(@agent_session.GoalCheckPrefix) => notice
    ]
    assert_eq(checks.length(), 1)
    // Both provider responses are preserved as ordinary assistant messages.
    // The second one is the durable step boundary for the repeated plain final;
    // the matching Terminal remains only its visible completion record.
    let held = [
      for event in events if event.item() is Assistant(message) &&
      message.content() == "premature answer" => message
    ]
    assert_eq(held.length(), 2)
    assert_true(held.all(message => !message.is_replay()))
  }
}

///|
async test "a finish tool call mid-batch closes the batch before the check" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    let finish_then_probe =
      #|{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_finish","function":{"name":"finish_test","arguments":"{}"}},{"index":1,"id":"call_probe","function":{"name":"probe","arguments":"{}"}}]}}]}
    guard goal_check_test_server(group, bodies, [
        finish_then_probe,
        final_answer_payload("confirmed done"),
      ])
      is Some(url) else {
      return
    }
    let mut probe_ran = false
    let tools = @agent_tool.Tools([
      AgentToolDefinition(
        name="finish_test",
        description="Finish stand-in.",
        schema=JsonSchema({ "type": "object" }),
        execute=Sync(_args => @agent_tool.ToolAction::finish("early answer")),
      ),
      AgentToolDefinition(
        name="probe",
        description="Probe tool.",
        schema=JsonSchema({ "type": "object" }),
        execute=Sync(_args => {
          probe_ran = true
          @agent_tool.respond("probe-result")
        }),
      ),
    ])
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=answered_goal_session("goal-check-batch"),
      task="do the next chunk",
      append_item=(session, item) => session.append(item),
      max_steps=3,
      api_url=url,
      tools~,
    )
    assert_eq(bodies.length(), 2)
    assert_false(probe_ran)
    // The second request stays API-valid: both batch calls carry results —
    // the finish result and the skipped note — before the goal check.
    assert_true(bodies[1].contains("call_finish"))
    assert_true(bodies[1].contains("finished: early answer"))
    assert_true(bodies[1].contains("call_probe"))
    // The remainder is closed by the finish call's own unconditional
    // close (in call order) before the goal check converts the completion
    // into a check round.
    assert_true(
      bodies[1].contains("an earlier finish tool call ended the batch"),
    )
    assert_true(bodies[1].contains(@agent_session.GoalCheckPrefix))
    let events = result.events()
    guard events.peek() is Some(last) &&
      last.item() is Terminal(Finished(answer)) else {
      fail("expected finished terminal")
    }
    assert_eq(answer, "confirmed done")
    // The finish call was converted into a goal-check continuation. Preserve
    // the follow-up plain final as its own durable model step so session-backed
    // renderers can distinguish it from the original finish response.
    guard events[events.length() - 2].item() is Assistant(confirmed) else {
      fail("expected the continued final before its terminal")
    }
    assert_eq(confirmed.content(), "confirmed done")
    let skipped = [
      for event in events if event.item() is Tool(tool_result) &&
      tool_result.tool_call_id() == "call_probe" => tool_result
    ]
    assert_eq(skipped.length(), 1)
    assert_true(skipped[0].is_error())
  }
}

///|
async test "checkpoint replay provenance distinguishes a same-text follow-up" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    let checkpoint_bodies : Array[String] = []
    let pressured_finish =
      #|{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_finish","function":{"name":"finish_test","arguments":"{}"}}]}}],"usage":{"prompt_tokens":749000,"completion_tokens":1000,"total_tokens":750000}}
    guard goal_ceiling_test_server(group, bodies, checkpoint_bodies, [
        pressured_finish,
        pressured_final_payload("same answer", 750_000),
      ])
      is Some(url) else {
      return
    }
    let tools = @agent_tool.Tools([
      AgentToolDefinition(
        name="finish_test",
        description="Finish stand-in.",
        schema=JsonSchema({ "type": "object" }),
        execute=Sync(_args => @agent_tool.ToolAction::finish("same answer")),
      ),
    ])
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=answered_goal_session("goal-check-replay-provenance"),
      task="finish carefully",
      append_item=(session, item) => session.append(item),
      max_steps=3,
      api_url=url,
      tools~,
    )
    assert_eq(bodies.length(), 2)
    assert_eq(checkpoint_bodies.length(), 2)
    let replays = [
      for event in result.events() if event.item() is Assistant(message) &&
      message.content() == "same answer" &&
      message.is_replay() => message
    ]
    let provider_finals = [
      for event in result.events() if event.item() is Assistant(message) &&
      message.content() == "same answer" &&
      !message.is_replay() => message
    ]
    assert_eq(replays.length(), 1)
    assert_eq(provider_finals.length(), 1)
    guard result.events().peek() is Some(last) &&
      last.item() is Terminal(Finished("same answer")) else {
      fail("expected the repeated provider final to seal the turn")
    }
  }
}

///|
async test "a check on the reminder boundary is not buried by a reminder" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    // 29 probe rounds put the finish attempt (request 30) exactly on the
    // 30-request reminder boundary; the check resets the cadence, so the
    // post-check request carries the check as the tail instruction with no
    // fresh reminder after it.
    let responses = []
    for _ in 0..<29 {
      responses.push(
        (
          #|{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_probe","function":{"name":"probe","arguments":"{}"}}]}}]}
        ),
      )
    }
    responses.push(final_answer_payload("premature answer"))
    responses.push(final_answer_payload("really done"))
    guard goal_check_test_server(group, bodies, responses) is Some(url) else {
      return
    }
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=answered_goal_session("goal-check-boundary"),
      task="grind through it",
      append_item=(session, item) => session.append(item),
      max_steps=40,
      api_url=url,
      tools=goal_probe_tools(),
    )
    assert_eq(bodies.length(), 31)
    let last = bodies[30]
    assert_true(last.contains(@agent_session.GoalCheckPrefix))
    // Only the turn-start reminder — the boundary reminder was absorbed by
    // the check.
    assert_eq(count_reminders(last), 1)
    guard result.events().peek() is Some(event) &&
      event.item() is Terminal(Finished(answer)) else {
      fail("expected finished terminal")
    }
    assert_eq(answer, "really done")
  }
}

///|
async test "no goal or a cleared goal never triggers the check" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard goal_check_test_server(group, bodies, [
        final_answer_payload("done"),
        final_answer_payload("done again"),
      ])
      is Some(url) else {
      return
    }
    let cleared = answered_goal_session("goal-check-cleared").append(
      Runtime(RuntimeNotice(@agent_session.GoalClearedNotice)),
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=cleared,
      task="just answer",
      append_item=(session, item) => session.append(item),
      max_steps=2,
      api_url=url,
      tools=goal_probe_tools(),
    )
    assert_eq(bodies.length(), 1)
    assert_false(bodies[0].contains(@agent_session.GoalCheckPrefix))
    guard result.events().peek() is Some(last) &&
      last.item() is Terminal(Finished(answer)) else {
      fail("expected finished terminal")
    }
    assert_eq(answer, "done")
  }
}

///|
async test "a goal check at the ceiling checkpoints first" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    let checkpoint_bodies : Array[String] = []
    guard goal_ceiling_test_server(group, bodies, checkpoint_bodies, [
        pressured_final_payload("premature answer", 750_000),
        final_answer_payload("really done"),
      ])
      is Some(url) else {
      return
    }
    let session = answered_goal_session("goal-check-ceiling")
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="do the big task",
      append_item=(session, item) => session.append(item),
      api_url=url,
    )
    // The pressured completion with an unchecked goal checkpoints FIRST,
    // then runs the check round from the compacted projection — never from
    // the pressured history plus a check notice.
    assert_eq(bodies.length(), 2)
    assert_eq(checkpoint_bodies.length(), 1)
    // The checkpoint request precedes the kept answer and the check.
    assert_false(checkpoint_bodies[0].contains("premature answer"))
    assert_false(checkpoint_bodies[0].contains(@agent_session.GoalCheckPrefix))
    // The check round is compacted: summary in, original task folded away,
    // kept answer and check notice verbatim.
    assert_true(bodies[1].contains("GOAL-CEILING-SUMMARY"))
    assert_true(bodies[1].contains("premature answer"))
    assert_true(bodies[1].contains(@agent_session.GoalCheckPrefix))
    assert_false(bodies[1].contains("do the big task"))
    // The confirmation seals the turn normally below the ceiling.
    guard result.events().peek() is Some(last) &&
      last.item() is Terminal(Finished(answer)) else {
      fail("expected finished terminal")
    }
    assert_eq(answer, "really done")
    // Durable order: Summary before the check notice.
    let mut summary_sequence = 0
    let mut check_sequence = 0
    for event in result.events() {
      match event.item() {
        Summary(_) => summary_sequence = event.sequence()
        Runtime(notice) if notice
          .content()
          .contains(@agent_session.GoalCheckPrefix) =>
          check_sequence = event.sequence()
        _ => ()
      }
    }
    assert_true(summary_sequence > 0)
    assert_true(check_sequence > summary_sequence)
  }
}

///|
async test "a pressured goal-met-then-finish batch salvages both" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    let checkpoint_bodies : Array[String] = []
    guard goal_ceiling_test_server(group, bodies, checkpoint_bodies, [
        (
          #|{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"goal","arguments":"{\"status\":\"met\"}"}},{"index":1,"id":"c2","function":{"name":"finish","arguments":"{\"answer\":\"all done\"}"}}]}}],"usage":{"prompt_tokens":899000,"completion_tokens":1000,"total_tokens":900000}}
        ),
      ])
      is Some(url) else {
      return
    }
    let session = answered_goal_session("goal-met-salvage")
    let tools : @agent_tool.Tools = Tools([
      @goal.definition(),
      @finish.definition(),
    ])
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="wrap it all up",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools~,
    )
    // The check text asks for goal(met) BEFORE finish: at the hard ceiling
    // BOTH control calls execute — skip-closing the goal verdict would
    // resurrect a completed goal for auto-continue.
    assert_eq(bodies.length(), 1)
    assert_eq(checkpoint_bodies.length(), 1)
    guard result.events().peek() is Some(last) &&
      last.item() is Terminal(Finished(answer)) else {
      fail("expected finished terminal")
    }
    assert_eq(answer, "all done")
    // The met verdict landed durably: the goal no longer stands.
    assert_true(result.current_goal() is None)
  }
}
