///|
fn summary_model_content(summary : SessionSummary) -> String {
  (
    $|[conversation summary]
    $|source_events=\{summary.from_sequence()}..\{summary.to_sequence()}
    $|\{summary.content()}
  )
}

///|
/// A status line for a non-finished turn: the bare `label` when `reason` is
/// blank, otherwise the label followed by the reason on its own line.
fn agent_status_message(label : String, reason : String) -> String? {
  if reason.is_blank() {
    Some(label)
  } else {
    Some("\{label}\n\{reason}")
  }
}

///|
fn terminal_model_message(terminal : TurnTerminal) -> String? {
  match terminal {
    Finished(answer) =>
      // A context-yield terminal is synthetic run status, not something the
      // assistant said: replaying it would make the model read its own
      // ceiling notice as a prior answer — and, worse, as the "reply" to a
      // steer preserved past the checkpoint, so the steer looks handled.
      // The resumed turn starts from the checkpoint summary and any
      // preserved user input alone. (Raw-log consumers still see the
      // terminal; only the model-facing projection skips it.)
      if answer.is_blank() || answer.has_prefix(ContextYieldAnswerPrefix) {
        None
      } else {
        Some(answer)
      }
    Aborted(reason) => agent_status_message("[agent aborted]", reason)
    Interrupted(reason) => agent_status_message("[agent interrupted]", reason)
    Failed(reason) => agent_status_message("[agent failed]", reason)
  }
}

///|
fn append_item_message(
  item : SessionItem,
  messages : Array[@deepseek.ChatMessage],
) -> Unit {
  match item {
    User(message) => messages.push(ChatMessage(User, content=message.content()))
    Runtime(notice) =>
      messages.push(ChatMessage(User, content=notice.content()))
    Summary(summary) =>
      messages.push(ChatMessage(User, content=summary_model_content(summary)))
    Assistant(message) =>
      messages.push(
        ChatMessage(
          Assistant,
          content=message.content(),
          tool_calls=message.tool_calls(),
          reasoning_content?=message.reasoning_content(),
        ),
      )
    Tool(result) =>
      messages.push(
        ChatMessage(Tool(result.tool_call_id()), content=result.content()),
      )
    Terminal(terminal) =>
      if terminal_model_message(terminal) is Some(content) {
        // Current final answers are stored as a full Assistant payload before
        // their terminal. The terminal seals the turn but must not replay the
        // same answer a second time.
        if !(messages.last() is Some(last) &&
          last.role is Assistant &&
          last.content == content) {
          messages.push(ChatMessage(Assistant, content~))
        }
      }
  }
}

///|
fn flush_pending_tool_calls(
  pending : Array[@deepseek.ToolCall],
  messages : Array[@deepseek.ChatMessage],
) -> Unit {
  for call in pending {
    messages.push(
      ChatMessage(
        Tool(call.id),
        content="error: previous agent process exited before recording a result for tool \{call.name}",
      ),
    )
  }
  pending.clear()
}

///|
fn summary_covers_event(summary_event : SessionEvent, sequence : Int) -> Bool {
  guard summary_event.item() is Summary(summary) else { return false }
  summary_event.sequence() > sequence &&
  summary.from_sequence() <= sequence &&
  sequence <= summary.to_sequence()
}

///|
fn is_covered_by_later_summary(
  event : SessionEvent,
  events : @vector.Vector[SessionEvent],
) -> Bool {
  events
  .iter()
  .any(candidate => summary_covers_event(candidate, event.sequence()))
}

///|
/// Project the durable session log into DeepSeek chat messages.
///
/// The first returned message is always the session's system prompt. Remaining
/// messages are derived from events in log order after applying repair and
/// compaction rules:
///
/// - events covered by a later `Summary` are skipped;
/// - `User`, `Runtime`, and `Summary` become user-role messages; a summary is
///   emitted where its covered range starts, not where it was appended;
/// - `Assistant` preserves visible content, tool calls, and reasoning content;
/// - `Tool` is emitted only when it answers a pending assistant tool call;
/// - pending tool calls are closed with synthetic tool-error messages before a
///   non-tool event or at the end of projection;
/// - `Terminal(Finished(text))` becomes a final assistant message when `text`
///   is non-blank, is not a context-yield status (see
///   `ContextYieldAnswerPrefix`), and the preceding Assistant did not already
///   preserve the same final answer;
/// - `Terminal(Aborted|Interrupted|Failed)` becomes an assistant status
///   message, preserving any non-blank reason.
///
/// This method is a read-only projection. It never mutates the session and never
/// removes durable events.
pub fn Session::chat_messages(self : Session) -> Array[@deepseek.ChatMessage] {
  let messages : Array[@deepseek.ChatMessage] = [
    ChatMessage(System, content=self.system_prompt()),
  ]
  let pending_tool_calls : Array[@deepseek.ToolCall] = []
  let events = self.events()
  for event in events {
    // A surviving summary stands in for the events it covers, so its text is
    // emitted where the covered range starts — not where the summary event
    // was appended, which can be after uncovered later events (a stage-one
    // auto-compaction lands after the active turn's task and must not read
    // as newer input than that task).
    for candidate in events {
      if candidate.item() is Summary(summary) &&
        summary.from_sequence() == event.sequence() &&
        !is_covered_by_later_summary(candidate, events) {
        flush_pending_tool_calls(pending_tool_calls, messages)
        append_item_message(candidate.item(), messages)
      }
    }
    if is_covered_by_later_summary(event, events) {
      continue
    }
    match event.item() {
      // Already emitted at the start of its covered range.
      Summary(_) => ()
      Assistant(message) => {
        flush_pending_tool_calls(pending_tool_calls, messages)
        append_item_message(Assistant(message), messages)
        pending_tool_calls.append(message.tool_calls())
      }
      Tool(result) =>
        if pending_tool_calls.search_by(call => call.id == result.tool_call_id())
          is Some(index) {
          ignore(pending_tool_calls.remove(index))
          append_item_message(Tool(result), messages)
        }
      item => {
        flush_pending_tool_calls(pending_tool_calls, messages)
        append_item_message(item, messages)
      }
    }
  }
  flush_pending_tool_calls(pending_tool_calls, messages)
  messages
}
