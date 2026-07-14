// Mapping from the engine's decoded JSONL values to typed `AgentEvent`s. Reading
// lines, skipping blanks, and parsing each as JSON is `bobzhang/jsonl`'s job
// (`@jsonl.each` in `cmd/tui`); this module only maps an already-parsed value,
// keyed by its `"event"` discriminator.

///|
/// Map one decoded JSONL value from the engine into an `AgentEvent`.
///
/// Returns `None` for a non-object value or an unrecognized `"event"` string so
/// a noisy or newer engine never crashes the UI; the caller simply drops it.
pub fn decode_event(object : Json) -> AgentEvent? {
  match @jsonx.string(object, "event") {
    "agent_step" => Some(AgentStep)
    "assistant_delta" => Some(AssistantDelta(@jsonx.string(object, "content")))
    "reasoning_delta" => Some(ReasoningDelta(@jsonx.string(object, "content")))
    "reasoning_message" =>
      Some(ReasoningMessage(@jsonx.string(object, "content")))
    "steer_applied" => {
      let content = @jsonx.string(object, "content")
      match @jsonx.string(object, "kind") {
        "command" => Some(SteerApplied(Command(content)))
        "notice" => Some(SteerApplied(Notice(content)))
        _ => Some(SteerApplied(Prompt(content)))
      }
    }
    "steer_dropped" => Some(SteerDropped(@jsonx.string(object, "content")))
    "background_notice" =>
      Some(BackgroundNotice(@jsonx.string(object, "content")))
    "assistant_message" =>
      Some(AssistantMessage(@jsonx.string(object, "content")))
    "session_error" => Some(SessionError(@jsonx.string(object, "error")))
    "usage" => {
      let usage : @deepseek.Usage = @json.from_json(
        @jsonx.field(object, "usage").unwrap_or_default(),
      ) catch {
        // Drop malformed usage events rather than crashing the UI.
        _ => return None
      }
      Some(
        Usage({ total_tokens: usage.prompt_tokens + usage.completion_tokens }),
      )
    }
    "tool_result" =>
      Some(
        ToolResult({
          name: @jsonx.string(object, "tool_name"),
          content: @jsonx.string(object, "content"),
          is_error: @jsonx.bool(object, "is_error"),
        }),
      )
    "tool_call_decode_error" =>
      Some(
        ToolResult({
          name: @jsonx.string(object, "tool_name"),
          content: "error: \{@jsonx.string(object, "error")}",
          is_error: true,
        }),
      )
    "agent_finished" => Some(AgentFinished(@jsonx.string(object, "answer")))
    "agent_aborted" => Some(AgentAborted(@jsonx.string(object, "reason")))
    "max_steps_exhausted" => Some(MaxStepsExhausted)
    "agent_setup_failed" =>
      Some(AgentError("agent setup failed: \{@jsonx.string(object, "error")}"))
    // A serve-mode turn that died with a non-cancellation error. Terminal for
    // the run even though the engine process lives on.
    "turn_failed" =>
      Some(AgentError("turn failed: \{@jsonx.string(object, "error")}"))
    // The engine rejected a command and keeps serving (no terminal event of its
    // own). Whether this should end a run depends on which command was rejected
    // — only the controller knows the active operation — so this stays a
    // non-terminal event the loop resolves (see `CommandRejected` handling).
    "command_error" => Some(CommandRejected(@jsonx.string(object, "error")))
    // Compaction lifecycle on a serve engine. `compaction_started` carries no
    // controller-visible state — the run is already shown busy — so it is left
    // to drop as an unknown event. The two outcomes are terminal for the
    // compaction run: success carries the summary (the new context) for a
    // preview, failure folds into the general agent-error category like a
    // failed turn.
    "compaction_finished" =>
      Some(CompactionFinished(@jsonx.string(object, "summary")))
    "compaction_failed" =>
      Some(AgentError("compaction failed: \{@jsonx.string(object, "error")}"))
    // A durably recorded goal update. Decoded null-aware — a cleared goal is
    // {"goal": null}, which must not collapse into an empty-string set.
    "goal_updated" =>
      match object {
        { "goal": String(goal), .. } => Some(GoalUpdated(Some(goal)))
        _ => Some(GoalUpdated(None))
      }
    "goal_continue" => Some(GoalContinue(@jsonx.int(object, "remaining")))
    "goal_budget_exhausted" => Some(GoalBudgetExhausted)
    // A turn that ended at the context ceiling: run-terminal, not success.
    "context_yield" => Some(ContextYield(@jsonx.string(object, "answer")))
    // MCP lifecycle diagnostics, surfaced as notices so a typo'd config or a
    // dead server is visible in the UI instead of silently yielding no tools.
    "mcp_tools_registered" => {
      let tools = @jsonx.int(object, "tools")
      let servers = @jsonx.int(object, "servers")
      // `servers` counts the configuration's entries, not successful
      // contributors — say so, since some may have failed or been skipped.
      Some(
        BackgroundNotice(
          "MCP: registered \{tools} tool(s) from \{servers} configured server(s)",
        ),
      )
    }
    "mcp_connect_failed" =>
      Some(
        BackgroundNotice(
          "MCP: server `\{mcp_safe(object, "server")}` failed to connect",
        ),
      )
    "mcp_list_tools_failed" | "mcp_list_tools_timeout" =>
      Some(
        BackgroundNotice(
          "MCP: server `\{mcp_safe(object, "server")}` did not list its tools",
        ),
      )
    "mcp_config_unreadable" | "mcp_config_invalid" =>
      Some(
        BackgroundNotice(
          "MCP config error (\{mcp_safe(object, "path")}): \{mcp_safe(object, "error")}",
        ),
      )
    _ => None
  }
}

///|
/// A field of an MCP diagnostic, made terminal-safe for a notice: whitespace
/// runs collapse to one space, C0/C1 controls and DEL are dropped (the
/// transcript layout strips C0 but not C1, and these strings carry
/// configuration metadata), and anything past 120 characters is elided.
fn mcp_safe(object : Json, key : String) -> String {
  let text = @jsonx.string(object, key)
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
