///|
/// One provider response as the transcript shows it: its thought behind a
/// fold, its prose as a bubble, and every tool call on display as its own
/// one-line row (`tool_request_view`), expandable to that call's arguments and
/// output — in the order the model produced them, so a step that ran ten
/// tools reads as ten scannable rows after the narration that announced them.
/// Only reasoning stays behind a fold: a step that opens with a thought
/// carries the ordinal and commit instant on that fold's summary
/// ("#2 14:32:10 · Thought"), and a numbered step that goes straight to
/// tools puts the same columns on a plain heading line instead. The open
/// state of every disclosure is the browser's (`<details>`), so a reader's
/// toggle survives re-renders and the run growing while live.
///
/// The response still streaming renders through this same view (`live`), so
/// nothing shown live restyles when its durable event lands: the thought
/// stays plain text until it completes, and the prose bubble is marked
/// streaming until the commit replaces it.
///
/// Failures need no badge up here: a failed call's own row is visible and
/// carries its own literal `failed` marker. Its potentially large arguments
/// and output stay folded by default, like every other call.
fn assistant_view(
  on_open : (String) -> @cmd.Cmd,
  prose? : String,
  reasoning? : String,
  calls? : Array[@transcript.ToolCall] = [],
  sequence? : Int,
  ts? : Double,
  step_label? : String,
  assistant_name? : String = "OpenSeek",
  finished? : Bool = false,
  live? : Bool = false,
  reasoning_complete? : Bool = true,
  subrun? : SubrunLink,
) -> @html.Html {
  // The step ordinal is its own span so it can carry the accent and a fixed
  // numeral column, then the instant in a second fixed column: the run reads
  // as a table. The instant belongs beside the ordinal rather than out at the
  // row's right edge — the reason to show it at all is the gap to the step
  // above and below, and comparing a column is the eye's job only when
  // nothing variable-width sits between its entries and their anchor.
  let header : Array[@html.Html] = []
  let stamp = step_stamp(ts?)
  if step_label is Some(label) {
    header.push(@html.span(class="activity-step", label))
    // A real space, not a CSS margin, and only when the instant follows it: the
    // gap has to exist in the text as well, or the accessible name and anything
    // copied out of the row read "#1Committed 14:32:10".
    if stamp is Some(_) {
      header.push(@html.text(" "))
    }
  }
  if stamp is Some(stamp) {
    header.push(stamp)
  }
  // The header rides the thought fold's summary when the step opens with
  // reasoning, keeping the common step's one-line "#2 · Thought" lead. A step
  // that goes straight to tools gets a plain heading line instead: a call
  // row's summary belongs to that call alone. Prose alone carries no heading.
  let lead : Array[@html.Html] = []
  if reasoning is Some(text) {
    let thinking = live && !reasoning_complete
    let label = if thinking { "Thinking…" } else { "Thought" }
    let summary : Array[@html.Html] = []
    if header.is_empty() {
      // The separator introduces the label only when something precedes it:
      // a Codex thought with no ordinal and no stamp is the label alone.
      summary.push(@html.text(label))
    } else {
      summary.append(header)
      summary.push(@html.text(" · \{label}"))
    }
    let body = if thinking {
      // Do not parse an unfinished Markdown document on every provider token.
      // Newlines are preserved by CSS while fragments are still arriving.
      @html.div(
        class="msg-content activity-thinking activity-thinking-live",
        @html.text(text),
      )
    } else {
      @html.div(
        class="msg-content markdown activity-thinking",
        @markdown.markdown_nodes(text, open_file=on_open),
      )
    }
    lead.push(
      @html.details(class="activity", open=live, [
        @html.summary(class="activity-summary", [
          @html.span(class="activity-text", summary),
        ]),
        @html.div(class="activity-body", [body]),
      ]),
    )
  } else if !header.is_empty() && !calls.is_empty() {
    lead.push(@html.div(class="activity-heading", header))
  }
  let work = if calls.is_empty() {
    None
  } else {
    Some(
      @html.div(
        class="activity-work",
        tool_run_views(calls, sequence?, subrun?),
      ),
    )
  }
  // The prose bubble separates the thought from the work it announced; a
  // response without prose keeps both under one quiet guide line.
  let parts : Array[@html.Html] = []
  if prose is Some(text) {
    if !lead.is_empty() {
      parts.push(@html.div(class="activity-row", lead))
    }
    parts.push(
      assistant_message_view(
        text,
        on_open,
        assistant_name,
        is_danger=false,
        completed_at?=if finished { ts } else { None },
        show_actions=finished,
        streaming=live,
      ),
    )
    if work is Some(work) {
      parts.push(@html.div(class="activity-row", [work]))
    }
  } else {
    if work is Some(work) {
      lead.push(work)
    }
    if !lead.is_empty() {
      parts.push(@html.div(class="activity-row", lead))
    }
  }
  @html.div(class="step", parts)
}

