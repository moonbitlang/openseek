///|
/// A session with a baselined standing goal, already answered.
fn baselined_goal_session(id : String) -> @agent_session.Session {
  @agent_session.Session(SessionId(id), system_prompt="system")
  .append(
    Runtime(
      RuntimeNotice(
        @agent_session.goal_baseline_notice(sha="abc123", dirty=false),
      ),
    ),
  )
  .append(Runtime(RuntimeNotice("\{@agent_session.GoalPrefix}\nship the gate")))
  .append(Terminal(Finished("earlier answer")))
}

///|
fn goal_met_payload() -> String {
  (
    #|{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"goal","arguments":"{\"status\":\"met\"}"}}]}}],"usage":{"prompt_tokens":9000,"completion_tokens":1000,"total_tokens":10000}}
  )
}

///|
fn gate_final_payload(text : String) -> String {
  (
    $|{"choices":[{"delta":{"content":"\{text}"}}],"usage":{"prompt_tokens":9000,"completion_tokens":1000,"total_tokens":10000}}
  )
}

///|
fn review_notice_count(session : @agent_session.Session) -> Int {
  session
  .events()
  .iter()
  .filter(event => {
    event.item() is Runtime(notice) && notice.content().has_prefix("[review]")
  })
  .count()
}

///|
/// goal(met) recorded mid-turn: the gate runs once at the next batch-safe
/// boundary — before the following model request — and injects its digest
/// as a durable notice the model then sees.
async test "a met goal runs the gate once before the next request" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard goal_check_test_server(group, bodies, [
        goal_met_payload(),
        gate_final_payload("done"),
      ])
      is Some(url) else {
      return
    }
    let calls : Array[(String, String)] = []
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=baselined_goal_session("gate-basic"),
      task="wrap up the goal",
      append_item=(session, item) => session.append(item),
      max_steps=6,
      api_url=url,
      tools=Tools([@goal.definition()]),
      on_goal_met=(goal, baseline) => {
        calls.push((goal, "\{Repr(baseline)}"))
        Some("[review] goal-met audit: 0 finding(s) — clean")
      },
    )
    // met batch, then one more request that already sees the notice.
    assert_eq(bodies.length(), 2)
    guard calls is [(goal, baseline)] else {
      fail("expected exactly one gate call, got \{calls.length()}")
    }
    assert_eq(goal, "ship the gate")
    assert_true(baseline.contains("abc123"))
    assert_true(baseline.contains("dirty: false"))
    assert_eq(review_notice_count(result), 1)
    // The request AFTER the gate carried the digest to the model.
    assert_true(bodies[1].contains("goal-met audit"))
  }
}

///|
/// met and finish in the SAME batch: the finish converts into a review
/// continuation (mirroring the goal check), the model sees the digest, and
/// the next finish seals.
async test "a same-batch met plus finish continues through the gate" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    let met_then_finish =
      #|{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"goal","arguments":"{\"status\":\"met\"}"}},{"index":1,"id":"c2","function":{"name":"finish","arguments":"{\"answer\":\"all done\"}"}}]}}],"usage":{"prompt_tokens":9000,"completion_tokens":1000,"total_tokens":10000}}
    guard goal_check_test_server(group, bodies, [
        met_then_finish,
        gate_final_payload("confirmed done"),
      ])
      is Some(url) else {
      return
    }
    let mut gate_calls = 0
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=baselined_goal_session("gate-same-batch"),
      task="wrap up the goal",
      append_item=(session, item) => session.append(item),
      max_steps=6,
      api_url=url,
      tools=Tools([@goal.definition(), @finish.definition()]),
      on_goal_met=(_goal, _baseline) => {
        gate_calls += 1
        Some(
          "[review] goal-met audit: 1 finding(s) (1 blocker, 0 high) — vacuous test",
        )
      },
    )
    assert_eq(bodies.length(), 2)
    assert_eq(gate_calls, 1)
    assert_eq(review_notice_count(result), 1)
    assert_true(bodies[1].contains("vacuous test"))
    assert_true(finished_answer(result).contains("confirmed done"))
    guard result.events()[result.events().length() - 2].item()
      is Assistant(confirmed) else {
      fail("expected the post-review final before its terminal")
    }
    assert_eq(confirmed.content(), "confirmed done")
  }
}

