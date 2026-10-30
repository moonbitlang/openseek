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

///|
test "chart references and display data survive replay and fork without entering model context" {
  let embed = "![Revenue](artifact://chart_revenue)"
  let data : Json = {
    "artifacts": [
      {
        "id": "chart_revenue",
        "kind": "mathplotlib",
        "version": 1,
        "spec": {
          "title": "Revenue",
          "series": [{ "y": [17, 29], "label": "CHART_DATA_ONLY" }],
        },
      },
    ],
  }
  let session = @agent_session.Session(
      SessionId("charts"),
      system_prompt="system",
    )
    .append(User(UserMessage(Content([Text("Chart revenue")]))))
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="plot", name="mbtx", arguments="{}"),
        ]),
      ),
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="plot",
          tool_name="mbtx",
          content=[Text("{\"artifact_id\":\"chart_revenue\"}")],
          data~,
        ),
      ),
    )
    .append(Assistant(AssistantMessage(embed)))
    .append(Terminal(Finished(embed)))
  let fork = session.fork(SessionId("chart-fork"), system_prompt="fork system")
  let mut restored_charts = 0
  for event in fork.events() {
    let restored : @agent_session.SessionEvent = @json.from_json(
      ToJson::to_json(event),
    )
    if restored.item() is Tool(result) {
      assert_eq(result.data(), Some(data))
      restored_charts += 1
    }
  }
  assert_eq(restored_charts, 1)
  let model = fork
    .chat_messages()
    .map(message => message.content.text())
    .join("\n")
  assert_true(model.contains("artifact://chart_revenue"))
  assert_false(model.contains("CHART_DATA_ONLY"))
}