///|
/// A durable runtime notice — a goal marker, or an engine notice injected
/// between turns — as the compact completed-result row a tool result gets,
/// under the instant it committed. Never a numbered step: nothing in it is
/// the model's work.
fn notice_view(
  label : String,
  brief : String?,
  is_error : Bool,
  body : String?,
  ts? : Double,
  sequence? : Int,
) -> @html.Html {
  let rows : Array[@html.Html] = []
  if step_stamp(ts?) is Some(stamp) {
    rows.push(@html.div(class="activity-heading", [stamp]))
  }
  let row = result_row_view(
    label,
    None,
    pending=false,
    is_error~,
    brief~,
    body,
    tool_call_tabs_key(label, sequence),
  )
  rows.push(@html.div(class="activity-work", { "notice": row }))
  @html.div(class="activity-row", rows)
}

///|
/// Render one response's tool calls. Several calls of one provider response
/// are a parallel burst: show every request first and every result after it,
/// exactly as the viz HTML renderer's Assistant card followed by result cards
/// makes a burst readable. A lone call — every Codex item, and a notice —
/// keeps its request beside its own result instead of implying concurrency.
fn tool_run_views(
  calls : Array[@transcript.ToolCall],
  sequence? : Int,
  subrun? : SubrunLink,
) -> Map[String, @html.Html] {
  let rows : Map[String, @html.Html] = Map([])
  let burst = calls.length() > 1 && calls.all(call => call.arguments is Some(_))
  if burst {
    for index, call in calls {
      rows[tool_run_row_key(call, index, "request")] = tool_request_view(
        call,
        sequence?,
      )
    }
    for index, call in calls {
      if tool_result_row_is_visible(call) {
        rows[tool_run_row_key(call, index, "result")] = tool_result_view(
          call,
          sequence?,
          subrun?,
        )
      }
    }
  } else {
    for index, call in calls {
      if call.arguments is Some(_) {
        rows[tool_run_row_key(call, index, "request")] = tool_request_view(
          call,
          sequence?,
        )
      }
      if tool_result_row_is_visible(call) {
        rows[tool_run_row_key(call, index, "result")] = tool_result_view(
          call,
          sequence?,
          subrun?,
        )
      }
    }
  }
  rows
}

///|
/// Stable VDOM identity for one side of a tool exchange. Results can arrive
/// after later calls are already visible, so keyed children keep browser-owned
/// disclosure and radio state attached to the same call instead of the same
/// array position. The index disambiguates malformed logs with duplicate ids;
/// call order itself is stable in the transcript projection.
fn tool_run_row_key(
  call : @transcript.ToolCall,
  index : Int,
  side : String,
) -> String {
  "\{side}\u{0}\{call.call_id}\u{0}\{index}"
}

///|
/// What a sub-run tool card needs to offer its child transcript: the session
/// this card is being rendered under (an `sr-N` is only unique within its own
/// engine, so the child id cannot be derived without it), and the way to open
/// another session.
///
/// Absent for every transcript source that has no sub-runs, which is also what
/// keeps the chip out of the rendering tests that do not supply one.
priv struct SubrunLink {
  parent : String
  open : (String) -> @cmd.Cmd
}

