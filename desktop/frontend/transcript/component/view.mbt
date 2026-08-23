///|
/// The summary line for a run of consecutive tool cards, counting calls by
/// what the engine's tools do — "Read 3 files, edited 2 files, ran 1
/// command". Every built-in `cmd/openseek` tool has a category; unknown and
/// dynamically registered tools remain generic tool calls. Only the name's
/// first token matters, so a runtime-update title like "moon_check compiling"
/// counts as a check update. The retired `moon_cmd` spelling remains readable
/// when replaying an older session.
fn tool_group_summary(items : Array[@transcript.TranscriptItem]) -> String {
  let mut reads = 0
  let mut writes = 0
  let mut edits = 0
  let mut removes = 0
  let mut runs = 0
  let mut background_reads = 0
  let mut background_stops = 0
  let mut plans = 0
  let mut goals = 0
  let mut finishes = 0
  let mut checks = 0
  let mut others = 0
  for item in items {
    guard item.kind is Tool(name~, ..) else { continue }
    let head = match name.trim().split(" ").head() {
      Some(head) => head.to_owned()
      None => ""
    }
    match head {
      "read" => reads = reads + 1
      "write" => writes = writes + 1
      "edit" | "multi_edit" => edits = edits + 1
      "remove" => removes = removes + 1
      "shell" | "moon_cmd" | "run_moonbit" => runs = runs + 1
      "job_output" | "shell_output" => background_reads = background_reads + 1
      "job_stop" | "shell_stop" => background_stops = background_stops + 1
      "plan" => plans = plans + 1
      "goal" => goals = goals + 1
      "finish" => finishes = finishes + 1
      "moon_check" => checks = checks + 1
      _ => others = others + 1
    }
  }
  let parts : Array[String] = []
  // Each tuple is one display category in summary order. Keeping singular and
  // plural text beside its counter makes additions visible in one place.
  let categories = [
    (reads, "read 1 file", "read # files"),
    (writes, "wrote 1 file", "wrote # files"),
    (edits, "edited 1 file", "edited # files"),
    (removes, "removed 1 file", "removed # files"),
    (runs, "ran 1 command", "ran # commands"),
    (background_reads, "checked 1 background job", "checked # background jobs"),
    (background_stops, "stopped 1 background job", "stopped # background jobs"),
    (plans, "1 plan update", "# plan updates"),
    (goals, "1 goal update", "# goal updates"),
    (finishes, "finished", "# finish calls"),
    (checks, "1 check update", "# check updates"),
    (others, "1 tool call", "# tool calls"),
  ]
  for category in categories {
    let (value, singular, plural) = category
    if value > 0 {
      parts.push(
        if value == 1 {
          singular
        } else {
          plural.replace(old="#", new=value.to_string())
        },
      )
    }
  }
  capitalize(parts.join(", "))
}

///|
/// The user-facing reading of a tool burst. Completed tools already carry the
/// concise outcome their executor recorded for `viz_app`; promote those briefs
/// instead of reducing an exact action such as `moon test` to "ran 1 command".
/// Show at most two so a large parallel burst remains a single scannable line;
/// the remainder count includes both unshown briefs and calls still waiting for
/// a result. Old/briefless sessions keep the category summary above.
fn tool_activity_summary(items : Array[@transcript.TranscriptItem]) -> String {
  let briefs : Array[String] = []
  let mut tools = 0
  for item in items {
    guard item.kind is Tool(brief~, ..) else { continue }
    tools = tools + 1
    if brief is Some(brief) {
      let brief = brief.trim()
      if !brief.is_empty() {
        briefs.push(brief.to_owned())
      }
    }
  }
  if briefs.is_empty() {
    return tool_group_summary(items)
  }
  let shown : Array[String] = []
  for brief in briefs {
    if shown.length() == 2 {
      break
    }
    shown.push(brief)
  }
  let remaining = tools - shown.length()
  if remaining > 0 {
    shown.push("+\{remaining} more")
  }
  capitalize(shown.join(" · "))
}

