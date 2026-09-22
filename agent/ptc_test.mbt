///|
/// A model turn that runs `source` through mbtx with PTC on.
fn ptc_payload(source : String) -> String {
  wait_call_payload("mbtx", { "ptc": true, "source": source })
}

///|
async test "agent PTC stores nested calls while only selected output reaches the next model step" {
  @async.with_task_group(group => {
    let bodies : Array[String] = []
    let source =
      #|import { "bobzhang/openseek_tools@0.1.0" @tools, "moonbitlang/async" }
      #|async fn main {
      #|  let result = @tools.call("web_search", { "query": "documentation" })
      #|  if result.is_error { fail(result.content) }
      #|  guard result.data is Some({ "url": String(url), .. }) else { fail("no data") }
      #|  println(url)
      #|}
    guard goal_check_test_server(group, bodies, [
        ptc_payload(source),
        final_answer_payload("done"),
      ])
      is Some(url) else {
      fail("test server unavailable")
    }
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    let tool = @agent_tool.AgentToolDefinition(
      name="web_search",
      description="search",
      schema=JsonSchema({}),
      program_callable=true,
      concurrent_safe=true,
      execute=Sync(_ => {
        @agent_tool.respond("INTERMEDIATE_ONLY", data={
          "url": "https://example.com",
        })
      }),
    )
    let tools = @agent.build_tools(runtime, scope, extra_tools=[tool])
    let session = @async.with_timeout(30000, () => {
      @agent.run_turn_in_scope(
        runtime~,
        scope~,
        tools~,
        api_key="offline",
        model=Deepseek(V4Flash),
        api_url=url,
        session=Session(SessionId("ptc-model"), system_prompt="system"),
        content=Content([Text("search")]),
        max_steps=3,
        append_item=(session, item) => session.append(item),
      )
    })
    let nested = [
      for event in session.events() if event.item() is Tool(result) &&
      result.tool_name() == "mbtx" => result.data()
    ]
    assert_true(
      nested
      is [
        Some(
          { "ptc_calls": [{ "name": "web_search", "status": "done", .. }], .. }
        ),
      ],
    )
    assert_eq(bodies.length(), 2)
    assert_true(bodies[1].contains("https://example.com"))
    assert_false(bodies[1].contains("INTERMEDIATE_ONLY"))
  })
}

///|
async test "agent cancellation persists interrupted PTC metadata before terminal" {
  @async.with_task_group(group => {
    let bodies : Array[String] = []
    guard goal_check_test_server(group, bodies, [
        ptc_payload(
          "import { \"bobzhang/openseek_tools@0.1.0\" @tools, \"moonbitlang/async\" }\nasync fn main { @tools.call(\"block\", {}).content |> println }",
        ),
        // A build failure (for example, an unpublished SDK) can lead to one
        // more model request. End it without exhausting the mock responses.
        final_answer_payload("PTC script did not start"),
      ])
      is Some(url) else {
      fail("test server unavailable")
    }
    let started : @async.Queue[Unit] = Queue(kind=Unbounded)
    let stopped = Ref(false)
    let tool = @agent_tool.AgentToolDefinition(
      name="block",
      description="block",
      schema=JsonSchema({}),
      program_callable=true,
      execute=Async(_ => {
        defer {
          stopped.val = true
        }
        started.put(())
        @async.sleep(60000)
        @agent_tool.respond("unexpected")
      }),
    )
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    let tools = @agent.build_tools(runtime, scope, extra_tools=[tool])
    let items : Array[@agent_session.SessionItem] = []
    let operation = group.spawn(() => {
      @agent.run_turn_in_scope(
        runtime~,
        scope~,
        tools~,
        api_key="offline",
        model=Deepseek(V4Flash),
        api_url=url,
        session=Session(SessionId("ptc-cancel"), system_prompt="system"),
        content=Content([Text("block")]),
        max_steps=3,
        append_item=(session, item) => {
          items.push(item)
          session.append(item)
        },
      )
    })
    @async.with_timeout(30000, () => started.get())
    operation.cancel()
    try operation.wait() |> ignore catch {
      _ => ()
    }
    assert_true(stopped.val)
    assert_true(
      items.any(item => {
        item is Tool(result) &&
        result.data()
        is Some({ "ptc_calls": [{ "status": "interrupted", .. }], .. })
      }),
    )
    assert_true(items.last() is Some(Terminal(Interrupted(_))))
  })
}