///|
/// The chip linking a sub-run's tool card to the child's own transcript.
///
/// It leads the card body rather than sitting in the summary: a button
/// inside a `<summary>` would have to fight that element's toggle activation,
/// and the body keeps it beside the report it explains.
fn subrun_chip(child : String, open : (String) -> @cmd.Cmd) -> @html.Html {
  @html.div(class="tool-call-section", [
    @html.button(
      class="subrun-chip",
      type_="button",
      title="Open this subagent's own transcript (\{child})",
      on_click=open(child),
      "↳ subagent transcript",
    ),
  ])
}

///|
/// A completed result always gets its own row, including an empty one. Codex
/// command items can also stream output while still in progress; surface that
/// stream immediately, with the row still labelled pending until the
/// completed item arrives.
fn tool_result_row_is_visible(call : @transcript.ToolCall) -> Bool {
  match call.outcome {
    Done(..) => true
    Pending(output~) => output is Some(_)
  }
}

///|
/// One recorded tool request, always on display as its own row. Its brief is
/// the result-derived caption the viz renderer also promotes onto the call;
/// expanding reveals only what the model sent. Failed calls read red and carry
/// a literal marker, while their separate result row owns the output.
fn tool_request_view(
  call : @transcript.ToolCall,
  sequence? : Int,
) -> @html.Html {
  guard call.arguments is Some(arguments) else { return @html.nothing }
  let name = call.name
  // A pending call has no result to be wrong about, and no brief yet.
  let (is_error, brief) = match call.outcome {
    Done(is_error~, brief~, ..) => (is_error, brief)
    Pending(..) => (false, None)
  }
  let label = if brief is Some(brief) && !brief.is_blank() {
    brief
  } else {
    name
  }
  let error_class = (if is_error { " error" } else { "" }) +
    failure_stage_class(name, brief, is_error, Some(arguments))
  // The row's always-visible line: the brief, a literal marker when the
  // result errored and the brief does not already carry the state in words
  // (see `failure_marker`), and — for an applied `plan` call — the compact
  // progress meter. `fold_progress` renders nothing for every other call.
  let line : Array[@html.Html] = [
    @html.span(class="tool-flow", "→"),
    @html.span(class="tool-call-text", label),
  ]
  if failure_marker(
      name,
      brief,
      is_error,
      Some(arguments),
      // The request row's label is the brief whenever one exists.
      brief_shown=brief is Some(brief) && !brief.is_blank(),
    )
    is Some(marker) {
    line.push(marker)
  }
  line.push(@plan.fold_progress(call))
  let body : Array[@html.Html] = []
  // A `plan` call shows the checklist it recorded rather than its JSON, in
  // every state where that checklist is what the model asked for. A pending
  // call qualifies: the card is a record of the call, and the missing Output
  // section already marks it unfinished. A rejected one does not — the
  // malformed arguments are what the reader needs, and dressing them up as a
  // checklist would report a plan that never took effect.
  if @plan.classify(call) is Some(Applied(steps) | Pending(steps)) {
    body.push(@html.div(class="tool-call-section", [@plan.card(steps)]))
  } else if tool_arguments_tabbed_view(
      tool_call_tabs_key(call.call_id, sequence),
      name,
      Some(arguments),
    )
    is Some(tabs) {
    body.push(@html.div(class="tool-call-section", [tabs]))
  } else if custom_card(name, arguments) is Some((label, card)) {
    // Some tools' arguments have a shape JSON hides, such as an `edit` split
    // across two blobs whose difference is the whole point. Those get a card.
    // A payload the card cannot read falls through to the generic rendering
    // below, so nothing is ever shown as a change that is not one.
    body.push(
      @html.div(class="tool-call-section", [
        @html.div(class="tool-call-section-label", label),
        card,
      ]),
    )
  } else {
    let trimmed = arguments.trim()
    if !trimmed.is_empty() && trimmed != "{}" {
      body.push(
        @html.div(class="tool-call-section", [
          @html.div(class="tool-call-section-label", "Arguments"),
          json_arguments_content(arguments).body,
        ]),
      )
    }
  }
  if body.is_empty() {
    @html.div(class="tool-call-label" + error_class, line)
  } else {
    @html.details(
      class="tool-call" + error_class,
      [
        // The full label as the row's tooltip: a brief longer than the pane
        // is ellipsized by the stylesheet, and the body holds the arguments
        // but not the brief — hover (or opening the row, which the
        // stylesheet un-clamps) is how the whole text stays reachable.
        @html.summary(class="tool-call-summary", title=label, line),
        ..body,
      ],
    )
  }
}

