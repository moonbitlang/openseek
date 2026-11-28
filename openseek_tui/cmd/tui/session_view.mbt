///|
fn session_tool_item(result : @agent_session.ToolResult) -> @ui.TranscriptItem {
  let event : @event.ToolResultEvent = {
    name: result.tool_name(),
    content: result.content().text(),
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
    Finished(answer) if !answer.is_blank() => Some(Response(answer))
    Finished(_) => None
    // Rendered as its notice, as when yields were saved as `finished`.
    ContextYield(notice) => Some(Response(notice))
    Aborted(reason) => Some(Error("aborted: \{reason}"))
    Interrupted(reason) => Some(Error("interrupted: \{reason}"))
    MaxStepsExhausted => Some(Error(@agent_session.MaxStepsExhaustedMessage))
    Failed(message) => Some(Error(message))
  }
}

///|
fn session_items(
  item : @agent_session.SessionItem,
) -> Array[@ui.TranscriptItem] {
  let items : Array[@ui.TranscriptItem] = []
  match item {
    User(message) =>
      match command_text_item(message.content().text()) {
        Some(item) => items.push(item)
        None => items.push(Input(Prompt(message.content().text())))
      }
    Assistant(message) => {
      if message.reasoning_content() is Some(reasoning) && !reasoning.is_blank() {
        items.push(reasoning_item(reasoning))
      }
      if !message.content().is_blank() {
        items.push(Response(message.content()))
      }
    }
    Tool(result) => items.push(session_tool_item(result))
    // Goal markers are transport, not display — the resume path seeds a
    // single "goal: ..." notice from current_goal(), matching the live
    // path where markers are filtered and goal_updated is what renders.
    Runtime(notice) if @agent_session.goal_marker(notice.content()) is Some(_) =>
      ()
    // The baseline pairing record is transport too: filtered on the live
    // path, so resume must not resurrect it as a notice card.
    Runtime(notice) if @agent_session.parse_goal_baseline(notice.content())
      is Some(_) => ()
    Runtime(notice) => items.push(runtime_notice_item(notice.content()))
    Summary(summary) => items.push(summary_item(summary))
    Terminal(terminal) =>
      if terminal_item(terminal) is Some(item) {
        items.push(item)
      }
  }
  items
}

///|
fn session_transcript_items(
  session : @agent_session.Session,
) -> Array[@ui.TranscriptItem] {
  let items : Array[@ui.TranscriptItem] = []
  let mut previous_assistant_answer : String? = None
  for event in session.events() {
    let item = event.item()
    let repeated_terminal = item is Terminal(Finished(answer)) &&
      previous_assistant_answer is Some(previous) &&
      previous == answer
    if !repeated_terminal {
      items.append(session_items(item))
    }
    previous_assistant_answer = match item {
      Assistant(message) => Some(message.content())
      _ => None
    }
  }
  items
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
  state.session_created = true
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
  guard session_items(User(UserMessage(Content([Text("hello")]))))
    is [Input(Prompt(text))] else {
    fail("expected input")
  }
  assert_eq(text, "hello")
  guard session_items(Terminal(Finished("done"))) is [Response(answer)] else {
    fail("expected response")
  }
  assert_eq(answer, "done")
  // A yield renders its notice and step exhaustion its error, as they did
  // when older logs saved them as `finished` and `failed`.
  guard session_items(Terminal(ContextYield("[context ceiling] go on")))
    is [Response(notice)] else {
    fail("expected yield notice")
  }
  assert_eq(notice, "[context ceiling] go on")
  guard session_items(Terminal(MaxStepsExhausted)) is [Error(message)] else {
    fail("expected max-steps error")
  }
  assert_eq(message, "max steps exhausted")
  guard session_items(
      Tool(
        ToolResult(tool_call_id="call_1", tool_name="read", content=[Text("ok")]),
      ),
    )
    is [ToolCall(_)] else {
    fail("expected tool")
  }
  guard session_items(User(UserMessage(Content([Text(shell_context)]))))
    is [ToolCall(_)] else {
    fail("expected command user message to render as a tool")
  }
  guard session_items(
      Runtime(RuntimeNotice("\{@agent_session.PlanReminderPrefix}\nrun tests")),
    )
    is [Notice(_)] else {
    fail("expected runtime notice")
  }
}

///|
test "session history renders an assistant final answer once" {
  let session = @agent_session.Session(SessionId("reasoning"), system_prompt="")
    .append(User(UserMessage(Content([Text("question")]))))
    .append(Assistant(AssistantMessage("answer")))
    .append(Terminal(Finished("answer")))
  let items = session_transcript_items(session)
  inspect(items.length(), content="2")
  guard items[1] is Response(answer) else { fail("expected one answer") }
  assert_eq(answer, "answer")
}

///|
test "session history still renders a reasoning-bearing final answer once" {
  let session = @agent_session.Session(SessionId("reasoning"), system_prompt="")
    .append(User(UserMessage(Content([Text("question")]))))
    .append(
      Assistant(
        AssistantMessage("answer", reasoning_content="consider the question"),
      ),
    )
    .append(Terminal(Finished("answer")))
  let items = session_transcript_items(session)
  inspect(items.length(), content="3")
  guard items[1] is Thought(_) else { fail("expected durable reasoning") }
  guard items[2] is Response(answer) else { fail("expected one answer") }
  assert_eq(answer, "answer")
}
