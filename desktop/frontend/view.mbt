///|
fn can_stop(conv : Conversation) -> Bool {
  conv.running && conv.active_run_id is Some(_)
}

///|
fn token_label(tokens : Int) -> String {
  "\{compact_count(tokens)} tokens"
}

///|
/// A count compacted for a pill: exact under a thousand, otherwise one
/// decimal of k/M with a whole value's ".0" dropped — 999 → "999",
/// 12_345 → "12.3k", 10_000 → "10k", 1_230_000 → "1.2M".
fn compact_count(value : Int) -> String {
  fn scaled(tenths : Int, unit : String) -> String {
    if tenths % 10 == 0 {
      "\{tenths / 10}\{unit}"
    } else {
      "\{tenths / 10}.\{tenths % 10}\{unit}"
    }
  }

  if value < 1000 {
    value.to_string()
  } else if value < 999_950 {
    // Rounded tenths of a thousand; the cap keeps the k form from rounding
    // up to "1000k" — beyond it the M form takes over.
    scaled((value + 50) / 100, "k")
  } else {
    scaled((value + 50_000) / 100_000, "M")
  }
}

///|
/// One settings row: name and optional description on the left, the control
/// on the right. `stack=true` drops the control below the text at full
/// width instead, for free-form fields (URLs, keys) that a narrow right
/// column would squeeze.
fn setting_row(
  name : String,
  controls : Array[@html.Html],
  desc? : String,
  stack? : Bool = false,
) -> @html.Html {
  let text : Array[@html.Html] = [@html.div(class="setting-name", name)]
  if desc is Some(desc) && !desc.is_empty() {
    text.push(@html.div(class="setting-desc", desc))
  }
  @html.div(class=if stack { "setting-row stack" } else { "setting-row" }, [
    @html.div(class="setting-text", text),
    @html.div(class="setting-control", controls),
  ])
}

///|
/// A titled run of settings rows under an uppercase heading, mirroring the
/// Skills page's "Installed" / "Mooncakes registry" sections.
fn settings_group(title : String, rows : Array[@html.Html]) -> @html.Html {
  let children : Array[@html.Html] = [
    @html.div(class="settings-group-title", title),
  ]
  for row in rows {
    children.push(row)
  }
  @html.div(class="settings-group", children)
}

///|
fn model_select(dispatch : @cmd.Emit[Msg], selected : String) -> @html.Html {
  @html.select(on_change=dispatch.map(value => ModelChanged(value)), [
    @html.option(
      value="deepseek-v4-pro",
      selected=selected == "deepseek-v4-pro",
      "deepseek-v4-pro",
    ),
    @html.option(
      value="deepseek-v4-flash",
      selected=selected == "deepseek-v4-flash",
      "deepseek-v4-flash",
    ),
  ])
}

///|
fn conversation_title(conv : Conversation) -> String {
  for item in conv.messages {
    if item.kind is User {
      let title = item.content.trim().to_owned()
      if !title.is_empty() {
        return title
      }
    }
  }
  @transcript.non_empty_or(conv.task.trim().to_owned(), "OpenSeek Desktop")
}

///|
/// One sidebar row. A conversation with a turn in flight gets a pulsing dot,
/// so background work stays visible while another conversation is on screen.
/// A durable, idle row also carries a hover-revealed archive button; the row
/// itself is a div (not a button) so that control can nest inside it.
fn session_row(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  session_id : String,
  label : String,
  archivable? : Bool = false,
) -> @html.Html {
  let active = session_id == model.active_session
  let running = model.find_conversation(session_id) is Some(conv) &&
    conv.running
  let mut class = "conversation-row"
  if active {
    class = class + " active"
  }
  if running {
    class = class + " running"
  }
  let children = [@html.span(class="sidebar-label", label)]
  if running {
    children.push(@html.span(class="run-dot accent pulse", ""))
  }
  // Archiving a running conversation would pull the workspace out from under
  // its engine, so the button waits for the turn to end.
  if archivable && !running {
    children.push(
      @html.button(
        class="row-archive",
        type_="button",
        title="Archive — zip the workspace folder and tuck this chat away",
        attrs=@html.Attrs::build().on_click(event => {
          // The row itself opens the session; the archive click must not.
          event.stop_propagation()
          dispatch(ArchiveSession(session_id))
        }),
        icon(icon_archive),
      ),
    )
  }
  @html.div(
    class~,
    title=session_id,
    on_click=dispatch(OpenSession(session_id)),
    children,
  )
}

///|
/// Sidebar rows: conversations that only exist in this app run (no turn has
/// reached the store yet) first, then the engine's durable sessions, newest
/// first. Rows stay clickable while runs are active — switching between
/// conversations mid-run is the point of keeping them concurrent.
fn session_rows(dispatch : @cmd.Emit[Msg], model : Model) -> Array[@html.Html] {
  let rows : Array[@html.Html] = []
  let listed = (id : String) => {
    for item in model.sessions {
      if item.id == id {
        return true
      }
    }
    false
  }
  // Newest rotation last in the array; show unlisted conversations newest
  // first to match the store list's ordering.
  for conv in model.conversations.rev_iter() {
    if !listed(conv.session_id) && !model.archived.contains(conv.session_id) {
      rows.push(
        session_row(dispatch, model, conv.session_id, conversation_title(conv)),
      )
    }
  }
  for item in model.sessions {
    if model.archived.contains(item.id) {
      continue
    }
    let label = if model.find_conversation(item.id) is Some(conv) &&
      item.id == model.active_session {
      conversation_title(conv)
    } else {
      @transcript.non_empty_or(item.title, item.id)
    }
    rows.push(session_row(dispatch, model, item.id, label, archivable=true))
  }
  if !model.sessions_error.is_empty() {
    rows.push(
      @html.div(class="conversation-row error", title=model.sessions_error, [
        @html.span(class="sidebar-label", "sessions unavailable"),
      ]),
    )
  }
  if !model.archive_error.is_empty() {
    rows.push(
      @html.div(class="conversation-row error", title=model.archive_error, [
        @html.span(class="sidebar-label", "archive failed"),
      ]),
    )
  }
  // Archived conversations stay reachable (their transcripts live in the
  // engine's store; only the workspace folder was zipped away) but fold
  // behind a collapsed group at the end of the list.
  let archived_rows : Array[@html.Html] = []
  for item in model.sessions {
    if model.archived.contains(item.id) {
      archived_rows.push(
        session_row(
          dispatch,
          model,
          item.id,
          @transcript.non_empty_or(item.title, item.id),
        ),
      )
    }
  }
  if archived_rows.length() > 0 {
    rows.push(
      @html.details(class="sidebar-archived", [
        @html.summary(
          class="sidebar-heading archived-heading",
          "Archived (\{archived_rows.length()})",
        ),
        @html.div(class="archived-rows", archived_rows),
      ]),
    )
  }
  rows
}

