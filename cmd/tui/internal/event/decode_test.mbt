///|
test "decode maps each engine event kind" {
  assert_true(
    @event.decode_event({ "event": "agent_step", "step": 3 }) is Some(AgentStep),
  )
  assert_true(
    @event.decode_event({ "event": "max_steps_exhausted" })
    is Some(MaxStepsExhausted),
  )
  assert_true(
    @event.decode_event({ "event": "assistant_delta", "content": "tok" })
    is Some(AssistantDelta("tok")),
  )
  assert_true(
    @event.decode_event({ "event": "reasoning_delta", "content": "hmm" })
    is Some(ReasoningDelta("hmm")),
  )
  assert_true(
    @event.decode_event({
      "event": "reasoning_message",
      "content": "full thought",
    })
    is Some(ReasoningMessage("full thought")),
  )
  assert_true(
    @event.decode_event({ "event": "agent_finished", "answer": "done" })
    is Some(AgentFinished("done")),
  )
  assert_true(
    @event.decode_event({ "event": "session_error", "error": "stale session" })
    is Some(SessionError("stale session")),
  )
  match
    @event.decode_event({
      "event": "tool_result",
      "tool_call_id": "c1",
      "tool_name": "bash",
      "is_error": true,
      "content": "boom",
    }) {
    Some(ToolResult(result)) => {
      assert_eq(result.name, "bash")
      assert_eq(result.content, "boom")
      assert_true(result.is_error)
    }
    _ => fail("expected ToolResult")
  }
}

///|
test "steer wire events decode to their applied and dropped forms" {
  assert_true(
    @event.decode_event({ "event": "steer_applied", "content": "go left" })
    is Some(SteerApplied(Prompt("go left"))),
  )
  assert_true(
    @event.decode_event({
      "event": "steer_applied",
      "kind": "prompt",
      "content": "go right",
    })
    is Some(SteerApplied(Prompt("go right"))),
  )
  assert_true(
    @event.decode_event({
      "event": "steer_applied",
      "kind": "command",
      "content": "<user_shell_command>",
    })
    is Some(SteerApplied(Command("<user_shell_command>"))),
  )
  assert_true(
    @event.decode_event({
      "event": "steer_applied",
      "kind": "notice",
      "content": "background job bg-1 finished",
    })
    is Some(SteerApplied(Notice("background job bg-1 finished"))),
  )
  assert_true(
    @event.decode_event({ "event": "steer_dropped", "content": "too late" })
    is Some(SteerDropped("too late")),
  )
}

///|
test "an idle background-job completion decodes to an untagged notice" {
  assert_true(
    @event.decode_event({
      "event": "background_notice",
      "content": "background job bg-2 finished (exit=0)",
    })
    is Some(BackgroundNotice("background job bg-2 finished (exit=0)")),
  )
}

///|
test "a failed serve turn decodes to a terminal agent error" {
  assert_true(
    @event.decode_event({
      "event": "turn_failed",
      "error": "DeepSeek API error",
    })
    is Some(AgentError("turn failed: DeepSeek API error")),
  )
}

///|
test "a rejected command decodes to a non-terminal CommandRejected" {
  // An engine that does not understand a command keeps serving and emits no
  // terminal event. The rejection carries the raw error; the loop decides
  // whether it ends a run (only `/compact` needs that), so it is not decoded as
  // a terminal `AgentError`.
  assert_true(
    @event.decode_event({
      "event": "command_error",
      "error": "unknown command: compact",
    })
    is Some(CommandRejected("unknown command: compact")),
  )
}

///|
test "compaction wire events decode to their terminal forms" {
  // Success carries the summary so the controller can preview the new context.
  assert_true(
    @event.decode_event({
      "event": "compaction_finished",
      "from_sequence": 1,
      "to_sequence": 42,
      "summary": "handoff",
    })
    is Some(CompactionFinished("handoff")),
  )
  // Failure folds into the general agent-error category like a failed turn.
  assert_true(
    @event.decode_event({ "event": "compaction_failed", "error": "cancelled" })
    is Some(AgentError("compaction failed: cancelled")),
  )
  // The start marker carries no controller state, so it drops like any unknown.
  assert_true(@event.decode_event({ "event": "compaction_started" }) is None)
}

///|
test "decode returns None for a non-object value or unknown event" {
  // `@jsonl` handles blank and malformed lines before decoding; the mapping only
  // has to tolerate a non-object value and a newer engine's unknown event kind.
  assert_true(@event.decode_event(Json::string("not an object")) is None)
  assert_true(@event.decode_event({ "event": "future_event_kind" }) is None)
}

///|
test "usage total is derived from prompt and completion tokens" {
  match
    @event.decode_event({
      "event": "usage",
      "usage": {
        "prompt_tokens": 100,
        "completion_tokens": 23,
        "total_tokens": 123,
        "prompt_cache_hit_tokens": 0,
        "prompt_cache_miss_tokens": 100,
      },
    }) {
    Some(Usage(usage)) => assert_eq(usage.total_tokens, 123)
    _ => fail("expected Usage")
  }
}

///|
test "goal updates decode null-aware" {
  assert_true(
    @event.decode_event({ "event": "goal_updated", "goal": "ship it" })
    is Some(GoalUpdated(Some("ship it"))),
  )
  // A cleared goal is {"goal": null}: it must decode to None, not collapse
  // into an empty-string set.
  assert_true(
    @event.decode_event({ "event": "goal_updated", "goal": Json::null() })
    is Some(GoalUpdated(None)),
  )
  assert_true(
    @event.decode_event({ "event": "goal_updated" }) is Some(GoalUpdated(None)),
  )
}

///|
test "goal auto-continue lifecycle decodes" {
  assert_true(
    @event.decode_event({ "event": "goal_continue", "remaining": 19 })
    is Some(GoalContinue(19)),
  )
  assert_true(
    @event.decode_event({ "event": "goal_budget_exhausted", "turns": 20 })
    is Some(GoalBudgetExhausted),
  )
}

///|
test "a context yield decodes as its own run terminal" {
  assert_true(
    @event.decode_event({
      "event": "context_yield",
      "to_sequence": 41,
      "answer": "[context ceiling] checkpointed",
    })
    is Some(ContextYield("[context ceiling] checkpointed")),
  )
}

///|
test "decode_event surfaces MCP diagnostics as notices" {
  guard @event.decode_event({
      "event": "mcp_tools_registered",
      "servers": 2,
      "tools": 5,
    })
    is Some(BackgroundNotice(registered)) else {
    fail("expected a notice")
  }
  assert_eq(registered, "MCP: registered 5 tool(s) from 2 configured server(s)")
  guard @event.decode_event({ "event": "mcp_connect_failed", "server": "fs" })
    is Some(BackgroundNotice(failed)) else {
    fail("expected a notice")
  }
  assert_eq(failed, "MCP: server `fs` failed to connect")
  guard @event.decode_event({
      "event": "mcp_config_invalid",
      "path": "/x/mcp.json",
      "error": "boom",
    })
    is Some(BackgroundNotice(config)) else {
    fail("expected a notice")
  }
  assert_eq(config, "MCP config error (/x/mcp.json): boom")
  guard @event.decode_event({
      "event": "mcp_list_tools_timeout",
      "server": "slow",
    })
    is Some(BackgroundNotice(timeout)) else {
    fail("expected a notice")
  }
  assert_eq(timeout, "MCP: server `slow` did not list its tools")
}