///|
/// Ordinary tool-only activity needs one disclosure level, not the generic
/// activity fold wrapped around another tool-burst fold. Keep the outer fold
/// for failures (its explicit failure badge is accessible without relying on
/// red alone) and for plan calls (it carries the compact progress meter).
fn flatten_tool_activity(items : Array[@transcript.TranscriptItem]) -> Bool {
  !items.is_empty() &&
  count_failed(items) == 0 &&
  items.all(item => item.kind is Tool(name~, ..) && name != "plan")
}

///|
/// A mixed activity card already promotes its only successful tool's brief to
/// the outer summary. Return that tool so the expanded body can show its
/// arguments/output directly instead of repeating the same disclosure label.
/// Keep failed and plan calls nested: their badge and progress affordances
/// belong to the ordinary tool-card rendering.
fn inline_singleton_tool(
  items : Array[@transcript.TranscriptItem],
  allow_tool_only? : Bool = false,
) -> @transcript.TranscriptItem? {
  let mut tool : @transcript.TranscriptItem? = None
  let mut has_reasoning = false
  for item in items {
    match item.kind {
      Reasoning => has_reasoning = true
      Tool(name~, is_error~, ..) if name != "plan" && !is_error =>
        if tool is Some(_) {
          return None
        } else {
          tool = Some(item)
        }
      _ => return None
    }
  }
  if has_reasoning || allow_tool_only {
    tool
  } else {
    None
  }
}

///|
fn capitalize(text : String) -> String {
  // `[first, .. rest]` binds the first Unicode scalar and the true remainder.
  // The old `iter().next()` + `text[1:]` mixed a scalar with a code-unit slice:
  // a non-BMP first char left `text[1:]` inside its surrogate pair, corrupting
  // the tail on native and *panicking* on js (StringView sub mid-surrogate).
  match text {
    [first, .. rest] => "\{first.to_ascii_uppercase()}\{rest}"
    [] => text
  }
}

///|
fn count_failed(items : Array[@transcript.TranscriptItem]) -> Int {
  let mut failed = 0
  for item in items {
    if item.kind is Tool(is_error=true, ..) {
      failed = failed + 1
    }
  }
  failed
}

///|
fn failed_badge(failed : Int) -> @html.Html {
  @html.span(
    class="activity-failed",
    if failed == 1 {
      "1 failed"
    } else {
      "\{failed} failed"
    },
  )
}

