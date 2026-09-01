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
    is [@mention_context.File(path="desktop/frontend/codex/model.mbt")],
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
test "Codex omits unavailable command metadata from shared arguments" {
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
              "commandActions": [{ "type": "read", "path": "src/main.mbt" }],
              "status": "completed",
              "aggregatedOutput": "ok",
            },
          ],
        },
      ],
    },
  })
  let items = state.transcript_items()
  guard items[0].kind is @transcript.Assistant(calls=[call], ..) &&
    call.arguments is Some(arguments) else {
    fail("expected read metadata in shared tool arguments")
  }
  assert_eq(arguments, "{\"path\":\"src/main.mbt\"}")
}

///|
test "Codex sleep brief preserves an absent duration" {
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [
        {
          "id": "turn-1",
          "status": "completed",
          "items": [{ "id": "sleep-1", "type": "sleep" }],
        },
      ],
    },
  })
  let items = state.transcript_items()
  assert_eq(items.length(), 1)
  guard items[0].kind is @transcript.Assistant(calls=[call], ..) else {
    fail("expected a sleep tool call")
  }
  assert_eq(call.name, "sleep")
  assert_eq(call.arguments, None)
  assert_true(call.outcome is Done(brief=Some("slept"), ..))
}

///|
test "Codex omits unavailable metadata from other tool arguments" {
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [
        {
          "id": "turn-1",
          "status": "completed",
          "items": [
            { "id": "collab-1", "type": "collabAgentToolCall", "tool": "wait" },
            {
              "id": "subagent-1",
              "type": "subAgentActivity",
              "agentPath": "root/reviewer",
            },
            {
              "id": "search-1",
              "type": "webSearch",
              "action": { "type": "search" },
            },
            { "id": "view-1", "type": "imageView" },
            {
              "id": "image-1",
              "type": "imageGeneration",
              "transparentBackground": false,
            },
            { "id": "review-1", "type": "enteredReviewMode" },
          ],
        },
      ],
    },
  })
  let items = state.transcript_items()
  assert_eq(items.length(), 6)
  guard items[0].kind is @transcript.Assistant(calls=[collab_call], ..) &&
    collab_call.arguments is Some(collab) else {
    fail("expected collaboration arguments")
  }
  assert_eq(collab, "{\"tool\":\"wait\"}")
  guard items[1].kind is @transcript.Assistant(calls=[subagent_call], ..) &&
    subagent_call.arguments is Some(subagent) else {
    fail("expected subagent arguments")
  }
  assert_eq(subagent, "{\"agentPath\":\"root/reviewer\"}")
  guard items[2].kind is @transcript.Assistant(calls=[search_call], ..) &&
    search_call.arguments is Some(search) else {
    fail("expected web-search arguments")
  }
  assert_true(search.contains("\"action\""))
  assert_false(search.contains("\"query\""))
  guard items[3].kind is @transcript.Assistant(calls=[view_call], ..) &&
    view_call.arguments is Some(image_view) else {
    fail("expected image-view arguments")
  }
  assert_eq(image_view, "{}")
  guard items[4].kind is @transcript.Assistant(calls=[generation_call], ..) &&
    generation_call.arguments is Some(generation) else {
    fail("expected image-generation arguments")
  }
  assert_eq(generation, "{\"transparentBackground\":false}")
  guard items[5].kind is @transcript.Assistant(calls=[review_call], ..) &&
    review_call.arguments is Some(review) else {
    fail("expected review arguments")
  }
  assert_eq(review, "{}")
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
            {
              "id": "agent-1",
              "type": "agentMessage",
              "phase": Json::null(),
              "text": "Done.",
            },
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
    items[1].kind
    is @transcript.Assistant(
      reasoning=None,
      prose=Some("Done."),
      calls=[],
      finished=true,
      ..
    ),
  )
  assert_eq(items[1].text(), Some("Done."))
}

///|
test "Codex preserves item ids, step groups, and explicit final answers" {
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [
        {
          "id": "turn-1",
          "status": "completed",
          "completedAt": 123,
          "items": [
            {
              "id": "user-1",
              "type": "userMessage",
              "clientId": "page-1-submission-1",
              "content": [{ "type": "text", "text": "inspect" }],
            },
            {
              "id": "reasoning-1",
              "type": "reasoning",
              "summary": [{ "text": "Checking" }],
            },
            {
              "id": "command-1",
              "type": "commandExecution",
              "command": "moon check",
              "status": "completed",
              "aggregatedOutput": "ok",
            },
            {
              "id": "agent-1",
              "type": "agentMessage",
              "phase": "final_answer",
              "text": "Done.",
            },
          ],
        },
      ],
    },
  })
  let rows = state.transcript_rows()
  assert_eq(rows.length(), 4)
  assert_eq(rows[0].identity, "turn\u{0}turn-1\u{0}item\u{0}user-1")
  assert_eq(rows[0].step_identity, None)
  assert_eq(rows[1].step_identity, rows[2].step_identity)
  assert_true(rows[1].step_identity is Some(_))
  assert_true(rows[3].step_identity is Some(_))
  assert_true(rows[3].step_identity != rows[2].step_identity)
  assert_true(
    rows[3].item.kind
    is @transcript.Assistant(prose=Some("Done."), finished=true, ..),
  )
  assert_eq(rows[3].item.ts, Some(123000.0))
}

