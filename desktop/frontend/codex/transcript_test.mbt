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
  guard items[0].kind is @transcript.User(prompt) else {
    fail("expected the submitted prompt as the first item")
  }
  guard @mention_context.parse(prompt) is Some(user) else {
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
  assert_true(call.outcome is Done(content="test failed", is_error=true, ..))
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
test "Codex normalizes semantic app-server tools for the shared transcript" {
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [
        {
          "id": "turn-1",
          "status": "completed",
          "items": [
            {
              "id": "read-1",
              "type": "commandExecution",
              "command": "sed -n '1,20p' src/main.mbt",
              "cwd": "/work/project",
              "commandActions": [
                {
                  "type": "read",
                  "command": "sed -n '1,20p' src/main.mbt",
                  "name": "main.mbt",
                  "path": "src/main.mbt",
                },
              ],
              "status": "completed",
              "exitCode": 0,
              "aggregatedOutput": "fn main { }",
            },
            {
              "id": "edit-1",
              "type": "fileChange",
              "status": "completed",
              "changes": [
                {
                  "path": "src/main.mbt",
                  "kind": { "type": "update", "move_path": Json::null() },
                  "diff": "@@ -1 +1 @@\n-fn old { }\n+fn main { }",
                },
              ],
            },
            {
              "id": "edit-2",
              "type": "fileChange",
              "status": "completed",
              "changes": [
                {
                  "path": "a.mbt",
                  "kind": { "type": "add" },
                  "diff": "+let a = 1",
                },
                {
                  "path": "b.mbt",
                  "kind": { "type": "delete" },
                  "diff": "-let b = 2",
                },
              ],
            },
            {
              "id": "mcp-1",
              "type": "mcpToolCall",
              "server": "docs",
              "tool": "lookup",
              "arguments": { "query": "TranscriptItem" },
              "status": "completed",
              "result": {
                "content": [{ "type": "text", "text": "MCP result" }],
              },
              "error": Json::null(),
            },
            {
              "id": "dynamic-1",
              "type": "dynamicToolCall",
              "namespace": "workspace",
              "tool": "run_moonbit",
              "arguments": { "source": "fn main { println(\"hi\") }" },
              "status": "completed",
              "success": true,
              "contentItems": [
                { "type": "inputText", "text": "program passed" },
              ],
            },
          ],
        },
      ],
    },
  })
  let items = state.transcript_items()
  assert_eq(items.length(), 5)
  guard items[0].kind
    is @transcript.Tool(
      name="read",
      arguments=Some(read_arguments),
      has_result=true,
      is_error=false,
      ..
    ) else {
    fail("expected a classified command read")
  }
  assert_true(read_arguments.contains("src/main.mbt"))
  assert_eq(items[0].content, "fn main { }")
  guard items[1].kind
    is @transcript.Tool(name="edit", arguments=Some(edit_arguments), ..) else {
    fail("expected one file change to become edit")
  }
  assert_true(edit_arguments.contains("@@ -1 +1 @@"))
  assert_true(edit_arguments.contains("src/main.mbt"))
  guard items[2].kind
    is @transcript.Tool(name="multi_edit", arguments=Some(multi_arguments), ..) else {
    fail("expected several file changes to become multi_edit")
  }
  assert_true(multi_arguments.contains("\"edits\""))
  assert_true(multi_arguments.contains("a.mbt"))
  assert_true(multi_arguments.contains("b.mbt"))
  guard items[3].kind
    is @transcript.Tool(name="mcp__docs__lookup", arguments=Some(mcp_args), ..) else {
    fail("expected an MCP registry-style tool name")
  }
  assert_true(mcp_args.contains("TranscriptItem"))
  assert_eq(items[3].content, "MCP result")
  guard items[4].kind
    is @transcript.Tool(
      name="run_moonbit",
      arguments=Some(dynamic_args),
      is_error=false,
      ..
    ) else {
    fail("expected a dynamic tool to retain its semantic name")
  }
  assert_true(dynamic_args.contains("fn main"))
  assert_eq(items[4].content, "program passed")
}

