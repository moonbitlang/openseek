///|
test "chat message constructor keeps labeled fields" {
  let call = @deepseek.ToolCall(
    id="call_123",
    name="shell",
    arguments="{\"cmd\":\"moon test\"}",
  )
  let message = @deepseek.ChatMessage(
    Assistant,
    content="",
    tool_calls=[call],
    reasoning_content="run tests first",
  )
  assert_eq(message.tool_calls.length(), 1)
  assert_true(message.reasoning_content is Some("run tests first"))
}

///|
test "model parsing" {
  assert_true(@deepseek.Model::parse("deepseek-flash") is Deepseek(V4Flash))
  // The retired name still parses as an alias for the same tier.
  assert_true(@deepseek.Model::parse("deepseek-v4-flash") is Deepseek(V4Flash))
  assert_true(
    @deepseek.Model::parse("kimi-k2.7-code-highspeed") is Kimi(K27CodeHighSpeed),
  )
  assert_true(@deepseek.Model::parse("glm-5.3") is Glm(G53))
  assert_true(@deepseek.Model::parse("glm-5.3-flash") is Glm(G53Flash))
  assert_eq(
    @deepseek.Model::parse("deepseek-flash").to_string(),
    "deepseek-flash",
  )
  assert_eq(
    @deepseek.Model::parse("deepseek-v4-flash").to_string(),
    "deepseek-flash",
  )
  assert_eq(
    @deepseek.Model::parse("deepseek-v4-pro").to_string(),
    "deepseek-v4-pro",
  )
  assert_eq(
    @deepseek.Model::parse("kimi-k2.7-code").to_string(),
    "kimi-k2.7-code",
  )
  assert_eq(
    @deepseek.Model::parse("kimi-k2.7-code-highspeed").to_string(),
    "kimi-k2.7-code-highspeed",
  )
  assert_eq(@deepseek.Model::parse("glm-5.3").to_string(), "glm-5.3")
  assert_eq(
    @deepseek.Model::parse("glm-5.3-flash").to_string(),
    "glm-5.3-flash",
  )
}

///|
test "context windows per model" {
  assert_eq((Deepseek(V4Flash) : @deepseek.Model).context_window(), 1_000_000)
  assert_eq((Deepseek(V4Pro) : @deepseek.Model).context_window(), 1_000_000)
  assert_eq((Kimi(K27Code) : @deepseek.Model).context_window(), 262_144)
  assert_eq(
    (Kimi(K27CodeHighSpeed) : @deepseek.Model).context_window(),
    262_144,
  )
  assert_eq((Glm(G53) : @deepseek.Model).context_window(), 1_000_000)
  assert_eq((Glm(G53Flash) : @deepseek.Model).context_window(), 1_000_000)
  // A custom endpoint's real window is unknown, so the guard assumes the
  // conservative floor rather than guessing high and overflowing.
  assert_eq((Custom("qwen3-coder") : @deepseek.Model).context_window(), 131_072)
}

///|
test "an unknown model is a custom model only with an explicit endpoint" {
  // With an endpoint the id travels verbatim: the endpoint, not this build,
  // decides whether it exists.
  let custom = @deepseek.Model::parse_for_endpoint(
    " qwen3-coder ",
    Some("https://proxy.example/chat/completions"),
  )
  assert_true(custom is Custom("qwen3-coder"))
  assert_eq(custom.to_string(), "qwen3-coder")
  // The same name without an endpoint stays an error, so a typo cannot
  // silently become a model id sent to an official provider.
  let _ = @deepseek.Model::parse_for_endpoint("qwen3-coder", None) catch {
    error => {
      assert_true("\{error}".contains("unknown model: qwen3-coder"))
      return
    }
  }
  fail("unknown model accepted without an endpoint")
}

///|
test "built-in names parse the same with or without an endpoint" {
  assert_true(
    @deepseek.Model::parse_for_endpoint(
      "glm-5.3",
      Some("https://proxy.example/chat/completions"),
    )
    is Glm(G53),
  )
  assert_true(
    @deepseek.Model::parse_for_endpoint("deepseek-v4-flash", None)
    is Deepseek(V4Flash),
  )
}

///|
test "a malformed custom model id is refused" {
  for id in ["", "   ", "qwen 3", "qwen3\tcoder", "a".repeat(129)] {
    let rejected = try {
      ignore(@deepseek.Model::parse_for_endpoint(id, Some("https://x/y")))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  assert_true(@deepseek.is_valid_custom_model_id("vendor/family:tag"))
  assert_false(@deepseek.is_valid_custom_model_id("vendor family"))
}

///|
test "a custom model resolves its key from the DeepSeek bucket" {
  let custom : @deepseek.Model = Custom("qwen3-coder")
  let stored : Map[String, Array[String]] = {
    "deepseek-api-key": ["sk-proxy"],
    "glm-api-key": ["sk-glm"],
  }
  assert_eq(custom.api_key(stored), Some("sk-proxy"))
  // An explicit generic key still wins, as it does for every model.
  let explicit : Map[String, Array[String]] = {
    "api-key": ["sk-explicit"],
    "deepseek-api-key": ["sk-proxy"],
  }
  assert_eq(custom.api_key(explicit), Some("sk-explicit"))
  let glm_only : Map[String, Array[String]] = { "glm-api-key": ["sk-glm"] }
  assert_eq(custom.api_key(glm_only), None)
}

///|
test "a custom model sends no provider thinking fields" {
  let modes : Array[@deepseek.ThinkingMode] = [No, High, Max]
  for thinking in modes {
    let body = @deepseek.encode_chat_request(
      model=Custom("qwen3-coder"),
      thinking~,
    ) <| [
      ChatMessage(User, content="hi"),
    ]
    // Claiming a dialect (DeepSeek's `thinking`, GLM's `reasoning_effort`)
    // could fail a request the endpoint would otherwise serve, so only the
    // model id and the shared fields travel.
    json_inspect(body, content={
      "model": "qwen3-coder",
      "messages": [{ "role": "user", "content": "hi" }],
      "stream": false,
    })
  }
}

///|
test "thinking controls stringify" {
  let no : @deepseek.ThinkingMode = No
  let high : @deepseek.ThinkingMode = High
  let max : @deepseek.ThinkingMode = Max
  assert_eq(no.to_string(), "no")
  assert_eq(high.to_string(), "high")
  assert_eq(max.to_string(), "max")
}

///|
test "thinking controls parse their wire names and reject others" {
  assert_true(@deepseek.ThinkingMode::parse("no") is No)
  assert_true(@deepseek.ThinkingMode::parse("high") is High)
  assert_true(@deepseek.ThinkingMode::parse("max") is Max)
  assert_true(@deepseek.ThinkingMode::parse("disabled") is No)
  assert_true(@deepseek.ThinkingMode::parse("enabled") is Max)
  let _ = @deepseek.ThinkingMode::parse("on") catch {
    error => {
      assert_true("\{error}".contains("unknown thinking mode"))
      return
    }
  }
  fail("bad thinking mode accepted")
}
