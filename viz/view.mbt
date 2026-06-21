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
pub fn render_notices(parsed : @session_log.ParsedLog) -> @html.Html {
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
  let briefs = tool_call_briefs(session)
  let step_labels = agent_step_labels(session)
  let turns = group_turns(session.events())
  let blocks : Array[@html.Html] = []
  for index, turn in turns {
    blocks.push(turn_block(index + 1, turn, briefs, step_labels))
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
/// Durable session logs do not store the transient `agent_step` events the CLI
/// emits while running. Most model iterations persist as `Assistant` events,
/// but the common final-answer path stores the no-tool response only as
/// `Terminal(Finished(_))`, so derive stable human-facing labels from both.
fn agent_step_labels(session : @agent_session.Session) -> Map[Int, String] {
  let total = agent_step_count(session)
  let labels : Map[Int, String] = Map([])
  let mut step = 0
  let mut previous : @agent_session.SessionEvent? = None
  for event in session.events() {
    if event_represents_agent_step(event, previous) {
      step += 1
      labels.set(event.sequence(), "Step \{step}/\{total}")
    }
    previous = Some(event)
  }
  labels
}

///|
fn agent_step_count(session : @agent_session.Session) -> Int {
  let mut count = 0
  let mut previous : @agent_session.SessionEvent? = None
  for event in session.events() {
    if event_represents_agent_step(event, previous) {
      count += 1
    }
    previous = Some(event)
  }
  count
}

///|
fn event_represents_agent_step(
  event : @agent_session.SessionEvent,
  previous : @agent_session.SessionEvent?,
) -> Bool {
  match event.item() {
    Assistant(_) => true
    Terminal(Finished(_)) => terminal_finished_represents_agent_step(previous)
    _ => false
  }
}

///|
fn terminal_finished_represents_agent_step(
  previous : @agent_session.SessionEvent?,
) -> Bool {
  match previous {
    Some(event) =>
      match event.item() {
        Assistant(_) => false
        Tool(result) => result.tool_name() != "finish"
        _ => true
      }
    None => true
  }
}

///|
fn turn_block(
  number : Int,
  turn : Array[@agent_session.SessionEvent],
  briefs : Map[String, String],
  step_labels : Map[Int, String],
) -> @html.Html {
  // Offsets are relative to the turn's first stamped event: for reading a
  // log, "how far into the turn" answers latency questions directly, where
  // absolute wall clock would force mental subtraction (and a timezone).
  let base = turn_base_ms(turn)
  let cards : Array[@html.Html] = [
    for event in turn => {
      event_card(
        event,
        time=offset_label(base, event),
        briefs,
        step_label=step_labels.get(event.sequence()).unwrap_or(""),
      )
    }
  ]
  let label = match turn_duration_label(turn) {
    Some(duration) => "Turn \{number} · \{turn_preview(turn)} · \{duration}"
    None => "Turn \{number} · \{turn_preview(turn)}"
  }
  // Surface failed tools in the turn header so a turn carrying errors is
  // scannable even while its cards are folded or the turn itself is collapsed.
  let summary : Array[@html.Html] = [@html.text(label)]
  let errors = count_turn_tool_errors(turn)
  if errors > 0 {
    summary.push(
      @html.span(
        class="turn-error-badge",
        " · 🚩 \{errors} error\{plural(errors)}",
      ),
    )
  }
  @html.details(open=true, class="turn", [
    @html.summary(class="turn-summary", summary),
    @html.div(class="turn-body", cards),
  ])
}

///|
/// Number of failed tool results in a turn, for the turn header's error badge.
fn count_turn_tool_errors(turn : Array[@agent_session.SessionEvent]) -> Int {
  for event in turn; count = 0 {
    if event.item() is Tool(result) && result.is_error() {
      continue count + 1
    }
  } nobreak {
    count
  }
}

///|
/// `""` for one, `"s"` otherwise — for pluralizing a count in a label.
fn plural(n : Int) -> String {
  if n == 1 {
    ""
  } else {
    "s"
  }
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
  "+\{format_span_total_seconds(event.unix_ms() - base)}"
}

///|
fn model_offset_label(
  base : Int64,
  event : @agent_session.SessionEvent,
) -> String {
  if base == 0 || event.unix_ms() == 0 {
    return ""
  }
  "+\{format_span_total_seconds(event.unix_ms() - base)}"
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
    Some(format_span_total_seconds(last - base))
  } else {
    None
  }
}

///|
/// A millisecond span as total elapsed seconds. Session-view timestamp chips use
/// this instead of minute-splitting so `70.3s` cannot read like just `10.3s`.
fn format_span_total_seconds(span_ms : Int64) -> String {
  let tenths = span_ms / 100
  "\{tenths / 10}.\{tenths % 10}s"
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
  briefs : Map[String, String],
  step_label~ : String,
) -> @html.Html {
  let seq = event.sequence()
  match event.item() {
    User(message) =>
      card("user", "User", seq, time~, [text_block(message.content())])
    Assistant(message) =>
      assistant_card(seq, time, message, briefs, step_label~)
    Tool(result) => tool_card(seq, time, result)
    Runtime(notice) =>
      card("runtime", "Runtime notice", seq, time~, [
        text_block(notice.content()),
      ])
    Summary(summary) => summary_card(seq, time, summary)
    Terminal(terminal) => terminal_card(seq, time, terminal, step_label~)
  }
}

///|
fn assistant_card(
  seq : Int,
  time : String,
  message : @agent_session.AssistantMessage,
  briefs : Map[String, String],
  step_label~ : String,
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
      for call in calls => tool_call_view(call, briefs)
    ]
    body.push(@html.div(class="tool-calls", call_views))
  }
  card("assistant", "Assistant", seq, time~, body, step_label~)
}

