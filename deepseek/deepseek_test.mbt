///|
test "chat message constructor" {
  let user = @deepseek.ChatMessage(User, content="hello")
  assert_eq(user.role.to_string(), "user")
  assert_eq(user.content, "hello")
  let assistant = @deepseek.ChatMessage(Assistant, content="done")
  assert_eq(assistant.role.to_string(), "assistant")
  assert_eq(assistant.content, "done")
  let tool = @deepseek.ChatMessage(Tool("call_123"), content="tool result")
  assert_eq(tool.role.to_string(), "tool")
  assert_eq(tool.content, "tool result")
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
  assert_eq(message.tool_calls.length(), 1)
  assert_true(message.reasoning_content is Some("run tests first"))
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
  let enabled : @deepseek.ThinkingMode = Enabled
  let disabled : @deepseek.ThinkingMode = Disabled
  let high : @deepseek.ReasoningEffort = High
  let max : @deepseek.ReasoningEffort = Max
  assert_eq(enabled.to_string(), "enabled")
  assert_eq(disabled.to_string(), "disabled")
  assert_eq(high.to_string(), "high")
  assert_eq(max.to_string(), "max")
}

///|
test "thinking controls parse their wire names and reject others" {
  assert_true(@deepseek.ThinkingMode::parse("enabled") is Enabled)
  assert_true(@deepseek.ThinkingMode::parse("disabled") is Disabled)
  assert_true(@deepseek.ReasoningEffort::parse("high") is High)
  assert_true(@deepseek.ReasoningEffort::parse("max") is Max)
  let _ = @deepseek.ThinkingMode::parse("on") catch {
    error => {
      assert_true("\{error}".contains("unknown thinking mode"))
      let _ = @deepseek.ReasoningEffort::parse("ultra") catch {
        error => {
          assert_true("\{error}".contains("unknown reasoning effort"))
          return
        }
      }
      fail("bad reasoning effort accepted")
    }
  }
  fail("bad thinking mode accepted")
}