///|
test "Codex gives every remaining app-server activity a shared semantic row" {
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [
        {
          "id": "turn-1",
          "status": "completed",
          "items": [
            { "id": "plan-1", "type": "plan", "text": "Proposed approach" },
            {
              "id": "hook-1",
              "type": "hookPrompt",
              "fragments": [
                { "hookRunId": "hook-run-1", "text": "Check generated files" },
              ],
            },
            {
              "id": "collab-1",
              "type": "collabAgentToolCall",
              "tool": "spawnAgent",
              "senderThreadId": "thread-1",
              "receiverThreadIds": ["thread-2"],
              "prompt": "Inspect the adapter",
              "model": "gpt-5",
              "reasoningEffort": "high",
              "status": "completed",
              "agentsStates": {
                "thread-2": { "status": "completed", "message": "done" },
              },
            },
            {
              "id": "subagent-1",
              "type": "subAgentActivity",
              "agentPath": "adapter_review",
              "agentThreadId": "thread-2",
              "kind": "interacted",
            },
            {
              "id": "search-1",
              "type": "webSearch",
              "query": "MoonBit adapter",
              "action": { "type": "search", "query": "MoonBit adapter" },
              "results": [{ "title": "Result" }],
            },
            { "id": "view-1", "type": "imageView", "path": "/work/a.png" },
            { "id": "sleep-1", "type": "sleep", "durationMs": 250 },
            {
              "id": "image-1",
              "type": "imageGeneration",
              "status": "completed",
              "result": "https://example.invalid/image.png",
              "savedPath": "/work/generated.png",
              "revisedPrompt": "A diagram",
              "transparentBackground": false,
              "failure": Json::null(),
            },
            {
              "id": "review-1",
              "type": "enteredReviewMode",
              "review": "Review the current changes",
            },
            { "id": "compact-1", "type": "contextCompaction" },
          ],
        },
      ],
    },
  })
  let items = state.transcript_items()
  assert_eq(items.length(), 10)
  assert_true(items[0].kind is @transcript.Assistant(is_danger=false))
  assert_eq(items[0].content, "Proposed approach")
  assert_true(items[1].kind is @transcript.Tool(name="hook_prompt", ..))
  assert_eq(items[1].content, "Check generated files")
  assert_true(
    items[2].kind is @transcript.Tool(name="spawnAgent", is_error=false, ..),
  )
  assert_true(items[2].content.contains("thread-2"))
  assert_true(items[3].kind is @transcript.Tool(name="subagent", ..))
  assert_true(items[4].kind is @transcript.Tool(name="web_search", ..))
  assert_true(items[4].content.contains("Result"))
  assert_true(items[5].kind is @transcript.Tool(name="image_view", ..))
  assert_true(items[6].kind is @transcript.Tool(name="sleep", ..))
  assert_true(
    items[7].kind
    is @transcript.Tool(name="image_generation", is_error=false, ..),
  )
  assert_eq(items[7].content, "https://example.invalid/image.png")
  assert_true(items[8].kind is @transcript.Tool(name="review", ..))
  assert_eq(items[8].content, "Review the current changes")
  assert_true(items[9].kind is @transcript.Summary)
}

///|
#warnings("-alert_unstable")
test "Codex structured plan notifications use the shared plan payload" {
  let dispatch : @cmd.Emit[@codex.Msg] = @cmd.Emit(_ => @cmd.none)
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [{ "id": "turn-1", "status": "inProgress", "items": [] }],
    },
  })
  let (_, planned) = @codex.update(
    dispatch,
    @codex.Msg::notification(
      "turn/plan/updated",
      {
        "threadId": "thread-1",
        "turnId": "turn-1",
        "explanation": "Starting with the adapter",
        "plan": [
          { "step": "Map items", "status": "completed" },
          { "step": "Run tests", "status": "inProgress" },
          { "step": "Review diff", "status": "pending" },
        ],
      },
      0,
    ),
    state,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let items = planned.transcript_items()
  assert_eq(items.length(), 1)
  guard items[0].kind
    is @transcript.Tool(
      name="plan",
      arguments=Some(arguments),
      has_result=true,
      is_error=false,
      brief=Some(brief),
      ..
    ) else {
    fail("expected a shared plan tool row")
  }
  assert_true(arguments.contains("\"title\":\"Run tests\""))
  assert_true(arguments.contains("\"status\":\"in_progress\""))
  assert_eq(brief, "plan 1/3 · Run tests")
}

