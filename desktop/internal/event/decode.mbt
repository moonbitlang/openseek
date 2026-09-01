// Mapping from the engine's typed protocol events to the host's `AgentEvent`.
// `@protocol.parse` owns the wire format; this module decides which events the
// host acts on. The webview receives the raw lines separately and decodes them
// for itself (see `frontend/transcript`), so what is ignored here is only what
// the *host* has no use for, not what the app never shows.

///|
/// Map one JSONL value from the engine into an `AgentEvent`.
///
/// The match over `@protocol.Event` is exhaustive on purpose: a new engine event
/// breaks this build until someone decides whether the host acts on it. `None`
/// means "nothing for the host to do", never "we forgot" — which is what the
/// previous `_ => None` could not distinguish.
///
/// `parse` returning `None` keeps the app tolerant of a newer engine: an event
/// this build does not know is dropped rather than fatal.
pub fn decode_event(object : Json) -> AgentEvent? {
  guard @protocol.parse(object) is Some(event) else { return None }
  match event {
    AgentStep(_) => Some(AgentStep)
    AssistantMessage(content~) => Some(AssistantMessage(content))
    // The host tracks that steering landed; the kind matters only to the UI,
    // which decodes the same line itself.
    SteerApplied(content~, ..) => Some(SteerApplied(content))
    SteerDropped(content~) => Some(SteerDropped(content))
    // This is synthesized by the desktop host after decoding the engine
    // stream, so a raw child event has no host-side routing work to perform.
    SteerUnconfirmed(..) => None
    // Only the derived total is shown.
    Usage(usage~) =>
      Some(
        Usage({ total_tokens: usage.prompt_tokens + usage.completion_tokens, }),
      )
    ToolResult(tool_name~, content~, is_error~, ..) =>
      Some(ToolResult({ name: tool_name, content, is_error, }))
    // A call the engine could not decode never ran: report it as a failed
    // result so the run still accounts for the model's request.
    ToolCallDecodeError(tool_name~, error~, ..) =>
      Some(
        ToolResult({
          name: tool_name,
          content: "error: \{error}",
          is_error: true,
        }),
      )
    AgentFinished(answer~) => Some(AgentFinished(answer))
    // The turn stopped at the model's context ceiling after checkpointing.
    // Terminal for the run, but not task success.
    ContextYield(answer~, ..) => Some(ContextYield(answer))
    AgentAborted(reason~) => Some(AgentAborted(reason))
    MaxStepsExhausted => Some(MaxStepsExhausted)
    AgentSetupFailed(error~) => Some(AgentError("agent setup failed: \{error}"))
    // A serve-mode turn that died with a non-cancellation error. Terminal for
    // the run even though the engine process lives on.
    TurnFailed(error~) => Some(AgentError("turn failed: \{error}"))
    // Compaction lifecycle: `started` is informational; finished/failed mean the
    // engine is done touching the durable record, which the host gates archiving
    // on. Not terminal for any run — compaction happens between turns.
    CompactionStarted(..) => Some(CompactionStarted)
    CompactionFinished(..) => Some(CompactionFinished)
    CompactionFailed(_) => Some(CompactionFailed)
    // Not the host's business. Streaming text, reasoning, notices and every
    // goal/plan signal are the webview's to render off the raw stream; the
    // sub-run lifecycle brackets are likewise the webview's (the outer run
    // already reads busy to the host throughout a sub-run); the
    // auto-compaction lifecycle is internal to a turn and never gates
    // archiving the way an explicit compaction does; `session_started`,
    // `workspace_created` and `fleet_started` describe a headless run's setup,
    // which the host performs itself; `command_error` reports a rejected
    // control command, which the host learns from the command's own reply; the
    // MCP registry events are diagnostics the UI surfaces.
    // A permission question and its settlement are the webview's: it renders
    // the prompt off the raw stream and answers with `agent.approval`. The
    // host's only stake is the run phase, which does not change — a blocked
    // turn is still a running one, and reporting it as anything else would
    // make the run look finishable while a tool sits waiting inside it.
    ApprovalRequested(..)
    | ApprovalResolved(..)
    | SubrunStarted(..)
    | SubrunFinished(..)
    | AssistantDelta(..)
    | ReasoningDelta(..)
    | ReasoningMessage(..)
    | BackgroundNotice(..)
    | SessionError(..)
    | GoalUpdated(..)
    | GoalBlocked(..)
    | GoalUnblocked
    | GoalCheck(..)
    | GoalReminder(..)
    | GoalContinue(..)
    | GoalBudgetExhausted(..)
    | PlanReminder(..)
    | AutoCompactionStarted(..)
    | AutoCompactionFinished(..)
    | AutoCompactionFailed(..)
    | SessionStarted(..)
    | WorkspaceCreated(..)
    | CommandError(..)
    | FleetStarted(..)
    | McpConfigIgnored(..)
    | McpConfigUnreadable(..)
    | McpConfigInvalid(..)
    | McpToolsRegistered(..)
    | McpToolDuplicate(..)
    | McpToolRenamed(..)
    | McpToolsCapped(..)
    | McpServerSkippedOverCap(..)
    | McpConnectFailed(..)
    | McpListToolsFailed(..)
    | McpListToolsTimeout(..)
    | McpNoTools(..) => None
  }
}
