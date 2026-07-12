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
    // Goal markers are transport, not display — the resume path seeds a
    // single "goal: ..." notice from current_goal(), matching the live
    // path where markers are filtered and goal_updated is what renders.
    Runtime(notice) if @agent_session.goal_marker(notice.content()) is Some(_) =>
      None
    Runtime(notice) => Some(runtime_notice_item(notice.content()))
    Summary(summary) => Some(summary_item(summary))
    Terminal(terminal) => terminal_item(terminal)
  }
}

///|
fn session_transcript_items(
  session : @agent_session.Session,
) -> Array[@ui.TranscriptItem] {
  session
  .events()
  .iter()
  .filter_map(event => session_item(event.item()))
  .collect()
}

///|
async fn append_session_history(state : State, ui : @ui.Ui) -> Unit {
  let config = state.config
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
  for item in session_transcript_items(session) {
    ui.append_item(item)
  }
  // Seed the mirrored goal from the durable log so `/goal` shows a resumed
  // session's standing goal before any engine is spawned or event arrives.
  if session.current_goal() is Some(goal) {
    state.goal = Some(goal.text())
    ui.append_item(Notice(ToolCall(@doc.Text::plain("goal: \{goal.text()}"))))
  }
}

///|
test "session items project to transcript items" {
  let shell_context =
    #|<user_shell_command>
    #|<command>
    #|ls
    #|</command>
    #|<result>
    #|exit=0
    #|_build
    #|</result>
    #|</user_shell_command>
  guard session_item(User(UserMessage("hello"))) is Some(Input(Prompt(text))) else {
    fail("expected input")
  }
  assert_eq(text, "hello")
  guard session_item(Terminal(Finished("done"))) is Some(Response(answer)) else {
    fail("expected response")
  }
  assert_eq(answer, "done")
  guard session_item(
      Tool(ToolResult(tool_call_id="call_1", tool_name="read", content="ok")),
    )
    is Some(ToolCall(_)) else {
    fail("expected tool")
  }
  guard session_item(User(UserMessage(shell_context))) is Some(ToolCall(_)) else {
    fail("expected command user message to render as a tool")
  }
  guard session_item(
      Runtime(RuntimeNotice("\{@agent_session.PlanReminderPrefix}\nrun tests")),
    )
    is Some(Notice(_)) else {
    fail("expected runtime notice")
  }
}