///|
/// One tool result, separate from the request that produced it as in the viz
/// HTML renderer. A completed row remains visible even when empty; a pending
/// Codex command gets a row only after it has streamed output, and its label
/// deliberately says "output" rather than claiming completion.
fn tool_result_view(
  call : @transcript.ToolCall,
  sequence? : Int,
  subrun? : SubrunLink,
) -> @html.Html {
  let key = tool_call_tabs_key(call.call_id, sequence)
  match call.outcome {
    Pending(output~) =>
      result_row_view(
        call.name,
        call.arguments,
        pending=true,
        is_error=false,
        brief=None,
        output,
        key,
        subrun?,
      )
    Done(content~, is_error~, brief~) =>
      result_row_view(
        call.name,
        call.arguments,
        pending=false,
        is_error~,
        brief~,
        // An empty result still gets its row; it just has nothing to expand.
        if content.is_blank() {
          None
        } else {
          Some(content)
        },
        key,
        subrun?,
      )
  }
}

///|
/// The result row itself: a tool result's, or a runtime notice's, which wears
/// the same compact completed-result shape. `output` is the body the row
/// expands to, when there is one.
fn result_row_view(
  name : String,
  arguments : String?,
  pending~ : Bool,
  is_error~ : Bool,
  brief~ : String?,
  output : String?,
  key : String,
  subrun? : SubrunLink,
) -> @html.Html {
  let label = match (arguments, brief, pending) {
    (None, Some(brief), _) if !brief.is_blank() => brief
    (None, _, _) => name
    (_, _, true) => "Tool output · \{name}"
    _ if is_error => "Tool error · \{name}"
    _ => "Tool result · \{name}"
  }
  let error_class = (if is_error { " error" } else { "" }) +
    failure_stage_class(name, brief, is_error, arguments)
  let pending_class = if pending { " pending" } else { "" }
  let line : Array[@html.Html] = [
    @html.span(class="tool-flow", "←"),
    @html.span(class="tool-result-text", label),
  ]
  if failure_marker(
      name,
      brief,
      is_error,
      arguments,
      // The result row shows the brief as its label only for the
      // argument-less shape (the first `label` arm above); the common
      // "Tool error · mbtx" label carries no brief, so the stage word stays.
      brief_shown=arguments is None && brief is Some(brief) && !brief.is_blank(),
    )
    is Some(marker) {
    line.push(marker)
  }
  let body : Array[@html.Html] = []
  // A sub-run result names the child session it spawned in its brief. The
  // result owns the child report and therefore owns the way into its transcript.
  if subrun is Some(link) && brief is Some(brief) {
    for
      child in @transcript.subrun_child_sessions(
        name,
        brief,
        parent=link.parent,
      ) {
      body.push(subrun_chip(child, link.open))
    }
  }
  if output is Some(text) {
    let output = tool_output_tabs(name, arguments, text)
    if output is [tab] {
      body.push(
        @html.div(class="tool-call-section", [
          @html.div(class="tool-call-section-label", tab.label),
          tab.body,
        ]),
      )
    } else if output.length() > 1 {
      body.push(
        @html.div(class="tool-call-section", [
          tool_call_tabs("\{key}-result", output),
        ]),
      )
    }
  }
  if body.is_empty() {
    @html.div(class="tool-result-label" + error_class + pending_class, line)
  } else {
    @html.details(
      class="tool-result" + error_class + pending_class,
      [@html.summary(class="tool-result-summary", title=label, line), ..body],
    )
  }
}