///|
fn sidebar_view(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let sessions_section : Array[@html.Html] = [
    @html.div(class="sidebar-heading", "Chats"),
  ]
  for row in session_rows(dispatch, model) {
    sessions_section.push(row)
  }
  @html.aside([
    @html.div(class="sidebar-main", [
      @html.div(class="sidebar-section", [
        @html.button(class="sidebar-button", on_click=dispatch(NewChat), [
          @html.span(class="sidebar-icon", icon(icon_add)),
          @html.span(class="sidebar-label", "New chat"),
        ]),
      ]),
      @html.div(class="sidebar-section sessions", sessions_section),
    ]),
    @html.div(class="sidebar-footer", [
      @html.button(
        class=if model.screen is Skills {
          "sidebar-button active"
        } else {
          "sidebar-button"
        },
        on_click=dispatch(OpenSkills),
        [
          @html.span(class="sidebar-icon", icon(icon_extensions)),
          @html.span(class="sidebar-label", "Skills"),
        ],
      ),
      @html.button(
        class=if model.screen is Settings {
          "sidebar-button active"
        } else {
          "sidebar-button"
        },
        on_click=dispatch(OpenSetup),
        [
          @html.span(class="sidebar-icon", icon(icon_settings_gear)),
          @html.span(class="sidebar-label", "Settings"),
        ],
      ),
    ]),
  ])
}

///|
fn tool_class(is_error : Bool) -> String {
  if is_error {
    "tool-card error"
  } else {
    "tool-card"
  }
}

///|
/// One tool result's card (name header + output), shown inside an expanded
/// tool group.
fn tool_card(name : String, is_error : Bool, content : String) -> @html.Html {
  @html.div(class=tool_class(is_error), [
    @html.div(class="tool-head", @transcript.non_empty_or(name, "tool")),
    @html.pre(content),
  ])
}

///|
/// The summary line for a run of consecutive tool cards, counting calls by
/// what the engine's tools do — "Read 3 files, edited 2 files, ran 1
/// command". Only the name's first token matters, so a runtime-update title
/// like "moon_check compiling" counts as a check update.
fn tool_group_summary(items : Array[@transcript.TranscriptItem]) -> String {
  let mut reads = 0
  let mut writes = 0
  let mut edits = 0
  let mut runs = 0
  let mut checks = 0
  let mut others = 0
  for item in items {
    guard item.kind is Tool(name, _) else { continue }
    let head = match name.trim().split(" ").head() {
      Some(head) => head.to_owned()
      None => ""
    }
    match head {
      "read" => reads = reads + 1
      "write" => writes = writes + 1
      "edit" | "multi_edit" => edits = edits + 1
      "shell" | "moon_cmd" => runs = runs + 1
      "moon_check" => checks = checks + 1
      _ => others = others + 1
    }
  }
  fn count(value : Int, one : String, many : String) -> String {
    if value == 1 {
      one
    } else {
      many.replace(old="#", new=value.to_string())
    }
  }

  let parts : Array[String] = []
  if reads > 0 {
    parts.push(count(reads, "read 1 file", "read # files"))
  }
  if writes > 0 {
    parts.push(count(writes, "wrote 1 file", "wrote # files"))
  }
  if edits > 0 {
    parts.push(count(edits, "edited 1 file", "edited # files"))
  }
  if runs > 0 {
    parts.push(count(runs, "ran 1 command", "ran # commands"))
  }
  if checks > 0 {
    parts.push(count(checks, "1 check update", "# check updates"))
  }
  if others > 0 {
    parts.push(count(others, "1 tool call", "# tool calls"))
  }
  capitalize(parts.join(", "))
}

///|
fn capitalize(text : String) -> String {
  if text.iter().next() is Some(first) {
    "\{first.to_ascii_uppercase()}" + text[1:].to_owned()
  } else {
    text
  }
}

///|
/// A run of consecutive tool results, folded into one card: the collapsed
/// line is the group's summary, expanding shows the individual outputs. A
/// group with a failure starts open and badges the count — errors are the
/// one thing that must not hide behind the fold. The open state is the
/// browser's (`<details>`), so a reader's toggle survives streaming
/// re-renders.
fn tool_group_view(items : Array[@transcript.TranscriptItem]) -> @html.Html {
  let mut failed = 0
  let cards : Array[@html.Html] = []
  for item in items {
    guard item.kind is Tool(name, is_error) else { continue }
    if is_error {
      failed = failed + 1
    }
    cards.push(tool_card(name, is_error, item.content))
  }
  let summary : Array[@html.Html] = [
    @html.span(class="tool-group-text", tool_group_summary(items)),
  ]
  if failed > 0 {
    summary.push(
      @html.span(
        class="tool-group-failed",
        if failed == 1 {
          "1 failed"
        } else {
          "\{failed} failed"
        },
      ),
    )
  }
  @html.div(class="tool-row", [
    @html.details(
      class=if failed > 0 { "tool-group error" } else { "tool-group" },
      open=failed > 0,
      [
        @html.summary(class="tool-group-summary", summary),
        @html.div(class="tool-group-body", cards),
      ],
    ),
  ])
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
            nodes.push(@html.text(segment))
          }
        }
        rest = after.to_owned()
        in_code = !in_code
      }
      None => {
        if in_code {
          nodes.push(@html.text("`" + rest))
        } else if !rest.is_empty() {
          nodes.push(@html.text(rest))
        }
        done = true
      }
    }
  }
  nodes
}

