///|
/// A batch payload holding two calls to the same tool, then a plain finish.
fn two_probe_calls_payload() -> String {
  (
    #|{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"probe","arguments":"{\"tag\": \"a\"}"}},{"index":1,"id":"c2","function":{"name":"probe","arguments":"{\"tag\": \"b\"}"}}]}}],"usage":{"prompt_tokens":9000,"completion_tokens":1000,"total_tokens":10000}}
  )
}

///|
fn probe_final_payload() -> String {
  (
    #|{"choices":[{"delta":{"content":"done"}}],"usage":{"prompt_tokens":9000,"completion_tokens":1000,"total_tokens":10000}}
  )
}

///|
/// A slow tool that journals its own start/end, so a test can distinguish
/// overlapped execution from sequential.
fn probe_tool(
  journal : Array[String],
  concurrent_safe~ : Bool,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="probe",
    description="Probe tool.",
    schema=JsonSchema({ "type": "object" }),
    concurrent_safe~,
    execute=Async(arguments => {
      let tag = match arguments {
        { "tag": String(tag), .. } => tag.to_string()
        _ => "?"
      }
      journal.push("start-\{tag}")
      @async.sleep(60)
      journal.push("end-\{tag}")
      @agent_tool.respond("ok-\{tag}")
    }),
  )
}

///|
/// The recorded tool results for the batch, in session order.
fn probe_results(session : @agent_session.Session) -> Array[String] {
  [
    for event in session.events() if event.item() is Tool(result) &&
    result.tool_name() == "probe" => result.content()
  ]
}

///|
/// Two adjacent concurrent-safe calls overlap: both start before either
/// ends, while the recorded results keep call order. This is the batch
/// shape a model uses to fan out two subagent delegations at once.
async test "adjacent concurrent-safe calls overlap and keep result order" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard goal_check_test_server(group, bodies, [
        two_probe_calls_payload(),
        probe_final_payload(),
      ])
      is Some(url) else {
      return
    }
    let journal : Array[String] = []
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=Session(SessionId("concurrent-probes"), system_prompt="system"),
      task="probe twice",
      append_item=(session, item) => session.append(item),
      max_steps=4,
      api_url=url,
      tools=Tools([probe_tool(journal, concurrent_safe=true)]),
    )
    assert_eq(journal, ["start-a", "start-b", "end-a", "end-b"])
    assert_eq(probe_results(result), ["ok-a", "ok-b"])
  }
}

///|
/// The same batch WITHOUT the flag stays strictly sequential — the default
/// for every tool that never declared adjacent-call safety.
async test "unflagged adjacent calls stay sequential" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    guard goal_check_test_server(group, bodies, [
        two_probe_calls_payload(),
        probe_final_payload(),
      ])
      is Some(url) else {
      return
    }
    let journal : Array[String] = []
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=Session(SessionId("sequential-probes"), system_prompt="system"),
      task="probe twice",
      append_item=(session, item) => session.append(item),
      max_steps=4,
      api_url=url,
      tools=Tools([probe_tool(journal, concurrent_safe=false)]),
    )
    assert_eq(journal, ["start-a", "end-a", "start-b", "end-b"])
    assert_eq(probe_results(result), ["ok-a", "ok-b"])
  }
}

///|
/// Calls behind a batch-sealing control call never prefetch: the sealed
/// batch discards its remainder, and children sequential execution never
/// launches must not run. The finish at index 0 seals; neither probe
/// journals anything.
async test "no prefetch behind a batch-sealing control call" {
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    let finish_then_probes =
      #|{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c0","function":{"name":"finish","arguments":"{\"answer\":\"done early\"}"}},{"index":1,"id":"c1","function":{"name":"probe","arguments":"{\"tag\": \"a\"}"}},{"index":2,"id":"c2","function":{"name":"probe","arguments":"{\"tag\": \"b\"}"}}]}}],"usage":{"prompt_tokens":9000,"completion_tokens":1000,"total_tokens":10000}}
    guard goal_check_test_server(group, bodies, [finish_then_probes])
      is Some(url) else {
      return
    }
    let journal : Array[String] = []
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=Session(SessionId("sealed-batch"), system_prompt="system"),
      task="finish immediately",
      append_item=(session, item) => session.append(item),
      max_steps=4,
      api_url=url,
      tools=Tools([
        probe_tool(journal, concurrent_safe=true),
        @finish.definition(),
      ]),
    )
    assert_eq(journal, ([] : Array[String]))
    guard result.events().iter().last() is Some(event) &&
      event.item() is Terminal(Finished(answer)) else {
      fail("expected a sealed finish")
    }
    assert_eq(answer, "done early")
  }
}
