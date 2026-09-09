///|
/// Render commentary directly, with independent disclosures for reasoning and tools.
fn assistant_view(
  on_open : (String) -> @cmd.Cmd,
  wait_labels? : Map[Int, String] = Map([]),
  prose? : String,
  reasoning? : String,
  calls? : Array[@transcript.ToolCall] = [],
  sequence? : Int,
  ts? : Double,
  assistant_name? : String = "OpenSeek",
  finished? : Bool = false,
  live? : Bool = false,
  reasoning_complete? : Bool = true,
  subrun? : SubrunLink,
) -> @html.Html {
  let content : Map[String, @html.Html] = Map([])
  if reasoning is Some(text) && !text.is_blank() {
    content.set(
      "thinking",
      @html.details(class="work-thinking", [
        @html.summary(class="work-toggle", [
          @html.span(class="work-chevron", @icons.icon_chevron_down()),
          @html.text(
            if live && !reasoning_complete {
              "Thinking · in progress"
            } else {
              "Thinking"
            },
          ),
        ]),
        @html.div(
          class="work-thinking-body msg-content markdown",
          // Keep growing reasoning as text; Markdown parsing and MoonBit
          // tokenization start only once the reasoning is complete.
          if live && !reasoning_complete {
            [@html.text(text)]
          } else {
            @markdown.markdown_nodes(text, open_file=on_open)
          },
        ),
      ]),
    )
  }
  if prose is Some(text) {
    content.set(
      "message",
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
  }
  if !calls.is_empty() {
    content.set(
      "tools",
      @html.div(
        class="work-tools",
        tool_run_views(calls, sequence?, subrun?, wait_labels~),
      ),
    )
  }
  if finished || (live && reasoning is None) {
    return @html.div(class="step", content)
  }
  @html.div(class="work-step", content)
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
/// Pair each invocation's inputs and output under one stable disclosure. The
/// index disambiguates malformed histories with duplicate call ids; results
/// update in place without changing the request order or browser-owned state.
fn tool_run_views(
  calls : Array[@transcript.ToolCall],
  sequence? : Int,
  subrun? : SubrunLink,
  wait_labels? : Map[Int, String] = Map([]),
) -> Map[String, @html.Html] {
  let rows : Map[String, @html.Html] = Map([])
  for index, call in calls {
    rows["call\u{0}\{call.call_id}\u{0}\{index}"] = tool_exchange_view(
      call,
      sequence?,
      subrun?,
      wait_label?=wait_labels.get(index),
    )
  }
  rows
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
  let body = tool_output_sections(name, arguments, brief, output, key, subrun?)
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
/// Exact output and child-transcript links, reusable inside a notice or call.
fn tool_output_sections(
  name : String,
  arguments : String?,
  brief : String?,
  output : String?,
  key : String,
  subrun? : SubrunLink,
) -> Array[@html.Html] {
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
  body
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
  @html.div(
    class="msg user",
    id?=anchor,
    attrs=@html.Attrs::build().tabindex(0),
    [@html.div(class="user-bubble", body)],
  )
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
  let now : @js.Value = date_constructor.new(([] : FixedArray[@js.Value]))
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
    ([] : FixedArray[@js.Value]),
  )
  let today : String = now.apply_with_string(
    "toDateString",
    ([] : FixedArray[@js.Value]),
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
/// The prompt's send time, aligned beneath its bubble. Unstamped history
/// leaves this row empty; styling removes it from the layout.
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
/// Render one normalized transcript item; the work grouping owns its placement.
fn transcript_item_view(
  item : @transcript.TranscriptItem,
  on_open : (String) -> @cmd.Cmd,
  wait_labels? : Map[Int, String] = Map([]),
  anchor? : String,
  on_jump? : (@mention_context.Target) -> @cmd.Cmd,
  assistant_name? : String = "OpenSeek",
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
        wait_labels~,
        sequence?=item.sequence,
        ts?=item.ts,
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
/// markdown on every delta. Diagram fences render only after their closing
/// marker arrives; unclosed fences remain source in completed messages too.
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
  // Nothing in the app reads the session back from the DOM: the component is
  // created per conversation. The attribute is a test hook only: a draft
  // rotation has no other visible signal (`rabbita_dom.spec.js`, "new-chat
  // project title filters and switches registered projects").
  @html.section(
    attrs=@html.Attrs::build()
      .id("transcript")
      .class("transcript")
      .data_set("transcript-session", input.active_session)
      .data_set(
        "transcript-theme",
        if input.dark_mode {
          "dark"
        } else {
          "light"
        },
      ),
    children,
  )
}
