// Mapping from the engine's typed protocol events to the TUI's `AgentEvent`.
// Reading lines, skipping blanks, and parsing each as JSON is `bobzhang/jsonl`'s
// job (`@jsonl.each` in `cmd/tui`); `@protocol.parse` turns a parsed value into
// an `Event`; this module maps that into what the UI actually renders.

///|
/// Map one JSONL value from the engine into an `AgentEvent`.
///
/// `AgentEvent` is a view model, not a mirror of the wire: several engine events
/// fold into one UI concept (`agent_setup_failed`, `turn_failed` and
/// `compaction_failed` all read as `AgentError`), and most carry less than the
/// wire does (`usage` keeps only the derived total).
///
/// The match over `@protocol.Event` is exhaustive on purpose. Every event the
/// engine can report is either mapped or listed in the ignore arm below, so
/// adding one to the protocol breaks this build until someone decides which it
/// is — the reason this indirection exists at all. `None` here means "the engine
/// said something the UI has nothing to show for", never "we forgot".
pub fn decode_event(object : Json) -> AgentEvent? {
  guard @protocol.parse(object) is Some(event) else {
    // Not an event this engine emits: a blank-ish line, or one from a newer
    // engine. Dropping it keeps a mixed-version pair usable.
    return None
  }
  match event {
    AgentStep(_) => Some(AgentStep)
    AssistantDelta(content~) => Some(AssistantDelta(content))
    ReasoningDelta(content~) => Some(ReasoningDelta(content))
    ReasoningMessage(content~) => Some(ReasoningMessage(content))
    SteerApplied(kind~, content~) =>
      match kind {
        "command" => Some(SteerApplied(Command(content)))
        "notice" => Some(SteerApplied(Notice(content)))
        _ => Some(SteerApplied(Prompt(content)))
      }
    SteerDropped(content~) => Some(SteerDropped(content))
    BackgroundNotice(content~) => Some(BackgroundNotice(content))
    AssistantMessage(content~) => Some(AssistantMessage(content))
    SessionError(error~) => Some(SessionError(error))
    // Only the derived total reaches the status line.
    Usage(usage~) =>
      Some(
        Usage({ total_tokens: usage.prompt_tokens + usage.completion_tokens }),
      )
    ToolResult(tool_name~, content~, is_error~, ..) =>
      Some(ToolResult({ name: tool_name, content, is_error }))
    // A call the engine could not decode never ran: show it as a failed result
    // so the transcript still accounts for the model's request.
    ToolCallDecodeError(tool_name~, error~, ..) =>
      Some(
        ToolResult({
          name: tool_name,
          content: "error: \{error}",
          is_error: true,
        }),
      )
    AgentFinished(answer~) => Some(AgentFinished(answer))
    AgentAborted(reason~) => Some(AgentAborted(reason))
    MaxStepsExhausted => Some(MaxStepsExhausted)
    AgentSetupFailed(error~) => Some(AgentError("agent setup failed: \{error}"))
    // A serve-mode turn that died with a non-cancellation error. Terminal for
    // the run even though the engine process lives on.
    TurnFailed(error~) => Some(AgentError("turn failed: \{error}"))
    // The engine rejected a command and keeps serving (no terminal event of its
    // own). Whether this should end a run depends on which command was rejected
    // — only the controller knows the active operation — so this stays a
    // non-terminal event the loop resolves (see `CommandRejected` handling).
    CommandError(error~) => Some(CommandRejected(error))
    // Compaction outcomes are terminal for the compaction run: success carries
    // the summary (the new context) for a preview, failure folds into the
    // general agent-error category like a failed turn.
    CompactionFinished(summary~, ..) => Some(CompactionFinished(summary))
    CompactionFailed(error~) => Some(AgentError("compaction failed: \{error}"))
    GoalUpdated(goal~) => Some(GoalUpdated(goal))
    GoalContinue(remaining~) => Some(GoalContinue(remaining))
    GoalBudgetExhausted(_) => Some(GoalBudgetExhausted)
    // A turn that ended at the context ceiling: run-terminal, not success.
    ContextYield(answer~, ..) => Some(ContextYield(answer))
    // A sub-run's lifecycle brackets. The id pairs starts with finishes on
    // the wire; the UI shows them as ordered transcript notices, so only
    // the display fields survive decoding.
    SubrunStarted(kind~, label~, ..) => Some(SubrunStarted(kind~, label~))
    SubrunFinished(status~, steps~, ..) => Some(SubrunFinished(status~, steps~))
    // MCP lifecycle diagnostics, surfaced as notices so a typo'd config or a
    // dead server is visible in the UI instead of silently yielding no tools.
    // `servers` counts the configuration's entries, not successful contributors
    // — say so, since some may have failed or been skipped.
    McpToolsRegistered(servers~, tools~, ..) =>
      Some(
        BackgroundNotice(
          "MCP: registered \{tools} tool(s) from \{servers} configured server(s)",
        ),
      )
    McpConnectFailed(server~, ..) =>
      Some(
        BackgroundNotice("MCP: server `\{mcp_safe(server)}` failed to connect"),
      )
    McpListToolsFailed(server~, ..) | McpListToolsTimeout(server~) =>
      Some(
        BackgroundNotice(
          "MCP: server `\{mcp_safe(server)}` did not list its tools",
        ),
      )
    McpConfigUnreadable(path~, error~) | McpConfigInvalid(path~, error~) =>
      Some(
        BackgroundNotice(
          "MCP config error (\{mcp_safe(path)}): \{mcp_safe(error)}",
        ),
      )
    // Deliberately not shown. Each of these is a decision, and the compiler now
    // holds us to making one: a new protocol event lands here as a build error
    // rather than as a line the UI drops without anyone noticing.
    //
    // `compaction_started` and the auto-compaction lifecycle carry no
    // controller-visible state — the run already reads busy. The goal and plan
    // reminders, checks, and block/unblock markers are instructions to the
    // model, not news for the user; the standing goal reaches the UI as
    // `goal_updated`. `session_started`, `workspace_created` and `fleet_started`
    // describe a headless run's setup, which the TUI performs itself. The
    // remaining MCP events are per-tool registry bookkeeping, already summarized
    // by `mcp_tools_registered`.
    CompactionStarted(..)
    | AutoCompactionStarted(..)
    | AutoCompactionFinished(..)
    | AutoCompactionFailed(..)
    | GoalBlocked(..)
    | GoalUnblocked
    | GoalCheck(..)
    | GoalReminder(..)
    | PlanReminder(..)
    | SessionStarted(..)
    | WorkspaceCreated(..)
    | FleetStarted(..)
    | McpConfigIgnored(..)
    | McpToolDuplicate(..)
    | McpToolRenamed(..)
    | McpToolsCapped(..)
    | McpServerSkippedOverCap(..)
    | McpNoTools(..) => None
  }
}

///|
/// A field of an MCP diagnostic, made terminal-safe for a notice: whitespace
/// runs collapse to one space, C0/C1 controls and DEL are dropped (the
/// transcript layout strips C0 but not C1, and these strings carry
/// configuration metadata), and anything past 120 characters is elided.
fn mcp_safe(text : String) -> String {
  let out = StringBuilder()
  for ch in text.trim(); last_was_space = false, count = 0 {
    if count >= 120 {
      out.write_char('…')
      break
    }
    if ch is (' ' | '\t' | '\n' | '\r') {
      if !last_was_space {
        out.write_char(' ')
        continue true, count + 1
      }
      continue true, count
    } else if ch.to_int() < 0x20 ||
      ch.to_int() == 0x7F ||
      (ch.to_int() >= 0x80 && ch.to_int() <= 0x9F) {
      continue last_was_space, count
    } else {
      out.write_char(ch)
      continue false, count + 1
    }
  }
  out.to_string()
}
