///|
test "tool data persists but never enters model messages" {
  let result = @agent_session.ToolResult(
    tool_call_id="outer",
    tool_name="mbtx",
    content=[Text("selected output")],
    data={
      "ptc_calls": [
        { "arguments": { "secret_intermediate": "not model context" } },
      ],
    },
  )
  let encoded = ToJson::to_json(result)
  let decoded : @agent_session.ToolResult = @json.from_json(encoded)
  assert_eq(decoded.data(), result.data())
  let session = @agent_session.Session(SessionId("ptc"), system_prompt="system")
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="outer", name="mbtx", arguments="{}"),
        ]),
      ),
    )
    .append(Tool(result))
  let messages = session.chat_messages()
  // Inspect every text part; model content can also contain file references.
  assert_true(
    messages
    .map(message => message.content.text())
    .join("\n")
    .contains("selected output"),
  )
  assert_false(
    messages
    .map(message => message.content.text())
    .join("\n")
    .contains("secret_intermediate"),
  )
}
