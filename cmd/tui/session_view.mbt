///|
fn session_tool_item(result : @agent_session.ToolResult) -> @ui.TranscriptItem {
  let event : @event.ToolResultEvent = {
    name: result.tool_name(),
    content: result.content(),
    is_error: result.is_error(),
  }
  tool_item(event)
}

///|
fn summary_item(summary : @agent_session.SessionSummary) -> @ui.TranscriptItem {
  Notice(
    ToolCall(
      @doc.Text::plain(
        "conversation summary · events \{summary.from_sequence()}..\{summary.to_sequence()}",
      ),
      details=detail_texts(
        compact_lines(summary.content(), ToolOutputLineLimit),
      ),
    ),
  )
}

///|
fn terminal_item(terminal : @agent_session.TurnTerminal) -> @ui.TranscriptItem? {
  match terminal {
    Finished(answer) if !answer.trim().is_empty() => Some(Response(answer))
    Finished(_) => None
    Aborted(reason) => Some(Error("aborted: \{reason}"))
    Interrupted(reason) => Some(Error("interrupted: \{reason}"))
    Failed(message) => Some(Error(message))
  }
}

///|
fn session_item(item : @agent_session.SessionItem) -> @ui.TranscriptItem? {
  match item {
    User(message) =>
      match command_text_item(message.content()) {
        Some(item) => Some(item)
        None => Some(Input(Prompt(message.content())))
      }
    Assistant(message) =>
      if message.content().trim().is_empty() {
        None
      } else {
        Some(Response(message.content()))
      }
    Tool(result) => Some(session_tool_item(result))
    Runtime(notice) =>
      Some(runtime_item(parse_runtime_update(notice.content())))
    Summary(summary) => Some(summary_item(summary))
    Terminal(terminal) => terminal_item(terminal)
  }
}

///|
async fn append_session_history(config : AppConfig, ui : @ui.Ui) -> Unit {
  let session_id = config.session_id
  let store = @store.SessionStore(config.session_root)
  let exists = store.exists(session_id) catch {
    error => {
      ui.append_item(Error("failed to inspect session: \{error}"))
      return
    }
  }
  guard exists else { return }
  let session = store.load(session_id) catch {
    error => {
      ui.append_item(Error("failed to load session: \{error}"))
      return
    }
  }
  for event in session.events() {
    if session_item(event.item()) is Some(item) {
      ui.append_item(item)
    }
  }
}
