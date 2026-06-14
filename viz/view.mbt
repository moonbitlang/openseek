///|
/// Which projection of a session to render: the full append-only `RawLog` (every
/// event in file order, grouped into turns) or `ModelView` — exactly the
/// messages `Session::chat_messages` feeds the model, with summaries substituted
/// for the events they cover and dangling tool calls healed.
pub(all) enum ViewMode {
  RawLog
  ModelView
} derive(Eq, Debug)

///|
/// Render a session under the chosen view mode.
pub fn render_session(
  session : @agent_session.Session,
  mode : ViewMode,
) -> @html.Html {
  match mode {
    RawLog => render_raw(session)
    ModelView => render_model(session)
  }
}

///|
/// Banners for anything the parser flagged: decode failures on individual lines
/// and a truncated final record. Returns `@html.nothing` for a clean log so the
/// caller can stack it unconditionally.
pub fn render_notices(parsed : ParsedLog) -> @html.Html {
  let notices : Array[@html.Html] = []
  if parsed.partial_tail {
    notices.push(
      @html.div(class="notice notice-warn", [
        @html.text(
          "⚠ trailing partial line ignored (process likely exited mid-append)",
        ),
      ]),
    )
  }
  for error in parsed.errors {
    notices.push(
      @html.div(class="notice notice-error", [
        @html.div(class="notice-head", [
          @html.text(
            "⚠ line \{error.line_number} could not be decoded: \{error.message}",
          ),
        ]),
        @html.pre(class="notice-body", error.content),
      ]),
    )
  }
  if notices.is_empty() {
    @html.nothing
  } else {
    @html.div(class="notices", notices)
  }
}

// ---- raw log view ----------------------------------------------------------

///|
fn render_raw(session : @agent_session.Session) -> @html.Html {
  let turns = group_turns(session.events())
  let blocks : Array[@html.Html] = []
  for index, turn in turns {
    blocks.push(turn_block(index + 1, turn))
  }
  if blocks.is_empty() {
    return empty_state("This session has no events yet.")
  }
  @html.div(class="log raw-log", blocks)
}

///|
/// Split the flat event log into turns. Every turn closes with exactly one
/// `Terminal` event, so a turn runs up to and including the next `Terminal` —
/// keying off terminals rather than `User` events keeps mid-turn steering
/// (extra `User` events the engine appends before the terminal) inside the same
/// turn. A trailing group with no terminal is a turn cut off mid-flight.
fn group_turns(
  events : @vector.Vector[@agent_session.SessionEvent],
) -> Array[Array[@agent_session.SessionEvent]] {
  let turns : Array[Array[@agent_session.SessionEvent]] = []
  let mut current : Array[@agent_session.SessionEvent] = []
  for event in events {
    current.push(event)
    if event.item() is Terminal(_) {
      turns.push(current)
      current = []
    }
  }
  if !current.is_empty() {
    turns.push(current)
  }
  turns
}

///|
fn turn_block(
  number : Int,
  turn : Array[@agent_session.SessionEvent],
) -> @html.Html {
  // Offsets are relative to the turn's first stamped event: for reading a
  // log, "how far into the turn" answers latency questions directly, where
  // absolute wall clock would force mental subtraction (and a timezone).
  let base = turn_base_ms(turn)
  let cards : Array[@html.Html] = [
    for event in turn => event_card(event, time=offset_label(base, event))
  ]
  let label = match turn_duration_label(turn) {
    Some(duration) => "Turn \{number} · \{turn_preview(turn)} · \{duration}"
    None => "Turn \{number} · \{turn_preview(turn)}"
  }
  @html.details(open=true, class="turn", [
    @html.summary(class="turn-summary", label),
    @html.div(class="turn-body", cards),
  ])
}

///|
/// The turn's first wall-clock stamp (unix ms), or 0 when no event carries
/// one (events appended without a clock keep the 0 sentinel).
fn turn_base_ms(turn : Array[@agent_session.SessionEvent]) -> Int64 {
  for event in turn {
    if event.unix_ms() > 0 {
      return event.unix_ms()
    }
  }
  0
}

