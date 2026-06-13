///|
test "chat message constructor" {
  let user = @deepseek.ChatMessage(User, content="hello")
  assert_eq(user.role().to_string(), "user")
  assert_eq(user.content(), "hello")
  let assistant = @deepseek.ChatMessage(Assistant, content="done")
  assert_eq(assistant.role().to_string(), "assistant")
  assert_eq(assistant.content(), "done")
  let tool = @deepseek.ChatMessage(Tool("call_123"), content="tool result")
  assert_eq(tool.role().to_string(), "tool")
  assert_eq(tool.content(), "tool result")
}

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
  assert_eq(message.tool_calls().length(), 1)
  assert_true(message.reasoning_content() is Some("run tests first"))
}

///|
test "model parsing" {
  assert_eq(
    @deepseek.Model::parse("deepseek-v4-flash").to_string(),
    "deepseek-v4-flash",
  )
  assert_eq(
    @deepseek.Model::parse("deepseek-v4-pro").to_string(),
    "deepseek-v4-pro",
  )
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