///|
/// A tool call, with its arguments folded away by default: the row shows only
/// the tool name and expands to the full argument JSON on click. Calls with no
/// meaningful arguments render as a plain name (nothing to fold).
fn tool_call_view(
  call : @deepseek.ToolCall,
  briefs : Map[String, String],
) -> @html.Html {
  let name_row : Array[@html.Html] = [
    @html.text("→ "),
    @html.strong(call.name),
  ]
  if briefs.get(call.id) is Some(brief) && !brief.trim().is_empty() {
    name_row.push(@html.span(class="tool-call-brief", " · \{brief}"))
  }
  let args = pretty_json(call.arguments)
  if is_blank_args(args) {
    return @html.div(class="tool-call", [
      @html.div(class="tool-call-name", name_row),
    ])
  }
  @html.details(class="tool-call", [
    @html.summary(class="tool-call-name", name_row),
    @html.pre(class="tool-call-args", args),
  ])
}

///|
/// Map each tool call's id to the one-line brief its result recorded, for the
/// folded call line. Indexes every durable result, which is correct for the raw
/// view (it shows every event); the model view instead uses
/// `model_tool_call_briefs` so it never captions a compacted/healed call. Only
/// results that carry a brief appear; older logs and briefless tools produce no
/// entry (the call renders as a plain name).
fn tool_call_briefs(session : @agent_session.Session) -> Map[String, String] {
  let briefs : Map[String, String] = Map([])
  for event in session.events() {
    if event.item() is Tool(result) {
      if call_brief_display(result.brief(), result.is_error()) is Some(display) {
        briefs.set(result.tool_call_id(), display)
      }
    }
  }
  briefs
}

///|
/// The folded-call brief text: the tool's one-line brief (if any) plus a red
/// flag when its result errored, so a failed call (e.g. a missing-file `read`)
/// stands out in the assistant's action list without expanding it. `None` when
/// there is nothing to show (a successful call with no brief).
fn call_brief_display(brief : String?, is_error : Bool) -> String? {
  match (brief, is_error) {
    (None, false) => None
    (None, true) => Some("🚩")
    (Some(text), false) => Some(text)
    (Some(text), true) => Some("\{text} 🚩")
  }
}

