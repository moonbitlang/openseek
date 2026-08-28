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
  assert_true(@deepseek.Model::parse("deepseek-v4-flash") is Deepseek(V4Flash))
  assert_true(
    @deepseek.Model::parse("kimi-k2.7-code-highspeed") is Kimi(K27CodeHighSpeed),
  )
  assert_true(@deepseek.Model::parse("glm-5.3") is Glm(G53))
  assert_true(@deepseek.Model::parse("glm-5.3-flash") is Glm(G53Flash))
  assert_eq(
    @deepseek.Model::parse("deepseek-v4-flash").to_string(),
    "deepseek-v4-flash",
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