///|
fn offset_label(base : Int64, event : @agent_session.SessionEvent) -> String {
  if base == 0 || event.unix_ms() == 0 {
    return ""
  }
  "+" + format_span_seconds(event.unix_ms() - base)
}

///|
fn turn_duration_label(turn : Array[@agent_session.SessionEvent]) -> String? {
  let base = turn_base_ms(turn)
  guard base > 0 else { return None }
  let mut last = base
  for event in turn {
    if event.unix_ms() > 0 {
      last = event.unix_ms()
    }
  }
  if last > base {
    Some(format_span_seconds(last - base))
  } else {
    None
  }
}

///|
/// A millisecond span as a compact human duration: `3.4s`, `2m 05.1s`.
fn format_span_seconds(span_ms : Int64) -> String {
  let tenths = span_ms / 100
  if tenths < 600 {
    "\{tenths / 10}.\{tenths % 10}s"
  } else {
    let minutes = tenths / 600
    let rest = tenths % 600
    let seconds = rest / 10
    let pad = if seconds < 10 { "0" } else { "" }
    "\{minutes}m \{pad}\{seconds}.\{rest % 10}s"
  }
}

///|
fn turn_preview(turn : Array[@agent_session.SessionEvent]) -> String {
  for event in turn {
    if event.item() is User(message) {
      return truncate(one_line(message.content()), 80)
    }
  }
  "\{turn.length()} events"
}

///|
fn event_card(
  event : @agent_session.SessionEvent,
  time~ : String,
) -> @html.Html {
  let seq = event.sequence()
  match event.item() {
    User(message) =>
      card("user", "User", seq, time~, [text_block(message.content())])
    Assistant(message) => assistant_card(seq, time, message)
    Tool(result) => tool_card(seq, time, result)
    Runtime(notice) =>
      card("runtime", "Runtime notice", seq, time~, [
        text_block(notice.content()),
      ])
    Summary(summary) => summary_card(seq, time, summary)
    Terminal(terminal) => terminal_card(seq, time, terminal)
  }
}

///|
fn assistant_card(
  seq : Int,
  time : String,
  message : @agent_session.AssistantMessage,
) -> @html.Html {
  let body : Array[@html.Html] = []
  if message.reasoning_content() is Some(reasoning) &&
    !reasoning.trim().is_empty() {
    body.push(
      @html.details(class="reasoning", [
        @html.summary("reasoning"),
        text_block(reasoning),
      ]),
    )
  }
  if !message.content().trim().is_empty() {
    body.push(text_block(message.content()))
  }
  let calls = message.tool_calls()
  if !calls.is_empty() {
    let call_views : Array[@html.Html] = [
      for call in calls => tool_call_view(call)
    ]
    body.push(@html.div(class="tool-calls", call_views))
  }
  card("assistant", "Assistant", seq, time~, body)
}

///|
fn tool_call_view(call : @deepseek.ToolCall) -> @html.Html {
  @html.div(class="tool-call", [
    @html.div(class="tool-call-name", [
      @html.text("→ "),
      @html.strong(call.name),
    ]),
    @html.pre(class="tool-call-args", pretty_json(call.arguments)),
  ])
}

///|
fn tool_card(
  seq : Int,
  time : String,
  result : @agent_session.ToolResult,
) -> @html.Html {
  let kind = if result.is_error() { "tool error" } else { "tool" }
  let label = if result.is_error() {
    "Tool error · \{result.tool_name()}"
  } else {
    "Tool result · \{result.tool_name()}"
  }
  card(kind, label, seq, time~, [text_block(result.content())])
}

///|
fn summary_card(
  seq : Int,
  time : String,
  summary : @agent_session.SessionSummary,
) -> @html.Html {
  let label = "Summary · covers events \{summary.from_sequence()}..\{summary.to_sequence()}"
  card("summary", label, seq, time~, [text_block(summary.content())])
}

