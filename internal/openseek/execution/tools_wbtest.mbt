///|
test "web_search_api_key reuses the DeepSeek key only for official-endpoint runs" {
  let official = None
  let gateway = Some("https://gateway.example/v1")
  // DeepSeek model on the official endpoint: reuse the turn's key.
  assert_eq(
    web_search_api_key(Deepseek(V4Pro), "turn-key", official, Some("dk")),
    Some("turn-key"),
  )
  // A custom chat endpoint disables the tool regardless of provider: the key
  // in hand (and the desktop-exported $DEEPSEEK) may be a gateway credential
  // that must not reach the official search endpoint.
  assert_true(
    web_search_api_key(Deepseek(V4Pro), "gateway-token", gateway, Some("dk"))
    is None,
  )
  assert_true(
    web_search_api_key(Kimi(K27Code), "kimi-key", gateway, Some("dk")) is None,
  )
  // A Kimi run falls back to the dedicated $DEEPSEEK credential.
  assert_eq(
    web_search_api_key(Kimi(K27Code), "kimi-key", official, Some("dk")),
    Some("dk"),
  )
  // Without any DeepSeek credential the tool is simply not registered.
  assert_true(
    web_search_api_key(Kimi(K27Code), "kimi-key", official, None) is None,
  )
}

///|
/// The tools that watch and message subagents exist exactly where a turn has
/// a durable session to record children under.
async test "the subagent tools are registered only for a session that can delegate" {
  @async.with_task_group() <| group => {
    fn names(tools : Array[@agent_tool.AgentToolDefinition]) -> Array[String] {
      tools.map(tool => tool.name)
    }
    let scope = @agent_runtime.AgentTaskScope(group)
    // A custom endpoint keeps web_search out, so the subagent tools are the
    // whole difference between the two registries.
    let without = build_extra_tools(
      scope,
      model=Deepseek(V4Pro),
      api_key="k",
      workspace_root=".",
      api_url="https://gateway.example/v1",
    )
    assert_eq(names(without), [])
    let with_children = build_extra_tools(
      scope,
      model=Deepseek(V4Pro),
      api_key="k",
      workspace_root=".",
      api_url="https://gateway.example/v1",
      subagents=ChildSession(root="/store", parent="p"),
    )
    assert_eq(names(with_children), ["subagent_status", "subagent_send"])
  }
}
