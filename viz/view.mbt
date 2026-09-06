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
  subrun_children? : Map[String, @agent_session.Session] = Map([]),
) -> @html.Html {
  let subrun = SubrunView::{
    parent: session.id().value(),
    children: subrun_children,
    // A child opened on its own (from the sidebar, or a `#s=` link) is only
    // recognizable by the id shape the sub-run runner mints.
    delegated: is_subrun_session_id(session.id().value()),
  }
  match mode {
    RawLog => render_raw(session, subrun)
    ModelView => render_model(session, subrun)
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
fn render_raw(
  session : @agent_session.Session,
  subrun : SubrunView,
) -> @html.Html {
  let briefs = tool_call_briefs(session)
  let failed = raw_failed_call_ids(session)
  let tags = raw_pair_tags(session)
  let escalated = raw_escalated_result_ids(session, tags)
  let plans = raw_plan_baselines(session, failed)
  let step_labels = agent_step_labels(session)
  let turns = group_turns(session.events())
  if turns.is_empty() {
    return empty_state("This session has no events yet.")
  }
  let blocks : Array[@html.Html] = [prompt_rail(session, subrun)]
  for index, turn in turns {
    blocks.push(
      turn_block(
        index + 1,
        turn,
        briefs,
        failed,
        escalated,
        tags,
        plans,
        step_labels,
        subrun,
      ),
    )
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
/// emits while running. Each current-format provider response has one
/// non-replay `Assistant` event, whose sequence gives the stable step label.
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
  [
    for event in session.events() if event.is_agent_step() => event.sequence()
  ]
}

///|
fn turn_block(
  number : Int,
  turn : Array[@agent_session.SessionEvent],
  briefs : Map[String, String],
  failed : Map[String, Unit],
  escalated : Map[String, Unit],
  tags : Map[String, Int],
  plans : Map[String, Array[@steps.PlanStep]],
  step_labels : Map[Int, String],
  subrun : SubrunView,
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
        escalated,
        tags,
        plans,
        step_label=step_labels.get(event.sequence()).unwrap_or(""),
        subrun,
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
  // Same reason for steering: a mid-turn interjection can redirect the whole
  // turn, and it is the one thing in the turn the user wrote themselves.
  let steers = if subrun.delegated { 0 } else { count_turn_steers(turn) }
  if steers > 0 {
    summary.push(
      @html.span(class="turn-steer-badge") <| " · ✋ \{steers} steer\{plural(steers)}",
    )
  }
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
/// The turn header's one-line preview: what opened the turn. A turn the
/// engine relaunched on a standing goal always opens with the same boilerplate
/// prompt, so it is named for what it is instead of spending the header on 80
/// characters every such turn repeats.
fn turn_preview(turn : Array[@agent_session.SessionEvent]) -> String {
  for event in turn {
    if event.item() is User(message) {
      return if message.content() == @agent_session.GoalContinuePrompt {
        "↻ auto-continue"
      } else {
        truncate(one_line(message.content()), 80)
      }
    }
  }
  "\{turn.length()} events"
}

///|
test "an auto-continued turn is named rather than previewed" {
  let session = @agent_session.Session(SessionId("t"), system_prompt="")
    .append(User(UserMessage(@agent_session.GoalContinuePrompt)))
    .append(Terminal(Finished("done")))
    .append(User(UserMessage("now do the other thing")))
    .append(Terminal(Finished("done again")))
  let turns = group_turns(session.events())
  inspect(turn_preview(turns[0]), content="↻ auto-continue")
  inspect(turn_preview(turns[1]), content="now do the other thing")
}

///|
test "the turn header counts only the steers a person typed" {
  let session = @agent_session.Session(SessionId("t"), system_prompt="")
    .append(User(UserMessage("start")))
    .append(Assistant(AssistantMessage("working")))
    .append(User(UserMessage("actually, also this")))
    .append(User(UserMessage(@agent_session.GoalContinuePrompt)))
    .append(Terminal(Finished("done")))
  let turns = group_turns(session.events())
  // The opening prompt is not a steer, and the engine's prompt never is.
  inspect(count_turn_steers(turns[0]), content="1")
}

///|
/// Mid-turn steering: `User` events after the one that opened the turn that a
/// person actually typed. A collapsed turn hides its cards, so the header
/// carries a count — without it, an interjection that redirected a whole turn
/// is invisible until the turn is expanded.
fn count_turn_steers(turn : Array[@agent_session.SessionEvent]) -> Int {
  let mut steers = 0
  let mut seen_first = false
  for event in turn {
    guard event.item() is User(message) else { continue }
    if !seen_first {
      seen_first = true
      continue
    }
    if user_input(message.content(), delegated=false) is Typed {
      steers += 1
    }
  }
  steers
}

///|
/// Who actually wrote a user-role message.
///
/// Everything the engine replays to the model as a user turn lands in the log
/// as a `User` event, but only some of it is a person's own words: a standing
/// goal relaunches turns with `GoalContinuePrompt`, and a sub-run child's
/// opening task is written by the agent that spawned it. Captioning all three
/// "You" would put words in the reader's mouth — in a goal-driven session most
/// `User` events are auto-continuations.
priv enum UserInput {
  /// A prompt or mid-turn steer a person typed.
  Typed
  /// The exact prompt serve submits to open an auto-continuation turn.
  AutoContinue
  /// The task a parent agent handed a sub-run child.
  Delegated
}

///|
/// Classify one user-role message. `delegated` is a property of the session
/// being rendered, not of the text, so it decides first.
fn user_input(content : String, delegated~ : Bool) -> UserInput {
  if delegated {
    Delegated
  } else if content == @agent_session.GoalContinuePrompt {
    AutoContinue
  } else {
    Typed
  }
}

///|
/// Card class and caption for a user-role message. Only `Typed` gets the
/// `typed` raised card the stylesheet elevates and sets in bold type.
fn UserInput::card_style(self : UserInput) -> (String, String) {
  match self {
    Typed => ("user typed", "You")
    AutoContinue => ("user auto-continue", "Auto-continue")
    Delegated => ("user delegated", "Task from parent")
  }
}

///|
/// Card class and caption for a model-view user-role message, which the
/// projection feeds from three different durable items. A runtime notice or a
/// summary keeps the class the raw log gives it, so the same event reads the
/// same way in both views.
fn user_role_card_style(
  content : String,
  origin~ : MessageOrigin,
  delegated~ : Bool,
) -> (String, String) {
  match origin {
    FromRuntime => ("runtime", "Runtime notice")
    FromSummary(from~, to~) => ("summary", summary_label(from~, to~))
    // `Other` cannot reach a user-role card: the projection only synthesizes
    // assistant and tool messages. Classifying it as input is the honest
    // fallback if that ever changes — it says no more than the role does.
    FromUser | Other => user_input(content, delegated~).card_style()
  }
}

///|
/// The engine's auto-continuation prompt is matched against the exact constant
/// serve submits, so rewording it stops the match instead of silently
/// captioning engine text as the user's.
test "user cards name who actually wrote the message" {
  fn caption(content : String, delegated : Bool) -> String {
    let (kind, label) = user_input(content, delegated~).card_style()
    "\{kind} · \{label}"
  }

  inspect(caption("ship the feature", false), content="user typed · You")
  inspect(
    caption(@agent_session.GoalContinuePrompt, false),
    content="user auto-continue · Auto-continue",
  )
  // Text that only resembles the engine's prompt is still the user's own.
  inspect(
    caption("Continue working toward the standing goal.", false),
    content="user typed · You",
  )
  // A sub-run child's prompt is its parent agent's task, whatever it says.
  inspect(
    caption("survey the parser", true),
    content="user delegated · Task from parent",
  )
}

///|
fn event_card(
  event : @agent_session.SessionEvent,
  time~ : String,
  briefs : Map[String, String],
  failed : Map[String, Unit],
  escalated : Map[String, Unit],
  tags : Map[String, Int],
  plans : Map[String, Array[@steps.PlanStep]],
  step_label~ : String,
  subrun : SubrunView,
) -> @html.Html {
  let seq = event.sequence()
  match event.item() {
    User(message) => {
      let (kind, label) = user_input(
        message.content(),
        delegated=subrun.delegated,
      ).card_style()
      card(kind, label, seq, time~, [text_block(message.content())])
    }
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
    Tool(result) => tool_card(seq, time, result, escalated, tags, subrun)
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
/// Split text into line views for structured transcript notices.
fn string_lines(text : String) -> Array[StringView] {
  [..text.split("\n")]
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
        for step in lines[index + 1:] if !step.is_blank() => step.to_owned()
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
  if message.reasoning_content() is Some(reasoning) && !reasoning.is_blank() {
    body.push(
      @html.details(class="reasoning") <| [
        @html.summary("reasoning"),
        text_block(reasoning),
      ],
    )
  }
  if !message.content().is_blank() {
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
  if briefs.get(call.id) is Some(brief) && !brief.is_blank() {
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
  let cls = match (failed.contains(call.id), tool_call_is_escalated(call)) {
    (false, false) => "tool-call"
    (true, false) => "tool-call tool-call-failed"
    (false, true) => "tool-call tool-call-escalated"
    (true, true) => "tool-call tool-call-failed tool-call-escalated"
  }
  // A failed mbtx call names its STAGE — a build error is fixed in the
  // source, a runtime error in the program's behavior. A build-failed row
  // says it through its own brief, which already reads "build failed" /
  // "build timeout": appending a word there repeated the brief verbatim
  // ("· mbtx (build failed, exit=1) build error"), so the stage rides the
  // class alone and the stylesheet turns the brief amber. The runtime word
  // stays — "exit=1" never names the stage.
  let build_failed = tool_call_is_build_failed(call, briefs, failed, tags)
  let run_failed = !build_failed &&
    tool_call_is_run_failed(call, briefs, failed, tags)
  let cls = if build_failed {
    "\{cls} tool-call-build-failed"
  } else if run_failed {
    "\{cls} tool-call-run-failed"
  } else {
    cls
  }
  if run_failed {
    name_row.push(
      @html.span(class="tool-stage tool-stage-run") <| " runtime error",
    )
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
  let open_by_default = plan_steps.map(_ => true)
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
        for key, value in fields => arg_field(tool_name, key, value)
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
fn arg_field(tool_name : String, key : String, value : Json) -> @html.Html {
  // A synthesized `generated_diff` string renders as a colored diff block; every
  // other field uses the generic recursive rendering.
  let value_html = match value {
    String(text) if key == "generated_diff" => diff_block(text)
    // Numbered so the run's compiler diagnostics, which cite `line:column`
    // positions into this source, can be followed without counting lines.
    String(source) if tool_name == "mbtx" && key == "source" =>
      @html.pre(class="arg-value moonbit-source", [
        @syntax_html.moonbit_numbered_source(source),
      ])
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
    fields["generated_diff"] = Json(@edit_diff.generate(old, new))
  }
  json
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
        for key, field in fields => arg_field("", key, field)
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
  escalated : Map[String, Unit],
  tags : Map[String, Int],
  subrun : SubrunView,
) -> @html.Html {
  let is_error = result.is_error()
  let is_escalated = escalated.contains(result.tool_call_id())
  let kind = match (is_error, is_escalated) {
    (false, false) => "tool"
    (true, false) => "tool error"
    (false, true) => "tool escalated"
    (true, true) => "tool error escalated"
  }
  // Tag mbtx build failures so the build-errors-only filter keeps this result
  // card — the diagnostics live here — beside its originating call.
  let kind = if result_is_build_failed(result) {
    "\{kind} build-failed"
  } else {
    kind
  }
  let label = if is_error {
    "Tool error · \{result.tool_name()}"
  } else {
    "Tool result · \{result.tool_name()}"
  }
  let flag = result_flag(result)
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
  let summary = card_head(label, seq, time~, flag~, link~)
  let body : Array[@html.Html] = [
    tool_result_content(Some(result), result.content()),
  ]
  // A subrun result gets a chip to its child session and — when the caller
  // loaded that child — the transcript itself, nested inside this card.
  if subrun_child_id(result, subrun.parent) is Some(child_id) {
    summary.push(subrun_chip(child_id))
    if subrun.children.get(child_id) is Some(child) {
      body.push(subrun_transcript(child))
    }
  }
  @html.details(id=anchor, class="card \{kind}") <| [
    @html.summary(class="card-label") <| summary,
    @html.div(class="card-body") <| body,
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
/// The collapsed-card flag for a durable result: an mbtx build failure names
/// its stage (the fix lives in the source, not the program), every other
/// failure keeps the generic word. The run stage is deliberately not named
/// here — the result alone cannot see the call's target, and the call card
/// beside it already says it.
fn result_flag(result : @agent_session.ToolResult) -> @html.Html {
  if result_is_build_failed(result) {
    @html.span(class="tool-flag tool-stage-build") <| "🚩 build error"
  } else {
    failed_flag(result.is_error())
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
  let label = summary_label(
    from=summary.from_sequence(),
    to=summary.to_sequence(),
  )
  card("summary", label, seq, time~, [text_block(summary.content())])
}

///|
/// Caption for a compaction summary, shared by the raw log's card and the
/// model view's projection of the same event so the two cannot drift.
fn summary_label(from~ : Int, to~ : Int) -> String {
  "Summary · covers events \{from}..\{to}"
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
  if !message.is_blank() {
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
    for index in (seqs.length() - 1)>=..0 {
      if seqs[index] <= event.sequence() {
        flagged.set(index, ())
        break
      }
    }
  }
  flagged
}

// ---- prompt rail -----------------------------------------------------------

///|
/// One entry in the prompt navigator: a prompt the person actually typed,
/// with what a reader needs to decide whether to jump — when it was sent,
/// whether the work it started hit tool errors, and how the model's reply
/// opened.
priv struct PromptMark {
  seq : Int
  time : String
  text : String
  mut errors : Int
  mut reply : String
}

///|
/// The typed prompts of a session, in log order. Each mark's error count and
/// reply preview cover the span from its prompt up to the next typed prompt,
/// so a mid-turn steer owns the errors that followed it, not the whole
/// turn's. Replayed assistant events are skipped: the reply shown is the one
/// this prompt actually drew.
fn prompt_marks(
  session : @agent_session.Session,
  delegated~ : Bool,
) -> Array[PromptMark] {
  let marks : Array[PromptMark] = []
  for event in session.events() {
    match event.item() {
      User(message) =>
        if user_input(message.content(), delegated~) is Typed {
          marks.push({
            seq: event.sequence(),
            time: wall_clock_label(event.unix_ms()),
            text: message.content(),
            errors: 0,
            reply: "",
          })
        }
      Assistant(message) =>
        if !message.is_replay() &&
          !message.content().is_blank() &&
          marks.last() is Some(mark) &&
          mark.reply.is_empty() {
          mark.reply = message.content()
        }
      Tool(result) =>
        if result.is_error() && marks.last() is Some(mark) {
          mark.errors += 1
        }
      _ => ()
    }
  }
  marks
}

///|
/// A Codex-style prompt navigator: a slim column of tick marks riding the
/// log's left gutter, one per typed prompt. Hovering a tick raises the same
/// card the prompt itself wears — bold text, wall-clock stamp, an error
/// flag, the reply's opening — and clicking jumps to the prompt's card via
/// its `seq-` anchor, which both views share. Renders nothing when the
/// session has no typed prompts (a sub-run child's task is its parent's).
fn prompt_rail(
  session : @agent_session.Session,
  subrun : SubrunView,
) -> @html.Html {
  let marks = prompt_marks(session, delegated=subrun.delegated)
  guard !marks.is_empty() else { return @html.nothing }
  let items : Array[@html.Html] = [
    for mark in marks => {
      let preview : Array[@html.Html] = [
        @html.div(class="rail-preview-text") <| truncate(
          one_line(mark.text),
          220,
        ),
      ]
      if !mark.time.is_empty() {
        preview.push(@html.div(class="rail-preview-time") <| mark.time)
      }
      if mark.errors > 0 {
        preview.push(
          @html.div(class="rail-preview-errors") <| "had error\{plural(mark.errors)}",
        )
      }
      if !mark.reply.is_blank() {
        preview.push(
          @html.blockquote(class="rail-preview-reply") <| truncate(
            one_line(mark.reply),
            180,
          ),
        )
      }
      @html.a(class="rail-mark", href="#\{seq_anchor(mark.seq)}", [
        @html.span(class="rail-tick") <| "",
        @html.div(class="rail-preview") <| preview,
      ])
    }
  ]
  @html.nav(
    class="prompt-rail",
    attrs=@html.Attrs::build().aria_label("User prompts"),
  ) <| [
    @html.div(class="rail-marks") <| items,
  ]
}

///|
/// A unix-ms stamp as `YYYY-MM-DD HH:MM UTC` (the app header's spelling), or
/// `""` for the 0 sentinel of an event appended without a clock. Pure civil-
/// from-days arithmetic so the label is identical on every target and in
/// every test environment.
fn wall_clock_label(unix_ms : Int64) -> String {
  guard unix_ms > 0 else { return "" }
  let seconds = unix_ms / 1000
  let days = (seconds / 86400).to_int()
  let day_seconds = (seconds % 86400).to_int()
  let z = days + 719468
  let era = z / 146097
  let doe = z % 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let day = doy - (153 * mp + 2) / 5 + 1
  let month = if mp < 10 { mp + 3 } else { mp - 9 }
  let year = yoe + era * 400 + (if month <= 2 { 1 } else { 0 })
  let hour = day_seconds / 3600
  let minute = day_seconds % 3600 / 60
  "\{year}-\{pad2(month)}-\{pad2(day)} \{pad2(hour)}:\{pad2(minute)} UTC"
}

///|
/// Two-digit zero padding for the civil-time fields `wall_clock_label`
/// derives — month, day, hour and minute, so `n` is always in 0..=59. The
/// domain matters: `pad_start` pads the rendered text, so a negative would
/// come back as "-5" rather than a zero-padded field.
fn pad2(n : Int) -> String {
  n.to_string().pad_start(2, '0')
}

///|
test "wall_clock_label converts unix ms to a civil UTC stamp" {
  // 2026-09-02 02:41:05 UTC
  inspect(wall_clock_label(1788316865000), content="2026-09-02 02:41 UTC")
  // The unix epoch itself, exercising the year/month arithmetic at a boundary.
  inspect(wall_clock_label(31536000000), content="1971-01-01 00:00 UTC")
  // Events appended without a clock keep the 0 sentinel and get no stamp.
  inspect(wall_clock_label(0), content="")
}

///|
/// Marks segment the log by typed prompts: a steer's mark owns the errors
/// and the reply that followed it, and engine-authored user messages (the
/// auto-continue prompt) contribute no mark at all.
test "prompt_marks segments errors and replies by typed prompt" {
  let s = @agent_session.Session(SessionId("rail"), system_prompt="")
    .append(User(UserMessage("ship the feature")))
    .append(Assistant(AssistantMessage("Starting on it.")))
    .append(
      Tool(
        ToolResult(
          tool_call_id="c1",
          tool_name="shell",
          content="boom",
          is_error=true,
        ),
      ),
    )
    .append(User(UserMessage("also fix the docs")))
    .append(Assistant(AssistantMessage("Docs updated.")))
    .append(Terminal(Finished("done")))
    .append(User(UserMessage(@agent_session.GoalContinuePrompt)))
    .append(Terminal(Finished("done again")))
  let marks = prompt_marks(s, delegated=false)
  inspect(marks.length(), content="2")
  inspect(marks[0].text, content="ship the feature")
  inspect(marks[0].errors, content="1")
  inspect(marks[0].reply, content="Starting on it.")
  inspect(marks[1].errors, content="0")
  inspect(marks[1].reply, content="Docs updated.")
  // A sub-run child's user messages are its parent's task: no marks at all.
  inspect(prompt_marks(s, delegated=true).length(), content="0")
}

// ---- model projection view -------------------------------------------------

///|
fn render_model(
  session : @agent_session.Session,
  subrun : SubrunView,
) -> @html.Html {
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
  let escalated = model_escalated_result_ids(messages, tags)
  let plans = model_plan_baselines(messages, failed)
  let anchor_seqs = model_message_anchor_seqs(session)
  // The projection replays runtime notices and summaries as user-role
  // messages, so a card's caption comes from the durable item behind it.
  let origins = model_message_origins(session)
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
        escalated,
        briefs,
        tags,
        plans,
        subrun~,
        time~,
        step_label~,
        anchor~,
        origin=origins.get(index).unwrap_or(Other),
      )
    }
  ]
  if cards.is_empty() {
    return empty_state("The model projection is empty.")
  }
  let blocks : Array[@html.Html] = [prompt_rail(session, subrun)]
  blocks.append(cards)
  @html.div(class="log model-log") <| blocks
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
fn[T] flush_pending_tool_labels(
  pending : Array[String],
  labels : Array[T],
  unbacked~ : T,
) -> Unit {
  for _ in pending {
    // Synthetic repair messages are not backed by a durable event, so they do
    // not get a timestamp/step label.
    labels.push(unbacked)
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
      !answer.is_blank() &&
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
  model_message_labels(session, label_of~, tool_label_of=label_of, unbacked="")
}

///|
/// Step labels parallel to `Session::chat_messages()`. Only model-backed
/// assistant events get a label; terminal answers and synthetic healed tool
/// results may project as model messages, but they are not agent-loop steps.
fn model_message_step_labels(session : @agent_session.Session) -> Array[String] {
  let steps = agent_step_labels(session)
  model_message_labels(
    session,
    label_of=event => event_label(steps, event),
    tool_label_of=_ => "",
    unbacked="",
  )
}

///|
/// The durable item a projected model message came from.
///
/// The projection replays `User`, `Runtime` and `Summary` events alike as
/// user-role messages, so the model view cannot read "a person wrote this" off
/// a message's role — it asks here instead, and a goal marker or a compaction
/// summary keeps the caption the raw log gives it.
priv enum MessageOrigin {
  FromUser
  FromRuntime
  /// A compaction summary, carrying the range it covers so the model view can
  /// caption it exactly as the raw log's own card does.
  FromSummary(from~ : Int, to~ : Int)
  /// An assistant/tool/terminal event, or a message with no durable event at
  /// all: the system prompt and the projection's synthesized tool repairs.
  Other
}

///|
/// One origin per projected model message, parallel to
/// `Session::chat_messages()`.
fn model_message_origins(
  session : @agent_session.Session,
) -> Array[MessageOrigin] {
  let origin_of = (event : @agent_session.SessionEvent) => {
    match event.item() {
      User(_) => FromUser
      Runtime(_) => FromRuntime
      Summary(summary) =>
        FromSummary(from=summary.from_sequence(), to=summary.to_sequence())
      Assistant(_) | Tool(_) | Terminal(_) => Other
    }
  }
  model_message_labels(
    session,
    label_of=origin_of,
    tool_label_of=origin_of,
    unbacked=Other,
  )
}

///|
/// Durable sequence numbers parallel to `Session::chat_messages()`, as anchor
/// strings: every event-backed message gets its event's sequence, while the
/// system prompt and synthetic repair messages (which have no durable event
/// to anchor at) get `""`.
fn model_message_anchor_seqs(session : @agent_session.Session) -> Array[String] {
  let seq_of = (event : @agent_session.SessionEvent) => "\{event.sequence()}"
  model_message_labels(
    session,
    label_of=seq_of,
    tool_label_of=seq_of,
    unbacked="",
  )
}

///|
/// One label per projected model message, parallel to
/// `Session::chat_messages()`: the first system prompt has no backing event and
/// gets `""`, each event-backed message gets `label_of` for its event —
/// `tool_label_of` for a tool result — and each synthetic repair message gets
/// `""` (see `flush_pending_tool_labels`). This walker must mirror the
/// projection's message order exactly; one extra or missing label shifts every
/// later chip.
fn[T] model_message_labels(
  session : @agent_session.Session,
  label_of~ : (@agent_session.SessionEvent) -> T,
  tool_label_of~ : (@agent_session.SessionEvent) -> T,
  unbacked~ : T,
) -> Array[T] {
  let out : Array[T] = [unbacked]
  let pending_tool_calls : Array[String] = []
  let mut previous_assistant_answer : String? = None
  let events = session.events()
  for event in events {
    // Mirror `Session::chat_messages`: a surviving summary projects at the
    // start of its covered range, so its label lands there too.
    for candidate in events {
      if candidate.item() is Summary(summary) &&
        summary.from_sequence() == event.sequence() &&
        !model_event_covered_by_later_summary(candidate, events) {
        flush_pending_tool_labels(pending_tool_calls, out, unbacked~)
        out.push(label_of(candidate))
        previous_assistant_answer = None
      }
    }
    if model_event_covered_by_later_summary(event, events) {
      continue
    }
    match event.item() {
      // Labeled above at the start of its covered range.
      Summary(_) => ()
      Assistant(message) => {
        flush_pending_tool_labels(pending_tool_calls, out, unbacked~)
        out.push(label_of(event))
        previous_assistant_answer = Some(message.content())
        for call in message.tool_calls() {
          pending_tool_calls.push(call.id)
        }
      }
      Tool(result) =>
        if remove_pending_tool_id(pending_tool_calls, result.tool_call_id()) {
          out.push(tool_label_of(event))
          previous_assistant_answer = None
        }
      Terminal(terminal) => {
        if !pending_tool_calls.is_empty() {
          flush_pending_tool_labels(pending_tool_calls, out, unbacked~)
          previous_assistant_answer = None
        }
        let repeated_assistant_final = terminal is Finished(answer) &&
          previous_assistant_answer is Some(previous) &&
          previous == answer
        if terminal_projects_model_message(terminal) &&
          !repeated_assistant_final {
          out.push(label_of(event))
        }
        previous_assistant_answer = None
      }
      item => {
        flush_pending_tool_labels(pending_tool_calls, out, unbacked~)
        previous_assistant_answer = None
        if item_projects_model_message(item) {
          out.push(label_of(event))
        }
      }
    }
  }
  flush_pending_tool_labels(pending_tool_calls, out, unbacked~)
  out
}

///|
/// Everything the projection feeds the model as a user turn arrives with role
/// `User`, so captioning off the role alone would file a goal marker and a
/// compaction summary under the user's own words.
test "model-view user cards keep the caption of the event behind them" {
  let session = @agent_session.Session(
      SessionId("origins"),
      system_prompt="sys",
    )
    .append(Runtime(RuntimeNotice("\{@agent_session.GoalPrefix}\nship it")))
    .append(User(UserMessage("do the thing")))
    .append(Assistant(AssistantMessage("on it")))
    .append(
      Summary(SessionSummary(content="covered", from_sequence=1, to_sequence=3)),
    )
    .append(User(UserMessage(@agent_session.GoalContinuePrompt)))
    .append(
      Runtime(RuntimeNotice("\{@agent_session.GoalReminderPrefix}\nship it")),
    )
    .append(User(UserMessage("one more thing")))
    .append(Terminal(Finished("done")))
  let messages = session.chat_messages()
  let origins = model_message_origins(session)
  assert_eq(origins.length(), messages.length())
  let captions : Array[String] = []
  for index, message in messages {
    guard message.role is User else { continue }
    let (_, label) = user_role_card_style(
      message.content,
      origin=origins[index],
      delegated=false,
    )
    captions.push(label)
  }
  // The summary keeps the caption the raw log's own card gives it, range and
  // all, so the same event reads the same way in both views.
  debug_inspect(
    captions,
    content=(
      #|[
      #|  "Summary · covers events 1..3",
      #|  "Auto-continue",
      #|  "Runtime notice",
      #|  "You",
      #|]
    ),
  )
}

///|
/// The origins array is only useful if it stays index-for-index with
/// `chat_messages()`, and one extra or missing entry silently shifts every
/// later caption instead of failing loudly. The projection's own invariant
/// pins that down: `User`, `Runtime` and `Summary` are exactly the items that
/// become user-role messages, so an origin from one of them must land on a
/// user-role message and nothing else may. Exercised against the cases the
/// walker special-cases — a summary projecting at the start of its covered
/// range, a dangling call healed with a synthetic result, a terminal
/// repeating the assistant's final answer, and a context-yield terminal that
/// projects no message at all.
test "message origins stay aligned with the projection" {
  let session = @agent_session.Session(
      SessionId("aligned"),
      system_prompt="sys",
    )
    .append(Runtime(RuntimeNotice("\{@agent_session.GoalPrefix}\nobjective")))
    .append(User(UserMessage("first")))
    .append(
      Assistant(
        AssistantMessage("calling", tool_calls=[
          ToolCall(id="dangling", name="shell", arguments="{}"),
        ]),
      ),
    )
    // No result for `dangling`: the projection heals it with a synthetic tool
    // message that no durable event backs.
    .append(Terminal(Finished("first answer")))
    .append(User(UserMessage("second")))
    .append(Assistant(AssistantMessage("answer")))
    // Repeats the assistant final, so it projects no extra message.
    .append(Terminal(Finished("answer")))
    .append(User(UserMessage("third")))
    .append(
      Summary(SessionSummary(content="covered", from_sequence=8, to_sequence=8)),
    )
    .append(
      Terminal(Finished("\{@agent_session.ContextYieldAnswerPrefix} continued")),
    )
  let messages = session.chat_messages()
  let origins = model_message_origins(session)
  assert_eq(origins.length(), messages.length())
  for index, message in messages {
    let from_user_item = match origins[index] {
      FromUser | FromRuntime | FromSummary(..) => true
      Other => false
    }
    assert_eq(from_user_item, message.role is User)
  }
}

///|
test "model metadata omits an assistant final's duplicate terminal" {
  let session = @agent_session.Session(SessionId("labels"), system_prompt="")
    .append(User(UserMessage("first")))
    .append(Assistant(AssistantMessage("answer")))
    .append(Terminal(Finished("answer")))
    .append(User(UserMessage("second")))
    .append(Terminal(Finished("done")))
  let messages = session.chat_messages()
  let anchors = model_message_anchor_seqs(session)
  assert_eq(anchors.length(), messages.length())
  assert_eq(model_message_time_labels(session).length(), messages.length())
  assert_eq(model_message_step_labels(session).length(), messages.length())
  debug_inspect(anchors, content="[\"\", \"1\", \"2\", \"4\", \"5\"]")
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

///|
/// Whether a tool call explicitly carries the top-level JSON boolean
/// `"escalated": true`. Similar-looking values are deliberately rejected: a
/// string, nested field, false value, or malformed argument payload did not ask
/// the runtime for escalation.
fn tool_call_is_escalated(call : @deepseek.ToolCall) -> Bool {
  let json = @json.parse(call.arguments) catch { _ => return false }
  json is { "escalated": true, .. }
}

///|
/// Whether a failed `mbtx` call's brief reports a BUILD-stage failure — the
/// staged engine's `mbtx (build …)` shapes (`build failed`, `build timeout`,
/// `build fault`), which only it ever writes, so the tag carries no
/// pre-staging or single-shot ambiguity.
fn tool_call_is_build_failed(
  call : @deepseek.ToolCall,
  briefs : Map[String, String],
  failed : Map[String, Unit],
  tags : Map[String, Int],
) -> Bool {
  // `tags` holds exactly the unambiguous 1:1 call/result pairs. A duplicated
  // id collapses briefs into one map entry, which would make a call's stage
  // depend on event order — so an ambiguous call is labeled with no stage at
  // all. Its RESULT cards still carry their own per-result tags.
  //
  // The BRIEF is the whole identity here, deliberately: the brief map is
  // result data, and `result_is_build_failed` reads the same field, so call
  // tags, result tags, and the toolbar count classify one way even when a
  // hand-edited log's call name and result tool_name disagree. Re-checking a
  // name on either side is what would let them diverge.
  tags.contains(call.id) &&
  failed.contains(call.id) &&
  briefs.get(call.id) is Some(brief) &&
  brief.has_prefix("mbtx (build")
}

///|
/// Whether a failed `mbtx` call reads as a RUN-stage failure: an exit brief
/// on the staged wasm path (target absent or `"wasm"` in the call's own
/// arguments). A single-shot target's one exit code covers both stages and
/// claims neither. A wasm failure recorded before the staged engine shares
/// the brief shape and reads as runtime — an accepted imprecision, by
/// explicit owner decision (no backwards compatibility for old transcripts).
fn tool_call_is_run_failed(
  call : @deepseek.ToolCall,
  briefs : Map[String, String],
  failed : Map[String, Unit],
  tags : Map[String, Int],
) -> Bool {
  guard tags.contains(call.id) &&
    call.name == "mbtx" &&
    failed.contains(call.id) &&
    briefs.get(call.id) is Some(brief) &&
    brief.has_prefix("mbtx (exit=") else {
    return false
  }
  let json = @json.parse(call.arguments) catch { _ => return false }
  json is { "target"? : None | Some(String("wasm") | Null), .. }
}

///|
/// Whether a durable result reports an mbtx BUILD-stage failure, read from
/// the fields the result itself carries — no call lookup needed, so result
/// cards stay tagged in both view modes without extra threading.
fn result_is_build_failed(result : @agent_session.ToolResult) -> Bool {
  // Brief-only, matching `tool_call_is_build_failed`: one identity for both
  // sides of a pair keeps the tags and the toolbar count consistent even on
  // logs whose call name and result tool_name disagree. The `mbtx (build`
  // shape is written only by the staged engine.
  result.is_error() &&
  result.brief() is Some(brief) &&
  brief.has_prefix("mbtx (build")
}

///|
/// Escalated call ids whose result can be identified unambiguously in the raw
/// view. `tags` already contains exactly the 1:1 call/result pairs, so using it
/// avoids attaching an escalation marker to a result when duplicate ids make
/// the relationship ambiguous.
fn raw_escalated_result_ids(
  session : @agent_session.Session,
  tags : Map[String, Int],
) -> Map[String, Unit] {
  let ids : Map[String, Unit] = Map([])
  for event in session.events() {
    if event.item() is Assistant(message) {
      for call in message.tool_calls() {
        if tags.contains(call.id) && tool_call_is_escalated(call) {
          ids.set(call.id, ())
        }
      }
    }
  }
  ids
}

///|
/// Model-view counterpart of `raw_escalated_result_ids`, based only on calls
/// and result messages that the model projection actually renders.
fn model_escalated_result_ids(
  messages : Array[@deepseek.ChatMessage],
  tags : Map[String, Int],
) -> Map[String, Unit] {
  let ids : Map[String, Unit] = Map([])
  for message in messages {
    for call in message.tool_calls {
      if tags.contains(call.id) && tool_call_is_escalated(call) {
        ids.set(call.id, ())
      }
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
  "\{anchor_namespace.val}tool-call-\{n}"
}

///|
/// DOM anchor id for a tool result, keyed by pair number.
fn tool_result_anchor(n : Int) -> String {
  "\{anchor_namespace.val}tool-result-\{n}"
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
  escalated : Map[String, Unit],
  briefs : Map[String, String],
  tags : Map[String, Int],
  plans : Map[String, Array[@steps.PlanStep]],
  time~ : String,
  step_label~ : String,
  anchor~ : String?,
  origin~ : MessageOrigin,
  subrun~ : SubrunView,
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
    User => {
      let (kind, label) = user_role_card_style(
        message.content,
        origin~,
        delegated=subrun.delegated,
      )
      model_card(
        kind,
        label,
        message,
        briefs,
        failed,
        tags,
        plans,
        time~,
        step_label~,
        anchor~,
      )
    }
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
        escalated,
        tags,
        subrun,
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
/// How many tool calls rendered in `mode` explicitly request escalation via a
/// top-level JSON boolean `"escalated": true`. This is derived from the durable
/// tool-call arguments already stored in the session; no separate approval
/// event is needed.
pub fn rendered_escalated_count(
  session : @agent_session.Session,
  mode : ViewMode,
) -> Int {
  let mut count = 0
  match mode {
    RawLog =>
      for event in session.events() {
        if event.item() is Assistant(message) {
          count += message.tool_calls().count_if(tool_call_is_escalated)
        }
      }
    ModelView =>
      for message in session.chat_messages() {
        count += message.tool_calls.count_if(tool_call_is_escalated)
      }
  }
  count
}

///|
/// How many rendered BUILD-stage mbtx failures each view mode shows — what
/// the build-errors-only toolbar counts and jumps between. Counted from the
/// RESULTS, the same per-result test that tags their cards `build-failed`, so
/// the count and the visible tags can never disagree — including for an
/// orphan result with no matching call, which the raw renderer still shows
/// and the filter must not hide behind a zero count. The model view counts
/// only results the projection shows (`model_shown_result`).
pub fn rendered_build_error_count(
  session : @agent_session.Session,
  mode : ViewMode,
) -> Int {
  match mode {
    RawLog =>
      session
      .events()
      .iter()
      .count_if(event => {
        event.item() is Tool(result) && result_is_build_failed(result)
      })
    ModelView => {
      let tool_results = tool_results_by_id(session)
      session
      .chat_messages()
      .count_if(message => {
        model_shown_result(message, tool_results) is Some(result) &&
        result_is_build_failed(result)
      })
    }
  }
}

///|
/// Whether the session used `mbtx` at all — a call by that name, or a durable
/// result naming it. This is what makes the build-errors-only control
/// DISCOVERABLE: hidden-at-zero chrome told a user nothing when a session had
/// mbtx work but no build failures, so the toolbar shows whenever mbtx was in
/// play, and only a session with no mbtx activity stays chrome-free.
pub fn session_has_mbtx_activity(session : @agent_session.Session) -> Bool {
  session
  .events()
  .iter()
  .any(event => {
    match event.item() {
      Assistant(message) =>
        message.tool_calls().any(call => call.name == "mbtx")
      Tool(result) => result.tool_name() == "mbtx"
      _ => false
    }
  })
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
  escalated : Map[String, Unit],
  tags : Map[String, Int],
  subrun : SubrunView,
  time~ : String,
  anchor~ : String?,
) -> @html.Html {
  let is_error = shown is Some(r) && r.is_error()
  let name = match shown {
    Some(r) => r.tool_name()
    None => ""
  }
  let is_escalated = match message.role {
    Tool(id) => escalated.contains(id)
    _ => false
  }
  let kind = match (is_error, is_escalated) {
    (false, false) => "tool"
    (true, false) => "tool error"
    (false, true) => "tool escalated"
    (true, true) => "tool error escalated"
  }
  // Same build-failure tag as the raw view's result card, derived only from
  // the result the projection actually shows.
  let kind = if shown is Some(r) && result_is_build_failed(r) {
    "\{kind} build-failed"
  } else {
    kind
  }
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
  let flag = match shown {
    Some(r) => result_flag(r)
    None => failed_flag(is_error)
  }
  let summary = model_card_head(label, time~, flag~, link~)
  // Chip only, no nested transcript: the model view shows what the model
  // was fed, and the child's transcript never was.
  if shown is Some(result) &&
    subrun_child_id(result, subrun.parent) is Some(child_id) {
    summary.push(subrun_chip(child_id))
  }
  @html.details(id?=anchor, class="card \{kind}") <| [
    @html.summary(class="card-label") <| summary,
    @html.div(class="card-body") <| [
      tool_result_content(shown, message.content),
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
  if message.reasoning_content is Some(reasoning) && !reasoning.is_blank() {
    body.push(
      @html.details(class="reasoning") <| [
        @html.summary("reasoning"),
        text_block(reasoning),
      ],
    )
  }
  if !message.content.is_blank() {
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
  "\{anchor_namespace.val}seq-\{seq}"
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
  if content.is_blank() {
    @html.span(class="empty") <| "(empty)"
  } else {
    @html.pre(class="content") <| content
  }
}

///|
/// A read result whose tool-owned brief names a MoonBit file keeps its gutter
/// and footer plain while the source uses the shared editor tokenizer.
fn tool_result_content(
  result : @agent_session.ToolResult?,
  content : String,
) -> @html.Html {
  if result is Some(result) &&
    result.tool_name() == "read" &&
    result.brief() is Some(brief) &&
    @read_html.moonbit_output_for_brief(brief, content) is Some(rendered) {
    @html.div([
      @html.pre(class="content tool-call-args-rendered", [rendered]),
      @html.pre(class="content tool-call-args-original", content),
    ])
  } else {
    text_block(content)
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

// ---- subagent transcripts ---------------------------------------------------

///|
/// Rendering context for subagent (sub-run) transcripts: the parent
/// session's id — the prefix of every child session id — plus any child
/// sessions the caller already loaded for inline display. An empty context
/// renders plain tool cards.
pub struct SubrunView {
  parent : String
  children : Map[String, @agent_session.Session]
  /// Whether the session being rendered is itself a sub-run child. Its
  /// `User` events are the task its parent agent handed it, so the view must
  /// not caption them as the person's own words.
  delegated : Bool
}

///|
/// Whether a session id is one the sub-run runner minted for a child
/// (`<parent>-sr-N`, the shape `subrun_child_id` builds). Parent ids are
/// user-chosen, so a hand-named session can wear the shape; it only decides
/// how a `User` card is captioned, never what is shown.
fn is_subrun_session_id(id : String) -> Bool {
  lexmatch id {
    re"^(.|\n)*" + re"-sr-[0-9]+$" => true
    _ => false
  }
}

///|
test "sub-run child ids are the ones ending in -sr-<n>" {
  inspect(is_subrun_session_id("run7-sr-1"), content="true")
  inspect(is_subrun_session_id("run7-sr-12"), content="true")
  // A parent id may itself contain dashes and digits without being a child.
  inspect(is_subrun_session_id("run7"), content="false")
  inspect(is_subrun_session_id("run-sr-x"), content="false")
  inspect(is_subrun_session_id("run7-sr-1-more"), content="false")
}

///|
/// The child session id a subrun tool result names, or `None` for every
/// other result. The contract is the brief the review tool stamps:
/// `"<tool> sr-N (…)"` — display-only metadata, so parsing it here never
/// touches what the model saw.
fn subrun_child_id(
  result : @agent_session.ToolResult,
  parent : String,
) -> String? {
  guard result.tool_name() is "review" else { return None }
  guard result.brief() is Some(brief) else { return None }
  let tokens = brief.split(" ").collect()
  guard tokens.get(1) is Some(token) else { return None }
  guard token.has_prefix("sr-") else { return None }
  let digits = token.view(start_offset=3)
  guard !digits.is_empty() && digits.iter().all(c => c.is_ascii_digit()) else {
    return None
  }
  Some("\{parent}-\{token}")
}

///|
/// The folded-card chip linking a subrun result to its child session: an
/// in-page `#s=<child id>` navigation the app resolves against its session
/// listing. Rendered whenever the brief names a sub-run — if the child
/// never persisted (ephemeral parent), following the link reports "session
/// not found" rather than hiding that a transcript could have existed.
fn subrun_chip(child_id : String) -> @html.Html {
  @html.a(
    class="subrun-link",
    href="#s=\{encode_hash_component(child_id)}",
    title="Open the subagent's own transcript",
  ) <| "↳ subagent"
}

///|
/// Percent-encode a value for a `#key=value` hash parameter. The reader is
/// `URLSearchParams`, which decodes `%XX` and turns a bare `+` into a
/// space — parent session ids are user-chosen and unrestricted, so
/// everything outside the RFC 3986 unreserved set is encoded, UTF-8
/// bytewise.
fn encode_hash_component(value : String) -> String {
  let hex = [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F",
  ]
  let out = StringBuilder()
  fn put_byte(b : Int) -> Unit {
    out <+ "%\{hex[b >> 4 & 0xF]}\{hex[b & 0xF]}"
  }

  for c in value {
    let code = c.to_int()
    if (code >= 0x61 && code <= 0x7A) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x30 && code <= 0x39) ||
      code == 0x2D ||
      code == 0x5F ||
      code == 0x2E ||
      code == 0x7E {
      out <+ "\{c}"
    } else if code < 0x80 {
      put_byte(code)
    } else if code < 0x800 {
      put_byte(0xC0 | (code >> 6))
      put_byte(0x80 | (code & 0x3F))
    } else if code < 0x10000 {
      put_byte(0xE0 | (code >> 12))
      put_byte(0x80 | ((code >> 6) & 0x3F))
      put_byte(0x80 | (code & 0x3F))
    } else {
      put_byte(0xF0 | (code >> 18))
      put_byte(0x80 | ((code >> 12) & 0x3F))
      put_byte(0x80 | ((code >> 6) & 0x3F))
      put_byte(0x80 | (code & 0x3F))
    }
  }
  out.to_string()
}

///|
/// DOM-anchor namespace for the render in progress: empty at top level,
/// `<child id>--` while a child transcript is being nested — WITHOUT it,
/// a nested child would re-emit the parent's `seq-N`/`tool-call-N`/
/// `tool-result-N` ids (duplicate DOM ids; in-child pair links resolving
/// to parent elements). Rendering is pure and synchronous, and this
/// package is single-threaded js, so a save/restore around the one
/// nesting entry point (`subrun_transcript`) is race-free.
let anchor_namespace : Ref[String] = { val: "", }

///|
/// The inline child transcript for an expanded subrun card: the child's
/// full raw log (its own turn structure, cards, and anchors) nested inside
/// the parent's card body. Children cannot spawn sub-runs of their own, so
/// the nesting is one level deep by construction.
fn subrun_transcript(child : @agent_session.Session) -> @html.Html {
  let steps = child
    .events()
    .iter()
    .count_if(event => {
      event.item() is Assistant(message) && !message.is_replay()
    })
  let tools = child.events().iter().count_if(event => event.item() is Tool(_))
  // Namespace every anchor the child render emits (and the pair links
  // referencing them), so the nested transcript never duplicates the
  // parent document's ids.
  let saved = anchor_namespace.val
  anchor_namespace.val = "\{child.id().value()}--"
  let body = render_raw(child, {
    parent: child.id().value(),
    children: Map([]),
    // Known for certain here, whatever the child's id looks like: this
    // transcript is nested inside the parent's own tool result.
    delegated: true,
  })
  anchor_namespace.val = saved
  @html.details(class="subrun-transcript") <| [
    @html.summary(class="subrun-transcript-label") <| [
      @html.text(
        "Subagent transcript · \{child.id().value()} · \{steps} step\{plural(steps)} · \{tools} tool call\{plural(tools)}",
      ),
    ],
    @html.div(class="subrun-transcript-body") <| [
      body,
    ],
  ]
}

///|
/// Every child session id this session's subrun tool results reference, in
/// first-appearance order — the set a viewer prefetches for inline
/// transcripts.
pub fn subrun_child_ids(
  session : @agent_session.Session,
  parent : String,
) -> Array[String] {
  let ids : Array[String] = []
  for event in session.events() {
    if event.item() is Tool(result) &&
      subrun_child_id(result, parent) is Some(child_id) &&
      !ids.contains(child_id) {
      ids.push(child_id)
    }
  }
  ids
}

///|
pub extend ViewMode with Debug::{to_repr}

///|
pub extend ViewMode with Eq::{equal, not_equal}