///|
fn transcript_item_view(
  item : @transcript.TranscriptItem,
  on_open : (String) -> @cmd.Cmd,
) -> @html.Html {
  match item.kind {
    User =>
      @html.div(class="msg", [
        @html.div(class="avatar user", "›"),
        @html.div(class="msg-body", [
          @html.div(class="msg-role", "You"),
          @html.div(class="msg-content", inline_code_nodes(item.content)),
        ]),
      ])
    Assistant(is_danger) => {
      // Errors and abort notices are plain text; only real assistant replies
      // are markdown.
      let content = if is_danger {
        @html.div(class="msg-content danger", inline_code_nodes(item.content))
      } else {
        @html.div(
          class="msg-content markdown",
          @markdown.markdown_nodes(item.content, open_file=on_open),
        )
      }
      @html.div(class="msg", [
        @html.div(class="avatar agent", "✦"),
        @html.div(class="msg-body", [
          @html.div(class="msg-role", "openseek"),
          content,
        ]),
      ])
    }
    Reasoning => collapsed_reasoning_view(item.content, on_open)
    // Reached only for a tool item outside a group (the transcript loop
    // batches consecutive ones into `tool_group_view` itself).
    Tool(_) => tool_group_view([item])
  }
}

///|
/// A committed reasoning block, folded to its "Thinking" line: the transcript
/// is for answers, so past thinking tucks away behind a native `<details>`
/// toggle. The open state lives in the DOM — index-based diffing patches the
/// same element across renders, so it survives streaming without any model
/// bookkeeping. The in-flight stream stays expanded (`reasoning_view`).
fn collapsed_reasoning_view(
  content : String,
  on_open : (String) -> @cmd.Cmd,
) -> @html.Html {
  @html.div(class="msg", [
    @html.div(class="avatar agent", "✧"),
    @html.div(class="msg-body", [
      @html.details(class="reasoning-details", [
        @html.summary(class="msg-role reasoning-summary", "Thinking"),
        @html.div(
          class="msg-content markdown reasoning",
          @markdown.markdown_nodes(content, open_file=on_open),
        ),
      ]),
    ]),
  ])
}

