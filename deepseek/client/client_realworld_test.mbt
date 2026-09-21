///|
async test "realworld DeepSeek API smoke test" {
  guard @env.get_env_var("DEEPSEEK") is Some(api_key) && api_key != "" else {
    println(
      "DEEPSEEK environment variable is not set or is empty; skipping realworld API smoke test",
    )
    return
  }

  let client = @client.Client(api_key~, model=Deepseek(V4Pro), thinking=High)
  let response = client.chat(
    [
      ChatMessage(System, content=[
        Text(
          (
            #|Reply with exactly this JSON object and no markdown: {"answer":"pong"}
          ),
        ),
      ]),
      ChatMessage(User, content=[Text("ping")]),
    ],
    response_format=JsonObject,
  )
  // It may fail in theory, but in practice it should always work.
  debug_inspect(
    response.content,
    content=(
      #|"{\"answer\":\"pong\"}"
    ),
  )
  assert_true(response.content.contains("pong"))
  assert_true(response.usage.total_tokens > 0)
}

///|
async test "realworld Kimi API smoke test" {
  guard @env.get_env_var("OPENSEEK_MODEL") is Some(model_name) &&
    (model_name == "kimi-k2.7-code" || model_name == "kimi-k2.7-code-highspeed") else {
    println(
      "OPENSEEK_MODEL is not a Kimi model; skipping realworld Kimi API smoke test",
    )
    return
  }
  guard @env.get_env_var("KIMI") is Some(api_key) && api_key != "" else {
    println(
      "KIMI environment variable is not set or is empty; skipping realworld Kimi API smoke test",
    )
    return
  }

  let model = @deepseek.Model::parse(model_name)
  let client = @client.Client(api_key~, model~)
  let response = client.chat([
    ChatMessage(System, content=[
      Text("Reply with exactly this plain text and no markdown: pong"),
    ]),
    ChatMessage(User, content=[Text("ping")]),
  ])
  assert_true(response.content.contains("pong"))
  assert_true(response.usage.total_tokens > 0)
}

///|
async test "realworld Kimi API streaming smoke test" {
  guard @env.get_env_var("KIMI") is Some(api_key) && api_key != "" else {
    println(
      "KIMI environment variable is not set or is empty; skipping realworld Kimi API streaming smoke test",
    )
    return
  }

  let model = @deepseek.Kimi(K27Code)
  let client = @client.Client(api_key~, model~)
  let deltas : Array[String] = []
  let response = client.chat(
    [
      ChatMessage(System, content=[
        Text("Reply with exactly this plain text and no markdown: pong"),
      ]),
      ChatMessage(User, content=[Text("ping")]),
    ],
    stream=StreamHandler(on_content_delta=delta => deltas.push(delta)),
  )
  assert_true(deltas.join("").contains("pong"))
  assert_true(response.content.contains("pong"))
  assert_true(response.usage.total_tokens > 0)
}

///|
async test "realworld Kimi API tool-call smoke test" {
  guard @env.get_env_var("KIMI") is Some(api_key) && api_key != "" else {
    println(
      "KIMI environment variable is not set or is empty; skipping realworld Kimi API tool-call smoke test",
    )
    return
  }

  let model = @deepseek.Kimi(K27Code)
  let client = @client.Client(api_key~, model~)
  let tool = @deepseek.ToolDefinition(
    "return_token",
    "Return the exact token requested by the user.",
    {
      "type": "object",
      "properties": { "token": { "type": "string" } },
      "required": ["token"],
    },
  )
  let response = client.chat(
    [
      ChatMessage(System, content=[
        Text(
          (
            #|You must call the return_token tool exactly once. Do not answer in text.
          ),
        ),
      ]),
      ChatMessage(User, content=[Text("Call return_token with token pong.")]),
    ],
    tools=[tool],
  )
  assert_true(response.tool_calls.length() > 0)
  assert_eq(response.tool_calls[0].name, "return_token")
  assert_true(response.tool_calls[0].id != "")
  assert_true(response.tool_calls[0].arguments.contains("pong"))
  assert_true(response.usage.total_tokens > 0)
}

///|
async test "realworld Kimi API multi-turn reasoning-content smoke test" {
  guard @env.get_env_var("KIMI") is Some(api_key) && api_key != "" else {
    println(
      "KIMI environment variable is not set or is empty; skipping realworld Kimi API multi-turn reasoning-content smoke test",
    )
    return
  }

  let model = @deepseek.Kimi(K27Code)
  let client = @client.Client(api_key~, model~)
  let tool = @deepseek.ToolDefinition(
    "return_token",
    "Return the exact token requested by the user.",
    {
      "type": "object",
      "properties": { "token": { "type": "string" } },
      "required": ["token"],
    },
  )
  let first_user : @deepseek.ChatMessage = ChatMessage(User, content=[
    Text("Call return_token with token pong."),
  ])
  let first = client.chat(
    [
      ChatMessage(System, content=[
        Text(
          (
            #|You must call the return_token tool exactly once. Do not answer in text.
          ),
        ),
      ]),
      first_user,
    ],
    tools=[tool],
  )
  assert_true(first.reasoning_content != "")
  assert_true(first.tool_calls.length() > 0)
  let call = first.tool_calls[0]
  let second = client.chat(
    [
      ChatMessage(System, content=[
        Text(
          (
            #|After the tool result is available, do not call any tool again. Reply exactly: done
          ),
        ),
      ]),
      first_user,
      ChatMessage(
        Assistant,
        content=[Text(first.content)],
        tool_calls=first.tool_calls,
        reasoning_content=first.reasoning_content,
      ),
      ChatMessage(Tool(call.id), content=[Text("{\"token\":\"pong\"}")]),
      ChatMessage(User, content=[Text("Use the tool result now.")]),
    ],
    tools=[tool],
  )
  assert_true(second.tool_calls.length() == 0)
  assert_true(second.content.contains("done"))
  assert_true(second.usage.total_tokens > 0)
}

///|
async test "realworld GLM streaming tool-call smoke test" {
  guard @env.get_env_var("GLM") is Some(api_key) && api_key != "" else {
    println(
      "GLM environment variable is not set or is empty; skipping realworld GLM streaming tool-call smoke test",
    )
    return
  }

  let client = @client.Client(api_key~, model=Glm(G53), thinking=High)
  let tool = @deepseek.ToolDefinition(
    "return_token",
    "Return the exact token requested by the user.",
    {
      "type": "object",
      "properties": { "token": { "type": "string" } },
      "required": ["token"],
    },
    strict=true,
  )
  let response = client.chat(
    [
      ChatMessage(System, content=[
        Text(
          (
            #|You must call the return_token tool exactly once. Do not answer in text.
          ),
        ),
      ]),
      ChatMessage(User, content=[Text("Call return_token with token pong.")]),
    ],
    tools=[tool],
    stream=StreamHandler(on_content_delta=_ => ()),
  )
  assert_eq(response.tool_calls.length(), 1)
  assert_eq(response.tool_calls[0].name, "return_token")
  assert_true(response.tool_calls[0].id != "")
  assert_true(response.tool_calls[0].arguments.contains("pong"))
  assert_true(response.usage.total_tokens > 0)
}
