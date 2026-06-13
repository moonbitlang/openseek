///|
fn summary_model_content(summary : SessionSummary) -> String {
  (
    $|[conversation summary]
    $|source_events=\{summary.from_sequence()}..\{summary.to_sequence()}
    $|\{summary.content()}
  )
}

///|
fn terminal_model_message(terminal : TurnTerminal) -> String? {
  match terminal {
    Finished(answer) if !answer.trim().is_empty() => Some(answer)
    Finished(_) => None
    Aborted(reason) if !reason.trim().is_empty() =>
      Some("[agent aborted]\n\{reason}")
    Aborted(_) => Some("[agent aborted]")
    Interrupted(reason) if !reason.trim().is_empty() =>
      Some("[agent interrupted]\n\{reason}")
    Interrupted(_) => Some("[agent interrupted]")
    Failed(message) if !message.trim().is_empty() =>
      Some("[agent failed]\n\{message}")
    Failed(_) => Some("[agent failed]")
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
        messages.push(ChatMessage(Assistant, content~))
      }
  }
}

///|
fn remove_pending_tool_call(
  pending : Array[@deepseek.ToolCall],
  tool_call_id : String,
) -> Bool {
  for index in 0..<pending.length() {
    if pending[index].id() == tool_call_id {
      ignore(pending.remove(index))
      return true
    }
  }
  false
}

///|
fn flush_pending_tool_calls(
  pending : Array[@deepseek.ToolCall],
  messages : Array[@deepseek.ChatMessage],
) -> Unit {
  for call in pending {
    messages.push(
      ChatMessage(
        Tool(call.id()),
        content="error: previous agent process exited before recording a result for tool \{call.name()}",
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
  for candidate in events {
    if summary_covers_event(candidate, event.sequence()) {
      return true
    }
  }
  false
}

///|
/// Project this durable session into the typed DeepSeek chat message array used
/// by the model client. Summary events compact the model-facing context: any
/// earlier event in a later summary's source range is skipped, while the raw
/// event stays in the durable session log.
pub fn Session::chat_messages(self : Session) -> Array[@deepseek.ChatMessage] {
  let messages : Array[@deepseek.ChatMessage] = [
    ChatMessage(System, content=self.system_prompt()),
  ]
  let pending_tool_calls : Array[@deepseek.ToolCall] = []
  let events = self.events()
  for event in events {
    if is_covered_by_later_summary(event, events) {
      continue
    }
    match event.item() {
      Assistant(message) => {
        flush_pending_tool_calls(pending_tool_calls, messages)
        append_item_message(Assistant(message), messages)
        for call in message.tool_calls() {
          pending_tool_calls.push(call)
        }
      }
      Tool(result) =>
        if remove_pending_tool_call(pending_tool_calls, result.tool_call_id()) {
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