///|
/// The live reasoning stream, always expanded — folding text that is still
/// arriving would hide the one thing the user is watching.
fn reasoning_view(
  content : String,
  streaming~ : Bool,
  on_open : (String) -> @cmd.Cmd,
) -> @html.Html {
  let msg_class = if streaming { "msg streaming" } else { "msg" }
  @html.div(class=msg_class, [
    @html.div(class="avatar agent", "✧"),
    @html.div(class="msg-body", [
      @html.div(class="msg-role", "Thinking"),
      @html.div(
        class="msg-content markdown reasoning",
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
) -> @html.Html {
  @html.div(class="msg streaming", [
    @html.div(class="avatar agent", "✦"),
    @html.div(class="msg-body", [
      @html.div(class="msg-role", "openseek"),
      @html.div(
        class="msg-content markdown",
        @markdown.markdown_nodes(content, open_file=on_open),
      ),
    ]),
  ])
}

///|
fn transcript_view(
  dispatch : @cmd.Emit[Msg],
  conv : Conversation,
  pinned~ : Bool,
  on_open : (String) -> @cmd.Cmd,
) -> @html.Html {
  let items : Array[@html.Html] = []
  if conv.messages.is_empty() {
    items.push(
      @html.div(class="empty", [
        @html.div(class="empty-badge", "✦"),
        @html.div(class="empty-title", "What should we build?"),
        @html.div(
          class="empty-sub",
          "OpenSeek plans the work, edits files across your workspace, runs your tests, and hands back a reviewable result.",
        ),
      ]),
    )
  } else {
    // Consecutive tool results fold into one summarized group card; any
    // other item breaks the run.
    let mut index = 0
    while index < conv.messages.length() {
      if conv.messages[index].kind is Tool(_) {
        let group : Array[@transcript.TranscriptItem] = []
        while index < conv.messages.length() &&
              conv.messages[index].kind is Tool(_) {
          group.push(conv.messages[index])
          index = index + 1
        }
        items.push(tool_group_view(group))
      } else {
        items.push(transcript_item_view(conv.messages[index], on_open))
        index = index + 1
      }
    }
  }
  // Both buffers can be non-empty at once: the answer starts streaming
  // before the engine commits the reasoning. Only the bubble that text is
  // currently appearing in gets the caret.
  if !conv.streaming_reasoning.is_empty() {
    items.push(
      reasoning_view(
        conv.streaming_reasoning,
        streaming=conv.streaming_response.is_empty(),
        on_open,
      ),
    )
  }
  if !conv.streaming_response.is_empty() {
    items.push(streaming_response_view(conv.streaming_response, on_open))
  }
  let children = [@html.div(id="stream", class="stream", items)]
  // Reading history unpins auto-follow (see `watch_transcript_scroll`); the
  // floating button is the way back to the live tail. Sticky inside the
  // scroller with zero height, so it never adds scroll length.
  if !pinned {
    children.push(
      @html.div(class="jump-latest-wrap", [
        @html.button(
          class="jump-latest",
          type_="button",
          title="Jump to latest",
          on_click=dispatch(JumpToLatest),
          icon(icon_arrow_down),
        ),
      ]),
    )
  }
  @html.section(id="transcript", class="transcript", children)
}

///|
/// Steering input the engine has not settled yet, shown as a panel docked
/// above the composer: the submission is acknowledged immediately, but it
/// only joins the transcript when the engine folds it into the turn
/// (`steer_applied` commits it as a real user message).
fn pending_steers_panel(conv : Conversation) -> @html.Html {
  let rows : Array[@html.Html] = []
  for text in conv.pending_steers {
    rows.push(
      @html.div(class="pending-steer-row", title=text, [
        @html.span(class="pending-steer-icon", "⤷"),
        @html.span(class="pending-steer-text", text),
        @html.span(class="pending-steer-state", "steering…"),
      ]),
    )
  }
  @html.div(class="pending-steers", rows)
}

///|
/// Composer key handling. While the completion menu is open it captures the
/// navigation keys — ↑/↓ move the highlight, Enter/Tab accept, Escape closes —
/// so they drive the menu instead of the textarea; everything else (and every
/// key with the menu closed) falls through to the normal submit shortcut.
fn task_attrs(dispatch : @cmd.Emit[Msg], menu_open : Bool) -> @html.Attrs {
  @html.Attrs::build().on_keydown(fn(event) {
    if menu_open {
      match event.key() {
        "ArrowDown" => {
          event.prevent_default()
          dispatch(CompletionMove(1))
        }
        "ArrowUp" => {
          event.prevent_default()
          dispatch(CompletionMove(-1))
        }
        "Tab" => {
          event.prevent_default()
          dispatch(CompletionAccept)
        }
        "Enter" =>
          if !event.shift_key() && !event.is_composing() {
            event.prevent_default()
            dispatch(CompletionAccept)
          } else {
            @cmd.none
          }
        "Escape" => {
          event.prevent_default()
          dispatch(CompletionDismiss)
        }
        _ => @cmd.none
      }
    } else if is_submit_shortcut(event) {
      event.prevent_default()
      dispatch(Send)
    } else {
      @cmd.none
    }
  })
}

///|
/// The completion menu floating above the composer: one row per match, the
/// highlighted row marked for the keyboard and clickable by mouse. A pointer
/// press accepts a row; `mousedown` (not `click`) is used so the textarea does
/// not blur the menu away before the selection registers.
fn completion_popup(
  dispatch : @cmd.Emit[Msg],
  completion : Completion,
) -> @html.Html {
  let rows : Array[@html.Html] = []
  for index, item in completion.items {
    let selected = index == completion.selected
    let row_class = if selected {
      "completion-item selected"
    } else {
      "completion-item"
    }
    rows.push(
      @html.div(
        class=row_class,
        attrs=@html.Attrs::build().on_mousedown(fn(event) {
          // Keep focus in the textarea; accept the row the press landed on.
          event.prevent_default()
          dispatch(CompletionPick(index))
        }),
        [
          @html.span(class="completion-label", item.label),
          @html.span(class="completion-detail", item.detail),
        ],
      ),
    )
  }
  // A `#` menu opens before its results arrive, so an empty list is a state to
  // narrate — searching, or genuinely nothing — not an empty box.
  if rows.is_empty() {
    let text = if completion.loading { "Searching…" } else { "No symbols" }
    rows.push(@html.div(class="completion-empty", text))
  }
  let hint = match completion.kind {
    SlashCommands => "Commands"
    SkillMentions => "Skills"
    Symbols => "Symbols"
  }
  @html.div(class="completion-menu", [
    @html.div(class="completion-hint", hint),
    @html.div(class="completion-list", rows),
  ])
}

///|
/// The chips above the textarea for the draft's mentions (`$` skills, `#`
/// symbols), each removable by its `×`. Always rendered (empty when there are
/// no chips) so the textarea keeps a stable child index and never loses focus
/// when a chip comes or goes; CSS collapses the empty tray to nothing. A
/// symbol chip with a resolved location is also clickable, opening (or
/// refocusing) the editor side-panel on that spot.
fn mention_tray(dispatch : @cmd.Emit[Msg], conv : Conversation) -> @html.Html {
  let chips : Array[@html.Html] = []
  for index, mention in conv.mentions {
    let glyph = @html.span(class="mention-glyph", mention.kind.glyph())
    let label = @html.span(class="mention-label", mention.label)
    let body = if mention.path is Some(path) {
      @html.button(
        class="mention-jump",
        type_="button",
        title="Jump to \{path}",
        on_click=dispatch(JumpToMention(index)),
        [glyph, label],
      )
    } else {
      @html.span(class="mention-body", [glyph, label])
    }
    chips.push(
      @html.div(class="mention-chip", [
        body,
        @html.button(
          class="mention-remove",
          type_="button",
          title="Remove",
          on_click=dispatch(RemoveMention(index)),
          icon(icon_close),
        ),
      ]),
    )
  }
  @html.div(class="mention-tray", chips)
}

///|
fn composer_view(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let conv = model.active()
  let has_input = model.bridge_ready && model.api_ready() && !conv.draft_empty()
  let can_send = !conv.running && has_input
  let controls : Array[@html.Html] = [
    @html.span(
      class="composer-model",
      title=model.selected_model,
      model.selected_model,
    ),
  ]
  if conv.running {
    // One morphing button while this conversation's turn runs: a non-empty
    // draft (text or chips) turns it into a steer submit, an empty composer
    // leaves it as the interrupt. A turn being cancelled cannot be steered, so
    // the button waits with the user's draft in the composer.
    if conv.draft_empty() {
      controls.push(
        @html.button(
          id="stop",
          class="icon-button stop-button",
          title="Stop",
          disabled=!can_stop(conv),
          on_click=dispatch(Stop),
          icon(icon_debug_stop),
        ),
      )
    } else {
      let can_steer = has_input && !(conv.status is Cancelling)
      controls.push(
        @html.button(
          id="send",
          class="icon-button send-button",
          title="Steer the running task",
          disabled=!can_steer,
          on_click=dispatch(Send),
          icon(icon_arrow_up),
        ),
      )
    }
  } else {
    controls.push(
      @html.button(
        id="send",
        class="icon-button send-button",
        title="Send",
        disabled=!can_send,
        on_click=dispatch(Send),
        icon(icon_arrow_up),
      ),
    )
  }
  let children : Array[@html.Html] = []
  if conv.pending_steers.length() > 0 {
    children.push(pending_steers_panel(conv))
  }
  if conv.compacting {
    children.push(
      @html.div(class="composer-notice", [
        @html.span(class="composer-notice-icon", icon(icon_fold)),
        @html.span(class="composer-notice-text", "Compacting context…"),
      ]),
    )
  }
  let inner : Array[@html.Html] = [
    // First child, always present, so the textarea's index never shifts (which
    // would rebuild the node and drop focus) as chips come and go.
    mention_tray(dispatch, conv),
    @html.textarea(
      id="task",
      value=conv.task,
      placeholder=if conv.running {
        "Steer the running task — your message joins it at the next step."
      } else {
        "Ask OpenSeek to inspect, edit, or explain this workspace."
      },
      on_input=dispatch.map(value => TaskChanged(value)),
      attrs=task_attrs(dispatch, model.completion is Some(_)),
      "",
    ),
    @html.div(class="composer-toolbar", [
      @html.div(class="composer-controls", controls),
    ]),
  ]
  // The menu floats above the composer via CSS, so its DOM position does not
  // affect layout. It is appended last (not inserted before the textarea) so
  // toggling it never shifts the textarea's child index — index-based vdom
  // diffing would otherwise rebuild the textarea node and drop its focus.
  if model.completion is Some(completion) {
    inner.push(completion_popup(dispatch, completion))
  }
  children.push(@html.div(class="composer-inner", inner))
  @html.section(class="composer", children)
}

///|
fn provider_select(
  dispatch : @cmd.Emit[Msg],
  selected : ApiProvider,
) -> @html.Html {
  @html.select(on_change=dispatch.map(value => ProviderChanged(value)), [
    @html.option(
      value="openseek",
      selected=selected is Openseek,
      "OpenSeek (default, no API key)",
    ),
    @html.option(
      value="deepseek",
      selected=selected is Deepseek,
      "DeepSeek official (your API key)",
    ),
    @html.option(value="custom", selected=selected is Custom, "Custom URL"),
  ])
}

///|
fn wsl_select(dispatch : @cmd.Emit[Msg], enabled : Bool) -> @html.Html {
  @html.select(on_change=dispatch.map(value => WslModeChanged(value)), [
    @html.option(value="native", selected=!enabled, "Windows (native)"),
    @html.option(value="wsl", selected=enabled, "WSL"),
  ])
}

///|
fn provider_hint(provider : ApiProvider) -> String {
  match provider {
    Openseek => "Requests go through the OpenSeek service; no key needed."
    Deepseek => "Requests go straight to api.deepseek.com with your key."
    Custom => "Any DeepSeek-compatible chat-completions URL; key optional."
  }
}

///|
/// The Settings page, shown in the main area in place of the conversation
/// (mirroring the Skills page — the sidebar is the way out, no Done button).
/// While the configured endpoint is unusable the page takes over on its own,
/// and the composer keeps Send disabled until a usable endpoint is saved.
fn settings_page(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let ready = model.api_ready()
  let model_rows : Array[@html.Html] = [
    setting_row(
      "Model",
      [model_select(dispatch, model.selected_model)],
      desc="Used for new turns in every conversation.",
    ),
    setting_row(
      "Max steps",
      [
        @html.input(
          input_type=@html.InputType::Number,
          value=model.max_steps,
          placeholder="1000",
          on_input=dispatch.map(value => MaxStepsChanged(value)),
        ),
      ],
      desc="How many agent steps one turn may take.",
    ),
  ]
  let api_rows : Array[@html.Html] = [
    setting_row(
      "API endpoint",
      [provider_select(dispatch, model.api_provider)],
      desc=provider_hint(model.api_provider),
    ),
  ]
  if model.api_provider is Custom {
    api_rows.push(
      setting_row(
        "Endpoint URL",
        [
          @html.input(
            input_type=@html.InputType::Text,
            value=model.custom_api_url,
            placeholder="https://host/chat/completions",
            on_input=dispatch.map(value => CustomApiUrlChanged(value)),
          ),
        ],
        stack=true,
      ),
    )
  }
  // The OpenSeek proxy ignores keys, so the key field only appears for the
  // endpoints that can use one. The saved key is never echoed back into the
  // field; saving a new one overwrites it.
  if !(model.api_provider is Openseek) {
    let saved_key = if model.api_provider is Custom {
      model.custom_api_key
    } else {
      model.api_key
    }
    api_rows.push(
      setting_row(
        if model.api_provider is Custom {
          "Custom API key"
        } else {
          "DeepSeek API key"
        },
        [
          @html.input(
            input_type=@html.InputType::Password,
            value=model.setup_api_key,
            placeholder=if saved_key.trim().is_empty() {
              "sk-..."
            } else {
              "saved — enter to replace"
            },
            on_input=dispatch.map(value => SetupApiKeyChanged(value)),
          ),
          @html.button(
            id="saveApiKey",
            disabled=model.setup_api_key.trim().is_empty(),
            on_click=dispatch(SaveApiKey),
            "Save API key",
          ),
        ],
        desc="Stored on this machine and sent only with API requests.",
        stack=true,
      ),
    )
  }
  let groups : Array[@html.Html] = [
    settings_group("Model", model_rows),
    settings_group("API", api_rows),
  ]
  // WSL is Windows-only; elsewhere the section would be dead weight.
  if model.is_windows {
    let engine_rows : Array[@html.Html] = [
      setting_row(
        "Engine environment",
        [wsl_select(dispatch, model.wsl_enabled)],
        desc="WSL runs the agent engine inside the distro, so its shell and tools see the Linux environment. Conversations stay in the shared session store either way.",
      ),
    ]
    if model.wsl_enabled {
      engine_rows.push(
        setting_row(
          "WSL distro",
          [
            @html.input(
              input_type=@html.InputType::Text,
              value=model.wsl_distro,
              placeholder="default distro",
              on_input=dispatch.map(value => WslDistroChanged(value)),
            ),
          ],
          desc="Blank uses the default distro.",
        ),
      )
      engine_rows.push(
        setting_row(
          "Engine command in WSL",
          [
            @html.input(
              input_type=@html.InputType::Text,
              value=model.wsl_engine,
              placeholder="bundled engine",
              on_input=dispatch.map(value => WslEngineChanged(value)),
            ),
          ],
          desc="Blank runs the Linux engine bundled with the app, falling back to openseek on the distro's PATH.",
        ),
      )
    }
    groups.push(settings_group("Engine", engine_rows))
  }
  @html.section(class="settings-page", [
    @html.div(class="settings-page-inner", [
      @html.div(class="settings-header", [
        @html.h1("Settings"),
        @html.div(
          class="settings-subtitle",
          if ready {
            "Runtime settings for the OpenSeek engine."
          } else if model.api_provider is Custom {
            "Enter a chat-completions endpoint URL to start."
          } else {
            "Enter a DeepSeek API key to start."
          },
        ),
      ]),
      @html.div(class="settings", groups),
    ]),
  ])
}

///|
/// One local-library row: name, description, and — for registry installs
/// only — the source tag and the uninstall button. Hand-written skills are
/// listed so the user sees everything the engine advertises, but the app
/// never offers to delete them.
fn installed_skill_row(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  skill : @transcript.InstalledSkillItem,
) -> @html.Html {
  let info : Array[@html.Html] = [@html.div(class="skill-name", skill.name)]
  if !skill.description.trim().is_empty() {
    info.push(@html.div(class="skill-desc", skill.description))
  }
  info.push(
    @html.div(
      class="skill-meta",
      if skill.source.is_empty() {
        "hand-written"
      } else {
        skill.source
      },
    ),
  )
  let children : Array[@html.Html] = [
    @html.div(class="skill-avatar", icon(icon_extensions)),
    @html.div(class="skill-info", info),
  ]
  if skill.source.is_empty() {
    children.push(@html.span(class="skill-check ok", "✓"))
  } else {
    let busy = model.skills_busy.contains(skill.id)
    children.push(
      @html.button(
        class="secondary skill-action",
        disabled=busy,
        on_click=dispatch(UninstallSkill(skill.id)),
        if busy {
          "Removing…"
        } else {
          "Uninstall"
        },
      ),
    )
  }
  @html.div(class="skill-row", children)
}

///|
/// One catalog row. The action button morphs: already installed at this
/// exact version reads as a disabled "Installed" (an older install keeps
/// the button alive as the upgrade path), an install in flight reads as
/// "Installing…".
fn market_skill_row(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  item : @transcript.MarketSkillItem,
) -> @html.Html {
  let source = @transcript.market_source_label(item)
  let busy = model.skills_busy.contains(source)
  let installed = model.skill_installed(source)
  let info : Array[@html.Html] = [@html.div(class="skill-name", item.name)]
  if !item.description.trim().is_empty() {
    info.push(@html.div(class="skill-desc", item.description))
  }
  let meta = if item.author.is_empty() {
    "v\{item.version}"
  } else {
    "v\{item.version} · \{item.author}"
  }
  info.push(@html.div(class="skill-meta", meta))
  let action = if installed {
    @html.span(class="skill-check ok", "✓ Installed")
  } else {
    @html.button(
      class="secondary skill-action",
      disabled=busy,
      on_click=dispatch(InstallSkill(item)),
      if busy {
        "Installing…"
      } else {
        "Install"
      },
    )
  }
  @html.div(class="skill-row", title=item.repository, [
    @html.div(class="skill-avatar", icon(icon_extensions)),
    @html.div(class="skill-info", info),
    action,
  ])
}

///|
/// Whether a skill row survives the page's search filter: a blank query
/// keeps everything, otherwise any listed field must contain it
/// (case-insensitive).
fn skill_matches(query : String, fields : Array[String]) -> Bool {
  let query = query.trim().to_owned().to_lower()
  if query.is_empty() {
    return true
  }
  for field in fields {
    if field.to_lower().contains(query) {
      return true
    }
  }
  false
}

///|
/// The Skills page, shown in the main area in place of the conversation:
/// header, search, the local library, then the mooncakes.io catalog.
fn skills_page(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let sections : Array[@html.Html] = [
    @html.div(class="skills-header", [
      @html.h1("Skills"),
      @html.div(
        class="skills-subtitle",
        "Playbooks the agent reads when a task matches. Skills apply to new chats.",
      ),
    ]),
    @html.input(
      input_type=@html.InputType::Search,
      value=model.skills_query,
      placeholder="Search skills",
      on_input=dispatch.map(value => SkillsQueryChanged(value)),
      attrs=@html.Attrs::build().class("skills-search"),
    ),
  ]
  if !model.skills_notice.is_empty() {
    sections.push(@html.div(class="skills-notice danger", model.skills_notice))
  }
  sections.push(@html.div(class="skills-heading", "Installed"))
  let mut listed = 0
  for skill in model.installed_skills {
    if skill_matches(model.skills_query, [
        skill.name,
        skill.description,
        skill.source,
      ]) {
      sections.push(installed_skill_row(dispatch, model, skill))
      listed = listed + 1
    }
  }
  if listed == 0 {
    sections.push(
      @html.div(
        class="skills-empty",
        if model.installed_skills.is_empty() {
          "No skills installed yet."
        } else {
          "No installed skill matches the search."
        },
      ),
    )
  }
  sections.push(@html.div(class="skills-heading", "Mooncakes registry"))
  match model.skills_catalog {
    CatalogIdle | CatalogLoading =>
      sections.push(
        @html.div(class="skills-empty", "Loading the skill catalog…"),
      )
    CatalogFailed(message) =>
      sections.push(@html.div(class="skills-empty danger", message))
    CatalogReady(items) => {
      let mut shown = 0
      for item in items {
        if skill_matches(model.skills_query, [
            item.name,
            item.description,
            item.author,
          ]) {
          sections.push(market_skill_row(dispatch, model, item))
          shown = shown + 1
        }
      }
      if shown == 0 {
        sections.push(
          @html.div(
            class="skills-empty",
            if items.is_empty() {
              "The registry lists no installable skills yet."
            } else {
              "No registry skill matches the search."
            },
          ),
        )
      }
    }
  }
  @html.section(class="skills-page", [
    @html.div(class="skills-page-inner", sections),
  ])
}

///|
fn run_indicator(model : Model) -> @html.Html {
  let status = model.display_status()
  let label = status.label()
  if model.active().running {
    @html.div(class="run-status accent", [
      @html.span(class="run-dot accent pulse", ""),
      @html.span(class="run-text", label),
    ])
  } else {
    @html.div(class="run-status", [
      @html.span(class="run-dot \{status.kind().css()}", ""),
      @html.span(class="run-text", label),
    ])
  }
}

///|
/// The workspace line appears once the host has reported it via `started`;
/// before the conversation's first run only the session id is known.
fn session_tooltip(conv : Conversation) -> String {
  if conv.cwd.is_empty() {
    "session \{conv.session_id}"
  } else {
    "session \{conv.session_id}\nworkspace \{conv.cwd}"
  }
}

///|
/// The first letter of an app name, for the icon fallback when the host could
/// not extract a real icon.
fn app_initial(name : String) -> String {
  if name.iter().next() is Some(c) {
    "\{c.to_ascii_uppercase()}"
  } else {
    "?"
  }
}

///|
/// The launcher dropdown's rows: a real icon (or letter fallback) and the app
/// name, each launching the app on the active workspace. Falls back to a
/// loading / error / empty notice when there is nothing to list.
fn launcher_menu(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let rows : Array[@html.Html] = []
  if !model.launcher.error.is_empty() {
    rows.push(@html.div(class="launcher-empty danger", model.launcher.error))
  } else if !model.launcher.loaded {
    rows.push(@html.div(class="launcher-empty", "Finding apps…"))
  } else if model.launcher.apps.is_empty() {
    rows.push(@html.div(class="launcher-empty", "No apps found"))
  } else {
    for app in model.launcher.apps {
      let icon = if app.icon.is_empty() {
        @html.span(class="launcher-icon letter", app_initial(app.name))
      } else {
        @html.img(
          class="launcher-icon",
          src=app.icon,
          alt=app.name,
          width=24,
          height=24,
        )
      }
      rows.push(
        @html.button(
          class="launcher-item",
          type_="button",
          on_click=dispatch(LaunchApp(app.id)),
          [icon, @html.span(class="launcher-name", app.name)],
        ),
      )
    }
  }
  @html.div(class="launcher-menu", rows)
}

///|
/// The topbar app launcher: a button that opens a dropdown of installed apps,
/// each opening the active conversation's workspace. While open a full-screen
/// backdrop catches a click away to close it.
fn launcher_view(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  // A conversation's workspace exists only once it has run; a fresh chat with
  // no turn yet has nothing to open, so the launcher is disabled until then.
  let conv = model.active()
  let ready = !conv.messages.is_empty() || conv.running
  let children : Array[@html.Html] = [
    @html.button(
      class=if model.launcher.open {
        "launcher-button open"
      } else {
        "launcher-button"
      },
      type_="button",
      disabled=!ready,
      title=if ready {
        "Open this workspace in an app"
      } else {
        "Send a message to create this chat's workspace"
      },
      on_click=dispatch(ToggleLauncher),
      [
        @html.span(class="launcher-glyph", icon(icon_link_external)),
        @html.span(class="launcher-caret", icon(icon_chevron_down)),
      ],
    ),
  ]
  if ready && model.launcher.open {
    children.push(
      @html.div(
        class="launcher-backdrop",
        on_click=dispatch(ToggleLauncher),
        @html.nothing,
      ),
    )
    children.push(launcher_menu(dispatch, model))
  }
  @html.div(class="launcher", children)
}

///|
/// Top bar: conversation identity on the left (session id and workspace in
/// the tooltip), live run state on the right — these are per-conversation
/// runtime facts, not settings, so they live here rather than in the
/// settings popup.
fn topbar_view(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let conv = model.active()
  let items : Array[@html.Html] = [
    @html.button(
      class="topbar-toggle",
      title=if model.sidebar_open { "Hide sidebar" } else { "Show sidebar" },
      on_click=dispatch(ToggleSidebar),
      icon(icon_layout_sidebar_left),
    ),
    @html.span(class="topbar-icon", "✦"),
    @html.span(
      class="topbar-title",
      title=session_tooltip(conv),
      conversation_title(conv),
    ),
  ]
  // The workspace's real branch, reported by the host; a workspace that is
  // not a repository simply has no chip.
  if !conv.branch.is_empty() {
    items.push(@html.span(class="topbar-branch", conv.branch))
  }
  items.push(run_indicator(model))
  if conv.usage_tokens > 0 {
    items.push(@html.span(class="pill", token_label(conv.usage_tokens)))
  }
  if !conv.watcher_status.is_empty() {
    items.push(@html.span(class="pill", "moon_check \{conv.watcher_status}"))
  }
  // Right-aligned toggle for the whole right-hand panel. The file-tree column
  // has its own collapse button above the tree (see `file_panel_view`).
  items.push(
    @html.button(
      class=if model.file_panel.open {
        "panel-toggle active"
      } else {
        "panel-toggle"
      },
      title=if model.file_panel.open { "Hide panel" } else { "Show panel" },
      on_click=dispatch(ToggleFilePanel),
      icon(icon_layout_sidebar_right),
    ),
  )
  items.push(launcher_view(dispatch, model))
  @html.div(class="topbar", items)
}

///|
/// The editor part: a single pane that shows either the workspace tree (a
/// filterable, expandable tree always rooted at the workspace root) or the
/// selected file's content, never both — a file tree is just the editor for
/// a directory. The whole part is always rendered so the viewer's host
/// element (`viewer-host`) stays put across renders and screen switches; CSS
/// hides whichever half is not current and collapses the pane to zero width
/// when the panel is closed.
fn file_panel_view(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let panel = model.file_panel
  let conv = model.active()
  let query = panel.filter.trim().to_owned()
  let tree_children = if conv.session_id.is_empty() {
    [@html.div(class="file-panel-empty", "No conversation selected.")]
  } else if !panel.children.contains("") {
    [@html.div(class="file-panel-empty", "Loading…")]
  } else if !query.is_empty() {
    // Filtering flattens the loaded tree to the matching rows.
    let rows = []
    filtered_file_rows(dispatch, model, "", query.to_lower(), rows)
    if rows.is_empty() {
      [@html.div(class="file-panel-empty", "No file matches the filter.")]
    } else {
      rows
    }
  } else {
    let rows = file_tree_rows(dispatch, model, "", 0)
    if rows.is_empty() {
      // The workspace exists once the conversation runs; until then (or if the
      // agent has written nothing) it is simply empty.
      [@html.div(class="file-panel-empty", "This workspace is empty.")]
    } else {
      rows
    }
  }
  // The filter box, in a header bar matching the topbar/breadcrumb height.
  let browse_children : Array[@html.Html] = [
    @html.div(class="file-tree-header", [
      @html.input(
        input_type=@html.InputType::Search,
        value=panel.filter,
        placeholder="Filter files…",
        on_input=dispatch.map(value => FileFilterChanged(value)),
        attrs=@html.Attrs::build().class("file-filter"),
      ),
    ]),
  ]
  if !panel.error.is_empty() {
    browse_children.push(@html.div(class="file-panel-error", panel.error))
  }
  browse_children.push(@html.div(class="file-tree", tree_children))
  // The stable element the viewer attaches its imperative DOM into; it must
  // stay empty and never be re-keyed (see editor_panel.mbt).
  // `editor-shell` brings in the viewer's `--vscode-*` / `--editor-*` theme
  // variables (defined on that class in the bundled viewer.css); `data-theme`
  // picks the palette matching the app's own light/dark scheme (the shell's
  // default is dark, `light` overrides). The viewer's colors cascade from
  // this host.
  let viewer_host = @html.div(
    attrs=@html.Attrs::build()
      .id(ViewerHostId)
      .class("viewer-host editor-shell")
      .data_set("theme", if model.dark_mode { "dark" } else { "light" }),
    ([] : Array[@html.Html]),
  )
  // A grab strip on the editor's left edge for drag-to-resize. Absolutely
  // positioned, so it is not a grid item and never disturbs the pane's
  // children; its drag is wired imperatively (see editor_resize.mbt). Always
  // rendered (CSS hides it while the panel is closed) so its position among
  // the editor's children — and thus the never-re-keyed viewer host — stays
  // stable.
  let resize_handle = @html.div(
    attrs=@html.Attrs::build().id(ResizeHandleId).class("editor-resize-handle"),
    ([] : Array[@html.Html]),
  )
  let children = [resize_handle, viewer_breadcrumb(dispatch, panel)]
  for child in browse_children {
    children.push(child)
  }
  children.push(viewer_host)
  @html.div(
    class=if panel.selected is None { "editor browsing" } else { "editor" },
    children,
  )
}

///|
/// Split a relative path into its non-empty segments, e.g.
/// `"cef/runtime.mbt"` → `["cef", "runtime.mbt"]`.
fn path_segments(path : String) -> Array[String] {
  let segments : Array[String] = []
  let mut rest = path
  while rest.split_once("/") is Some((head, tail)) {
    if !head.is_empty() {
      segments.push(head.to_owned())
    }
    rest = tail.to_owned()
  }
  if !rest.is_empty() {
    segments.push(rest)
  }
  segments
}

///|
/// The path formed by joining `segments`' first `count` entries, e.g.
/// `segments_prefix(["cef", "runtime.mbt"], 1)` → `"cef"`. The inverse of
/// `path_segments`, used to recover an ancestor directory's path for a
/// breadcrumb click.
fn segments_prefix(segments : Array[String], count : Int) -> String {
  let mut path = ""
  for index in 0..<count {
    path = child_path(path, segments[index])
  }
  path
}

///|
/// The proper ancestors of `path`, nearest-root first, e.g.
/// `ancestor_paths("src/foo/bar.mbt")` → `["src", "src/foo"]`. Excludes the
/// workspace root (`""`) and `path` itself.
fn ancestor_paths(path : String) -> Array[String] {
  let segments = path_segments(path)
  let paths : Array[String] = []
  for count in 1..<segments.length() {
    paths.push(segments_prefix(segments, count))
  }
  paths
}

///|
/// A breadcrumb segment that reveals `path` in the tree when clicked.
fn crumb_link(
  dispatch : @cmd.Emit[Msg],
  label : String,
  path : String,
) -> @html.Html {
  @html.span(
    class="crumb",
    attrs=@html.Attrs::build().on_click(_ => dispatch(RevealDirectory(path))),
    label,
  )
}

///|
/// The breadcrumb header over the panel: in file mode, the open file's path
/// as `dir › dir › file` (the file segment emphasized) behind a leading
/// "Workspace" crumb; in browse mode, just the "Workspace" crumb, since the
/// tree is always rooted there. Every crumb but the last reveals that
/// ancestor directory in the (always-rooted) tree when clicked.
fn viewer_breadcrumb(
  dispatch : @cmd.Emit[Msg],
  panel : FilePanel,
) -> @html.Html {
  let crumbs : Array[@html.Html] = []
  match panel.selected {
    Some(path) => {
      crumbs.push(crumb_link(dispatch, "Workspace", ""))
      let segments = path_segments(path)
      for index, segment in segments {
        crumbs.push(@html.span(class="crumb-sep", "›"))
        if index == segments.length() - 1 {
          crumbs.push(@html.span(class="crumb crumb-file", segment))
        } else {
          crumbs.push(
            crumb_link(dispatch, segment, segments_prefix(segments, index + 1)),
          )
        }
      }
    }
    None => crumbs.push(@html.span(class="crumb crumb-file", "Workspace"))
  }
  @html.div(class="viewer-breadcrumb", [@html.div(class="crumb-path", crumbs)])
}

///|
/// The rows for the entries of one directory, with expanded directories'
/// children spliced in beneath them, depth-first. `depth` drives indentation.
fn file_tree_rows(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  dir_path : String,
  depth : Int,
) -> Array[@html.Html] {
  guard model.file_panel.children.get(dir_path) is Some(entries) else {
    return []
  }
  let rows : Array[@html.Html] = []
  for entry in entries {
    rows.push(tree_row(dispatch, model, entry, depth))
    if entry.is_dir && model.file_panel.expanded.contains(entry.path) {
      for child in file_tree_rows(dispatch, model, entry.path, depth + 1) {
        rows.push(child)
      }
    }
  }
  rows
}

///|
/// Filter mode: walk the already-loaded tree depth-first and append every entry
/// whose name contains `query` (already lower-cased) as a flat row. Only loaded
/// directories are descended into, so the filter spans the root listing plus
/// whatever the user has expanded.
fn filtered_file_rows(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  dir_path : String,
  query : String,
  into : Array[@html.Html],
) -> Unit {
  guard model.file_panel.children.get(dir_path) is Some(entries) else { return }
  for entry in entries {
    if entry.name.to_lower().contains(query) {
      into.push(tree_row(dispatch, model, entry, 0))
    }
    if entry.is_dir {
      filtered_file_rows(dispatch, model, entry.path, query, into)
    }
  }
}

///|
fn tree_row(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  entry : FileEntry,
  depth : Int,
) -> @html.Html {
  let pad = "padding-left: \{8 + depth * 14}px"
  if entry.is_dir {
    let chevron = if model.file_panel.expanded.contains(entry.path) {
      "▾"
    } else {
      "▸"
    }
    // `data-path` is `reveal_tree_row`'s hook for scrolling a breadcrumb's
    // `RevealDirectory` target into view.
    @html.div(
      class=if model.file_panel.highlighted == Some(entry.path) {
        "tree-row tree-dir highlighted"
      } else {
        "tree-row tree-dir"
      },
      style=[pad],
      on_click=dispatch(DirToggle(entry.path)),
      attrs=@html.Attrs::build().data_set("path", entry.path),
      [
        @html.span(class="tree-chevron", chevron),
        @html.span(class="tree-name", entry.name),
      ],
    )
  } else {
    @html.div(
      class=if model.file_panel.selected == Some(entry.path) {
        "tree-row tree-file selected"
      } else {
        "tree-row tree-file"
      },
      style=[pad],
      on_click=dispatch(
        FileSelected(path=entry.path, name=entry.name, line=None),
      ),
      [@html.span(class="tree-name", entry.name)],
    )
  }
}

///|
fn view(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let content = match model.screen {
    Chat =>
      [
        topbar_view(dispatch, model),
        transcript_view(
          dispatch,
          model.active(),
          pinned=model.transcript_pinned,
          path => dispatch(OpenFile(path)),
        ),
        composer_view(dispatch, model),
      ]
    Skills => [skills_page(dispatch, model)]
    Settings => [settings_page(dispatch, model)]
  }
  // The app is `sidebar | content`; `content` itself splits into the
  // conversation (left) and the editor (right) as two independent parts, so
  // either side can be swapped out later. The files panel only opens over the
  // chat; on the Skills page it stays collapsed, but the editor column (and the
  // viewer host inside it) is still rendered so the attached viewer is never
  // torn down.
  let panel_open = model.file_panel.open && model.screen is Chat
  @html.div(
    class=if model.sidebar_open { "app" } else { "app sidebar-collapsed" },
    [
      sidebar_view(dispatch, model),
      @html.div(
        class=if panel_open { "content panel-open" } else { "content" },
        [@html.main_(content), file_panel_view(dispatch, model)],
      ),
    ],
  )
}