///|
/// Clamp tool arguments or output around skip markers before constructing the
/// transcript DOM. The code-unit bound handles huge single-line JSON payloads;
/// the line bound keeps logs readable. `clamped_view` keeps cuts out of UTF-16
/// surrogate pairs. The transcript remains the only scroll area, so bounded
/// payloads grow the page instead of adding a nested scrollbar.
///
/// `line_prefix_width` preserves a fixed-width line marker on a retained tail
/// fragment when the code-unit cut lands inside a line. Diff rows use this for
/// their two-character `+ ` / `- ` / context marker; ordinary output leaves it
/// at zero.
fn truncate_output(content : String, line_prefix_width? : Int = 0) -> String {
  let code_unit_head_limit = 12_000
  let code_unit_tail_limit = 8_000
  let bounded = if content.length() <=
    code_unit_head_limit + code_unit_tail_limit {
    content
  } else {
    let head = content.clamped_view(end=code_unit_head_limit)
    let tail = content.clamped_view(
      start=content.length() - code_unit_tail_limit,
    )
    let retained_tail = restore_retained_tail_prefix(
      content, tail, line_prefix_width,
    )
    [
      head.to_owned(),
      "⋯ \{content.length() - head.length() - tail.length()} UTF-16 code units skipped ⋯",
      retained_tail,
    ].join("\n")
  }
  let head_limit = 60
  let tail_limit = 40
  let lines = [..bounded.split("\n")]
  if lines.length() <= head_limit + tail_limit + 1 {
    return bounded
  }
  [
    ..lines[0:head_limit],
    "⋯ \{lines.length() - head_limit - tail_limit} lines skipped ⋯",
    ..lines[lines.length() - tail_limit:],
  ].join("\n")
}

///|
/// Repeat a line's fixed-width prefix when `tail` starts partway through that
/// line. If the cut itself bisects the prefix, discard the retained suffix of
/// the old prefix before prepending the whole one, so `+ text` cannot become
/// `+  text`. `tail` is a suffix view of `content`, so its start is recovered
/// from their lengths after `clamped_view` has made the UTF-16 boundary safe.
fn restore_retained_tail_prefix(
  content : String,
  tail : StringView,
  line_prefix_width : Int,
) -> String {
  if line_prefix_width <= 0 {
    return tail.to_owned()
  }
  let tail_start = content.length() - tail.length()
  let line_start = match content.clamped_view(end=tail_start).rev_find("\n") {
    Some(index) => index + 1
    None => 0
  }
  if line_start == tail_start {
    return tail.to_owned()
  }
  let prefix = content.clamped_view(
    start=line_start,
    end=line_start + line_prefix_width,
  )
  let prefix_end = line_start + prefix.length()
  let overlap = if tail_start < prefix_end {
    prefix_end - tail_start
  } else {
    0
  }
  prefix.to_owned() + tail.clamped_view(start=overlap).to_owned()
}

///|
fn inline_code_nodes(content : String) -> Array[@html.Html] {
  let nodes : Array[@html.Html] = []
  let mut rest = content
  let mut in_code = false
  let mut done = false
  while !done {
    match rest.split_once("`") {
      Some((before, after)) => {
        let segment = before.to_owned()
        if !segment.is_empty() {
          if in_code {
            nodes.push(@html.code(class="inline-code", segment))
          } else {
            for child in @markdown.linkified_text_nodes(segment) {
              nodes.push(child)
            }
          }
        }
        rest = after.to_owned()
        in_code = !in_code
      }
      None => {
        if in_code {
          nodes.push(@html.text("`\{rest}"))
        } else if !rest.is_empty() {
          for child in @markdown.linkified_text_nodes(rest) {
            nodes.push(child)
          }
        }
        done = true
      }
    }
  }
  nodes
}

///|
/// Who is speaking, for anyone who cannot see the bubble that says so. The
/// alignment, the fill, and the rule between turns are all pure CSS, so
/// without this the transcript reaches a screen reader as an unattributed
/// stream of text. It is the same word the visible caption used to carry,
/// kept in the accessibility tree and out of the layout.
fn speaker_label(name : String) -> @html.Html {
  @html.span(class="visually-hidden", name)
}

