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
  assert_true(
    items[1].kind is @transcript.Assistant(reasoning=None, calls=[], ..),
  )
  assert_eq(items[1].content, "**Working on it.**")
  guard items[2].kind is @transcript.Assistant(reasoning=None, calls=[call], ..) else {
    fail("expected commandExecution to become one shared tool call")
  }
  assert_eq(call.name, "shell")
  guard call.arguments is Some(arguments) else {
    fail("expected the command as the call's arguments")
  }
  assert_true(arguments.contains("moon test"))
  assert_true(call.is_error)
  assert_eq(call.content, "test failed")
  assert_eq(items[2].content, "")
  assert_true(items[3].kind is @transcript.Failure)
  assert_eq(items[3].content, "turn failed")
}

///|
test "Codex omits reasoning without visible summary text" {
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [
        {
          "id": "turn-1",
          "status": "completed",
          "items": [
            {
              "id": "reasoning-empty",
              "type": "reasoning",
              "summary": [],
              "encryptedContent": "opaque",
            },
            {
              "id": "reasoning-blank",
              "type": "reasoning",
              "summary": [{ "type": "summary_text", "text": "  " }],
            },
            {
              "id": "reasoning-visible",
              "type": "reasoning",
              "summary": [
                { "type": "summary_text", "text": "Inspecting the fix" },
              ],
            },
            { "id": "agent-1", "type": "agentMessage", "text": "Done." },
          ],
        },
      ],
    },
  })
  let items = state.transcript_items()
  assert_eq(items.length(), 2)
  guard items[0].kind
    is @transcript.Assistant(reasoning=Some(thought), calls=[], ..) else {
    fail("expected the visible thought as its own response")
  }
  assert_eq(thought, "Inspecting the fix")
  assert_eq(items[0].content, "")
  assert_true(
    items[1].kind is @transcript.Assistant(reasoning=None, calls=[], ..),
  )
  assert_eq(items[1].content, "Done.")
}
