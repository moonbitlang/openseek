///|
/// Generic evaluation of one recorded OpenSeek session.
///
/// This deliberately knows nothing about prompt-task manifests, workspaces, or
/// task-specific validation. Callers that own a benchmark can attach their own
/// metadata and probes around this result.
pub struct EvalResult {
  session_id : String
  success : Bool
  reason : String
  steps : Int
  tool_results : Int
  tool_errors : Int
  runtime_notices : Int
  finished : Bool
  finish_message : String
  terminal_status : String
  terminal_message : String
}

///|
priv struct SessionMetrics {
  finish_message : String
  steps : Int
  tool_results : Int
  tool_errors : Int
  runtime_notices : Int
  /// The last terminal event the session reached, already scored, or `None`
  /// when it never reached one.
  terminal : TerminalOutcome?
}

///|
/// How one terminal event scores: the label reported to tooling, its message,
/// and whether it counts as task success.
priv struct TerminalOutcome {
  status : String
  message : String
  success : Bool
}

///|
fn terminal_outcome(terminal : @agent_session.TurnTerminal) -> TerminalOutcome {
  match terminal {
    Finished(message) => { status: "finished", message, success: true, }
    ContextYield(message) =>
      { status: "context_yield", message, success: false, }
    Aborted(message) => { status: "aborted", message, success: false, }
    Interrupted(message) => { status: "interrupted", message, success: false, }
    Failed(message) => { status: "failed", message, success: false, }
  }
}

///|
/// Analyze one already-loaded session.
pub fn analyze_session(session : @agent_session.Session) -> EvalResult {
  let metrics = summarize_session(session)
  let reason = match metrics.terminal {
    Some({ success: true, .. }) => "ok"
    Some({ status, message, .. }) => "agent terminal \{status}: \{message}"
    None => "finish marker missing"
  }
  let finished = metrics.terminal is Some({ success: true, .. })
  {
    session_id: session.id().value(),
    success: finished,
    reason,
    steps: metrics.steps,
    tool_results: metrics.tool_results,
    tool_errors: metrics.tool_errors,
    runtime_notices: metrics.runtime_notices,
    finished,
    finish_message: metrics.finish_message,
    terminal_status: metrics.terminal.map_or("", outcome => outcome.status),
    terminal_message: metrics.terminal.map_or("", outcome => outcome.message),
  }
}

///|
/// Build the transcript text used by analyzers that count prompt-sensitive
/// behavior. User prompts and summaries are intentionally excluded so a task
/// statement cannot inflate model-behavior counters.
pub fn transcript_text(session : @agent_session.Session) -> String {
  let out = StringBuilder()
  let mut previous_assistant_answer : String? = None
  for event in session.events() {
    let item = event.item()
    let repeated_terminal = item is Terminal(Finished(answer)) &&
      previous_assistant_answer is Some(previous) &&
      previous == answer
    let checkpoint_replay = item is Assistant(message) && message.is_replay()
    if !repeated_terminal && !checkpoint_replay {
      append_item_text(out, item)
    }
    previous_assistant_answer = match item {
      Assistant(message) => Some(message.content())
      _ => None
    }
  }
  out.to_string()
}

///|
fn summarize_session(session : @agent_session.Session) -> SessionMetrics {
  let steps = session.events().iter().count_if(event => event.is_agent_step())
  // The answer of the last *successful* finish, kept even when a later
  // terminal event supersedes it.
  let mut finish_message = ""
  let mut terminal : TerminalOutcome? = None
  let mut tool_results = 0
  let mut tool_errors = 0
  let mut runtime_notices = 0
  for event in session.events() {
    match event.item() {
      Assistant(_) | Summary(_) | User(_) => ()
      Tool(result) => {
        tool_results += 1
        if result.is_error() {
          tool_errors += 1
        }
      }
      Goal(_) | Runtime(_) => runtime_notices += 1
      Terminal(event_terminal) => {
        let outcome = terminal_outcome(event_terminal)
        if outcome.success {
          finish_message = outcome.message
        }
        terminal = Some(outcome)
      }
    }
  }
  {
    finish_message,
    steps,
    tool_results,
    tool_errors,
    runtime_notices,
    terminal,
  }
}

///|
fn append_item_text(
  out : StringBuilder,
  item : @agent_session.SessionItem,
) -> Unit {
  match item {
    User(_) | Summary(_) => ()
    Assistant(message) => {
      if message.reasoning_content() is Some(reasoning) {
        write_line(out, reasoning)
      }
      write_line(out, message.content())
      for call in message.tool_calls() {
        write_line(out, call.name)
        write_line(out, call.arguments)
      }
    }
    Tool(result) => {
      write_line(out, result.tool_name())
      write_line(out, result.content())
    }
    Goal(change) => write_line(out, change.model_content())
    Runtime(notice) => write_line(out, notice.content())
    Terminal(terminal) =>
      match terminal {
        Finished(message)
        | ContextYield(message)
        | Aborted(message)
        | Interrupted(message)
        | Failed(message) => write_line(out, message)
      }
  }
}

///|
fn write_line(out : StringBuilder, value : String) -> Unit {
  out.write_string(value)
  out.write_char('\n')
}