///|
/// A user message bubble. The bubble itself is what marks the turn as the
/// user's — no avatar, no role label — so everything unbubbled below it reads
/// as the agent's side of the conversation. A content that carries a
/// `<user_mentions>` envelope (a prompt sent with chips) renders as the chips
/// it was composed with — the same tray the composer showed, minus the remove
/// buttons — above the typed text; anything else is plain text. A chip with a
/// resolved location jumps the editor panel there via `on_jump`, when the
/// caller wires one.
fn user_message_view(
  content : String,
  anchor? : String,
  on_jump? : (@mention_context.Target) -> @cmd.Cmd,
) -> @html.Html {
  let body : Array[@html.Html] = [speaker_label("You")]
  match @mention_context.parse(content) {
    Some(parsed) => {
      let chips : Array[@html.Html] = []
      for mention in parsed.mentions {
        let glyph = @html.span(
          class="mention-glyph",
          @mention_context.glyph(mention),
        )
        let label_text = @mention_context.label(mention)
        let label = @html.span(class="mention-label", label_text)
        let target = @mention_context.target(mention)
        let title = if mention is Annotation(comment~, ..) {
          comment
        } else if target is Some(target) {
          if target.range is Some(range) {
            "Jump to \{target.file}:\{range.start_line_number}"
          } else {
            "Jump to \{target.file}"
          }
        } else {
          label_text
        }
        let chip = if target is Some(target) && on_jump is Some(jump) {
          @html.button(
            class="mention-jump",
            type_="button",
            title~,
            on_click=jump(target),
            [glyph, label],
          )
        } else {
          @html.span(class="mention-body", [glyph, label])
        }
        chips.push(@html.div(class="mention-chip", [chip]))
      }
      body.push(@html.div(class="mention-tray", chips))
      if !parsed.task.is_empty() {
        body.push(
          @html.div(class="msg-content", inline_code_nodes(parsed.task)),
        )
      }
    }
    None =>
      body.push(@html.div(class="msg-content", inline_code_nodes(content)))
  }
  // The overview rail and scroll watcher share this stable turn anchor.
  @html.div(class="msg user", id?=anchor, [@html.div(class="user-bubble", body)])
}

///|
/// Format a durable event's stamp for the turn rule: the clock alone for
/// something sent today, the date in front of it for anything older, and
/// nothing at all for the zero/absent stamps old stores wrote. Local time and
/// locale order come from the viewer's own environment.
fn clock_label(unix_ms : Double) -> String {
  guard !unix_ms.is_nan() && !unix_ms.is_inf() && unix_ms > 0.0 else {
    return ""
  }
  guard @interop.js_prop(@js.globalThis, "Date") is Some(date_constructor) else {
    return ""
  }
  let at : @js.Value = date_constructor.new([@js.Value::cast_from(unix_ms)])
  let now : @js.Value = date_constructor.new(([] : Array[@js.Value]))
  let locales = @js.Value::cast_from(([] : Array[String]))
  let time_options = @js.Object::new()
  time_options["hour"] = "2-digit"
  time_options["minute"] = "2-digit"
  let clock : String = at.apply_with_string("toLocaleTimeString", [
    locales,
    time_options.to_value(),
  ])
  let at_date : String = at.apply_with_string(
    "toDateString",
    ([] : Array[@js.Value]),
  )
  let today : String = now.apply_with_string(
    "toDateString",
    ([] : Array[@js.Value]),
  )
  if at_date == today {
    return clock
  }
  let date_options = @js.Object::new()
  date_options["month"] = "numeric"
  date_options["day"] = "numeric"
  let date : String = at.apply_with_string("toLocaleDateString", [
    locales,
    date_options.to_value(),
  ])
  date + " " + clock
}

///|
/// The element carrying when a step committed, or `None` when it has no usable
/// stamp — an unstamped row, or the `0` old stores wrote for "no time
/// recorded".
///
/// A step's stamp is the one stamp of the Assistant event that produced it — a
/// matched tool result deliberately leaves its call's stamp alone — so a step
/// is an instant, not a span, and the column of instants down a turn is what
/// shows where its time went.
///
/// The visible label is time-only so the column stays narrow, which leaves one
/// thing it cannot say: which day. A turn running through midnight shows a
/// later step at an earlier clock time. The dated form rides along as the
/// title rather than in the column, since the ambiguity is rare and checking
/// it is deliberate.
fn step_stamp(ts? : Double) -> @html.Html? {
  guard ts is Some(ts) else { return None }
  let label = step_time_label(ts)
  guard !label.is_empty() else { return None }
  Some(
    @html.span(class="activity-time", title=clock_label(ts), [
      speaker_label("Committed "),
      @html.text(label),
    ]),
  )
}