///|
/// Whether a tool call's (pretty-printed) arguments carry nothing worth folding
/// away — empty text or an empty object.
fn is_blank_args(args : String) -> Bool {
  let trimmed = args.trim().to_owned()
  trimmed.is_empty() || trimmed == "{}"
}

///|
/// Tool output is noisy, so fold it behind the label by default. The summary
/// keeps the tool name and, on failure, a red flag — both visible while the card
/// is collapsed — so a failed tool stands out without expanding it.
fn tool_card(
  seq : Int,
  time : String,
  result : @agent_session.ToolResult,
) -> @html.Html {
  let is_error = result.is_error()
  let kind = if is_error { "tool error" } else { "tool" }
  let label = if is_error {
    "Tool error · \{result.tool_name()}"
  } else {
    "Tool result · \{result.tool_name()}"
  }
  let flag = if is_error {
    @html.span(class="tool-flag", "🚩 failed")
  } else {
    @html.nothing
  }
  @html.details(class="card \{kind}", [
    @html.summary(class="card-label", card_head(label, seq, time~, flag~)),
    @html.div(class="card-body", [text_block(result.content())]),
  ])
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
  step_label~ : String,
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
  card("terminal", "Turn ended", seq, time~, body, step_label~)
}

// ---- model projection view -------------------------------------------------

///|
fn render_model(session : @agent_session.Session) -> @html.Html {
  // The projection keys each tool message only by id and drops is_error / tool
  // name, so recover them from the durable events for display (the messages fed
  // to the model are unchanged — this is view-only enrichment).
  let tool_results = tool_results_by_id(session)
  let messages = session.chat_messages()
  let time_labels = model_message_time_labels(session)
  let step_labels = model_message_step_labels(session)
  // Model-view briefs must come only from results the projection actually
  // emitted and the view trusts (see `model_shown_result`); using every durable
  // brief would caption a healed/compacted call with a result the model never
  // saw. The raw view, which shows every event, uses all briefs.
  let briefs = model_tool_call_briefs(messages, tool_results)
  let cards : Array[@html.Html] = [
    for index, message in messages => {
      let time = if index < time_labels.length() {
        time_labels[index]
      } else {
        ""
      }
      let step_label = if index < step_labels.length() {
        step_labels[index]
      } else {
        ""
      }
      message_card(message, tool_results, briefs, time~, step_label~)
    }
  ]
  if cards.is_empty() {
    return empty_state("The model projection is empty.")
  }
  @html.div(class="log model-log", cards)
}

///|
/// Relative event-time labels, keyed by durable event sequence. This uses the
/// same per-turn base as the raw log, but keeps labels in total seconds so
/// minute-boundary chips stay unambiguous in the compact model projection.
fn event_time_labels(session : @agent_session.Session) -> Map[Int, String] {
  let labels : Map[Int, String] = Map([])
  for turn in group_turns(session.events()) {
    let base = turn_base_ms(turn)
    for event in turn {
      labels.set(event.sequence(), model_offset_label(base, event))
    }
  }
  labels
}

///|
fn model_summary_covers_event(
  summary_event : @agent_session.SessionEvent,
  sequence : Int,
) -> Bool {
  guard summary_event.item() is Summary(summary) else { return false }
  summary_event.sequence() > sequence &&
  summary.from_sequence() <= sequence &&
  sequence <= summary.to_sequence()
}

///|
fn model_event_covered_by_later_summary(
  event : @agent_session.SessionEvent,
  events : @vector.Vector[@agent_session.SessionEvent],
) -> Bool {
  for candidate in events {
    if model_summary_covers_event(candidate, event.sequence()) {
      return true
    }
  }
  false
}

