///|
/// An optional string field as the wire carries it: the value itself, or
/// `null`.
///
/// Not the field's own `ToJson` — MoonBit encodes `Some(v)` as the one-element
/// array `[v]`, which every decoder's string lookup rejects, silently turning a
/// present field into an absent one.
fn or_null(value : String?) -> Json {
  match value {
    Some(value) => Json(value)
    None => Json::null()
  }
}

///|
/// The event as one line's worth of JSON: its `"event"` name plus its payload,
/// flat.
///
/// This is the wire shape, and the only place it is written. `emit` writes it
/// as the whole line; the desktop host forwards it for a compaction its engine
/// died before reporting. Two writers of the same event
/// must not spell it two ways — they did once, and nothing noticed until a
/// decoder was asked to be exhaustive.
///
/// Flat, not nested under a payload key, because the writer emits each event's
/// own fields as one line; `parse` reads them from the top level.
pub fn Event::to_json(self : Event) -> Json {
  match self {
    AgentSetupFailed(error~) =>
      { "event": "agent_setup_failed", "error": error }
    AgentStep(step~) => { "event": "agent_step", "step": step }
    AgentAborted(reason~) => { "event": "agent_aborted", "reason": reason }
    AgentFinished(answer~) => { "event": "agent_finished", "answer": answer }
    MaxStepsExhausted => { "event": "max_steps_exhausted" }
    TurnFailed(error~) => { "event": "turn_failed", "error": error }
    AssistantDelta(content~) =>
      { "event": "assistant_delta", "content": content }
    ReasoningDelta(content~) =>
      { "event": "reasoning_delta", "content": content }
    AssistantMessage(content~) =>
      { "event": "assistant_message", "content": content }
    ReasoningMessage(content~) =>
      { "event": "reasoning_message", "content": content }
    Usage(usage~) => { "event": "usage", "usage": ToJson::to_json(usage) }
    ToolResult(tool_call_id~, tool_name~, is_error~, content~, brief~) =>
      {
        "event": "tool_result",
        "tool_call_id": tool_call_id,
        "tool_name": tool_name,
        "is_error": is_error,
        "content": content,
        "brief": or_null(brief),
      }
    ToolCallDecodeError(tool_call_id~, tool_name~, error~) =>
      {
        "event": "tool_call_decode_error",
        "tool_call_id": tool_call_id,
        "tool_name": tool_name,
        "error": error,
      }
    ApprovalRequested(id~, tool_name~, detail~, body~) =>
      {
        "event": "approval_requested",
        "id": id,
        "tool_name": tool_name,
        "detail": detail,
        "body": or_null(body),
      }
    ApprovalResolved(id~, outcome~) =>
      { "event": "approval_resolved", "id": id, "outcome": outcome }
    SteerApplied(kind~, content~) =>
      { "event": "steer_applied", "kind": kind, "content": content }
    SteerDropped(content~) => { "event": "steer_dropped", "content": content }
    BackgroundNotice(content~) =>
      { "event": "background_notice", "content": content }
    GoalUpdated(goal~) => { "event": "goal_updated", "goal": or_null(goal) }
    GoalBlocked(reason~) => { "event": "goal_blocked", "reason": reason }
    GoalUnblocked => { "event": "goal_unblocked" }
    GoalCheck(content~) => { "event": "goal_check", "content": content }
    GoalReminder(content~) => { "event": "goal_reminder", "content": content }
    GoalContinue(remaining~) =>
      { "event": "goal_continue", "remaining": remaining }
    GoalBudgetExhausted(turns~) =>
      { "event": "goal_budget_exhausted", "turns": turns }
    PlanReminder(content~) => { "event": "plan_reminder", "content": content }
    CompactionStarted(from_sequence~, to_sequence~) =>
      {
        "event": "compaction_started",
        "from_sequence": from_sequence,
        "to_sequence": to_sequence,
      }
    CompactionFinished(from_sequence~, to_sequence~, summary~) =>
      {
        "event": "compaction_finished",
        "from_sequence": from_sequence,
        "to_sequence": to_sequence,
        "summary": summary,
      }
    CompactionFailed(error~) => { "event": "compaction_failed", "error": error }
    SubrunStarted(id~, kind~, label~) =>
      { "event": "subrun_started", "id": id, "kind": kind, "label": label }
    SubrunFinished(id~, status~, steps~, prompt_tokens~, completion_tokens~) =>
      {
        "event": "subrun_finished",
        "id": id,
        "status": status,
        "steps": steps,
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
      }
    AutoCompactionStarted(from_sequence~, to_sequence~) =>
      {
        "event": "auto_compaction_started",
        "from_sequence": from_sequence,
        "to_sequence": to_sequence,
      }
    AutoCompactionFinished(from_sequence~, to_sequence~, summary~) =>
      {
        "event": "auto_compaction_finished",
        "from_sequence": from_sequence,
        "to_sequence": to_sequence,
        "summary": summary,
      }
    AutoCompactionFailed(error~) =>
      { "event": "auto_compaction_failed", "error": error }
    ContextYield(to_sequence~, answer~) =>
      { "event": "context_yield", "to_sequence": to_sequence, "answer": answer }
    SessionStarted(session~, session_root~, workspace_root~) =>
      {
        "event": "session_started",
        "session": session,
        "session_root": session_root,
        "workspace_root": or_null(workspace_root),
      }
    SessionError(error~) => { "event": "session_error", "error": error }
    WorkspaceCreated(dir~) => { "event": "workspace_created", "dir": dir }
    CommandError(error~) => { "event": "command_error", "error": error }
    FleetStarted(runs~, task~) =>
      { "event": "fleet_started", "runs": runs, "task": task }
    McpConfigIgnored(reason~) =>
      { "event": "mcp_config_ignored", "reason": reason }
    McpConfigUnreadable(path~, error~) =>
      { "event": "mcp_config_unreadable", "path": path, "error": error }
    McpConfigInvalid(path~, error~) =>
      { "event": "mcp_config_invalid", "path": path, "error": error }
    McpToolsRegistered(servers~, tools~, names~) =>
      {
        "event": "mcp_tools_registered",
        "servers": servers,
        "tools": tools,
        "names": names.to_json(),
      }
    McpToolDuplicate(server~, tool~) =>
      { "event": "mcp_tool_duplicate", "server": server, "tool": tool }
    McpToolRenamed(from~, to~) =>
      { "event": "mcp_tool_renamed", "from": from, "to": to }
    McpToolsCapped(server~, kept~) =>
      { "event": "mcp_tools_capped", "server": server, "kept": kept }
    McpServerSkippedOverCap(server~) =>
      { "event": "mcp_server_skipped_over_cap", "server": server }
    McpConnectFailed(server~, error~) =>
      {
        "event": "mcp_connect_failed",
        "server": server,
        "error": or_null(error),
      }
    McpListToolsFailed(server~, error~) =>
      { "event": "mcp_list_tools_failed", "server": server, "error": error }
    McpListToolsTimeout(server~) =>
      { "event": "mcp_list_tools_timeout", "server": server }
    McpNoTools(server~) => { "event": "mcp_no_tools", "server": server }
  }
}