///|
/// A step's commit instant: local time to the second, never a date.
///
/// Deliberately not `clock_label`. That one dates a user's prompt, where the
/// day matters and the minute is precise enough; steps of one turn commit
/// seconds apart, so at `hh:mm` a whole turn would read as the same label
/// repeated. The date is the turn rule's job — a step is always inside the
/// turn already dated above it.
fn step_time_label(unix_ms : Double) -> String {
  guard !unix_ms.is_nan() && !unix_ms.is_inf() && unix_ms > 0.0 else {
    return ""
  }
  guard @interop.js_prop(@js.globalThis, "Date") is Some(date_constructor) else {
    return ""
  }
  let at : @js.Value = date_constructor.new([@js.Value::cast_from(unix_ms)])
  let options = @js.Object::new()
  options["hour"] = "2-digit"
  options["minute"] = "2-digit"
  options["second"] = "2-digit"
  at.apply_with_string("toLocaleTimeString", [
    @js.Value::cast_from(([] : Array[String])),
    options.to_value(),
  ])
}

///|
/// The hairline closing a user's turn: everything below it until the next
/// bubble is the agent's answer. Drawn after the bubble rather than before it
/// because that is the boundary a reader needs — the bubble's own alignment
/// already separates it from the answer above. The rule carries the prompt's
/// send time at its right end, under the bubble it dates; a turn replayed
/// from an unstamped store keeps the bare rule.
fn turn_rule_view(ts? : Double) -> @html.Html {
  let children : Array[@html.Html] = []
  if ts is Some(ts) {
    let label = clock_label(ts)
    if !label.is_empty() {
      children.push(
        @html.span(class="turn-time", [
          speaker_label("Sent "),
          @html.text(label),
        ]),
      )
    }
  }
  @html.div(class="turn-rule", children)
}

///|
/// One transcript item as its own stream child. `step_label` is the ordinal an
/// OpenSeek provider response carries ("#3"); every other source and kind
/// has none.
fn transcript_item_view(
  item : @transcript.TranscriptItem,
  on_open : (String) -> @cmd.Cmd,
  anchor? : String,
  on_jump? : (@mention_context.Target) -> @cmd.Cmd,
  assistant_name? : String = "OpenSeek",
  step_label? : String,
  subrun? : SubrunLink,
) -> @html.Html {
  match item.kind {
    User(prompt) => user_message_view(prompt, anchor?, on_jump?)
    Assistant(reasoning~, prose~, calls~, replay=_, finished~) =>
      assistant_view(
        on_open,
        prose?,
        reasoning?,
        calls~,
        sequence?=item.sequence,
        ts?=item.ts,
        step_label?,
        assistant_name~,
        finished~,
        subrun?,
      )
    Answer(text) =>
      assistant_message_view(
        text,
        on_open,
        assistant_name,
        is_danger=false,
        completed_at?=item.ts,
        show_actions=true,
      )
    Failure(text) =>
      assistant_message_view(text, on_open, assistant_name, is_danger=true)
    Notice(label~, brief~, is_error~, body~) =>
      notice_view(
        label,
        brief,
        is_error,
        body,
        ts?=item.ts,
        sequence?=item.sequence,
      )
    Summary(text) => summary_card_view(text, on_open)
  }
}