///|
/// One durable model step's work, or adjacent activity from another source,
/// folded behind a single summary line ("#2 · Read moon.mod · moon test").
/// Expanding shows the work log in order:
/// reasoning as muted prose — never a labelled "Thinking" row of its own —
/// each burst of tool calls as a one-line sublist. A stretch that only
/// thought folds behind a plain "Thought" line. Failures never force the fold
/// open; they badge the summary instead. The open state is the browser's
/// (`<details>`), so a reader's toggle survives re-renders and the run
/// growing while live.
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
) -> @html.Html {
  if step_label.is_empty() &&
    live_reasoning is None &&
    flatten_tool_activity(items) {
    return @html.div(class="activity-row", [tool_line_view(items)])
  }
  let inline_tool = inline_singleton_tool(
    items,
    allow_tool_only=!step_label.is_empty(),
  )
  let log : Array[@html.Html] = []
  let mut index = 0
  while index < items.length() {
    if items[index].kind is Tool(..) {
      let tools : Array[@transcript.TranscriptItem] = []
      while index < items.length() && items[index].kind is Tool(..) {
        tools.push(items[index])
        index = index + 1
      }
      if inline_tool is Some(tool) && tools.length() == 1 {
        log.push(inline_tool_call_view(tool))
      } else if !step_label.is_empty() {
        // The outer disclosure already groups this model step. Show each call
        // directly rather than adding a redundant second burst disclosure.
        log.append(tools.map(tool_call_view))
      } else {
        log.push(tool_line_view(tools))
      }
    } else {
      // Reasoning; callers never pass user messages, assistant prose, or
      // error bubbles.
      log.push(
        @html.div(
          class="msg-content markdown activity-thinking",
          @markdown.markdown_nodes(items[index].content, open_file=on_open),
        ),
      )
      index = index + 1
    }
  }
  if live_reasoning is Some(content) {
    if reasoning_complete {
      // The semantic completion supplies one whole document, so Markdown is
      // safe and cheap now. The durable item will take over the same card.
      log.push(
        @html.div(
          class="msg-content markdown activity-thinking",
          @markdown.markdown_nodes(content, open_file=on_open),
        ),
      )
    } else {
      // Do not parse an unfinished Markdown document on every provider token.
      // Newlines are preserved by CSS while fragments are still arriving.
      log.push(
        @html.div(
          class="msg-content activity-thinking activity-thinking-live",
          @html.text(content),
        ),
      )
    }
  }
  let failed = count_failed(items)
  let summary_label = tool_activity_summary(items)
  let activity_label = if summary_label.is_empty() {
    if live_reasoning is Some(_) && !reasoning_complete {
      "Thinking…"
    } else {
      "Thought"
    }
  } else {
    summary_label
  }
  // The step ordinal is its own span so it can carry the accent and a fixed
  // numeral column: every step's `·` lands on the same x, so a long run reads
  // as a numbered list rather than a ragged stack of sentences.
  let summary : Array[@html.Html] = [
    if step_label.is_empty() {
      @html.span(class="activity-text", activity_label)
    } else {
      @html.span(class="activity-text", [
        @html.span(class="activity-step", step_label),
        @html.text(" · \{activity_label}"),
      ])
    },
  ]
  if failed > 0 {
    summary.push(failed_badge(failed))
  }
  // The plan as this run left it, so a folded turn reads as the checklist
  // filling up without unfolding anything. A run that touched no plan adds
  // nothing.
  summary.push(@plan.fold_progress(items))
  // When this step committed. Every row of a step shares the one stamp of the
  // Assistant event that produced it — a matched tool result deliberately
  // keeps its call's stamp — so a step is an instant, not a span, and the
  // column of instants down a turn is what shows where its time went.
  if items is [first, ..] && first.ts is Some(ts) {
    let label = step_time_label(ts)
    if !label.is_empty() {
      summary.push(
        @html.span(class="activity-time", [
          speaker_label("Committed "),
          @html.text(label),
        ]),
      )
    }
  }
  @html.div(class="activity-row", [
    @html.details(class="activity", open=live_reasoning is Some(_), [
      @html.summary(class="activity-summary", summary),
      @html.div(class="activity-body", log),
    ]),
  ])
}

///|
/// A burst of consecutive tool calls: one gray line built from the recorded
/// briefs (falling back to category counts for old or pending results) that
/// expands to the per-call arguments and outputs. A singleton is already one
/// call disclosure, so it does not get a redundant burst disclosure around it.
/// A burst with a failure starts open — the failure is what the reader came for.
fn tool_line_view(tools : Array[@transcript.TranscriptItem]) -> @html.Html {
  if tools.length() == 1 {
    return tool_call_view(tools[0])
  }
  let failed = count_failed(tools)
  let summary : Array[@html.Html] = [
    @html.span(class="tool-line-text", tool_activity_summary(tools)),
  ]
  if failed > 0 {
    summary.push(failed_badge(failed))
  }
  @html.details(class="tool-line", open=failed > 0, [
    @html.summary(class="tool-line-summary", summary),
    @html.div(class="tool-line-body", tools.map(tool_call_view)),
  ])
}

///|
/// One tool call inside an expanded burst: its brief ("Read moon.mod", the
/// tool name when the engine sent none), expandable to the original arguments
/// and the later result. Failed calls start open and read red. Calls from older
/// sessions may have no recorded arguments; unmatched results keep their old
/// output-only presentation.
fn tool_call_view(item : @transcript.TranscriptItem) -> @html.Html {
  tool_call_view_mode(item, show_label=true)
}

