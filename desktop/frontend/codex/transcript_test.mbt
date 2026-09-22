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
  guard items[0].kind is @transcript.User(content=prompt) else {
    fail("expected the submitted prompt as the first item")
  }
  guard @mention_context.parse(prompt.text()) is Some(user) else {
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
  assert_eq(items[1].text(), Some("**Working on it.**"))
  guard items[2].kind is @transcript.Assistant(reasoning=None, calls=[call], ..) else {
    fail("expected commandExecution to become one shared tool call")
  }
  assert_eq(call.name, "shell")
  guard call.arguments is Some(arguments) else {
    fail("expected the command as the call's arguments")
  }
  assert_true(arguments.contains("moon test"))
  assert_true(
    call.outcome
    is Done(content=Content([Text("test failed")]), is_error=true, ..),
  )
  assert_true(items[2].text() is None)
  assert_true(items[3].kind is @transcript.Failure(_))
  assert_eq(items[3].text(), Some("turn failed"))
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
  assert_true(items[0].text() is None)
  assert_true(
    items[1].kind is @transcript.Assistant(reasoning=None, calls=[], ..),
  )
  assert_eq(items[1].text(), Some("Done."))
}

///|
test "Codex marks only the final answer of a successful turn finished" {
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "t",
      "turns": [
        {
          "id": "done",
          "status": "completed",
          "items": [
            {
              "id": "progress",
              "type": "agentMessage",
              "phase": "commentary",
              "text": "Looking",
            },
            {
              "id": "answer",
              "type": "agentMessage",
              "phase": "final_answer",
              "text": "Result",
            },
          ],
        },
        {
          "id": "running",
          "status": "inProgress",
          "items": [
            { "id": "live", "type": "agentMessage", "text": "Still working" },
          ],
        },
      ],
    },
  })
  let items = state.transcript_items()
  assert_true(items[0].kind is @transcript.Assistant(finished=false, ..))
  assert_true(items[1].kind is @transcript.Assistant(finished=true, ..))
  assert_true(items[2].kind is @transcript.Assistant(finished=false, ..))
}

///|
test "Codex preserves interrupted failed and answerless boundaries" {
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "t",
      "turns": [
        {
          "id": "stopped",
          "status": "interrupted",
          "items": [{ "id": "a", "type": "agentMessage", "text": "Partial" }],
        },
        {
          "id": "failed",
          "status": "failed",
          "items": [],
          "error": { "message": "Unavailable" },
        },
        {
          "id": "empty",
          "status": "completed",
          "items": [
            {
              "id": "b",
              "type": "agentMessage",
              "phase": "commentary",
              "text": "Checking",
            },
          ],
        },
        {
          "id": "legacy",
          "status": "completed",
          "items": [
            { "id": "c", "type": "agentMessage", "text": "Legacy final" },
          ],
        },
      ],
    },
  })
  let items = state.transcript_items()
  assert_eq(items.length(), 6)
  assert_true(items[0].kind is @transcript.Assistant(finished=false, ..))
  assert_true(items[1].kind is @transcript.Failure("Stopped"))
  assert_true(items[2].kind is @transcript.Failure("Unavailable"))
  assert_true(items[3].kind is @transcript.Assistant(finished=false, ..))
  assert_true(items[4].kind is @transcript.TurnEnd)
  assert_true(items[5].kind is @transcript.Assistant(finished=true, ..))
}

///|
test "Codex tool categories use explicit operation metadata" {
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "t",
      "turns": [
        {
          "id": "work",
          "status": "inProgress",
          "items": [
            {
              "id": "spawn",
              "type": "collabAgentToolCall",
              "tool": "spawnAgent",
              "status": "completed",
            },
            {
              "id": "wait",
              "type": "collabAgentToolCall",
              "tool": "wait",
              "status": "inProgress",
            },
            {
              "id": "mcp",
              "type": "mcpToolCall",
              "server": "example",
              "tool": "read",
              "status": "completed",
            },
          ],
        },
      ],
    },
  })
  let names : Array[String] = []
  for item in state.transcript_items() {
    if item.kind is @transcript.Assistant(calls=[call], ..) {
      names.push(call.name)
    }
  }
  // An MCP tool named read is not necessarily a filesystem read.
  assert_eq(names, ["spawn_agent", "wait_agent", "mcp__example__read"])
}

///|
test "Codex covers every declared collaboration operation and dynamic names" {
  let operations = [
    ("spawnAgent", "spawn_agent", "Create subagent"),
    ("wait", "wait_agent", "Wait for subagents"),
    ("sendInput", "send_input", "Send message to subagent"),
    ("sendMessage", "send_message", "Send message to subagent"),
    ("resumeAgent", "resume_agent", "Resume subagent"),
    ("followupTask", "followup_task", "Assign subagent task"),
    ("interruptAgent", "interrupt_agent", "Stop subagent"),
    ("closeAgent", "close_agent", "Close subagent"),
    ("listAgents", "list_agents", "List subagents"),
  ]
  let raw : Array[Json] = operations.map(operation => {
    "id": Json(operation.0),
    "type": "collabAgentToolCall",
    "tool": Json(operation.0),
    "status": "completed",
  })
  raw.push({
    "id": "dynamic",
    "type": "dynamicToolCall",
    "namespace": "example",
    "tool": "edit",
    "status": "completed",
    "success": false,
  })
  raw.push({
    "id": "dynamic-bare",
    "type": "dynamicToolCall",
    "tool": "read",
    "status": "inProgress",
  })
  raw.push({ "id": "image", "type": "imageGeneration", "status": "in_progress" })
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "t",
      "turns": [{ "id": "work", "status": "inProgress", "items": Json(raw) }],
    },
  })
  let items = state.transcript_items()
  for index, (_, name, brief) in operations {
    assert_true(
      items[index].kind
      is @transcript.Assistant(
        calls=[{ name: actual, outcome: Done(brief=Some(caption), ..), .. }],
        ..
      ) &&
      actual == name &&
      caption == brief,
    )
  }
  assert_true(
    items[9].kind
    is @transcript.Assistant(
      calls=[
        { name: "dynamic__example__edit", outcome: Done(is_error=true, ..), .. },
      ],
      ..
    ),
  )
  assert_true(
    items[10].kind
    is @transcript.Assistant(
      calls=[{ name: "dynamic__read", outcome: Pending(..), .. }],
      ..
    ),
  )
  assert_true(
    items[11].kind
    is @transcript.Assistant(calls=[{ outcome: Pending(..), .. }], ..),
  )
}

///|
test "Codex history preserves image-only and mixed user messages" {
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "images",
      "turns": [
        {
          "id": "turn-images",
          "status": "completed",
          "items": [
            {
              "id": "user-images",
              "type": "userMessage",
              "content": [
                { "type": "text", "text": "Look at this" },
                { "type": "image", "url": "data:image/png;base64,YQ==" },
                { "type": "image", "url": "data:image/jpeg;base64,Yg==" },
              ],
            },
          ],
        },
      ],
    },
  })
  guard state.transcript_items()[0].kind is @transcript.User(content~) else {
    fail("expected image content in the user message")
  }
  assert_eq(content.text(), "Look at this")
  assert_true(
    content.0
    is [
      Text("Look at this"),
      ImageUrl(url="data:image/png;base64,YQ=="),
      ImageUrl(url="data:image/jpeg;base64,Yg=="),
    ],
  )
}