///|
#warnings("-alert_unstable")
test "Codex item notifications preserve pending tool state" {
  let dispatch : @cmd.Emit[@codex.Msg] = @cmd.Emit(_ => @cmd.none)
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [{ "id": "turn-1", "status": "inProgress", "items": [] }],
    },
  })
  let started : Json = {
    "threadId": "thread-1",
    "turnId": "turn-1",
    "startedAtMs": 1000,
    "item": { "id": "search-1", "type": "webSearch", "query": "MoonBit" },
  }
  let (_, pending) = @codex.update(
    dispatch,
    @codex.Msg::notification("item/started", started, 0),
    state,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(
    pending.transcript_items()[0].kind
    is @transcript.Tool(name="web_search", has_result=false, ..),
  )
  assert_eq(pending.transcript_items()[0].ts, Some(1000.0))
  let completed_params : Json = {
    "threadId": "thread-1",
    "turnId": "turn-1",
    "completedAtMs": 2000,
    "item": { "id": "search-1", "type": "webSearch", "query": "MoonBit" },
  }
  let (_, completed) = @codex.update(
    dispatch,
    @codex.Msg::notification("item/completed", completed_params, 0),
    pending,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_true(
    completed.transcript_items()[0].kind
    is @transcript.Tool(name="web_search", has_result=true, ..),
  )
  assert_eq(completed.transcript_items()[0].ts, Some(2000.0))
}

///|
#warnings("-alert_unstable")
test "Codex live patch and MCP progress update their shared rows" {
  let dispatch : @cmd.Emit[@codex.Msg] = @cmd.Emit(_ => @cmd.none)
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [{ "id": "turn-1", "status": "inProgress", "items": [] }],
    },
  })
  let (_, editing) = @codex.update(
    dispatch,
    @codex.Msg::notification(
      "item/started",
      {
        "threadId": "thread-1",
        "turnId": "turn-1",
        "startedAtMs": 1000,
        "item": {
          "id": "edit-1",
          "type": "fileChange",
          "status": "inProgress",
          "changes": [],
        },
      },
      0,
    ),
    state,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let (_, patched) = @codex.update(
    dispatch,
    @codex.Msg::notification(
      "item/fileChange/patchUpdated",
      {
        "threadId": "thread-1",
        "turnId": "turn-1",
        "itemId": "edit-1",
        "changes": [
          {
            "path": "main.mbt",
            "kind": { "type": "update", "move_path": Json::null() },
            "diff": "-old\n+new",
          },
        ],
      },
      0,
    ),
    editing,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  guard patched.transcript_items()[0].kind
    is @transcript.Tool(
      name="edit",
      arguments=Some(arguments),
      has_result=false,
      ..
    ) else {
    fail("expected a pending live edit")
  }
  assert_true(arguments.contains("-old\\n+new"))
  let (_, mcp_started) = @codex.update(
    dispatch,
    @codex.Msg::notification(
      "item/started",
      {
        "threadId": "thread-1",
        "turnId": "turn-1",
        "startedAtMs": 1100,
        "item": {
          "id": "mcp-1",
          "type": "mcpToolCall",
          "server": "docs",
          "tool": "lookup",
          "arguments": { "query": "adapter" },
          "status": "inProgress",
          "result": Json::null(),
          "error": Json::null(),
        },
      },
      0,
    ),
    patched,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let (_, progressed) = @codex.update(
    dispatch,
    @codex.Msg::notification(
      "item/mcpToolCall/progress",
      {
        "threadId": "thread-1",
        "turnId": "turn-1",
        "itemId": "mcp-1",
        "message": "Searching documentation",
      },
      0,
    ),
    mcp_started,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  assert_eq(
    progressed.transcript_items()[1].content,
    "Searching documentation\n",
  )
}

///|
test "Codex keeps skill and local media inputs as shared mention chips" {
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [
        {
          "id": "turn-1",
          "status": "completed",
          "items": [
            {
              "id": "user-1",
              "type": "userMessage",
              "content": [
                { "type": "text", "text": "Inspect these" },
                { "type": "skill", "name": "moonbit", "path": "SKILL.md" },
                { "type": "localImage", "path": "/work/screenshot.png" },
              ],
            },
          ],
        },
      ],
    },
  })
  let items = state.transcript_items()
  guard @mention_context.parse(items[0].content) is Some(message) else {
    fail("expected a shared mention envelope")
  }
  assert_eq(message.task, "Inspect these")
  assert_true(
    message.mentions
    is [
      @mention_context.Skill(name="moonbit"),
      @mention_context.File(path="/work/screenshot.png"),
    ],
  )
}
