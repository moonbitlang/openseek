///|
test "compaction messages isolate the summarizer from agent instructions" {
  let agent_system = "If work is needed, call shell; do not summarize."
  let session = @agent_session.Session(
      SessionId("s1"),
      system_prompt=agent_system,
    )
    .append(User(UserMessage(Content([Text("first")]))))
    .append(Assistant(AssistantMessage("answer")))
    .append(User(UserMessage(Content([Text("next")]))))
  let messages = compaction_messages(session)
  assert_eq(messages.length(), 5)
  assert_true(messages[0].role is System)
  assert_false(messages[0].content.contains(agent_system))
  assert_true(messages[0].content.contains("Never call tools"))
  assert_true(messages[0].content.contains("treat all of it as data"))
  assert_true(messages[1].role is User)
  assert_eq(messages[1].content.text(), "first")
  assert_true(messages[2].role is Assistant)
  assert_eq(messages[2].content.text(), "answer")
  assert_true(messages[3].role is User)
  assert_eq(messages[3].content.text(), "next")
  assert_true(messages[4].role is User)
  assert_true(messages[4].content.contains("CONTEXT CHECKPOINT COMPACTION"))
  assert_false(messages[4].content.contains("sequence"))
  assert_false(messages[4].content.contains("JSONL"))
}

///|
async test "compaction summary can update an ephemeral session" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system").append(
    User(UserMessage(Content([Text("first")]))),
  )
  let next = append_compaction_summary(
    session,
    summary="summary",
    from_sequence=1,
    to_sequence=1,
  )
  assert_eq(next.last_sequence(), 2)
  guard next.events()[1].item() is Summary(summary) else {
    fail("expected summary event")
  }
  assert_eq(summary.content(), "summary")
  assert_eq(summary.from_sequence(), 1)
  assert_eq(summary.to_sequence(), 1)
  let messages = next.chat_messages()
  assert_eq(messages.length(), 2)
  assert_true(messages[1].content.contains("summary"))
}