///|
fn remove_pending_tool_id(
  pending : Array[String],
  tool_call_id : String,
) -> Bool {
  for index in 0..<pending.length() {
    if pending[index] == tool_call_id {
      ignore(pending.remove(index))
      return true
    }
  }
  false
}

///|
fn flush_pending_tool_time_labels(
  pending : Array[String],
  labels : Array[String],
) -> Unit {
  for _ in pending {
    // Synthetic repair messages are not backed by a durable event, so they do
    // not get a timestamp label.
    labels.push("")
  }
  pending.clear()
}

///|
fn flush_pending_tool_step_labels(
  pending : Array[String],
  labels : Array[String],
) -> Unit {
  for _ in pending {
    labels.push("")
  }
  pending.clear()
}

///|
fn terminal_projects_model_message(
  terminal : @agent_session.TurnTerminal,
) -> Bool {
  match terminal {
    Finished(answer) => !answer.trim().is_empty()
    Aborted(_) | Interrupted(_) | Failed(_) => true
  }
}

///|
fn item_projects_model_message(item : @agent_session.SessionItem) -> Bool {
  match item {
    User(_) | Runtime(_) | Summary(_) | Assistant(_) | Tool(_) => true
    Terminal(terminal) => terminal_projects_model_message(terminal)
  }
}

///|
fn event_label(
  labels : Map[Int, String],
  event : @agent_session.SessionEvent,
) -> String {
  labels.get(event.sequence()).unwrap_or("")
}

///|
/// Timestamp labels parallel to `Session::chat_messages()`: the first system
/// prompt has no event stamp, and each projected event-backed message receives
/// that event's relative turn offset.
fn model_message_time_labels(session : @agent_session.Session) -> Array[String] {
  let labels = event_time_labels(session)
  let times : Array[String] = [""]
  let pending_tool_calls : Array[String] = []
  let events = session.events()
  for event in events {
    if model_event_covered_by_later_summary(event, events) {
      continue
    }
    match event.item() {
      Assistant(message) => {
        flush_pending_tool_time_labels(pending_tool_calls, times)
        times.push(event_label(labels, event))
        for call in message.tool_calls() {
          pending_tool_calls.push(call.id)
        }
      }
      Tool(result) =>
        if remove_pending_tool_id(pending_tool_calls, result.tool_call_id()) {
          times.push(event_label(labels, event))
        }
      item => {
        flush_pending_tool_time_labels(pending_tool_calls, times)
        if item_projects_model_message(item) {
          times.push(event_label(labels, event))
        }
      }
    }
  }
  flush_pending_tool_time_labels(pending_tool_calls, times)
  times
}

///|
/// Step labels parallel to `Session::chat_messages()`. Only model-backed
/// assistant events get a label; terminal answers and synthetic healed tool
/// results may project as model messages, but they are not agent-loop steps.
fn model_message_step_labels(session : @agent_session.Session) -> Array[String] {
  let event_labels = agent_step_labels(session)
  let labels : Array[String] = [""]
  let pending_tool_calls : Array[String] = []
  let events = session.events()
  for event in events {
    if model_event_covered_by_later_summary(event, events) {
      continue
    }
    match event.item() {
      Assistant(message) => {
        flush_pending_tool_step_labels(pending_tool_calls, labels)
        labels.push(event_labels.get(event.sequence()).unwrap_or(""))
        for call in message.tool_calls() {
          pending_tool_calls.push(call.id)
        }
      }
      Tool(result) =>
        if remove_pending_tool_id(pending_tool_calls, result.tool_call_id()) {
          labels.push("")
        }
      item => {
        flush_pending_tool_step_labels(pending_tool_calls, labels)
        if item_projects_model_message(item) {
          labels.push(event_labels.get(event.sequence()).unwrap_or(""))
        }
      }
    }
  }
  flush_pending_tool_step_labels(pending_tool_calls, labels)
  labels
}

