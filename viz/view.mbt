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
      @html.div(class="notice notice-warn") <| [
        @html.text(
          "⚠ trailing partial line ignored (process likely exited mid-append)",
        ),
      ],
    )
  }
  for error in parsed.errors {
    notices.push(
      @html.div(class="notice notice-error") <| [
        @html.div(class="notice-head") <| [
          @html.text(
            "⚠ line \{error.line_number} could not be decoded: \{error.message}",
          ),
        ],
        @html.pre(class="notice-body") <| error.content,
      ],
    )
  }
  if notices.is_empty() {
    @html.nothing
  } else {
    @html.div(class="notices") <| notices
  }
}

// ---- raw log view ----------------------------------------------------------

///|
fn render_raw(session : @agent_session.Session) -> @html.Html {
  let briefs = tool_call_briefs(session)
  let failed = raw_failed_call_ids(session)
  let tags = raw_pair_tags(session)
  let plans = raw_plan_baselines(session, failed)
  let step_labels = agent_step_labels(session)
  let turns = group_turns(session.events())
  let blocks : Array[@html.Html] = [
    for index, turn in turns => {
      turn_block(index + 1, turn, briefs, failed, tags, plans, step_labels)
    }
  ]
  if blocks.is_empty() {
    return empty_state("This session has no events yet.")
  }
  @html.div(class="log raw-log") <| blocks
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
/// Turns are delimited by `Terminal` events, so a turn that contains mid-turn
/// steering (extra `User` events before the terminal) stays a single turn.
test "group_turns keeps steering messages within one turn" {
  let s = @agent_session.Session(SessionId("g"), system_prompt="")
    .append(User(UserMessage("do the thing")))
    .append(Assistant(AssistantMessage("working")))
    .append(User(UserMessage("actually, also this")))
    .append(Assistant(AssistantMessage("ok")))
    .append(Terminal(Finished("done")))
  let turns = group_turns(s.events())
  inspect(turns.length(), content="1")
  inspect(turns[0].length(), content="5")
}

///|
/// Two complete turns produce two groups; a trailing turn with no terminal
/// (cut off mid-flight) becomes its own final group.
test "group_turns splits on terminals and keeps an unterminated tail" {
  let s = @agent_session.Session(SessionId("g"), system_prompt="")
    .append(User(UserMessage("one")))
    .append(Terminal(Finished("first")))
    .append(User(UserMessage("two")))
    .append(Terminal(Finished("second")))
    .append(User(UserMessage("three (still running)")))
  let turns = group_turns(s.events())
  inspect(turns.length(), content="3")
  inspect(turns[0].length(), content="2")
  inspect(turns[1].length(), content="2")
  inspect(turns[2].length(), content="1")
}

///|
/// Durable session logs do not store the transient `agent_step` events the CLI
/// emits while running. Most model iterations persist as `Assistant` events,
/// but the common final-answer path stores the no-tool response only as
/// `Terminal(Finished(_))`, so derive stable human-facing labels from both.
fn agent_step_labels(session : @agent_session.Session) -> Map[Int, String] {
  let sequences = agent_step_sequences(session)
  let labels : Map[Int, String] = Map([])
  for index, sequence in sequences {
    labels.set(sequence, "Step \{index + 1}/\{sequences.length()}")
  }
  labels
}

///|
/// Sequence numbers of the events that represent agent steps, in log order.
fn agent_step_sequences(session : @agent_session.Session) -> Array[Int] {
  let sequences : Array[Int] = []
  let mut previous : @agent_session.SessionEvent? = None
  let mut finish_in_batch = false
  for event in session.events() {
    if event_represents_agent_step(event, previous, finish_in_batch) {
      sequences.push(event.sequence())
    }
    // A checkpoint Summary can sit between a finish-tool result and its
    // terminal (compact-on-finish); skip it when looking backward so the
    // terminal is still attributed to the finish call.
    match event.item() {
      Tool(result) =>
        if result.tool_name() == "finish" {
          finish_in_batch = true
        }
      Summary(_) => ()
      _ => finish_in_batch = false
    }
    if !(event.item() is Summary(_)) {
      previous = Some(event)
    }
  }
  sequences
}

///|
fn event_represents_agent_step(
  event : @agent_session.SessionEvent,
  previous : @agent_session.SessionEvent?,
  finish_in_batch : Bool,
) -> Bool {
  match event.item() {
    Assistant(_) => true
    Terminal(Finished(message)) =>
      // A context-ceiling yield's terminal is synthetic, not a model step.
      !message.has_prefix(@agent_session.ContextYieldAnswerPrefix) &&
      terminal_finished_represents_agent_step(previous, finish_in_batch)
    _ => false
  }
}

///|
/// Tool results are recorded in CALL order, so a finish result may be
/// followed by same-batch skip notes; `finish_in_batch` — a finish result
/// seen since the last assistant message — is the completion signal, not
/// "the finish result came last".
fn terminal_finished_represents_agent_step(
  previous : @agent_session.SessionEvent?,
  finish_in_batch : Bool,
) -> Bool {
  if finish_in_batch {
    return false
  }
  match previous {
    Some(event) =>
      match event.item() {
        Assistant(_) => false
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
  failed : Map[String, Unit],
  tags : Map[String, Int],
  plans : Map[String, Array[@steps.PlanStep]],
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
        failed,
        tags,
        plans,
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
      @html.span(class="turn-error-badge") <| " · 🚩 \{errors} error\{plural(errors)}",
    )
  }
  @html.details(open=true, class="turn") <| [
    @html.summary(class="turn-summary") <| summary,
    @html.div(class="turn-body") <| cards,
  ]
}

///|
/// Number of failed tool results in a turn, for the turn header's error badge.
fn count_turn_tool_errors(turn : Array[@agent_session.SessionEvent]) -> Int {
  turn.count_if(event => event.item() is Tool(result) && result.is_error())
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
  failed : Map[String, Unit],
  tags : Map[String, Int],
  plans : Map[String, Array[@steps.PlanStep]],
  step_label~ : String,
) -> @html.Html {
  let seq = event.sequence()
  match event.item() {
    User(message) =>
      card("user", "User", seq, time~, [text_block(message.content())])
    Assistant(message) =>
      assistant_card(
        seq,
        time,
        message,
        briefs,
        failed,
        tags,
        plans,
        step_label~,
      )
    Tool(result) => tool_card(seq, time, result, tags)
    Runtime(notice) => runtime_card(seq, time, notice.content())
    Summary(summary) => summary_card(seq, time, summary)
    Terminal(terminal) => terminal_card(seq, time, terminal, step_label~)
  }
}

///|
/// Render a `RuntimeNotice` card. Notices the agent loop stamps with a known
/// first line get dedicated cards: plan-cadence reminders render their
/// checklist, and the goal-command family — set/cleared/blocked markers
/// (recognized by the shared `@agent_session.goal_marker` decoder, so the
/// view can never disagree with the engine about what a marker means) plus
/// goal reminders and finish-time goal checks — surfaces the goal text
/// itself instead of a wall of boilerplate. Any other runtime notice keeps
/// the generic card.
fn runtime_card(seq : Int, time : String, content : String) -> @html.Html {
  if content.has_prefix(@agent_session.PlanReminderPrefix) {
    return plan_reminder_card(seq, time, content)
  }
  match @agent_session.goal_marker(content) {
    Some(GoalSet(text)) =>
      return card("runtime goal-set", "Goal set", seq, time~, [
        goal_text_block(text),
      ])
    Some(GoalCleared) =>
      return card("runtime goal-cleared", "Goal cleared", seq, time~, [
        @html.span(class="goal-cleared-note") <| "standing goal cleared",
      ])
    Some(GoalBlocked(reason)) =>
      return card("runtime goal-blocked", "Goal blocked", seq, time~, [
        text_block(reason),
      ])
    Some(GoalUnblocked) =>
      return card("runtime goal-unblocked", "Goal unblocked", seq, time~, [
        @html.span(class="goal-cleared-note") <| "goal resumed; auto-continuation re-enabled",
      ])
    None => ()
  }
  if content.has_prefix(@agent_session.GoalReminderPrefix) {
    return goal_notice_card(
      "goal-reminder",
      "Goal reminder",
      seq,
      time,
      content,
      boilerplate="Assess it briefly at this turn boundary:",
    )
  }
  if content.has_prefix(@agent_session.GoalCheckPrefix) {
    return goal_notice_card(
      "goal-check",
      "Goal check",
      seq,
      time,
      content,
      boilerplate="You attempted to finish.",
    )
  }
  card("runtime", "Runtime notice", seq, time~, [text_block(content)])
}

///|
/// A plan-cadence reminder card: prose kept verbatim, the re-surfaced
/// checklist (when present) as a progress meter plus status-classed rows.
fn plan_reminder_card(seq : Int, time : String, content : String) -> @html.Html {
  let body : Array[@html.Html] = []
  match split_plan_checklist(content) {
    Some((prose, steps)) => {
      body.push(text_block(prose))
      body.push(
        plan_progress_view(
          steps.count_if(step => reminder_step_status(step) is Some("completed")),
          steps.length(),
        ),
      )
      body.push(
        @html.ul(class="plan-steps") <| [
          for step in steps => plan_step_item(step)
        ],
      )
    }
    None => body.push(text_block(content))
  }
  card("runtime plan-reminder", "Plan reminder", seq, time~, body)
}

///|
/// A goal reminder / goal check card. The goal text is the only part that
/// varies — the surrounding assessment instructions are identical on every
/// card — so the goal renders prominently and the verbatim notice folds away
/// beneath it. An unrecognized shape falls back to the plain text block so
/// the card never drops content.
fn goal_notice_card(
  kind : String,
  label : String,
  seq : Int,
  time : String,
  content : String,
  boilerplate~ : String,
) -> @html.Html {
  let body : Array[@html.Html] = match
    split_goal_notice(content, boilerplate~) {
    Some(goal) =>
      [
        goal_text_block(goal),
        @html.details(class="goal-boilerplate") <| [
          @html.summary("full notice"),
          text_block(content),
        ],
      ]
    None => [text_block(content)]
  }
  card("runtime \{kind}", label, seq, time~, body)
}

///|
/// The goal text inside a reminder/check notice: the lines between the
/// "The standing goal for this session:" header and this notice kind's own
/// boilerplate delimiter (mirroring `goal_reminder_text` / `goal_check_text`
/// in `agent`). The goal is arbitrary user input and may itself contain
/// delimiter-looking lines, so only the caller's delimiter is recognized and
/// its LAST occurrence wins — the loop appends the instructions after the
/// goal, so everything above that line is goal text. `None` when the shape
/// is not recognized.
fn split_goal_notice(content : String, boilerplate~ : String) -> String? {
  let lines = string_lines(content)
  guard lines.length() >= 3 && lines[1] == "The standing goal for this session:" else {
    return None
  }
  for index in (lines.length() - 1)>=..3 {
    if lines[index].has_prefix(boilerplate) {
      return Some(lines[2:index].join("\n").trim().to_owned())
    }
  }
  None
}

///|
/// The standing goal, rendered as the card's payload: a marked block that
/// stands out from boilerplate prose.
fn goal_text_block(text : String) -> @html.Html {
  @html.div(class="goal-text") <| [
    @html.span(class="goal-icon", title="standing goal") <| "🎯",
    @html.pre(class="goal-text-body") <| text,
  ]
}

///|
/// Split a checklist-carrying reminder into its prose (through the
/// "Current plan:" line) and the step lines after it. `None` when the notice
/// has no checklist (the no-plan nag variant).
fn split_plan_checklist(content : String) -> (String, Array[String])? {
  let lines = string_lines(content)
  for index, line in lines {
    if line.trim_end().has_suffix("Current plan:") {
      let steps = [
        for step in lines[index + 1:] if !step.trim().is_empty() => step
      ]
      if steps.is_empty() {
        return None
      }
      return Some((lines[:index + 1].join("\n"), steps))
    }
  }
  None
}

///|
/// One checklist row: `N. [status] title` renders as a status icon plus the
/// numbered title — the same row shape `plan` tool calls use — with the status
/// doubling as a CSS class (pending/in_progress/completed). A line that does
/// not match the shape falls back to plain text so the card never drops
/// content.
fn plan_step_item(line : String) -> @html.Html {
  guard line.find("[") is Some(open) &&
    line.find("]") is Some(close) &&
    open < close else {
    return @html.li(class="plan-step") <| line
  }
  plan_step_row(
    status=line[open + 1:close].to_owned(),
    number=line[:open].trim_end().to_owned(),
    title=line[close + 1:].trim_start().to_owned(),
    chip=@html.nothing,
  )
}

///|
/// The status inside a reminder line's leading `[...]` bracket, or `None` for
/// a line that does not match the `N. [status] title` shape. The first
/// bracket pair is the status by construction, so a title that itself
/// mentions `[completed]` cannot be miscounted.
fn reminder_step_status(line : String) -> String? {
  guard line.find("[") is Some(open) &&
    line.find("]") is Some(close) &&
    open < close else {
    return None
  }
  Some(line[open + 1:close].to_owned())
}

// ---- plan tool-call rendering -----------------------------------------------

///|
/// Decoded steps when `call` is a well-formed `plan` call; `None` otherwise.
/// Uses the plan tool's own decoder (`@steps`, the same package the tool
/// validates with), so the checklist rendering accepts exactly what the tool
/// accepts — decoder drift was how a rejected call once fabricated diff
/// history. Anything the tool would reject keeps the generic arguments
/// rendering.
fn plan_call_steps(call : @deepseek.ToolCall) -> Array[@steps.PlanStep]? {
  guard call.name == "plan" else { return None }
  let json = @json.parse(call.arguments) catch { _ => return None }
  let input = @steps.decode(json) catch { _ => return None }
  Some(input.steps)
}

///|
/// For each well-formed `plan` call id, the decoded steps of the previous
/// *applied* plan call among `calls` — the baseline its card diffs against.
/// The first plan call has no entry, so it renders without change markers.
///
/// A call in `failed` never changed the recorded plan (the tool rejected it),
/// so it neither receives a baseline nor becomes one. And like
/// `assign_pair_tags`, an empty id (streaming glitch) or an id shared by
/// several plan calls gets no entry — a per-id lookup cannot say which call
/// it labels, and a wrong baseline fabricates plan history.
fn plan_baselines(
  calls : Array[@deepseek.ToolCall],
  failed : Map[String, Unit],
) -> Map[String, Array[@steps.PlanStep]] {
  let id_counts = occurrence_counts(
    [
      for call in calls if plan_call_steps(call) is Some(_) => call.id
    ],
  )
  let baselines : Map[String, Array[@steps.PlanStep]] = Map([])
  let mut previous : Array[@steps.PlanStep]? = None
  for call in calls {
    guard plan_call_steps(call) is Some(steps) else { continue }
    if failed.contains(call.id) {
      continue
    }
    if call.id != "" &&
      id_counts.get(call.id) == Some(1) &&
      previous is Some(prev) {
      baselines.set(call.id, prev)
    }
    previous = Some(steps)
  }
  baselines
}

///|
/// Plan baselines for the raw view, drawn from every durable assistant event;
/// `failed` is the durable errored-result set, so a rejected plan call is
/// never treated as applied.
fn raw_plan_baselines(
  session : @agent_session.Session,
  failed : Map[String, Unit],
) -> Map[String, Array[@steps.PlanStep]] {
  let calls : Array[@deepseek.ToolCall] = []
  for event in session.events() {
    if event.item() is Assistant(message) {
      calls.append(message.tool_calls())
    }
  }
  plan_baselines(calls, failed)
}

///|
/// Plan baselines for the model view, drawn from the projected messages it
/// renders — so a plan call compacted away is not a baseline, mirroring what
/// the model itself can still see. `failed` is the model view's trusted
/// failed-call set.
fn model_plan_baselines(
  messages : Array[@deepseek.ChatMessage],
  failed : Map[String, Unit],
) -> Map[String, Array[@steps.PlanStep]] {
  let calls : Array[@deepseek.ToolCall] = []
  for message in messages {
    calls.append(message.tool_calls)
  }
  plan_baselines(calls, failed)
}

///|
/// Dedicated rendering for `plan` tool-call arguments: a progress meter plus a
/// status-classed checklist, replacing the generic key/value rows. When the
/// call reads as an evolution of `baseline` (the previous plan call), steps
/// that changed carry a small delta chip and steps the update dropped stay
/// visible as ghost rows — a silent scope cut is exactly what a log reader
/// wants to notice. A wholesale rewrite would chip nearly every row
/// "new"/"dropped", so it gets a single rewrite note instead. Carries
/// `tool-call-args-rendered` so the Original toggle still swaps to raw JSON.
fn plan_args_view(
  steps : Array[@steps.PlanStep],
  baseline : Array[@steps.PlanStep]?,
) -> @html.Html {
  if steps.is_empty() {
    return @html.div(class="tool-call-args-rendered plan-args") <| [
      @html.span(class="plan-cleared") <| "plan cleared",
    ]
  }
  let diff_base = if plan_evolves(steps, baseline) { baseline } else { None }
  let rows : Array[@html.Html] = [
    for index, step in steps => plan_call_step(index + 1, step, diff_base)
  ]
  for dropped in dropped_steps(steps, diff_base) {
    rows.push(dropped_step_row(dropped))
  }
  let body : Array[@html.Html] = [
    plan_progress_view(
      steps.count_if(step => step.status is Completed),
      steps.length(),
    ),
  ]
  if diff_base is None && baseline is Some(prev) && !prev.is_empty() {
    body.push(
      @html.div(class="plan-rewrite-note") <| "rewritten — replaces the previous plan",
    )
  }
  body.push(@html.ul(class="plan-steps") <| rows)
  @html.div(class="tool-call-args-rendered plan-args") <| body
}

///|
/// Whether this plan update reads as an evolution of the baseline — at least
/// half the steps of the smaller of the two plans carried over by title —
/// rather than a wholesale rewrite. Measuring against the smaller plan keeps
/// a pure extension (every old step kept, new ones appended) an evolution
/// instead of branding an intact plan "rewritten". Only an evolution gets
/// per-step delta chips; diffing a rewrite (or reworded titles) against the
/// old plan would drown the checklist in noise.
fn plan_evolves(
  steps : Array[@steps.PlanStep],
  baseline : Array[@steps.PlanStep]?,
) -> Bool {
  guard baseline is Some(prev) && !prev.is_empty() else { return false }
  let carried = steps.count_if(step => prev.any(old => old.title == step.title))
  let smaller = if steps.length() < prev.length() {
    steps.length()
  } else {
    prev.length()
  }
  carried * 2 >= smaller
}

///|
/// A compact progress meter: a proportional fill plus a `completed/total`
/// tally. The fill switches to the "added" green only when every step is
/// completed, so a finished plan reads differently from one merely underway.
fn plan_progress_view(completed : Int, total : Int) -> @html.Html {
  let percent = if total == 0 { 0 } else { completed * 100 / total }
  let fill_class = if completed == total {
    "plan-progress-fill complete"
  } else {
    "plan-progress-fill"
  }
  @html.div(class="plan-progress") <| [
    @html.div(class="plan-progress-track") <| [
      @html.div(class=fill_class, style=["width: \{percent}%"]) <| "",
    ],
    @html.span(class="plan-progress-count") <| "\{completed}/\{total}",
  ]
}

///|
fn plan_call_step(
  number : Int,
  step : @steps.PlanStep,
  baseline : Array[@steps.PlanStep]?,
) -> @html.Html {
  let chip = match step_delta(step, baseline) {
    Some(delta) => @html.span(class="step-delta step-delta-\{delta}") <| delta
    None => @html.nothing
  }
  plan_step_row(
    status=step.status.label(),
    number="\{number}.",
    title=step.title,
    chip~,
  )
}

///|
/// One checklist row, shared by `plan` tool calls, plan-cadence reminders,
/// and dropped ghost rows so the three cannot drift apart: status cell,
/// optional number, title, optional trailing chip, with the status doubling
/// as the row's CSS class.
fn plan_step_row(
  status~ : String,
  number? : String = "",
  title~ : String,
  chip~ : @html.Html,
) -> @html.Html {
  let cells : Array[@html.Html] = [status_cell(status)]
  if !number.is_empty() {
    cells.push(@html.span(class="step-num") <| number)
  }
  cells.push(@html.span(class="step-title") <| title)
  cells.push(chip)
  @html.li(class="plan-step \{status}") <| cells
}

///|
/// The leading cell of a checklist row: a glyph for the statuses this build
/// knows, or the literal status word for anything else — reminder lines are
/// parsed from text and may carry statuses from another build, and disguising
/// one as a pending ring would misread e.g. a blocked step as untouched.
fn status_cell(status : String) -> @html.Html {
  match status_icon(status) {
    Some(icon) => @html.span(class="step-icon", title=status) <| icon
    None => @html.span(class="step-status") <| status
  }
}

///|
/// The checklist glyph for a known step status (`dropped` is view-internal,
/// for ghost rows); `None` for a status this build does not know.
fn status_icon(status : String) -> String? {
  match status {
    "completed" => Some("✓")
    "in_progress" => Some("◐")
    "pending" => Some("○")
    "dropped" => Some("✕")
    _ => None
  }
}

///|
/// What changed for `step` against the previous plan call, as chip text
/// (doubling as a CSS class suffix); `None` when nothing changed or there is
/// no usable baseline — the session's first plan, or one following a cleared
/// plan, where chipping every step "new" would be noise. Leaving a completed
/// step is checked first so finished work coming back reads "reopened", not
/// a benign "started".
fn step_delta(
  step : @steps.PlanStep,
  baseline : Array[@steps.PlanStep]?,
) -> String? {
  guard baseline is Some(prev) && !prev.is_empty() else { return None }
  for old in prev {
    if old.title == step.title {
      return match (old.status, step.status) {
        (before, after) if before == after => None
        (Completed, _) => Some("reopened")
        (_, Completed) => Some("done")
        (_, InProgress) => Some("started")
        // in_progress -> pending: the step was set aside, not reopened.
        (_, _) => Some("paused")
      }
    }
  }
  Some("new")
}

///|
/// Steps present in the baseline plan but absent (by title) from the new one.
fn dropped_steps(
  steps : Array[@steps.PlanStep],
  baseline : Array[@steps.PlanStep]?,
) -> Array[@steps.PlanStep] {
  guard baseline is Some(prev) else { return [] }
  prev.filter(old => !steps.any(step => step.title == old.title))
}

///|
fn dropped_step_row(step : @steps.PlanStep) -> @html.Html {
  plan_step_row(
    status="dropped",
    title=step.title,
    chip=@html.span(class="step-delta step-delta-dropped") <| "dropped",
  )
}

///|
/// The at-a-glance ribbon on a folded `plan` call: one fixed-width segment per
/// step, colored by status, so scrolling a long session shows the plan filling
/// up without unfolding a single card. Each segment names its step on hover.
fn plan_ribbon(steps : Array[@steps.PlanStep]) -> @html.Html {
  if steps.is_empty() {
    return @html.nothing
  }
  @html.span(class="plan-ribbon") <| [
    for index, step in steps => {
      @html.span(
        class="plan-ribbon-seg \{step.status.label()}",
        title="\{index + 1}. \{step.title} (\{step.status.label()})",
      ) <| ""
    }
  ]
}

///|
fn assistant_card(
  seq : Int,
  time : String,
  message : @agent_session.AssistantMessage,
  briefs : Map[String, String],
  failed : Map[String, Unit],
  tags : Map[String, Int],
  plans : Map[String, Array[@steps.PlanStep]],
  step_label~ : String,
) -> @html.Html {
  let body : Array[@html.Html] = []
  if message.reasoning_content() is Some(reasoning) &&
    !reasoning.trim().is_empty() {
    body.push(
      @html.details(class="reasoning") <| [
        @html.summary("reasoning"),
        text_block(reasoning),
      ],
    )
  }
  if !message.content().trim().is_empty() {
    body.push(text_block(message.content()))
  }
  let calls = message.tool_calls()
  if !calls.is_empty() {
    let call_views : Array[@html.Html] = [
      for call in calls => tool_call_view(call, briefs, failed, tags, plans)
    ]
    body.push(@html.div(class="tool-calls") <| call_views)
  }
  card("assistant", "Assistant", seq, time~, body, step_label~)
}

///|
/// A tool call, with its arguments folded away by default: the row shows only
/// the tool name and expands on click. Calls with no meaningful arguments render
/// as a plain name (nothing to fold).
///
/// Expanded, the call carries *two* renderings of its arguments: a human-friendly
/// one where each field's value is shown verbatim (a `write_file` body is real
/// text, not a quoted-and-escaped JSON string) and the original pretty-printed
/// JSON. Only one is visible at a time — the stylesheet shows the friendly form by
/// default and swaps to the original under `.show-original`, so the raw arguments
/// stay one toggle away for debugging without re-rendering.
///
/// A call whose result failed is tagged `tool-call-failed`, which flags it in the
/// full view and lets the "errors only" stylesheet keep its assistant card — so a
/// failure shows the originating call cell alongside the error result cell.
///
/// A well-formed `plan` call swaps the friendly rendering for a dedicated
/// checklist (see `plan_args_view`) and shows a per-step status ribbon while
/// still folded.
fn tool_call_view(
  call : @deepseek.ToolCall,
  briefs : Map[String, String],
  failed : Map[String, Unit],
  tags : Map[String, Int],
  plans : Map[String, Array[@steps.PlanStep]],
) -> @html.Html {
  let name_row : Array[@html.Html] = [
    @html.text("→ "),
    @html.strong(call.name),
  ]
  if briefs.get(call.id) is Some(brief) && !brief.trim().is_empty() {
    name_row.push(@html.span(class="tool-call-brief") <| " · \{brief}")
  }
  let plan_steps = plan_call_steps(call)
  if plan_steps is Some(steps) {
    name_row.push(plan_ribbon(steps))
  }
  // When this call forms an unambiguous pair with a result, tag it `call N` and
  // link forward to that result's card; the same number labels the result.
  let pair = tags.get(call.id)
  if pair is Some(n) {
    name_row.push(
      pair_link(
        n,
        href="#\{tool_result_anchor(n)}",
        title="Jump to this call's result (call \{n})",
      ),
    )
  }
  let anchor = pair.map(n => tool_call_anchor(n))
  let cls = if failed.contains(call.id) {
    "tool-call tool-call-failed"
  } else {
    "tool-call"
  }
  let original = pretty_json(call.arguments)
  if is_blank_args(original) {
    return @html.div(id?=anchor, class=cls) <| [
      @html.div(class="tool-call-name") <| name_row,
    ]
  }
  let rendered = match plan_steps {
    Some(steps) => plan_args_view(steps, plans.get(call.id))
    None => render_args_friendly(call.name, call.arguments)
  }
  // A plan is the task's live state, not noisy arguments: its card starts
  // unfolded (still collapsible), where every other call folds by default.
  let open_by_default : Bool? = if plan_steps is Some(_) {
    Some(true)
  } else {
    None
  }
  @html.details(open?=open_by_default, id?=anchor, class=cls) <| [
    @html.summary(class="tool-call-name") <| name_row,
    rendered,
    @html.pre(class="tool-call-args tool-call-args-original") <| original,
  ]
}

///|
/// The human-friendly rendering of a tool call's arguments: one row per field,
/// with the value shown verbatim rather than as a quoted-and-escaped JSON string,
/// so a `write_file` body or a `bash` command reads as plain text. Falls back to
/// the pretty-printed JSON (in the same hidden-on-toggle block) when the arguments
/// are not a JSON object — a bare value, an array, or text the model emitted that
/// does not parse.
fn render_args_friendly(tool_name : String, raw : String) -> @html.Html {
  let json = @json.parse(raw) catch {
    _ => return @html.pre(class="tool-call-args tool-call-args-rendered") <| raw
  }
  // For the edit tools, synthesize a `generated_diff` field so the change reads
  // as a diff without hunting through separate old_string / new_string fields.
  // The original fields are kept; the raw JSON (Original toggle) is untouched.
  let json = augment_with_diffs(tool_name, json)
  match json {
    Object(fields) if !fields.is_empty() => {
      let rows : Array[@html.Html] = [
        for key, value in fields => arg_field(key, value)
      ]
      @html.div(class="tool-call-args-rendered") <| rows
    }
    _ =>
      @html.pre(class="tool-call-args tool-call-args-rendered") <| pretty_json(
        raw,
      )
  }
}

///|
/// One `key: value` row of the friendly arguments view. String values render
/// verbatim — a multi-line value (e.g. a file body) as a preformatted block, a
/// single-line value inline. Non-string scalars render inline; nested arrays and
/// objects keep their JSON form, which is rare for tool arguments.
fn arg_field(key : String, value : Json) -> @html.Html {
  // A synthesized `generated_diff` string renders as a colored diff block; every
  // other field uses the generic recursive rendering.
  let value_html = match value {
    String(text) if key == "generated_diff" => diff_block(text)
    _ => render_value(value)
  }
  @html.div(class="arg-field") <| [
    @html.span(class="arg-key") <| key,
    value_html,
  ]
}

///|
/// Add a synthesized `generated_diff` field to the arguments of the edit tools,
/// leaving every other tool (and the raw JSON) untouched. `edit` gains one
/// top-level diff; `multi_edit` gains one per edit inside its `edits` array. The
/// parsed JSON is mutated in place — it is a throwaway parse used only to render
/// the friendly view, never the stored arguments.
fn augment_with_diffs(tool_name : String, json : Json) -> Json {
  match tool_name {
    "edit" => add_edit_diff(json)
    "multi_edit" => {
      if json is { "edits": Array(items), .. } {
        for item in items {
          add_edit_diff(item) |> ignore
        }
      }
      json
    }
    _ => json
  }
}

///|
/// Add a `generated_diff` field to one edit-shaped object (in place), derived
/// from its `old_string` / `new_string`. Leaves the object unchanged when those
/// are absent, not strings, or equal (a no-op the tool would reject anyway).
fn add_edit_diff(json : Json) -> Json {
  guard json is Object(fields) else { return json }
  guard json is { "old_string": String(old), "new_string": String(new), .. } else {
    return json
  }
  if old != new {
    fields["generated_diff"] = Json::string(generate_diff(old, new))
  }
  json
}

///|
/// A line-oriented diff of `old` → `new`: shared leading/trailing lines are
/// context (`  `), the differing middle is removed (`- `) then added (`+ `). An
/// insertion (empty `old`) is all `+` lines; a deletion (empty `new`) all `-`.
fn generate_diff(old : String, new : String) -> String {
  if old == "" {
    return prefix_lines(new, "+ ")
  }
  if new == "" {
    return prefix_lines(old, "- ")
  }
  let old_lines = string_lines(old)
  let new_lines = string_lines(new)
  let n = old_lines.length()
  let m = new_lines.length()
  let mut pre = 0
  while pre < n && pre < m && old_lines[pre] == new_lines[pre] {
    pre += 1
  }
  let mut suf = 0
  while suf < n - pre &&
        suf < m - pre &&
        old_lines[n - 1 - suf] == new_lines[m - 1 - suf] {
    suf += 1
  }
  [
    ..[
      for line in old_lines[:pre] => "  " + line
    ],
    ..[
      for line in old_lines[pre:n - suf] => "- " + line
    ],
    ..[
      for line in new_lines[pre:m - suf] => "+ " + line
    ],
    ..[
      for line in old_lines[n - suf:] => "  " + line
    ],
  ].join("\n")
}

///|
/// Split `text` into lines on `\n`.
fn string_lines(text : String) -> Array[String] {
  text.split("\n").map(line => line.to_owned()).collect()
}

///|
/// Prefix every line of `text` with `marker` (for all-added / all-removed diffs).
fn prefix_lines(text : String, marker : String) -> String {
  string_lines(text).map(line => marker + line).join("\n")
}

///|
/// Render a synthesized diff string as colored lines: `+ ` added (green), `- `
/// removed (red), anything else context (muted). Shown verbatim, monospace.
fn diff_block(text : String) -> @html.Html {
  let lines : Array[@html.Html] = [
    for raw in text.split("\n") => {
      let line = raw.to_owned()
      let cls = if line.has_prefix("+ ") {
        "diff-add"
      } else if line.has_prefix("- ") {
        "diff-del"
      } else {
        "diff-ctx"
      }
      @html.div(class=cls) <| line
    }
  ]
  @html.div(class="arg-value diff-block") <| lines
}

///|
/// Render a JSON value in the friendly view, recursing into nested objects and
/// arrays rather than dumping them as one escaped `stringify` blob. A string
/// leaf shows verbatim — a multi-line body (e.g. a `write_file` content) as a
/// preformatted block, otherwise inline. A nested object becomes an indented
/// block of the same `key: value` rows; an array becomes a list of rendered
/// items; other scalars render inline. Empty containers collapse to `{}` / `[]`.
fn render_value(value : Json) -> @html.Html {
  match value {
    String(text) =>
      if text.contains("\n") {
        @html.pre(class="arg-value") <| text
      } else {
        @html.span(class="arg-value-inline") <| text
      }
    Object(fields) if !fields.is_empty() =>
      @html.div(class="arg-object") <| [
        for key, field in fields => arg_field(key, field)
      ]
    Array(items) if !items.is_empty() =>
      @html.div(class="arg-array") <| [
        for item in items => @html.div(class="arg-item") <| render_value(item)
      ]
    Object(_) => @html.span(class="arg-value-inline") <| "{}"
    Array(_) => @html.span(class="arg-value-inline") <| "[]"
    scalar => @html.span(class="arg-value-inline") <| scalar_text(scalar)
  }
}

///|
/// A JSON scalar as the plain text to show inline. Numbers keep their original
/// source spelling when the parser preserved it.
fn scalar_text(value : Json) -> String {
  match value {
    True => "true"
    False => "false"
    Null => "null"
    Number(n, repr~) =>
      match repr {
        Some(text) => text
        None => n.to_string()
      }
    String(text) => text
    other => other.stringify()
  }
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
  tags : Map[String, Int],
) -> @html.Html {
  let is_error = result.is_error()
  let kind = if is_error { "tool error" } else { "tool" }
  let label = if is_error {
    "Tool error · \{result.tool_name()}"
  } else {
    "Tool result · \{result.tool_name()}"
  }
  let flag = failed_flag(is_error)
  // Pair this result back to the call that produced it (same `call N` tag).
  // The pair anchor wins the element's single id (the cross-link targets
  // it); an unpaired result anchors at its sequence like every other card —
  // scroll restore only needs a nearby anchor, not one on every card.
  let pair = tags.get(result.tool_call_id())
  let link = result_back_link(pair)
  let anchor = match pair {
    Some(n) => tool_result_anchor(n)
    None => seq_anchor(seq)
  }
  @html.details(id=anchor, class="card \{kind}") <| [
    @html.summary(class="card-label") <| card_head(
      label,
      seq,
      time~,
      flag~,
      link~,
    ),
    @html.div(class="card-body") <| [
      text_block(result.content()),
    ],
  ]
}

///|
/// The red flag a failed tool result shows while its card is still collapsed;
/// nothing for a success.
fn failed_flag(is_error : Bool) -> @html.Html {
  if is_error {
    @html.span(class="tool-flag") <| "🚩 failed"
  } else {
    @html.nothing
  }
}

///|
/// The `call N` chip on a result card, linking back to the originating call;
/// nothing for an unpaired result.
fn result_back_link(pair : Int?) -> @html.Html {
  match pair {
    Some(n) =>
      pair_link(
        n,
        href="#\{tool_call_anchor(n)}",
        title="Jump to the originating call (call \{n})",
      )
    None => @html.nothing
  }
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
  let body : Array[@html.Html] = [
    @html.span(class="badge badge-\{kind}") <| kind,
  ]
  if !message.trim().is_empty() {
    body.push(text_block(message))
  }
  card("terminal", "Turn ended", seq, time~, body, step_label~)
}

// ---- step scrubber -----------------------------------------------------------

///|
/// A click-to-jump scrubber over the session's agent steps: one segment per
/// step in log order, each carrying `data-seq` (the step event's durable
/// sequence) so the shell can scroll to — or near — its card via the `seq-N`
/// anchors. A segment is error-tinted when a failed tool result lands in
/// that step's range, so failure clusters are visible on the bar itself.
/// Renders nothing for sessions with fewer than two steps.
pub fn step_scrubber(session : @agent_session.Session) -> @html.Html {
  let seqs = agent_step_sequences(session)
  let total = seqs.length()
  if total < 2 {
    return @html.nothing
  }
  let flagged = steps_with_errors(session, seqs)
  // Labels ride a data attribute, not `title`: the shell shows them in an
  // instant tooltip that follows the pointer across the bar, where a native
  // title tooltip only appears after the OS hover delay (and would double up
  // with the custom one).
  @html.div(class="step-scrubber") <| [
    for index, seq in seqs => {
      let (cls, label) = if flagged.contains(index) {
        ("step-seg has-error", "Step \{index + 1}/\{total} · has failures")
      } else {
        ("step-seg", "Step \{index + 1}/\{total}")
      }
      @html.span(
        class=cls,
        attrs=@html.Attrs::build()
          .data_set("seq", "\{seq}")
          .data_set("label", label),
      ) <| ""
    }
  ]
}

///|
/// Indices of steps whose range — from the step's own event up to (but not
/// including) the next step's — contains a failed tool result. Results are
/// appended after the assistant step that called them, so the owning step is
/// the last one at or before the error.
fn steps_with_errors(
  session : @agent_session.Session,
  seqs : Array[Int],
) -> Map[Int, Unit] {
  let flagged : Map[Int, Unit] = Map([])
  for event in session.events() {
    guard event.item() is Tool(result) && result.is_error() else { continue }
    for index = seqs.length() - 1; index >= 0; index = index - 1 {
      if seqs[index] <= event.sequence() {
        flagged.set(index, ())
        break
      }
    }
  }
  flagged
}

// ---- model projection view -------------------------------------------------

///|
fn render_model(session : @agent_session.Session) -> @html.Html {
  // The projection keys each tool message only by id and drops is_error / tool
  // name, so recover them from the durable events for display (the messages fed
  // to the model are unchanged — this is view-only enrichment).
  let tool_results = tool_results_by_id(session)
  let messages = session.chat_messages()
  let failed = model_failed_call_ids(messages, tool_results)
  let time_labels = model_message_time_labels(session)
  let step_labels = model_message_step_labels(session)
  // Model-view briefs must come only from results the projection actually
  // emitted and the view trusts (see `model_shown_result`); using every durable
  // brief would caption a healed/compacted call with a result the model never
  // saw. The raw view, which shows every event, uses all briefs.
  let briefs = model_tool_call_briefs(messages, tool_results)
  let tags = model_pair_tags(messages)
  let plans = model_plan_baselines(messages, failed)
  let anchor_seqs = model_message_anchor_seqs(session)
  let cards : Array[@html.Html] = [
    for index, message in messages => {
      let time = time_labels.get(index).unwrap_or("")
      let step_label = step_labels.get(index).unwrap_or("")
      let anchor = match anchor_seqs.get(index) {
        Some(seq) if !seq.is_empty() => Some("seq-\{seq}")
        _ => None
      }
      message_card(
        message,
        tool_results,
        failed,
        briefs,
        tags,
        plans,
        time~,
        step_label~,
        anchor~,
      )
    }
  ]
  if cards.is_empty() {
    return empty_state("The model projection is empty.")
  }
  @html.div(class="log model-log") <| cards
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
      labels.set(event.sequence(), offset_label(base, event))
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
  for index, id in pending {
    if id == tool_call_id {
      ignore(pending.remove(index))
      return true
    }
  }
  false
}

///|
fn flush_pending_tool_labels(
  pending : Array[String],
  labels : Array[String],
) -> Unit {
  for _ in pending {
    // Synthetic repair messages are not backed by a durable event, so they do
    // not get a timestamp/step label.
    labels.push("")
  }
  pending.clear()
}

///|
fn terminal_projects_model_message(
  terminal : @agent_session.TurnTerminal,
) -> Bool {
  match terminal {
    // Mirrors Session::chat_messages exactly: blank answers and synthetic
    // context-yield terminals never reach the model, so they must not
    // consume a model-view label either — one extra label here shifts
    // every later timestamp/step chip after a continued yield.
    Finished(answer) =>
      !answer.trim().is_empty() &&
      !answer.has_prefix(@agent_session.ContextYieldAnswerPrefix)
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
  let label_of = (event : @agent_session.SessionEvent) => {
    event_label(labels, event)
  }
  model_message_labels(session, label_of~, tool_label_of=label_of)
}

///|
/// Step labels parallel to `Session::chat_messages()`. Only model-backed
/// assistant events get a label; terminal answers and synthetic healed tool
/// results may project as model messages, but they are not agent-loop steps.
fn model_message_step_labels(session : @agent_session.Session) -> Array[String] {
  let steps = agent_step_labels(session)
  model_message_labels(session, label_of=event => event_label(steps, event), tool_label_of=_ => {
    ""
  })
}

///|
/// Durable sequence numbers parallel to `Session::chat_messages()`, as anchor
/// strings: every event-backed message gets its event's sequence, while the
/// system prompt and synthetic repair messages (which have no durable event
/// to anchor at) get `""`.
fn model_message_anchor_seqs(session : @agent_session.Session) -> Array[String] {
  let seq_of = (event : @agent_session.SessionEvent) => "\{event.sequence()}"
  model_message_labels(session, label_of=seq_of, tool_label_of=seq_of)
}

///|
/// One label per projected model message, parallel to
/// `Session::chat_messages()`: the first system prompt has no backing event and
/// gets `""`, each event-backed message gets `label_of` for its event —
/// `tool_label_of` for a tool result — and each synthetic repair message gets
/// `""` (see `flush_pending_tool_labels`). This walker must mirror the
/// projection's message order exactly; one extra or missing label shifts every
/// later chip.
fn model_message_labels(
  session : @agent_session.Session,
  label_of~ : (@agent_session.SessionEvent) -> String,
  tool_label_of~ : (@agent_session.SessionEvent) -> String,
) -> Array[String] {
  let out : Array[String] = [""]
  let pending_tool_calls : Array[String] = []
  let events = session.events()
  for event in events {
    // Mirror `Session::chat_messages`: a surviving summary projects at the
    // start of its covered range, so its label lands there too.
    for candidate in events {
      if candidate.item() is Summary(summary) &&
        summary.from_sequence() == event.sequence() &&
        !model_event_covered_by_later_summary(candidate, events) {
        flush_pending_tool_labels(pending_tool_calls, out)
        out.push(label_of(candidate))
      }
    }
    if model_event_covered_by_later_summary(event, events) {
      continue
    }
    match event.item() {
      // Labeled above at the start of its covered range.
      Summary(_) => ()
      Assistant(message) => {
        flush_pending_tool_labels(pending_tool_calls, out)
        out.push(label_of(event))
        for call in message.tool_calls() {
          pending_tool_calls.push(call.id)
        }
      }
      Tool(result) =>
        if remove_pending_tool_id(pending_tool_calls, result.tool_call_id()) {
          out.push(tool_label_of(event))
        }
      item => {
        flush_pending_tool_labels(pending_tool_calls, out)
        if item_projects_model_message(item) {
          out.push(label_of(event))
        }
      }
    }
  }
  flush_pending_tool_labels(pending_tool_calls, out)
  out
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
/// Ids of tool calls whose durable result errored — used to tag the call in the
/// raw view so "errors only" keeps its assistant card next to the error result.
fn raw_failed_call_ids(session : @agent_session.Session) -> Map[String, Unit] {
  let ids : Map[String, Unit] = Map([])
  for event in session.events() {
    if event.item() is Tool(result) && result.is_error() {
      ids.set(result.tool_call_id(), ())
    }
  }
  ids
}

// ---- tool call ↔ result pairing --------------------------------------------

///|
/// A stable 1-based "pair number" for each tool call, so the view can show the
/// same `call N` chip on a tool call and on its result and cross-link the two by
/// DOM anchor — the whole point being that one assistant turn can emit several
/// tool calls and, without this, the separate result cards read only as `Tool
/// result · <name>` with no visible tie back to which call produced them.
///
/// A number is assigned only to an id that forms an unambiguous 1:1 pair in the
/// rendered view: it must be non-empty and appear exactly once among the calls
/// AND exactly once among the results. That deliberately skips empty ids (a
/// streaming glitch can leave `id=""`), duplicate ids, orphan results (a result
/// with no matching call), and dangling calls (a call with no result) — so a chip
/// never links to a missing anchor and no DOM id is ever emitted twice. Numbers
/// run in call order for readability.
fn assign_pair_tags(
  call_ids : Array[String],
  result_ids : Array[String],
) -> Map[String, Int] {
  let call_counts = occurrence_counts(call_ids)
  let result_counts = occurrence_counts(result_ids)
  let tags : Map[String, Int] = Map([])
  let mut next = 1
  // A call_count of 1 means the id occurs exactly once in `call_ids`, so the loop
  // reaches each tagged id once and assigns it a unique number in call order.
  for id in call_ids {
    if id != "" &&
      call_counts.get(id).unwrap_or(0) == 1 &&
      result_counts.get(id).unwrap_or(0) == 1 {
      tags.set(id, next)
      next += 1
    }
  }
  tags
}

///|
/// How many times each id occurs in `ids`.
fn occurrence_counts(ids : Array[String]) -> Map[String, Int] {
  let counts : Map[String, Int] = Map([])
  for id in ids {
    counts.set(id, counts.get(id).unwrap_or(0) + 1)
  }
  counts
}

///|
/// Pair numbers for the raw view, drawn from every durable event it renders.
fn raw_pair_tags(session : @agent_session.Session) -> Map[String, Int] {
  let call_ids : Array[String] = []
  let result_ids : Array[String] = []
  for event in session.events() {
    match event.item() {
      Assistant(message) =>
        for call in message.tool_calls() {
          call_ids.push(call.id)
        }
      Tool(result) => result_ids.push(result.tool_call_id())
      _ => ()
    }
  }
  assign_pair_tags(call_ids, result_ids)
}

///|
/// Pair numbers for the model view, drawn from the projected messages it renders
/// (so a healed synthetic tool message is a valid result partner, and a call
/// compacted away contributes nothing). Only the structural id feeds this — the
/// error flag, tool name, and brief still come solely through `model_shown_result`.
fn model_pair_tags(messages : Array[@deepseek.ChatMessage]) -> Map[String, Int] {
  let call_ids : Array[String] = []
  let result_ids : Array[String] = []
  for message in messages {
    for call in message.tool_calls {
      call_ids.push(call.id)
    }
    if message.role is Tool(id) {
      result_ids.push(id)
    }
  }
  assign_pair_tags(call_ids, result_ids)
}

///|
/// DOM anchor id for a tool call, keyed by pair number.
fn tool_call_anchor(n : Int) -> String {
  "tool-call-\{n}"
}

///|
/// DOM anchor id for a tool result, keyed by pair number.
fn tool_result_anchor(n : Int) -> String {
  "tool-result-\{n}"
}

///|
/// The `call N` chip shown on both a tool call and its result. It is an anchor
/// that jumps to its partner (`href`), so clicking the chip on a call scrolls to
/// its result card and vice versa; `title` states the direction.
fn pair_link(n : Int, href~ : String, title~ : String) -> @html.Html {
  @html.a(class="tool-link", href~, title~) <| "call \{n}"
}

///|
/// Ids of tool calls whose result the model view both showed and saw fail (see
/// `model_shown_result`). Mirrors the model view's error cards so a tagged call
/// always has a matching error result on screen — a compacted-away failure tags
/// nothing, just as it draws no error card.
fn model_failed_call_ids(
  messages : Array[@deepseek.ChatMessage],
  tool_results : Map[String, @agent_session.ToolResult],
) -> Map[String, Unit] {
  let ids : Map[String, Unit] = Map([])
  for message in messages {
    guard message.role is Tool(id) else { continue }
    if model_shown_result(message, tool_results) is Some(result) &&
      result.is_error() {
      ids.set(id, ())
    }
  }
  ids
}

///|
fn message_card(
  message : @deepseek.ChatMessage,
  tool_results : Map[String, @agent_session.ToolResult],
  failed : Map[String, Unit],
  briefs : Map[String, String],
  tags : Map[String, Int],
  plans : Map[String, Array[@steps.PlanStep]],
  time~ : String,
  step_label~ : String,
  anchor~ : String?,
) -> @html.Html {
  match message.role {
    System =>
      @html.section(class="card system") <| [
        @html.details(open=false) <| [
          @html.summary(class="card-label") <| model_card_head(
            "System prompt",
            time~,
          ),
          text_block(message.content),
        ],
      ]
    User =>
      model_card(
        "user",
        "User",
        message,
        briefs,
        failed,
        tags,
        plans,
        time~,
        step_label~,
        anchor~,
      )
    Assistant =>
      model_card(
        "assistant",
        "Assistant",
        message,
        briefs,
        failed,
        tags,
        plans,
        time~,
        step_label~,
        anchor~,
      )
    Tool(_) =>
      model_tool_card(
        message,
        model_shown_result(message, tool_results),
        tags,
        time~,
        anchor~,
      )
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
      session
      .events()
      .iter()
      .count_if(event => event.item() is Tool(result) && result.is_error())
    ModelView => {
      let tool_results = tool_results_by_id(session)
      session
      .chat_messages()
      .count_if(message => {
        model_shown_result(message, tool_results) is Some(result) &&
        result.is_error()
      })
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
  tags : Map[String, Int],
  time~ : String,
  anchor~ : String?,
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
  // The pair tag comes from the message's own id (structural), independent of
  // whether `model_shown_result` trusts the durable result for enrichment.
  // Like the raw view, the pair anchor wins the element's single id; the
  // sequence anchor is the fallback for unpaired results.
  let pair = match message.role {
    Tool(id) => tags.get(id)
    _ => None
  }
  let link = result_back_link(pair)
  let anchor = match pair {
    Some(n) => Some(tool_result_anchor(n))
    None => anchor
  }
  @html.details(id?=anchor, class="card \{kind}") <| [
    @html.summary(class="card-label") <| model_card_head(
      label,
      time~,
      flag=failed_flag(is_error),
      link~,
    ),
    @html.div(class="card-body") <| [
      text_block(message.content),
    ],
  ]
}

///|
fn model_card(
  kind : String,
  label : String,
  message : @deepseek.ChatMessage,
  briefs : Map[String, String],
  failed : Map[String, Unit],
  tags : Map[String, Int],
  plans : Map[String, Array[@steps.PlanStep]],
  time~ : String,
  step_label~ : String,
  anchor~ : String?,
) -> @html.Html {
  let body : Array[@html.Html] = []
  if message.reasoning_content is Some(reasoning) &&
    !reasoning.trim().is_empty() {
    body.push(
      @html.details(class="reasoning") <| [
        @html.summary("reasoning"),
        text_block(reasoning),
      ],
    )
  }
  if !message.content.trim().is_empty() {
    body.push(text_block(message.content))
  }
  if !message.tool_calls.is_empty() {
    let call_views : Array[@html.Html] = [
      for call in message.tool_calls => {
        tool_call_view(call, briefs, failed, tags, plans)
      }
    ]
    body.push(@html.div(class="tool-calls") <| call_views)
  }
  @html.section(id?=anchor, class="card \{kind}") <| [
    @html.div(class="card-label") <| model_card_head(label, time~, step_label~),
    @html.div(class="card-body") <| body,
  ]
}

// ---- shared helpers --------------------------------------------------------

///|
fn model_card_head(
  label : String,
  time~ : String,
  flag? : @html.Html = @html.nothing,
  link? : @html.Html = @html.nothing,
  step_label? : String = "",
) -> Array[@html.Html] {
  let head : Array[@html.Html] = [flag, @html.text(label), link]
  if !step_label.is_empty() {
    head.push(@html.span(class="card-step") <| step_label)
  }
  if !time.is_empty() {
    head.push(@html.span(class="card-ts") <| time)
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
  // Every raw-view card anchors at its durable sequence: the id is what the
  // shell's scrollspy/restore and the step scrubber navigate by, and the
  // sequence is stable across refreshes because it comes from the
  // append-only log.
  @html.section(id=seq_anchor(seq), class="card \{kind}") <| [
    @html.div(class="card-label") <| card_head(label, seq, time~, step_label~),
    @html.div(class="card-body") <| body,
  ]
}

///|
/// DOM anchor id for the card of the event with durable sequence `seq`.
fn seq_anchor(seq : Int) -> String {
  "seq-\{seq}"
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
  link? : @html.Html = @html.nothing,
  step_label? : String = "",
) -> Array[@html.Html] {
  [
    @html.span(class="card-seq") <| "#\{seq}",
    ..model_card_head(label, time~, flag~, link~, step_label~),
  ]
}

///|
/// A whitespace-preserving text block. Empty content renders an explicit
/// placeholder so a card never collapses to nothing.
fn text_block(content : String) -> @html.Html {
  if content.trim().is_empty() {
    @html.span(class="empty") <| "(empty)"
  } else {
    @html.pre(class="content") <| content
  }
}

///|
fn empty_state(message : String) -> @html.Html {
  @html.div(class="empty-state") <| [
    @html.text(message),
  ]
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

///|
test "one_line collapses newlines and trims whitespace" {
  assert_eq(one_line("  alpha\nbeta  "), "alpha beta")
}

///|
test "truncate caps by character without splitting surrogate pairs" {
  assert_eq(truncate("hello world", 5), "hello…")
  assert_eq(truncate("a🤣b", 2), "a🤣…")
}
