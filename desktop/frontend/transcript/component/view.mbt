///|
/// One durable model step's work, or adjacent activity from another source.
/// Every tool call is always on display as its own one-line row
/// (`tool_call_view`), expandable to that call's arguments and output — so a
/// step that ran ten tools reads as ten scannable rows, not one folded line
/// hiding them. Only reasoning stays behind a fold: a step that opens with a
/// thought carries the ordinal and commit instant on that fold's summary
/// ("#2 14:32:10 · Thought"), and a step that goes straight to tools puts
/// the same columns on a plain heading line instead. The open state of every
/// disclosure is the browser's (`<details>`), so a reader's toggle survives
/// re-renders and the run growing while live.
///
/// Failures need no badge up here: a failed call's own row is visible and
/// carries its own literal `failed` marker. Its potentially large arguments
/// and output stay folded by default, like every other call.
///
/// Assistant prose is never in here: every assistant message is its own
/// visible bubble, so a turn reads as narration, work, narration, work,
/// answer — the agent's own words are never behind a fold.
fn activity_view(
  items : Array[@transcript.TranscriptItem],
  on_open : (String) -> @cmd.Cmd,
  live_reasoning? : String,
  reasoning_complete? : Bool = false,
  step_label? : String = "",
  subrun? : SubrunLink,
) -> @html.Html {
  // The step ordinal is its own span so it can carry the accent and a fixed
  // numeral column, then the instant in a second fixed column: the run reads
  // as a table. The instant belongs beside the ordinal rather than out at the
  // row's right edge — the reason to show it at all is the gap to the step
  // above and below, and comparing a column is the eye's job only when
  // nothing variable-width sits between its entries and their anchor.
  let header : Array[@html.Html] = []
  let stamp = step_stamp(items)
  if !step_label.is_empty() {
    header.push(@html.span(class="activity-step", step_label))
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
  // The header rides the leading thought fold's summary when the step opens
  // with reasoning, keeping the common step's one-line "#2 · Thought" lead. A
  // step that goes straight to tools gets a plain heading line instead: a
  // call row's summary belongs to that call alone.
  let leads_with_thought = match items {
    [first, ..] => first.kind is Reasoning
    [] => live_reasoning is Some(_)
  }
  let mut pending_header = !header.is_empty()
  let rows : Array[@html.Html] = []
  if pending_header && !leads_with_thought {
    rows.push(@html.div(class="activity-heading", header))
    pending_header = false
  }
  fn thought_fold(
    label : String,
    prose : @html.Html,
    unfolded : Bool,
  ) -> @html.Html {
    let text : Array[@html.Html] = []
    if pending_header {
      text.append(header)
      // The separator introduces the label only when something precedes it: a
      // legacy run with no ordinal and no stamp is the label alone.
      text.push(@html.text(" · \{label}"))
      pending_header = false
    } else {
      text.push(@html.text(label))
    }
    @html.details(class="activity", open=unfolded, [
      @html.summary(class="activity-summary", [
        @html.span(class="activity-text", text),
      ]),
      @html.div(class="activity-body", [prose]),
    ])
  }

  let mut index = 0
  while index < items.length() {
    if items[index].kind is Tool(..) {
      let tools : Array[@transcript.TranscriptItem] = []
      while index < items.length() && items[index].kind is Tool(..) {
        tools.push(items[index])
        index += 1
      }
      rows.push(
        @html.div(class="activity-work", tool_run_views(tools, subrun?)),
      )
    } else {
      // Reasoning; callers never pass user messages, assistant prose, or
      // error bubbles.
      rows.push(
        thought_fold(
          "Thought",
          @html.div(
            class="msg-content markdown activity-thinking",
            @markdown.markdown_nodes(items[index].content, open_file=on_open),
          ),
          false,
        ),
      )
      index += 1
    }
  }
  if live_reasoning is Some(content) {
    let prose = if reasoning_complete {
      // The semantic completion supplies one whole document, so Markdown is
      // safe and cheap now. The durable item will take over the same card.
      @html.div(
        class="msg-content markdown activity-thinking",
        @markdown.markdown_nodes(content, open_file=on_open),
      )
    } else {
      // Do not parse an unfinished Markdown document on every provider token.
      // Newlines are preserved by CSS while fragments are still arriving.
      @html.div(
        class="msg-content activity-thinking activity-thinking-live",
        @html.text(content),
      )
    }
    rows.push(
      thought_fold(
        if reasoning_complete {
          "Thought"
        } else {
          "Thinking…"
        },
        prose,
        true,
      ),
    )
  }
  @html.div(class="activity-row", rows)
}

///|
/// Render one consecutive run of tool-shaped transcript items. Calls emitted
/// by the same durable Assistant event share a sequence: show every request
/// first and every result after it, exactly as the viz HTML renderer's
/// Assistant card followed by result cards makes a parallel burst readable.
/// Different or absent sequences cannot prove a burst, so keep each request
/// beside its own result instead of implying concurrency.
fn tool_run_views(
  items : Array[@transcript.TranscriptItem],
  subrun? : SubrunLink,
) -> Map[String, @html.Html] {
  let rows : Map[String, @html.Html] = Map([])
  let same_assistant_event = match items {
    [first, ..] if items.length() > 1 && first.sequence is Some(sequence) =>
      items.all(item => {
        item.sequence == Some(sequence) &&
        item.kind is Tool(arguments=Some(_), ..)
      })
    _ => false
  }
  if same_assistant_event {
    for index, item in items {
      if item.kind is Tool(arguments=Some(_), ..) {
        rows[tool_run_row_key(item, index, "request")] = tool_request_view(item)
      }
    }
    for index, item in items {
      if tool_result_row_is_visible(item) {
        rows[tool_run_row_key(item, index, "result")] = tool_result_view(
          item,
          subrun?,
        )
      }
    }
  } else {
    for index, item in items {
      if item.kind is Tool(arguments=Some(_), ..) {
        rows[tool_run_row_key(item, index, "request")] = tool_request_view(item)
      }
      if tool_result_row_is_visible(item) {
        rows[tool_run_row_key(item, index, "result")] = tool_result_view(
          item,
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
  item : @transcript.TranscriptItem,
  index : Int,
  side : String,
) -> String {
  guard item.kind is Tool(call_id~, name~, ..) else {
    return "\{side}\u{0}\{index}"
  }
  let identity = if call_id.is_empty() { name } else { call_id }
  "\{side}\u{0}\{identity}\u{0}\{index}"
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
/// command items can also accumulate output while still in progress; surface
/// that stream immediately, but let `has_result` keep the row labelled pending
/// until the completed item arrives.
fn tool_result_row_is_visible(item : @transcript.TranscriptItem) -> Bool {
  guard item.kind is Tool(has_result~, ..) else { return false }
  has_result || !item.content.is_blank()
}

///|
/// One recorded tool request, always on display as its own row. Its brief is
/// the result-derived caption the viz renderer also promotes onto the call;
/// expanding reveals only what the model sent. Failed calls read red and carry
/// a literal marker, while their separate result row owns the output.
fn tool_request_view(item : @transcript.TranscriptItem) -> @html.Html {
  guard item.kind
    is Tool(call_id~, name~, arguments=Some(arguments), is_error~, brief~, ..) else {
    return @html.nothing
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
  line.push(@plan.fold_progress([item]))
  let body : Array[@html.Html] = []
  // A `plan` call shows the checklist it recorded rather than its JSON, in
  // every state where that checklist is what the model asked for. A pending
  // call qualifies: the card is a record of the call, and the missing Output
  // section already marks it unfinished. A rejected one does not — the
  // malformed arguments are what the reader needs, and dressing them up as a
  // checklist would report a plan that never took effect.
  if @plan.classify(item) is Some(Applied(steps) | Pending(steps)) {
    body.push(@html.div(class="tool-call-section", [@plan.card(steps)]))
  } else if tool_arguments_tabbed_view(
      tool_call_tabs_key(call_id, item.sequence),
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
  item : @transcript.TranscriptItem,
  subrun? : SubrunLink,
) -> @html.Html {
  guard item.kind
    is Tool(call_id~, name~, arguments~, has_result~, is_error~, brief~) else {
    return @html.nothing
  }
  let label = match (arguments, brief, has_result) {
    (None, Some(brief), _) if !brief.is_blank() => brief
    (None, _, _) => name
    (_, _, false) => "Tool output · \{name}"
    _ if is_error => "Tool error · \{name}"
    _ => "Tool result · \{name}"
  }
  let error_class = (if is_error { " error" } else { "" }) +
    failure_stage_class(name, brief, is_error, arguments)
  let pending_class = if has_result { "" } else { " pending" }
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
  if !item.content.is_blank() {
    let key = tool_call_tabs_key(call_id, item.sequence)
    let output = tool_output_tabs(name, arguments, item.content)
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
/// Every row of a step shares the one stamp of the Assistant event that
/// produced it — a matched tool result deliberately keeps its call's stamp —
/// so a step is an instant, not a span, and the column of instants down a turn
/// is what shows where its time went.
///
/// The visible label is time-only so the column stays narrow, which leaves one
/// thing it cannot say: which day. A turn running through midnight shows a
/// later step at an earlier clock time. The dated form rides along as the
/// title rather than in the column, since the ambiguity is rare and checking
/// it is deliberate.
fn step_stamp(items : Array[@transcript.TranscriptItem]) -> @html.Html? {
  guard items is [first, ..] && first.ts is Some(ts) else { return None }
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
fn transcript_item_view(
  item : @transcript.TranscriptItem,
  on_open : (String) -> @cmd.Cmd,
  anchor? : String,
  on_jump? : (@mention_context.Target) -> @cmd.Cmd,
  assistant_name? : String = "OpenSeek",
) -> @html.Html {
  match item.kind {
    User => user_message_view(item.content, anchor?, on_jump?)
    Assistant(is_danger~) =>
      assistant_message_view(item.content, on_open, assistant_name, is_danger~)
    AssistantReplay =>
      assistant_message_view(
        item.content,
        on_open,
        assistant_name,
        is_danger=false,
      )
    TerminalAnswer =>
      assistant_message_view(
        item.content,
        on_open,
        assistant_name,
        is_danger=false,
        completed_at?=item.ts,
        show_actions=true,
      )
    // Unreachable in practice — the transcript loop batches every reasoning
    // and tool item into a run and builds the activity card itself — but the
    // match must cover them, so a stray item gets the same one-item card.
    Reasoning => activity_view([item], on_open)
    Tool(..) => activity_view([item], on_open)
    Summary => summary_card_view(item.content, on_open)
  }
}

///|
fn assistant_message_view(
  content : String,
  on_open : (String) -> @cmd.Cmd,
  assistant_name : String,
  is_danger~ : Bool,
  completed_at? : Double,
  show_actions? : Bool = false,
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
  @html.div(class=if is_danger { "msg transcript-error" } else { "msg" }, [
    @html.div(class="msg-body", children),
  ])
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
/// The in-flight assistant turn, rendered live from the engine's streamed
/// deltas. The committed `assistant_message` replaces it in the transcript.
/// The partial text is re-parsed as markdown on every delta; an unterminated
/// construct (e.g. an open code fence) simply renders as plain text until its
/// closing marker streams in.
fn streaming_response_view(
  content : String,
  on_open : (String) -> @cmd.Cmd,
  assistant_name? : String = "OpenSeek",
) -> @html.Html {
  @html.div(class="msg streaming", [
    @html.div(class="msg-body", [
      speaker_label(assistant_name),
      @html.div(
        class="msg-content markdown",
        @markdown.markdown_nodes(content, open_file=on_open),
      ),
    ]),
  ])
}

///|
fn transcript_view(
  input : Input,
  pinned~ : Bool,
  overview~ : @transcript_overview.State,
  overview_emit~ : @cmd.Emit[@transcript_overview.Msg],
  on_open : (String) -> @cmd.Cmd,
  on_jump : (@mention_context.Target) -> @cmd.Cmd,
  on_open_session : (String) -> @cmd.Cmd,
  on_jump_latest~ : @cmd.Cmd,
) -> @html.Html {
  let renderer : TranscriptRenderer = {
    input,
    on_open,
    on_jump,
    on_open_session,
  }
  let children = renderer.section_children(
    pinned, overview, overview_emit, on_jump_latest,
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