///|
/// Briefs for the model view: keyed by call id, but only from the durable result
/// the projection emitted for that call and whose content the view trusts. A
/// compacted-away or healed result contributes no brief, so the call line never
/// shows a summary the model was not actually fed.
fn model_tool_call_briefs(
  messages : Array[@deepseek.ChatMessage],
  tool_results : Map[String, @agent_session.ToolResult],
) -> Map[String, String] {
  let briefs : Map[String, String] = Map([])
  for message in messages {
    guard message.role is Tool(id) else { continue }
    if model_shown_result(message, tool_results) is Some(result) &&
      call_brief_display(result.brief(), result.is_error()) is Some(display) {
      briefs.set(id, display)
    }
  }
  briefs
}

///|
/// Index every `ToolResult` event by its `tool_call_id`, so the model view can
/// recover the error flag and tool name that the projection discards.
fn tool_results_by_id(
  session : @agent_session.Session,
) -> Map[String, @agent_session.ToolResult] {
  let map : Map[String, @agent_session.ToolResult] = Map([])
  for event in session.events() {
    if event.item() is Tool(result) {
      map.set(result.tool_call_id(), result)
    }
  }
  map
}

///|
fn message_card(
  message : @deepseek.ChatMessage,
  tool_results : Map[String, @agent_session.ToolResult],
  briefs : Map[String, String],
  time~ : String,
  step_label~ : String,
) -> @html.Html {
  match message.role {
    System =>
      @html.section(class="card system", [
        @html.details(open=false, [
          @html.summary(
            class="card-label",
            model_card_head("System prompt", time~),
          ),
          text_block(message.content),
        ]),
      ])
    User => model_card("user", "User", message, briefs, time~, step_label~)
    Assistant =>
      model_card("assistant", "Assistant", message, briefs, time~, step_label~)
    Tool(_) =>
      model_tool_card(message, model_shown_result(message, tool_results), time~)
  }
}

///|
/// The durable `ToolResult` the model view is allowed to surface for a projected
/// tool message: the one looked up by id whose content is exactly what the model
/// was fed. The projection skips results covered by a later summary and heals a
/// dangling call with a synthetic message; in those cases the looked-up result
/// is not what the model saw, so the content guard rejects it (returns `None`)
/// rather than misrepresent the model view. Shared by `model_tool_card` and
/// `rendered_error_count` so the on-screen flags and the error count never drift.
fn model_shown_result(
  message : @deepseek.ChatMessage,
  tool_results : Map[String, @agent_session.ToolResult],
) -> @agent_session.ToolResult? {
  guard message.role is Tool(id) else { return None }
  match tool_results.get(id) {
    Some(result) if result.content() == message.content => Some(result)
    _ => None
  }
}

///|
/// How many tool-error cards `render_session` draws for `mode` — i.e. failed
/// tool results actually shown, so it equals the number of `.card.tool.error`
/// elements on screen. `RawLog` shows every errored `ToolResult`; `ModelView`
/// shows only those the projection emitted and the view trusts (see
/// `model_shown_result`). Used to drive the "find failures" controls.
pub fn rendered_error_count(
  session : @agent_session.Session,
  mode : ViewMode,
) -> Int {
  match mode {
    RawLog =>
      for event in session.events(); count = 0 {
        if event.item() is Tool(result) && result.is_error() {
          continue count + 1
        }
      } nobreak {
        count
      }
    ModelView => {
      let tool_results = tool_results_by_id(session)
      for message in session.chat_messages(); count = 0 {
        if model_shown_result(message, tool_results) is Some(result) &&
          result.is_error() {
          continue count + 1
        }
      } nobreak {
        count
      }
    }
  }
}

