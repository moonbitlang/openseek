///|
test "Codex adapts app-server items to the shared transcript model" {
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [
        {
          "id": "turn-1",
          "status": "failed",
          "items": [
            {
              "id": "user-1",
              "type": "userMessage",
              "content": [
                { "type": "text", "text": "inspect this" },
                {
                  "type": "mention",
                  "name": "model.mbt",
                  "path": "desktop/frontend/codex/model.mbt",
                },
              ],
            },
            {
              "id": "agent-1",
              "type": "agentMessage",
              "text": "**Working on it.**",
            },
            {
              "id": "command-1",
              "type": "commandExecution",
              "command": "moon test",
              "status": "failed",
              "exitCode": 1,
              "aggregatedOutput": "test failed",
            },
          ],
          "error": { "message": "turn failed" },
        },
      ],
    },
  })
  let items = state.transcript_items()
  assert_eq(items.length(), 4)
  assert_true(items[0].kind is @transcript.User)
  guard @mention_context.parse(items[0].content) is Some(user) else {
    fail("expected the user mention to use the shared display envelope")
  }
  assert_eq(user.task, "inspect this")
  assert_true(
    user.mentions
    is [
      @mention_context.Symbol(
        name="model.mbt",
        file="desktop/frontend/codex/model.mbt",
        line=0
      ),
    ],
  )
  assert_true(items[1].kind is @transcript.Assistant(is_danger=false))
  assert_eq(items[1].content, "**Working on it.**")
  guard items[2].kind
    is @transcript.Tool(name~, arguments=Some(arguments), is_error~, ..) else {
    fail("expected commandExecution to become a shared tool item")
  }
  assert_eq(name, "shell")
  assert_true(arguments.contains("moon test"))
  assert_true(is_error)
  assert_eq(items[2].content, "test failed")
  assert_true(items[3].kind is @transcript.Assistant(is_danger=true))
  assert_eq(items[3].content, "turn failed")
}