///|
/// The gate is advisory: a reviewer failure folds into an `unavailable`
/// notice and the turn proceeds.
async test "a failing gate folds into an unavailable notice" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard goal_check_test_server(group, bodies, [
        goal_met_payload(),
        gate_final_payload("done anyway"),
      ])
      is Some(url) else {
      return
    }
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=baselined_goal_session("gate-fail"),
      task="wrap up the goal",
      append_item=(session, item) => session.append(item),
      max_steps=6,
      api_url=url,
      tools=Tools([@goal.definition()]),
      on_goal_met=(_goal, _baseline) => fail("reviewer exploded"),
    )
    assert_eq(review_notice_count(result), 1)
    assert_true(
      result
      .events()
      .iter()
      .any(event => {
        event.item() is Runtime(notice) &&
        notice.content().has_prefix("[review] unavailable")
      }),
    )
    assert_true(finished_answer(result).contains("done anyway"))
  }
}

///|
/// Without a callback the met flow is exactly what it was before the gate.
async test "no callback means no gate and no notice" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard goal_check_test_server(group, bodies, [
        goal_met_payload(),
        gate_final_payload("done"),
      ])
      is Some(url) else {
      return
    }
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=baselined_goal_session("gate-off"),
      task="wrap up the goal",
      append_item=(session, item) => session.append(item),
      max_steps=6,
      api_url=url,
      tools=Tools([@goal.definition()]),
    )
    assert_eq(review_notice_count(result), 0)
    assert_eq(bodies.length(), 2)
  }
}

///|
/// A replacement goal queued before the boundary cancels the owed review:
/// the superseded audit never launches.
async test "a replacement goal cancels the pending review before launch" {
  @async.with_task_group() <| group => {
    let runtime = @agent_runtime.AgentRuntime()
    let bodies : Array[String] = []
    let met_then_probe =
      #|{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"goal","arguments":"{\"status\":\"met\"}"}},{"index":1,"id":"c2","function":{"name":"probe","arguments":"{}"}}]}}],"usage":{"prompt_tokens":9000,"completion_tokens":1000,"total_tokens":10000}}
    guard goal_check_test_server(group, bodies, [
        met_then_probe,
        gate_final_payload("onward"),
        gate_final_payload("done"),
      ])
      is Some(url) else {
      return
    }
    let mut gate_calls = 0
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=baselined_goal_session("gate-superseded"),
      task="wrap up the goal",
      append_item=(session, item) => session.append(item),
      max_steps=6,
      api_url=url,
      tools=Tools([
        @goal.definition(),
        AgentToolDefinition(
          name="probe",
          description="Queues a replacement goal mid-batch.",
          schema=JsonSchema({ "type": "object" }),
          execute=Sync(_args => {
            // The replacement arrives WHILE the met batch is executing:
            // the next boundary applies it before the owed review would
            // launch, and the superseded audit is cancelled.
            runtime.queue_steer(
              Notice("\{@agent_session.GoalPrefix}\na brand new objective"),
            )
            @agent_tool.respond("queued")
          }),
        ),
      ]),
      on_goal_met=(_goal, _baseline) => {
        gate_calls += 1
        Some("[review] should never appear")
      },
    )
    assert_eq(gate_calls, 0)
    assert_eq(review_notice_count(result), 0)
  }
}

///|
/// The panel's executable repro: same-batch met+finish under ceiling
/// pressure with a FAILING checkpoint must neither resurrect the met goal
/// nor lose the audit — the fail-open seal flushes the tombstone and runs
/// the review before sealing.
async test "a failed checkpoint neither resurrects the goal nor loses the audit" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    let met_then_finish_pressured =
      #|{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"goal","arguments":"{\"status\":\"met\"}"}},{"index":1,"id":"c2","function":{"name":"finish","arguments":"{\"answer\":\"all done\"}"}}]}}],"usage":{"prompt_tokens":749000,"completion_tokens":1000,"total_tokens":750000}}
    // goal_check_test_server answers EVERY request with SSE — including the
    // checkpoint's non-streaming summary call, whose junk reply fails it.
    guard goal_check_test_server(group, bodies, [
        met_then_finish_pressured,
        gate_final_payload("unreached"),
      ])
      is Some(url) else {
      return
    }
    let mut gate_calls = 0
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=baselined_goal_session("gate-failed-checkpoint"),
      task="wrap up the goal",
      append_item=(session, item) => session.append(item),
      max_steps=6,
      api_url=url,
      tools=Tools([@goal.definition(), @finish.definition()]),
      on_goal_met=(_goal, _baseline) => {
        gate_calls += 1
        Some("[review] survived the failed checkpoint")
      },
    )
    // The met goal must NOT resurrect for auto-continue…
    assert_true(result.current_goal() is None)
    // …and the audit must not be lost with the checkpoint.
    assert_eq(gate_calls, 1)
    assert_eq(review_notice_count(result), 1)
  }
}