///|
/// Model-view tool result, folded by default like the raw view. `result` is the
/// durable `ToolResult` looked up by id, which lets this recover the tool name
/// and red-flag failures even though the projection drops `is_error`. A non-zero
/// command exit sets `is_error`, so an `exit=1` result is flagged here just as
/// in the raw log.
///
/// `shown` is the durable result the view trusts for this message (see
/// `model_shown_result`) — `None` when the projection healed/compacted it away,
/// in which case the card is plain and unflagged so it never misrepresents what
/// the model saw.
fn model_tool_card(
  message : @deepseek.ChatMessage,
  shown : @agent_session.ToolResult?,
  time~ : String,
) -> @html.Html {
  let is_error = shown is Some(r) && r.is_error()
  let name = match shown {
    Some(r) => r.tool_name()
    None => ""
  }
  let kind = if is_error { "tool error" } else { "tool" }
  let label = match (is_error, name.is_empty()) {
    (_, true) => "Tool result"
    (true, false) => "Tool error · \{name}"
    (false, false) => "Tool result · \{name}"
  }
  @html.details(class="card \{kind}", [
    @html.summary(
      class="card-label",
      model_card_head(
        label,
        time~,
        flag=if is_error {
          @html.span(class="tool-flag", "🚩 failed")
        } else {
          @html.nothing
        },
      ),
    ),
    @html.div(class="card-body", [text_block(message.content)]),
  ])
}

///|
fn model_card(
  kind : String,
  label : String,
  message : @deepseek.ChatMessage,
  briefs : Map[String, String],
  time~ : String,
  step_label~ : String,
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
      for call in message.tool_calls => tool_call_view(call, briefs)
    ]
    body.push(@html.div(class="tool-calls", call_views))
  }
  @html.section(class="card \{kind}", [
    @html.div(class="card-label", model_card_head(label, time~, step_label~)),
    @html.div(class="card-body", body),
  ])
}

// ---- shared helpers --------------------------------------------------------

///|
fn model_card_head(
  label : String,
  time~ : String,
  flag? : @html.Html = @html.nothing,
  step_label? : String = "",
) -> Array[@html.Html] {
  let head : Array[@html.Html] = [flag, @html.text(label)]
  if !step_label.is_empty() {
    head.push(@html.span(class="card-step", step_label))
  }
  if !time.is_empty() {
    head.push(@html.span(class="card-ts", time))
  }
  head
}

///|
fn card(
  kind : String,
  label : String,
  seq : Int,
  time~ : String,
  body : Array[@html.Html],
  step_label? : String = "",
) -> @html.Html {
  @html.section(class="card \{kind}", [
    @html.div(class="card-label", card_head(label, seq, time~, step_label~)),
    @html.div(class="card-body", body),
  ])
}

///|
/// The card header row: a sequence chip, the label, and (when stamped) a
/// relative-time chip. `flag` sits between the sequence and the label so a
/// folded card can still surface a status marker (e.g. a failed-tool flag) in
/// its summary; it defaults to nothing for ordinary cards.
fn card_head(
  label : String,
  seq : Int,
  time~ : String,
  flag? : @html.Html = @html.nothing,
  step_label? : String = "",
) -> Array[@html.Html] {
  let head : Array[@html.Html] = [
    @html.span(class="card-seq", "#\{seq}"),
    flag,
    @html.text(label),
  ]
  if !step_label.is_empty() {
    head.push(@html.span(class="card-step", step_label))
  }
  if !time.is_empty() {
    head.push(@html.span(class="card-ts", time))
  }
  head
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
  let one = text.replace_all(old="\n", new=" ").trim()
  "\{one}"
}

///|
/// Keep the first `limit` characters, appending an ellipsis when text is cut.
/// Iterates by character so it never splits a surrogate pair.
fn truncate(text : String, limit : Int) -> String {
  if text.length() <= limit {
    text
  } else {
    let kept = StringBuilder()
    for char in text; count = 0 {
      if count >= limit {
        break
      }
      kept.write_char(char)
      continue count + 1
    }
    kept.write_char('…')
    kept.to_string()
  }
}