///|
fn terminal_card(
  seq : Int,
  time : String,
  terminal : @agent_session.TurnTerminal,
) -> @html.Html {
  let (kind, message) = match terminal {
    Finished(answer) => ("finished", answer)
    Aborted(reason) => ("aborted", reason)
    Interrupted(reason) => ("interrupted", reason)
    Failed(message) => ("failed", message)
  }
  let body : Array[@html.Html] = [@html.span(class="badge badge-\{kind}", kind)]
  if !message.trim().is_empty() {
    body.push(text_block(message))
  }
  card("terminal", "Turn ended", seq, time~, body)
}

// ---- model projection view -------------------------------------------------

///|
fn render_model(session : @agent_session.Session) -> @html.Html {
  let messages = session.chat_messages()
  let cards : Array[@html.Html] = [
    for message in messages => message_card(message)
  ]
  if cards.is_empty() {
    return empty_state("The model projection is empty.")
  }
  @html.div(class="log model-log", cards)
}

///|
fn message_card(message : @deepseek.ChatMessage) -> @html.Html {
  match message.role {
    System =>
      @html.section(class="card system", [
        @html.details(open=false, [
          @html.summary(class="card-label", "System prompt"),
          text_block(message.content),
        ]),
      ])
    User => model_card("user", "User", message)
    Assistant => model_card("assistant", "Assistant", message)
    Tool(_) => model_card("tool", "Tool result", message)
  }
}

///|
fn model_card(
  kind : String,
  label : String,
  message : @deepseek.ChatMessage,
) -> @html.Html {
  let body : Array[@html.Html] = []
  if message.reasoning_content is Some(reasoning) &&
    !reasoning.trim().is_empty() {
    body.push(
      @html.details(class="reasoning", [
        @html.summary("reasoning"),
        text_block(reasoning),
      ]),
    )
  }
  if !message.content.trim().is_empty() {
    body.push(text_block(message.content))
  }
  if !message.tool_calls.is_empty() {
    let call_views : Array[@html.Html] = [
      for call in message.tool_calls => tool_call_view(call)
    ]
    body.push(@html.div(class="tool-calls", call_views))
  }
  @html.section(class="card \{kind}", [
    @html.div(class="card-label", label),
    @html.div(class="card-body", body),
  ])
}

// ---- shared helpers --------------------------------------------------------

///|
fn card(
  kind : String,
  label : String,
  seq : Int,
  time~ : String,
  body : Array[@html.Html],
) -> @html.Html {
  let head : Array[@html.Html] = [
    @html.span(class="card-seq", "#\{seq}"),
    @html.text(label),
  ]
  if !time.is_empty() {
    head.push(@html.span(class="card-ts", time))
  }
  @html.section(class="card \{kind}", [
    @html.div(class="card-label", head),
    @html.div(class="card-body", body),
  ])
}

///|
/// A whitespace-preserving text block. Empty content renders an explicit
/// placeholder so a card never collapses to nothing.
fn text_block(content : String) -> @html.Html {
  if content.trim().is_empty() {
    @html.span(class="empty", "(empty)")
  } else {
    @html.pre(class="content", content)
  }
}

///|
fn empty_state(message : String) -> @html.Html {
  @html.div(class="empty-state", [@html.text(message)])
}

///|
/// Pretty-print a tool call's raw argument string when it is valid JSON; fall
/// back to the raw string otherwise, since the model can emit malformed
/// arguments and the viewer should show them as-is.
fn pretty_json(raw : String) -> String {
  @json.parse(raw).stringify(indent=2) catch {
    _ => raw
  }
}

///|
fn one_line(text : String) -> String {
  text.replace_all(old="\n", new=" ").trim().to_owned()
}

///|
/// Keep the first `limit` characters, appending an ellipsis when text is cut.
/// Iterates by character so it never splits a surrogate pair.
fn truncate(text : String, limit : Int) -> String {
  if text.length() <= limit {
    return text
  }
  let kept = StringBuilder()
  let mut count = 0
  for char in text {
    if count >= limit {
      break
    }
    kept <+ "\{char}"
    count += 1
  }
  kept.to_string() + "…"
}