///|
/// The enclosing activity summary already names this singleton tool.
fn inline_tool_call_view(item : @transcript.TranscriptItem) -> @html.Html {
  tool_call_view_mode(item, show_label=false)
}

///|
fn tool_call_view_mode(
  item : @transcript.TranscriptItem,
  show_label~ : Bool,
) -> @html.Html {
  guard item.kind is Tool(name~, arguments~, is_error~, brief~, ..) else {
    return @html.text("")
  }
  let label = capitalize(
    if brief is Some(brief) && !brief.is_blank() {
      brief
    } else {
      name
    },
  )
  let error_class = if is_error { " error" } else { "" }
  let body : Array[@html.Html] = []
  // A `plan` call shows the checklist it recorded rather than its JSON, in
  // every state where that checklist is what the model asked for. A pending
  // call qualifies: the card is a record of the call, and the missing Output
  // section already marks it unfinished. A rejected one does not — the
  // malformed arguments are what the reader needs, and dressing them up as a
  // checklist would report a plan that never took effect.
  if @plan.classify(item) is Some(Applied(steps) | Pending(steps)) {
    body.push(@html.div(class="tool-call-section", [@plan.card(steps)]))
  } else if arguments is Some(arguments) &&
    custom_card(name, arguments) is Some((label, card)) {
    // Some tools' arguments have a shape JSON hides: a `run_moonbit` program
    // escaped onto one line, an `edit` split across two blobs whose difference
    // is the whole point. Those get a card. A payload the card cannot read
    // falls through to the generic rendering below, so nothing is ever shown
    // as a program or a change that is not one.
    body.push(
      @html.div(class="tool-call-section", [
        @html.div(class="tool-call-section-label", label),
        card,
      ]),
    )
  } else if arguments is Some(arguments) {
    let trimmed = arguments.trim()
    if !trimmed.is_empty() && trimmed != "{}" {
      // Bound the raw payload before parsing: even a collapsed details node is
      // built on every render, and write/edit arguments can contain whole
      // files. Clamp again after pretty-printing because indentation can make a
      // compact JSON payload substantially larger.
      let bounded = truncate_output(arguments)
      let rendered = truncate_output(
        @json.parse(bounded).stringify(indent=2) catch {
          _ => bounded
        },
      )
      body.push(
        @html.div(class="tool-call-section", [
          @html.div(class="tool-call-section-label", "Arguments"),
          @html.pre(class="tool-call-arguments", rendered),
        ]),
      )
    }
  }
  if !item.content.is_blank() {
    body.push(
      @html.div(class="tool-call-section", [
        @html.div(class="tool-call-section-label", "Output"),
        @html.pre(class="tool-call-output", truncate_output(item.content)),
      ]),
    )
  }
  if body.is_empty() {
    if !show_label {
      return @html.text("")
    }
    @html.div(class="tool-call-label" + error_class, label)
  } else if !show_label {
    // The enclosing activity disclosure already carries this one tool's
    // label. Keep the class so the existing section/pre styling still applies.
    @html.div(class="tool-call" + error_class, body)
  } else {
    @html.details(
      class="tool-call" + error_class,
      open=is_error,
      [@html.summary(class="tool-call-summary", label), ..body],
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
) -> @html.Html {
  // Errors and abort notices are plain text; only real assistant replies are
  // markdown. Finished-terminal answers share this exact presentation.
  let body = if is_danger {
    @html.div(class="msg-content danger", inline_code_nodes(content))
  } else {
    @html.div(
      class="msg-content markdown",
      @markdown.markdown_nodes(content, open_file=on_open),
    )
  }
  @html.div(class="msg", [
    @html.div(class="msg-body", [speaker_label(assistant_name), body]),
  ])
}

///|
/// A compaction checkpoint: the turns above it were summarized into this text
/// and dropped from the context the next prompt carries. Deliberately not an
/// ItemKind the transcript loop batches into a turn's activity fold — it
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
  on_jump_latest~ : @cmd.Cmd,
) -> @html.Html {
  let renderer : TranscriptRenderer = { input, on_open, on_jump }
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