///|
/// The agent's prose. A bubble still `streaming` is the in-flight answer
/// rendered live from the engine's deltas: the partial text is re-parsed as
/// markdown on every delta, and an unterminated construct (an open code
/// fence, say) simply renders as plain text until its closing marker streams
/// in. The committed response replaces it.
fn assistant_message_view(
  content : String,
  on_open : (String) -> @cmd.Cmd,
  assistant_name : String,
  is_danger~ : Bool,
  completed_at? : Double,
  show_actions? : Bool = false,
  streaming? : Bool = false,
) -> @html.Html {
  // Errors and abort notices are durable run status rather than assistant
  // prose. Keep their exact text and inline code readable in an unboxed status
  // row; only real assistant replies use markdown. Finished-terminal answers
  // share the ordinary assistant presentation.
  let body = if is_danger {
    @html.div(class="transcript-error-row", [
      @html.span(class="transcript-error-icon", @icons.icon(@icons.icon_close)),
      @html.div(
        class="msg-content transcript-error-message",
        inline_code_nodes(content),
      ),
    ])
  } else {
    @html.div(
      class="msg-content markdown",
      @markdown.markdown_nodes(content, open_file=on_open),
    )
  }
  let children = [speaker_label(assistant_name), body]
  // Only an answer confirmed by the durable Finished terminal gets this row.
  // Tool-prefacing Assistant prose, checkpoint replays, danger notices, and
  // the separate streaming view are not turn-ending answers.
  if show_actions {
    let actions = [
      @html.button(
        class="assistant-message-copy",
        type_="button",
        title="Copy Markdown",
        on_click=@clipboard.copy(@clipboard.Text(content)),
        attrs=@html.Attrs::build().aria_label(
          "Copy assistant message as Markdown",
        ),
        @icons.icon(@icons.icon_copy),
      ),
    ]
    // The durable row is committed only after its complete message becomes
    // available. Its store timestamp is therefore the completion instant; old
    // or client-local rows without a usable stamp simply omit the label.
    if completed_at is Some(ts) {
      let label = clock_label(ts)
      if !label.is_empty() {
        actions.push(
          @html.span(class="assistant-message-time", [
            speaker_label("Completed "),
            @html.text(label),
          ]),
        )
      }
    }
    children.push(@html.div(class="assistant-message-actions", actions))
  }
  let class = if is_danger {
    "msg transcript-error"
  } else if streaming {
    "msg streaming"
  } else {
    "msg"
  }
  @html.div(class~, [@html.div(class="msg-body", children)])
}

///|
/// A compaction checkpoint: the turns above it were summarized into this text
/// and dropped from the context the next prompt carries. Deliberately not an
/// ItemKind the transcript loop batches into a turn's activity group — it
/// stands alone between turns, labeled for what it is, with the summary prose
/// behind the fold.
fn summary_card_view(
  content : String,
  on_open : (String) -> @cmd.Cmd,
) -> @html.Html {
  @html.div(class="activity-row", [
    @html.details(class="summary-card", [
      @html.summary(class="summary-card-label", [
        @html.span(class="summary-card-icon", @icons.icon(@icons.icon_fold)),
        @html.span(class="summary-card-text", "Context compacted"),
      ]),
      @html.div(
        class="msg-content markdown summary-card-body",
        @markdown.markdown_nodes(content, open_file=on_open),
      ),
    ]),
  ])
}

///|
/// The transcript section around its already rendered stream children (see
/// `stream_blocks`): the component memoizes those per block, so this view
/// only assembles them.
fn transcript_view(
  input : Input,
  pinned~ : Bool,
  overview~ : @transcript_overview.State,
  overview_emit~ : @cmd.Emit[@transcript_overview.Msg],
  stream~ : Map[String, @html.Html],
  on_jump_latest~ : @cmd.Cmd,
) -> @html.Html {
  let children = section_children(
    input,
    stream~,
    pinned~,
    overview~,
    overview_emit~,
    on_jump_latest~,
  )
  // These identity attributes make conversation and root changes observable
  // even when the rendered children stay identical. The component subscription
  // reconciles local state on their mutation instead of relying on incidental
  // transcript DOM changes.
  @html.section(
    attrs=@html.Attrs::build()
      .id("transcript")
      .class("transcript")
      .data_set("transcript-source", input.source.wire())
      .data_set("transcript-channel", input.focused.uri_authority())
      .data_set("transcript-session", input.active_session)
      .data_set(
        "transcript-root",
        input.root.map(uri => uri.to_string()).unwrap_or(""),
      )
      .data_set(
        "transcript-submission",
        input.submission_generation.to_string(),
      ),
    children,
  )
}