///|
/// met+finish on the LAST bounded step: the model cannot react, but the
/// audit still runs and its digest lands durably for the user (and any
/// auto-continued turn) to judge the claim.
async test "a last-step met still gets its audit durably" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    let met_then_finish =
      #|{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"goal","arguments":"{\"status\":\"met\"}"}},{"index":1,"id":"c2","function":{"name":"finish","arguments":"{\"answer\":\"all done\"}"}}]}}],"usage":{"prompt_tokens":9000,"completion_tokens":1000,"total_tokens":10000}}
    guard goal_check_test_server(group, bodies, [met_then_finish]) is Some(url) else {
      return
    }
    let mut gate_calls = 0
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=baselined_goal_session("gate-last-step"),
      task="wrap up the goal",
      append_item=(session, item) => session.append(item),
      max_steps=1,
      api_url=url,
      tools=Tools([@goal.definition(), @finish.definition()]),
      on_goal_met=(_goal, _baseline) => {
        gate_calls += 1
        Some("[review] last-step audit")
      },
    )
    assert_eq(gate_calls, 1)
    assert_eq(review_notice_count(result), 1)
    assert_true(finished_answer(result).contains("all done"))
    // No continuation request ran on the last bounded step, so its terminal
    // remains owned by the finish response and no plain final is synthesized.
    let preserved_finals = [
      for event in result.events() if event.item() is Assistant(message) &&
      message.content() == "all done" => message
    ]
    assert_eq(preserved_finals.length(), 0)
  }
}

///|
/// met followed by a context yield: the audit runs before the yield seals,
/// so the auto-continued next turn inherits the verdict, not an unaudited
/// claim.
async test "a met claim yielding at the ceiling still gets its audit" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    let met_pressured =
      #|{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"goal","arguments":"{\"status\":\"met\"}"}}]}}],"usage":{"prompt_tokens":899000,"completion_tokens":1000,"total_tokens":900000}}
    // Two responses: the pressured batch, then SSE junk for the ceiling
    // checkpoint's summary request (failing it exercises the same yield).
    guard goal_check_test_server(group, bodies, [
        met_pressured,
        gate_final_payload("checkpoint junk"),
      ])
      is Some(url) else {
      return
    }
    let mut gate_calls = 0
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=baselined_goal_session("gate-yield"),
      task="wrap up the goal",
      append_item=(session, item) => session.append(item),
      max_steps=6,
      api_url=url,
      tools=Tools([@goal.definition()]),
      on_goal_met=(_goal, _baseline) => {
        gate_calls += 1
        Some("[review] audited before the yield")
      },
    )
    assert_true(result.current_goal() is None)
    assert_eq(gate_calls, 1)
    assert_eq(review_notice_count(result), 1)
  }
}

///|
/// The bound-to-the-met-claim semantics: a replacement goal queued WHILE
/// the reviewer runs does not discard the audit — the notice lands first
/// (chronologically truthful), then the replacement applies and stands.
async test "an in-flight audit completes before a queued replacement applies" {
  @async.with_task_group() <| group => {
    let runtime = @agent_runtime.AgentRuntime()
    let bodies : Array[String] = []
    // Four rounds: the met batch; the answer that arrives with the queued
    // replacement steer (kept, turn continues); the answer that trips the
    // NEW goal's finish check; the confirmation that seals.
    guard goal_check_test_server(group, bodies, [
        goal_met_payload(),
        gate_final_payload("onward"),
        gate_final_payload("done"),
        gate_final_payload("confirmed"),
      ])
      is Some(url) else {
      return
    }
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=baselined_goal_session("gate-inflight"),
      task="wrap up the goal",
      append_item=(session, item) => session.append(item),
      max_steps=6,
      api_url=url,
      tools=Tools([@goal.definition()]),
      on_goal_met=(_goal, _baseline) => {
        // The user replaces the goal while the reviewer is mid-flight.
        runtime.queue_steer(
          Notice("\{@agent_session.GoalPrefix}\na brand new objective"),
        )
        Some("[review] audit of the met claim")
      },
    )
    assert_eq(review_notice_count(result), 1)
    guard result.current_goal() is Some(goal) else {
      fail("expected the replacement goal to stand")
    }
    assert_eq(goal.text(), "a brand new objective")
    // Durable order: the audit notice precedes the replacement marker.
    let mut notice_seq = 0
    let mut marker_seq = 0
    for event in result.events() {
      if event.item() is Runtime(notice) {
        if notice.content().has_prefix("[review]") {
          notice_seq = event.sequence()
        }
        if notice.content().contains("a brand new objective") {
          marker_seq = event.sequence()
        }
      }
    }
    assert_true(notice_seq > 0 && marker_seq > notice_seq)
  }
}