///|
test "Codex keeps async final-shaped delivery as ordinary assistant prose" {
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [
        {
          "id": "turn-1",
          "status": "completed",
          "items": [
            {
              "id": "agent-1",
              "type": "agentMessage",
              "phase": "final_answer",
              "delivery": "async",
              "text": "Background result",
            },
          ],
        },
      ],
    },
  })
  let items = state.transcript_items()
  assert_eq(items.length(), 1)
  assert_true(
    items[0].kind
    is @transcript.Assistant(
      prose=Some("Background result"),
      finished=false,
      ..
    ),
  )
}

///|
#warnings("-alert_unstable")
test "Codex keeps indexed reasoning summary separate from raw content" {
  let dispatch : @cmd.Emit[@codex.Msg] = @cmd.Emit(_ => @cmd.none)
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [
        {
          "id": "turn-1",
          "status": "inProgress",
          "items": [{ "id": "reasoning-1", "type": "reasoning" }],
        },
      ],
    },
  })
  let (_, first_part) = @codex.update(
    dispatch,
    @codex.Msg::notification(
      "item/reasoning/summaryPartAdded",
      {
        "threadId": "thread-1",
        "turnId": "turn-1",
        "itemId": "reasoning-1",
        "summaryIndex": 0,
      },
      0,
    ),
    state,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let (_, first_text) = @codex.update(
    dispatch,
    @codex.Msg::notification(
      "item/reasoning/summaryTextDelta",
      {
        "threadId": "thread-1",
        "turnId": "turn-1",
        "itemId": "reasoning-1",
        "summaryIndex": 0,
        "delta": "First",
      },
      0,
    ),
    first_part,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let (_, second_text) = @codex.update(
    dispatch,
    @codex.Msg::notification(
      "item/reasoning/summaryTextDelta",
      {
        "threadId": "thread-1",
        "turnId": "turn-1",
        "itemId": "reasoning-1",
        "summaryIndex": 1,
        "delta": "Second",
      },
      0,
    ),
    first_text,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let (_, with_raw) = @codex.update(
    dispatch,
    @codex.Msg::notification(
      "item/reasoning/textDelta",
      {
        "threadId": "thread-1",
        "turnId": "turn-1",
        "itemId": "reasoning-1",
        "contentIndex": 0,
        "delta": "raw details",
      },
      0,
    ),
    second_text,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let items = with_raw.transcript_items()
  assert_eq(items.length(), 1)
  assert_true(
    items[0].kind
    is @transcript.Assistant(reasoning=Some("First\n\nSecond"), ..),
  )
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
  guard items[0].kind is @transcript.Assistant(calls=[read_call], ..) &&
    read_call.name == "read" &&
    read_call.arguments is Some(read_arguments) else {
    fail("expected a classified command read")
  }
  assert_true(read_arguments.contains("src/main.mbt"))
  assert_true(
    read_call.outcome is Done(content="fn main { }", is_error=false, ..),
  )
  guard items[1].kind is @transcript.Assistant(calls=[edit_call], ..) &&
    edit_call.name == "edit" &&
    edit_call.arguments is Some(edit_arguments) else {
    fail("expected one file change to become edit")
  }
  assert_true(edit_arguments.contains("@@ -1 +1 @@"))
  assert_true(edit_arguments.contains("src/main.mbt"))
  guard items[2].kind is @transcript.Assistant(calls=[multi_edit_call], ..) &&
    multi_edit_call.name == "multi_edit" &&
    multi_edit_call.arguments is Some(multi_arguments) else {
    fail("expected several file changes to become multi_edit")
  }
  assert_true(multi_arguments.contains("\"edits\""))
  assert_true(multi_arguments.contains("a.mbt"))
  assert_true(multi_arguments.contains("b.mbt"))
  guard items[3].kind is @transcript.Assistant(calls=[mcp_call], ..) &&
    mcp_call.name == "mcp__docs__lookup" &&
    mcp_call.arguments is Some(mcp_args) else {
    fail("expected an MCP registry-style tool name")
  }
  assert_true(mcp_args.contains("TranscriptItem"))
  assert_true(mcp_call.outcome is Done(content="MCP result", ..))
  guard items[4].kind is @transcript.Assistant(calls=[dynamic_call], ..) &&
    dynamic_call.name == "run_moonbit" &&
    dynamic_call.arguments is Some(dynamic_args) else {
    fail("expected a dynamic tool to retain its semantic name")
  }
  assert_true(dynamic_args.contains("fn main"))
  assert_true(
    dynamic_call.outcome is Done(content="program passed", is_error=false, ..),
  )
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
  assert_true(
    items[0].kind
    is @transcript.Assistant(prose=Some("Proposed approach"), calls=[], ..),
  )
  guard items[1].kind is @transcript.Assistant(calls=[hook_call], ..) else {
    fail("expected a hook prompt tool call")
  }
  assert_eq(hook_call.name, "hook_prompt")
  assert_true(hook_call.outcome is Done(content="Check generated files", ..))
  guard items[2].kind is @transcript.Assistant(calls=[spawn_call], ..) else {
    fail("expected a spawnAgent tool call")
  }
  assert_eq(spawn_call.name, "spawnAgent")
  guard spawn_call.outcome is Done(content=spawn_content, is_error=false, ..) else {
    fail("expected completed spawnAgent output")
  }
  assert_true(spawn_content.contains("thread-2"))
  guard items[3].kind is @transcript.Assistant(calls=[subagent_call], ..) else {
    fail("expected a subagent tool call")
  }
  assert_eq(subagent_call.name, "subagent")
  guard items[4].kind is @transcript.Assistant(calls=[search_call], ..) else {
    fail("expected a web search tool call")
  }
  assert_eq(search_call.name, "web_search")
  guard search_call.outcome is Done(content=search_content, ..) else {
    fail("expected completed web search output")
  }
  assert_true(search_content.contains("Result"))
  guard items[5].kind is @transcript.Assistant(calls=[view_call], ..) else {
    fail("expected an image view tool call")
  }
  assert_eq(view_call.name, "image_view")
  guard items[6].kind is @transcript.Assistant(calls=[sleep_call], ..) else {
    fail("expected a sleep tool call")
  }
  assert_eq(sleep_call.name, "sleep")
  guard items[7].kind is @transcript.Assistant(calls=[image_call], ..) else {
    fail("expected an image generation tool call")
  }
  assert_eq(image_call.name, "image_generation")
  assert_true(
    image_call.outcome
    is Done(content="https://example.invalid/image.png", is_error=false, ..),
  )
  guard items[8].kind is @transcript.Assistant(calls=[review_call], ..) else {
    fail("expected a review tool call")
  }
  assert_eq(review_call.name, "review")
  assert_true(
    review_call.outcome is Done(content="Review the current changes", ..),
  )
  assert_true(items[9].kind is @transcript.Summary(_))
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
  guard items[0].kind is @transcript.Assistant(calls=[call], ..) &&
    call.name == "plan" &&
    call.arguments is Some(arguments) &&
    call.outcome
    is Done(
      content="Starting with the adapter",
      is_error=false,
      brief=Some(brief)
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
  guard pending.transcript_items()[0].kind
    is @transcript.Assistant(calls=[pending_call], ..) else {
    fail("expected a pending web search")
  }
  assert_eq(pending_call.name, "web_search")
  assert_true(pending_call.outcome is Pending(_))
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
  guard completed.transcript_items()[0].kind
    is @transcript.Assistant(calls=[completed_call], ..) else {
    fail("expected a completed web search")
  }
  assert_eq(completed_call.name, "web_search")
  assert_true(completed_call.outcome is Done(_))
  assert_eq(completed.transcript_items()[0].ts, Some(2000.0))
}

///|
#warnings("-alert_unstable")
test "Codex summary turns retain item lifecycle timestamps" {
  let dispatch : @cmd.Emit[@codex.Msg] = @cmd.Emit(_ => @cmd.none)
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [{ "id": "turn-1", "status": "inProgress", "items": [] }],
    },
  })
  let (_, observed) = @codex.update(
    dispatch,
    @codex.Msg::notification(
      "item/completed",
      {
        "threadId": "thread-1",
        "turnId": "turn-1",
        "completedAtMs": 1234,
        "item": {
          "id": "agent-1",
          "type": "agentMessage",
          "phase": "commentary",
          "text": "Working",
        },
      },
      0,
    ),
    state,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let (_, settled) = @codex.update(
    dispatch,
    @codex.Msg::notification(
      "turn/completed",
      {
        "threadId": "thread-1",
        "turn": {
          "id": "turn-1",
          "status": "completed",
          "completedAt": 2,
          "itemsView": "summary",
          "items": [
            {
              "id": "agent-1",
              "type": "agentMessage",
              "phase": "commentary",
              "text": "Working",
            },
          ],
        },
      },
      0,
    ),
    observed,
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let items = settled.transcript_items()
  assert_eq(items.length(), 1)
  assert_true(
    items[0].kind
    is @transcript.Assistant(prose=Some("Working"), finished=false, ..),
  )
  assert_eq(items[0].ts, Some(1234.0))
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
    is @transcript.Assistant(calls=[edit_call], ..) &&
    edit_call.name == "edit" &&
    edit_call.arguments is Some(arguments) &&
    edit_call.outcome is Pending(_) else {
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
  guard progressed.transcript_items()[1].kind
    is @transcript.Assistant(calls=[mcp_call], ..) else {
    fail("expected MCP progress in the shared tool call")
  }
  assert_true(
    mcp_call.outcome is Pending(output=Some("Searching documentation\n")),
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
  guard items[0].kind is @transcript.User(content) &&
    @mention_context.parse(content) is Some(message) else {
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
