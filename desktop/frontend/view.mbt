///|
fn can_stop(conv : Conversation) -> Bool {
  conv.run is Open(..)
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
      // A prompt sent with chips titles by what was typed (or, chips alone,
      // by their labels) — never by the raw `<user_mentions>` envelope.
      let title = user_display_text(item.content).trim().to_owned()
      if !title.is_empty() {
        return title
      }
    }
  }
  let task = conv.task.trim().to_owned()
  if task.is_empty() {
    "OpenSeek Desktop"
  } else {
    task
  }
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
  nested? : Bool = false,
) -> @html.Html {
  let active = session_id == model.active_session
  let conv = model.find_conversation(session_id)
  let running = conv is Some(conv) && conv.is_running()
  // The row's status dot: pulsing while a run is in flight, then — when the
  // run finished off screen — settling into a solid dot (accent for success,
  // warn otherwise) until the conversation is opened (`Model::activate`
  // clears the mark).
  let dot = match conv {
    Some(conv) if conv.is_running() => Some("accent pulse")
    Some(conv) if conv.unseen_finish && !active =>
      // Success wears accent (continuity with the running pulse), any other
      // ending warn — the same success/other split `Status::kind` draws.
      Some(
        if conv.run is NoRun(ended=Some(RunFinished(Completed))) {
          "accent"
        } else {
          "warn"
        },
      )
    _ => None
  }
  let mut class = "conversation-row"
  if nested {
    class = class + " nested"
  }
  if active {
    class = class + " active"
  }
  if running {
    class = class + " running"
  }
  let children = [@html.span(class="sidebar-label", label)]
  // Status dot and archive button share one fixed trailing slot (stacked in
  // the same grid cell), so the dot sits at the same offset whether or not
  // the row is archivable; hovering an archivable row swaps the dot for the
  // button.
  let trailing : Array[@html.Html] = []
  if dot is Some(kind) {
    trailing.push(@html.span(class="run-dot \{kind}", ""))
  }
  // Archiving a running conversation would pull the durable record out from
  // under its engine, so the button waits for the turn to end.
  if archivable && !running {
    trailing.push(
      @html.button(
        class="row-archive",
        type_="button",
        title="Archive — tuck this chat away; its files stay where they are",
        attrs=@html.Attrs::build().on_click(event => {
          // The row itself opens the session; the archive click must not.
          event.stop_propagation()
          dispatch(ArchiveSession(session_id))
        }),
        icon(icon_archive),
      ),
    )
  }
  if trailing.length() > 0 {
    children.push(@html.span(class="row-trailing", trailing))
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
  // An archived record has moved out of the live store, so the live list
  // normally cannot contain it; the filter covers the moment between the
  // archive reply and the list refetch that follows it.
  let archived = (id : String) => {
    for item in model.archived {
      if item.id == id {
        return true
      }
    }
    false
  }
  // Two sections, matching the projects-then-chats shape chat apps settled
  // on: "Workspaces" lists each attached project as a folder row with its
  // conversations nested beneath, "Chats" holds the default store's loose
  // conversations. The section headings share one style; the ＋ on each adds
  // to that section (a workspace, or a chat outside any workspace).
  rows.push(
    section_heading(
      dispatch,
      "Workspaces",
      PickWorkspace,
      action_title="Add a workspace",
      toggle=ToggleWorkspacesSection,
      collapsed=model.workspaces_collapsed,
    ),
  )
  if !model.workspaces_collapsed {
    for control in add_workspace_controls(dispatch, model) {
      rows.push(control)
    }
    for path in model.workspaces {
      rows.push(workspace_row(dispatch, model, path))
      let before = rows.length()
      push_group_rows(
        rows,
        dispatch,
        model,
        path,
        listed~,
        archived~,
        nested=true,
      )
      if rows.length() == before {
        rows.push(
          @html.div(class="conversation-row nested placeholder", [
            @html.span(class="sidebar-label", "No chats yet"),
          ]),
        )
      }
    }
  }
  rows.push(
    section_heading(
      dispatch,
      "Chats",
      NewChatIn(""),
      action_title="New chat outside any workspace",
      toggle=ToggleChatsSection,
      collapsed=model.chats_collapsed,
    ),
  )
  if !model.chats_collapsed {
    push_group_rows(rows, dispatch, model, "", listed~, archived~)
  }
  // Archived conversations fold behind a collapsed group at the end of the
  // list. Their records live in the store's `archived` twin, so they come
  // from the host's archived reply, not the live list; each row carries a
  // restore control instead of the archive one.
  let archived_rows : Array[@html.Html] = []
  for item in model.archived {
    archived_rows.push(archived_row(dispatch, item))
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
/// One store's conversation rows: the app-run-only (unlisted) conversations
/// newest first, then the store's durable sessions in list order — the same
/// ordering the flat sidebar always had, applied per group.
fn push_group_rows(
  rows : Array[@html.Html],
  dispatch : @cmd.Emit[Msg],
  model : Model,
  workspace : String,
  listed~ : (String) -> Bool,
  archived~ : (String) -> Bool,
  nested? : Bool = false,
) -> Unit {
  // Only conversations that have gotten under way get a row — a fresh
  // "New chat" is already on screen, and a row for it is just noise until
  // its first send.
  for conv in model.conversations.rev_iter() {
    if workspace_token(conv.workspace) == workspace &&
      conv.has_begun() &&
      !listed(conv.session_id) &&
      !archived(conv.session_id) {
      rows.push(
        session_row(
          dispatch,
          model,
          conv.session_id,
          conversation_title(conv),
          nested~,
        ),
      )
    }
  }
  for item in model.sessions {
    if item.workspace != workspace || archived(item.id) {
      continue
    }
    let label = if model.find_conversation(item.id) is Some(conv) &&
      item.id == model.active_session {
      conversation_title(conv)
    } else {
      session_item_label(item)
    }
    rows.push(
      session_row(dispatch, model, item.id, label, archivable=true, nested~),
    )
  }
}

///|
/// A section heading in the chat list — "Workspaces" or "Chats" — with a
/// hover-revealed ＋ that adds to that section. Both sections share this one
/// style, so the two labels always match. `toggle`, when given, makes the
/// heading itself clickable to fold the section (the ＋ stops propagation, so
/// it never toggles); `collapsed` picks the chevron the CSS appends.
fn section_heading(
  dispatch : @cmd.Emit[Msg],
  label : String,
  action : Msg,
  action_title~ : String,
  toggle? : Msg,
  collapsed? : Bool = false,
) -> @html.Html {
  let class = match toggle {
    Some(_) =>
      if collapsed {
        "sidebar-heading section-heading collapsible collapsed"
      } else {
        "sidebar-heading section-heading collapsible"
      }
    None => "sidebar-heading section-heading"
  }
  let on_click = toggle.map(msg => dispatch(msg))
  @html.div(class~, on_click?, [
    @html.span(class="sidebar-label", label),
    @html.button(
      class="row-archive",
      type_="button",
      title=action_title,
      attrs=@html.Attrs::build().on_click(event => {
        event.stop_propagation()
        dispatch(action)
      }),
      icon(icon_add),
    ),
  ])
}

///|
/// One attached workspace: a folder row (full path in the tooltip) with its
/// conversations nested beneath it. Hover controls start a new chat in the
/// project or detach it (registry only; the folder and its sessions stay).
/// The active workspace — where a plain "New chat" lands — reads as the
/// darker label; while a fresh "New chat" is on screen there (no sidebar row
/// of its own yet) the workspace row wears the selected conversation's
/// accent pill in its place.
fn workspace_row(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  path : String,
) -> @html.Html {
  let mut class = "workspace-row"
  if path == model.active_workspace {
    class = class + " active"
    if model.composing_new_chat() {
      class = class + " composing"
    }
  }
  @html.div(class~, title=path, [
    @html.span(class="sidebar-icon", icon(icon_folder)),
    @html.span(class="sidebar-label", workspace_label(path)),
    @html.button(
      class="row-archive",
      type_="button",
      title="Detach this workspace — its files and sessions stay",
      attrs=@html.Attrs::build().on_click(event => {
        event.stop_propagation()
        dispatch(RemoveWorkspace(path))
      }),
      icon(icon_close),
    ),
    @html.button(
      class="row-archive",
      type_="button",
      title="New chat in this workspace",
      attrs=@html.Attrs::build().on_click(event => {
        event.stop_propagation()
        dispatch(NewChatIn(path))
      }),
      icon(icon_add),
    ),
  ])
}

///|
/// The rows under the "Workspaces" heading that back its ＋ control: the ＋
/// asks the host for the system folder chooser; on platforms without one it
/// opens this manual path input instead (Enter submits, Escape closes).
/// Either way the host validates the directory and the updated registry
/// comes back through `WorkspacesLoaded`.
fn add_workspace_controls(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> Array[@html.Html] {
  let controls : Array[@html.Html] = []
  if model.workspace_input is Some(text) {
    controls.push(
      @html.div(class="workspace-add", [
        @html.input(
          input_type=@html.InputType::Text,
          value=text,
          placeholder="/path/to/project",
          autofocus=true,
          on_input=dispatch.map(value => WorkspaceInput(value)),
          attrs=@html.Attrs::build().on_keydown(event => {
            match event.key() {
              "Enter" => dispatch(AddWorkspace)
              "Escape" => dispatch(ToggleWorkspaceInput)
              _ => @cmd.none
            }
          }),
        ),
      ]),
    )
  }
  controls
}

///|
/// A sidebar entry's display label: its engine-reported title, or the
/// session id for a conversation with no user message yet (absent or blank
/// title).
fn session_item_label(item : @transcript.SessionListItem) -> String {
  if item.title is Some(title) && !title.trim().is_empty() {
    title
  } else {
    item.id
  }
}

///|
/// One row of the Archived group: the conversation's title and a
/// hover-revealed restore button. The row is inert — an archived record is
/// invisible to `load_session` until it is restored, so the click that
/// brings it back is the unarchive control.
fn archived_row(
  dispatch : @cmd.Emit[Msg],
  item : @transcript.SessionListItem,
) -> @html.Html {
  @html.div(class="conversation-row archived", title=item.id, [
    @html.span(class="sidebar-label", session_item_label(item)),
    @html.button(
      class="row-archive",
      type_="button",
      title="Restore this conversation to the sidebar",
      attrs=@html.Attrs::build().on_click(event => {
        event.stop_propagation()
        dispatch(UnarchiveSession(item.id))
      }),
      icon(icon_arrow_up),
    ),
  ])
}

///|
fn sidebar_view(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let sessions_section : Array[@html.Html] = []
  for row in session_rows(dispatch, model) {
    sessions_section.push(row)
  }
  // A 46px header matching the content column's topbar, so the sidebar
  // toggle rides the window's left edge here while the sidebar is open and
  // at the same screen position while it's closed — the topbar's left on
  // Chat, a floating button on Skills/Settings (see `page_with_toggle`) —
  // mirroring how the right-panel toggle stays put (topbar-right when
  // closed, breadcrumb-right when open). New chat rides the header's right
  // edge on every screen — rotating a session lands back on Chat regardless.
  let header_children : Array[@html.Html] = [
    @html.button(
      class="topbar-toggle",
      title="Hide sidebar",
      on_click=dispatch(ToggleSidebar),
      icon(icon_layout_sidebar_left),
    ),
  ]
  header_children.push(
    @html.button(
      class="topbar-toggle header-new-chat",
      title="New chat",
      on_click=dispatch(NewChat),
      icon(icon_add),
    ),
  )
  @html.aside([
    @html.div(class="sidebar-header", header_children),
    @html.div(class="sidebar-main", [
      @html.div(class="sidebar-section sessions", sessions_section),
    ]),
    @html.div(class="sidebar-footer", sidebar_footer_buttons(dispatch, model)),
  ])
}

///|
/// The sidebar footer: Skills and Settings, and — while an installable
/// release is on offer — the accent Update button above them, tracking the
/// download so its progress stays visible from any screen.
fn sidebar_footer_buttons(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> Array[@html.Html] {
  let buttons : Array[@html.Html] = []
  let update_label : String? = match model.update_ux {
    UpdateAvailable(installable=true, ..) | ConfirmingRestart(..) =>
      Some("Update")
    DownloadingUpdate(..) => Some("Downloading…")
    RestartingForUpdate(..) => Some("Restarting…")
    _ => None
  }
  if update_label is Some(label) {
    buttons.push(
      @html.button(
        class="sidebar-button primary",
        disabled=!(model.update_ux is UpdateAvailable(..)),
        on_click=dispatch(UpdateClicked),
        [
          @html.span(class="sidebar-icon", icon(icon_arrow_up)),
          @html.span(class="sidebar-label", label),
        ],
      ),
    )
  }
  buttons.push(
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
  )
  buttons.push(
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
  )
  buttons
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
    guard item.kind is Tool(name~, ..) else { continue }
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
/// One turn's work — reasoning, tool results, and any interim assistant
/// narration between tool calls — folded behind a single summary line ("Read
/// 3 files, ran 1 command"), the way Codex folds a turn behind "Worked for
/// 46s". Expanding shows the work log in order: reasoning as muted prose —
/// never a labelled "Thinking" row of its own — narration as plain prose,
/// each burst of tool calls as a one-line sublist. A turn that only thought
/// folds behind a plain "Thought" line. Failures never force the fold open;
/// they badge the summary instead. The open state is the browser's
/// (`<details>`), so a reader's toggle survives re-renders and the run
/// growing while live.
fn activity_view(
  items : Array[@transcript.TranscriptItem],
  on_open : (String) -> @cmd.Cmd,
) -> @html.Html {
  let log : Array[@html.Html] = []
  let mut index = 0
  while index < items.length() {
    if items[index].kind is Tool(..) {
      let tools : Array[@transcript.TranscriptItem] = []
      while index < items.length() && items[index].kind is Tool(..) {
        tools.push(items[index])
        index = index + 1
      }
      log.push(tool_line_view(tools))
    } else {
      // Reasoning or interim assistant narration; callers never pass user
      // messages or error bubbles.
      let prose_class = if items[index].kind is Assistant(_) {
        "msg-content markdown activity-response"
      } else {
        "msg-content markdown activity-thinking"
      }
      log.push(
        @html.div(
          class=prose_class,
          @markdown.markdown_nodes(items[index].content, open_file=on_open),
        ),
      )
      index = index + 1
    }
  }
  let failed = count_failed(items)
  let summary_label = tool_group_summary(items)
  let summary : Array[@html.Html] = [
    @html.span(
      class="activity-text",
      if summary_label.is_empty() {
        "Thought"
      } else {
        summary_label
      },
    ),
  ]
  if failed > 0 {
    summary.push(failed_badge(failed))
  }
  @html.div(class="activity-row", [
    @html.details(class="activity", [
      @html.summary(class="activity-summary", summary),
      @html.div(class="activity-body", log),
    ]),
  ])
}

///|
/// A turn's work folded behind one collapsed activity card, rendered the same
/// whether the turn is still streaming or long settled; only the run's
/// trailing assistant message (the answer) pops out as a visible bubble.
/// Folding identically in both states is deliberate: the transcript never
/// shows anything live that would vanish or restyle once the turn lands.
fn push_run(
  items : Array[@html.Html],
  run : Array[@transcript.TranscriptItem],
  on_open : (String) -> @cmd.Cmd,
) -> Unit {
  let mut work_end = run.length()
  if run[work_end - 1].kind is Assistant(_) {
    work_end = work_end - 1
  }
  if work_end > 0 {
    items.push(activity_view(run[0:work_end].to_owned(), on_open))
  }
  if work_end < run.length() {
    items.push(transcript_item_view(run[work_end], on_open))
  }
}

///|
/// A burst of consecutive tool calls: one gray line ("Read 2 files, ran 1
/// command") that expands to the per-call briefs. A burst with a failure
/// starts open — the failure is what the reader came for.
fn tool_line_view(tools : Array[@transcript.TranscriptItem]) -> @html.Html {
  let failed = count_failed(tools)
  let summary : Array[@html.Html] = [
    @html.span(class="tool-line-text", tool_group_summary(tools)),
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
/// tool name when the engine sent none), expandable to the call's output.
/// Failed calls start open and read red.
fn tool_call_view(item : @transcript.TranscriptItem) -> @html.Html {
  guard item.kind is Tool(name~, is_error~, brief~) else {
    return @html.text("")
  }
  let label = capitalize(
    if brief is Some(brief) && !brief.trim().is_empty() {
      brief
    } else {
      name
    },
  )
  let error_class = if is_error { " error" } else { "" }
  if item.content.trim().is_empty() {
    @html.div(class="tool-call-label" + error_class, label)
  } else {
    @html.details(class="tool-call" + error_class, open=is_error, [
      @html.summary(class="tool-call-summary", label),
      @html.pre(truncate_output(item.content)),
    ])
  }
}

///|
/// Clamp a tool output to its first and last lines around a skip marker, so
/// one huge read or log dump cannot swallow the transcript. The transcript
/// is the only scroll area — outputs grow the page instead of nesting a
/// second scrollbar that traps the wheel.
fn truncate_output(content : String) -> String {
  let head_limit = 60
  let tail_limit = 40
  let lines = content.split("\n").map(line => line.to_owned()).to_array()
  if lines.length() <= head_limit + tail_limit + 1 {
    return content
  }
  let parts = lines[0:head_limit].to_owned()
  parts.push(
    "⋯ \{lines.length() - head_limit - tail_limit} lines skipped ⋯",
  )
  parts.append(lines[lines.length() - tail_limit:].to_owned())
  parts.join("\n")
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
/// The trigger glyph a chip renders with — the composer affordance the
/// mention came from.
fn mention_glyph(mention : @mention_context.MentionRef) -> String {
  match mention {
    Skill(_) => "$"
    Symbol(_) => "#"
    Annotation(_) => "✎"
  }
}

///|
/// A chip's label text; an annotation labels as its location — its texts
/// live in the chip's tooltip and the message body the model read.
fn mention_label(mention : @mention_context.MentionRef) -> String {
  match mention {
    Skill(name~) => name
    Symbol(name~, ..) => name
    Annotation(file~, start_line~, end_line~, ..) =>
      "\{file}:\{start_line}-\{end_line}"
  }
}

///|
/// Where a mention chip's jump lands: the referenced file, the line span the
/// envelope can rebuild (it stores no columns; `None` for a symbol placed
/// without a line), and — for an annotation — the comment to re-show as an
/// editor bubble over that range. `None` for a chip with nothing to jump to
/// (a skill, or an unresolved symbol).
priv struct MentionTarget {
  file : String
  range : @common.Range?
  annotation : String?
}

///|
fn mention_target(mention : @mention_context.MentionRef) -> MentionTarget? {
  match mention {
    Skill(_) => None
    Symbol(file~, line~, ..) =>
      if file.is_empty() {
        None
      } else {
        Some({
          file,
          range: if line >= 1 {
            Some(@common.Range::Range(line, 1, line, 1))
          } else {
            None
          },
          annotation: None,
        })
      }
    Annotation(file~, start_line~, end_line~, comment~, ..) =>
      Some({
        file,
        range: Some(
          @common.Range::Range(
            start_line,
            1,
            if end_line >= start_line {
              end_line
            } else {
              start_line
            },
            1,
          ),
        ),
        annotation: Some(comment),
      })
  }
}

///|
/// A user message bubble. A content that carries a `<user_mentions>` envelope
/// (a prompt sent with chips) renders as the chips it was composed with — the
/// same tray the composer showed, minus the remove buttons — above the typed
/// text; anything else is plain text. A chip with a resolved location jumps
/// the editor panel there via `on_jump`, when the caller wires one.
fn user_message_view(
  content : String,
  on_jump? : (MentionTarget) -> @cmd.Cmd,
) -> @html.Html {
  let body : Array[@html.Html] = [@html.div(class="msg-role", "You")]
  match @mention_context.parse(content) {
    Some(parsed) => {
      let chips : Array[@html.Html] = []
      for mention in parsed.mentions {
        let glyph = @html.span(class="mention-glyph", mention_glyph(mention))
        let label_text = mention_label(mention)
        let label = @html.span(class="mention-label", label_text)
        let target = mention_target(mention)
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
  @html.div(class="msg", [
    @html.div(class="avatar user", "›"),
    @html.div(class="msg-body", body),
  ])
}

///|
fn transcript_item_view(
  item : @transcript.TranscriptItem,
  on_open : (String) -> @cmd.Cmd,
  on_jump? : (MentionTarget) -> @cmd.Cmd,
) -> @html.Html {
  match item.kind {
    User => user_message_view(item.content, on_jump?)
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
    // Unreachable in practice — the transcript loop batches every reasoning
    // and tool item into a run and `push_run` folds those into the activity
    // card itself — but the match must cover them, so a stray item gets the
    // same one-item card.
    Reasoning => activity_view([item], on_open)
    Tool(..) => activity_view([item], on_open)
    Summary => summary_card_view(item.content, on_open)
  }
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
        @html.span(class="summary-card-icon", icon(icon_fold)),
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
/// The live reasoning stream: muted prose in the activity indent, with no
/// role label or avatar — the thought reads as quiet work and tucks into the
/// turn's folded activity card once it commits, so nothing shown here
/// vanishes or restyles at that point. It stays expanded while it streams:
/// folding text that is still arriving would hide the one thing the user is
/// watching.
fn reasoning_view(
  content : String,
  streaming~ : Bool,
  on_open : (String) -> @cmd.Cmd,
) -> @html.Html {
  let msg_class = if streaming { "msg streaming" } else { "msg" }
  @html.div(class="activity-row", [
    @html.div(class=msg_class, [
      @html.div(
        class="msg-content markdown activity-thinking",
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
    // A turn's work — reasoning, tool results, and any interim assistant
    // narration between tool calls — folds behind one collapsed activity
    // card; only the run's trailing assistant message (the answer) stays
    // out. The same fold renders whether the turn is still streaming or long
    // settled, so nothing shown live vanishes or restyles when the turn
    // lands. User messages and error bubbles always break the run and stay
    // visible.
    let mut index = 0
    while index < conv.messages.length() {
      guard conv.messages[index].kind
        is (Tool(..) | Reasoning | Assistant(false)) else {
        items.push(
          transcript_item_view(conv.messages[index], on_open, on_jump=target => {
            dispatch(
              JumpToLocation(
                path=target.file,
                range=target.range,
                annotation=target.annotation,
              ),
            )
          }),
        )
        index = index + 1
        continue
      }
      let run : Array[@transcript.TranscriptItem] = []
      while index < conv.messages.length() &&
            conv.messages[index].kind
            is (Tool(..) | Reasoning | Assistant(false)) {
        run.push(conv.messages[index])
        index = index + 1
      }
      push_run(items, run, on_open)
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
    let shown = user_display_text(text)
    rows.push(
      @html.div(class="pending-steer-row", title=shown, [
        @html.span(class="pending-steer-icon", "⤷"),
        @html.span(class="pending-steer-text", shown),
        @html.span(class="pending-steer-state", "steering…"),
      ]),
    )
  }
  @html.div(class="pending-steers", rows)
}

///|
/// The one-line display form of a submitted prompt (steer bubbles, sidebar
/// titles): a submission that carried chips is shown as its typed text plus
/// `$name`/`#name` markers rather than the raw `<user_mentions>` envelope the
/// engine receives.
fn user_display_text(text : String) -> String {
  guard @mention_context.parse(text) is Some(parsed) else { return text }
  let parts : Array[String] = []
  if !parsed.task.is_empty() {
    parts.push(parsed.task)
  }
  for mention in parsed.mentions {
    parts.push(mention_glyph(mention) + mention_label(mention))
  }
  parts.join(" ")
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
/// symbols, `✎` editor comments), each removable by its `×`. Always rendered
/// (empty when there are no chips) so the textarea keeps a stable child index
/// and never loses focus when a chip comes or goes; CSS collapses the empty
/// tray to nothing. A chip with a resolved location is also clickable,
/// opening (or refocusing) the editor side-panel on that spot; a comment
/// chip's tooltip is the comment itself.
fn mention_tray(dispatch : @cmd.Emit[Msg], conv : Conversation) -> @html.Html {
  let chips : Array[@html.Html] = []
  for index, mention in conv.mentions {
    let glyph = @html.span(class="mention-glyph", mention_glyph(mention.ref_))
    let label = @html.span(class="mention-label", mention_label(mention.ref_))
    let body = if mention_target(mention.ref_) is Some(target) {
      @html.button(
        class="mention-jump",
        type_="button",
        title=if mention.ref_ is Annotation(comment~, ..) {
          comment
        } else {
          "Jump to \{target.file}"
        },
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
  let has_input = model.bridge is Connected &&
    model.api_ready() &&
    conv.draft_sendable()
  // A compacting conversation cannot accept a prompt either: the serve
  // engine would queue it behind the compaction, where Stop cannot reach it.
  // Every unsettled phase — requested, queued, or running — holds the gate.
  let can_send = !conv.is_running() &&
    conv.compaction is NotCompacting &&
    has_input
  // The left status group: the model, plus the workspace's git branch (moved
  // out of the topbar; a workspace that is not a repository has no chip).
  let status : Array[@html.Html] = [
    @html.span(
      class="composer-model",
      title=model.selected_model,
      model.selected_model,
    ),
  ]
  if conv.branch is Some(branch) && !branch.is_empty() {
    status.push(@html.span(class="composer-branch", branch))
  }
  let controls : Array[@html.Html] = [
    @html.div(class="composer-status", status),
  ]
  if conv.is_running() {
    // One morphing button while this conversation's turn runs: a sendable
    // draft (typed text) turns it into a steer submit, anything else —
    // empty, or chips still waiting for their instruction — leaves it as the
    // interrupt. A turn being cancelled cannot be steered, so the button
    // waits with the user's draft in the composer.
    if !conv.draft_sendable() {
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
      let can_steer = has_input && !(conv.run is Open(stage=Cancelling, ..))
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
  // The requested phase reads as compacting already: the distinction (the
  // host may still be spawning the engine) is not the user's problem.
  match conv.compaction {
    Requested | Compacting =>
      children.push(
        @html.div(class="composer-notice", [
          @html.span(class="composer-notice-icon", icon(icon_fold)),
          @html.span(class="composer-notice-text", "Compacting context…"),
        ]),
      )
    Queued =>
      children.push(
        @html.div(class="composer-notice", [
          @html.span(class="composer-notice-icon", icon(icon_fold)),
          @html.span(
            class="composer-notice-text",
            "Compaction queued — starts when the current turn ends",
          ),
        ]),
      )
    NotCompacting => ()
  }
  let inner : Array[@html.Html] = [
    // First child, always present, so the textarea's index never shifts (which
    // would rebuild the node and drop focus) as chips come and go.
    mention_tray(dispatch, conv),
    @html.textarea(
      id="task",
      value=conv.task,
      placeholder=if conv.is_running() {
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
fn corner_select(
  dispatch : @cmd.Emit[Msg],
  selected : NotificationCorner,
) -> @html.Html {
  @html.select(
    on_change=dispatch.map(value => NotificationCornerChanged(value)),
    [
      @html.option(
        value="bottom-right",
        selected=selected is BottomRight,
        "Bottom right",
      ),
      @html.option(
        value="bottom-left",
        selected=selected is BottomLeft,
        "Bottom left",
      ),
      @html.option(
        value="top-right",
        selected=selected is TopRight,
        "Top right",
      ),
      @html.option(value="top-left", selected=selected is TopLeft, "Top left"),
    ],
  )
}

///|
fn tree_layout_select(
  dispatch : @cmd.Emit[Msg],
  selected : @fileeditor.TreeLayout,
) -> @html.Html {
  @html.select(on_change=dispatch.map(value => TreeLayoutChanged(value)), [
    @html.option(
      value="right-sidebar",
      selected=selected is RightSidebar,
      "Right sidebar",
    ),
    @html.option(
      value="bottom-panel",
      selected=selected is BottomPanel,
      "Bottom panel",
    ),
  ])
}

///|
fn channel_select(
  dispatch : @cmd.Emit[Msg],
  selected : UpdateChannel,
) -> @html.Html {
  @html.select(on_change=dispatch.map(value => UpdateChannelChanged(value)), [
    @html.option(
      value="production",
      selected=selected is Production,
      "Production",
    ),
    @html.option(value="staging", selected=selected is Staging, "Staging"),
  ])
}

///|
/// The Settings check-for-updates row: the last check's outcome — status
/// text, or the accent Update button once an installable release is found —
/// on the left, the Check button on the right.
fn update_check_controls(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> Array[@html.Html] {
  let controls : Array[@html.Html] = []
  match model.update_ux {
    UpdateUnknown => ()
    CheckingForUpdate =>
      controls.push(@html.span(class="update-status", "Checking…"))
    UpToDate =>
      controls.push(@html.span(class="update-status", "You are up to date."))
    UpdateAvailable(version~, installable~) =>
      if installable {
        controls.push(
          @html.button(
            class="primary",
            on_click=dispatch(UpdateClicked),
            "Update to \{version}",
          ),
        )
      } else {
        controls.push(
          @html.span(
            class="update-status",
            "\{version} is available, but this build cannot install updates.",
          ),
        )
      }
    ConfirmingRestart(version~) =>
      // The interrupt modal is up over this row; keep the button visible
      // behind it so the row does not blink while the user decides.
      controls.push(@html.button(class="primary", "Update to \{version}"))
    DownloadingUpdate(version~) =>
      controls.push(
        @html.span(class="update-status", "Downloading \{version}…"),
      )
    RestartingForUpdate(version~) =>
      controls.push(
        @html.span(class="update-status", "Restarting into \{version}…"),
      )
    UpdateCheckFailed(message~) =>
      controls.push(@html.span(class="update-status update-error", message))
  }
  controls.push(
    @html.button(
      class="secondary",
      disabled=model.update_ux
        is (CheckingForUpdate | DownloadingUpdate(..) | RestartingForUpdate(..)),
      on_click=dispatch(CheckForUpdates),
      "Check for updates",
    ),
  )
  controls
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
            // The id is layout only (grid placement); the fill is the
            // shared primary style.
            id="saveApiKey",
            class="primary",
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
    settings_group("Interface", [
      setting_row(
        "Notification corner",
        [corner_select(dispatch, model.notification_corner)],
        desc="Where error notifications pop up.",
      ),
      setting_row(
        "File tree layout",
        [tree_layout_select(dispatch, model.tree_layout)],
        desc="Where the editor panel docks its file tree.",
      ),
    ]),
    settings_group("Updates", [
      setting_row(
        "Update channel",
        [channel_select(dispatch, model.update_channel)],
        desc="Staging serves pre-release builds for testing.",
      ),
      setting_row(
        "Check for updates",
        update_check_controls(dispatch, model),
        desc="Current version: \{@version.AppVersion}.",
      ),
    ]),
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
  if model.active().is_running() {
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
  if conv.cwd is Some(cwd) {
    "session \{conv.session_id}\nworkspace \{cwd.0}"
  } else {
    "session \{conv.session_id}"
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
  match model.launcher.apps {
    AppsFailed(message) =>
      rows.push(@html.div(class="launcher-empty danger", message))
    AppsNotFetched =>
      rows.push(@html.div(class="launcher-empty", "Finding apps…"))
    AppsFetched([]) =>
      rows.push(@html.div(class="launcher-empty", "No apps found"))
    AppsFetched(apps) =>
      for app in apps {
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
  let ready = !conv.messages.is_empty() || conv.is_running()
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
  let items : Array[@html.Html] = []
  // The sidebar toggle rides the window's left edge. While the sidebar is open
  // it lives in the sidebar's own header; only when the sidebar is closed does
  // it fall back to the topbar's left, so it holds the same screen position
  // either way (the same trick the right-panel toggle uses on the right edge).
  if !model.sidebar_open {
    items.push(
      @html.button(
        class="topbar-toggle",
        title="Show sidebar",
        on_click=dispatch(ToggleSidebar),
        icon(icon_layout_sidebar_left),
      ),
    )
  }
  items.push(@html.span(class="topbar-icon", "✦"))
  items.push(
    @html.span(
      class="topbar-title",
      title=session_tooltip(conv),
      conversation_title(conv),
    ),
  )
  // The conversation's attached project; a scratch conversation has no chip.
  // The git branch is not shown here — it lives in the composer's status row.
  if conv.workspace is Some(workspace) {
    items.push(
      @html.span(class="topbar-workspace", title=workspace.0, [
        icon(icon_folder),
        @html.text(workspace_label(workspace.0)),
      ]),
    )
  }
  items.push(run_indicator(model))
  if conv.usage_tokens > 0 {
    items.push(@html.span(class="pill", token_label(conv.usage_tokens)))
  }
  if !conv.watcher_status.is_empty() {
    items.push(@html.span(class="pill", "moon_check \{conv.watcher_status}"))
  }
  items.push(launcher_view(dispatch, model))
  // Rightmost: the toggle for the whole right-hand panel — only while the
  // panel is closed; an open panel carries the toggle at the right edge of
  // its breadcrumb instead, keeping this bar uncrowded. Both spots hug the
  // window's right edge, so the toggle stays put as the panel opens/closes.
  if !model.file_panel.open {
    items.push(
      @html.button(
        class="panel-toggle",
        title="Show panel",
        on_click=dispatch(FileEditor(ToggleFilePanel)),
        icon(icon_layout_sidebar_right),
      ),
    )
  }
  @html.div(class="topbar", items)
}

///|
/// Skills and Settings have no topbar, so while the sidebar is closed they
/// float their own reopen button at the sidebar toggle's screen position —
/// without it the sidebar, their only way back to any other screen, would be
/// unrecoverable.
fn page_with_toggle(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  page : @html.Html,
) -> Array[@html.Html] {
  if model.sidebar_open {
    [page]
  } else {
    [
      @html.button(
        class="topbar-toggle page-sidebar-toggle",
        title="Show sidebar",
        on_click=dispatch(ToggleSidebar),
        icon(icon_layout_sidebar_left),
      ),
      page,
    ]
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
    Skills => page_with_toggle(dispatch, model, skills_page(dispatch, model))
    Settings =>
      page_with_toggle(dispatch, model, settings_page(dispatch, model))
  }
  // The app is `sidebar | content`; `content` itself splits into the
  // conversation (left) and the editor (right) as two independent parts, so
  // either side can be swapped out later. The files panel only opens over the
  // chat; on the Skills page it stays collapsed, but the editor column (and the
  // viewer host inside it) is still rendered so the attached viewer is never
  // torn down.
  let panel_open = model.file_panel.open && model.screen is Chat
  let children : Array[@html.Html] = [
    sidebar_view(dispatch, model),
    @html.div(class=if panel_open { "content panel-open" } else { "content" }, [
      @html.main_(content),
      @fileeditor.panel_view(
        dispatch.map(msg => FileEditor(msg)),
        model.file_panel,
        file_ctx(model),
      ),
    ]),
  ]
  // The toast stack floats over everything (position: fixed), so appending
  // it last never shifts the layout; skipping it entirely while empty keeps
  // the corner clickable.
  if model.notifications.length() > 0 {
    children.push(notifications_view(dispatch, model))
  }
  // The interrupt-confirmation modal floats the same way, above the toasts.
  if model.update_ux is ConfirmingRestart(version~) {
    children.push(update_confirm_modal(dispatch, version))
  }
  @html.div(
    class=if model.sidebar_open { "app" } else { "app sidebar-collapsed" },
    children,
  )
}

///|
/// The modal shown when updating would cut running conversations off:
/// restarting tears the engine processes down mid-run. The backdrop and the
/// Cancel button both keep the current version running.
fn update_confirm_modal(
  dispatch : @cmd.Emit[Msg],
  version : String,
) -> @html.Html {
  @html.div(class="modal-backdrop", on_click=dispatch(CancelUpdateRestart), [
    @html.div(class="modal", [
      @html.div(class="modal-title", "Update to \{version}?"),
      @html.div(
        class="modal-body",
        "A conversation is still running. Updating restarts the app and interrupts it; the transcript so far is saved.",
      ),
      @html.div(class="modal-actions", [
        @html.button(on_click=dispatch(CancelUpdateRestart), "Keep working"),
        @html.button(
          class="primary",
          on_click=dispatch(ConfirmUpdateRestart),
          "Update and restart",
        ),
      ]),
    ]),
  ])
}

///|
/// The floating toast stack, fixed to the configured window corner. Each
/// toast dismisses on click; its timer handles the rest.
fn notifications_view(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let toasts : Array[@html.Html] = []
  for toast in model.notifications {
    toasts.push(
      @html.div(
        class="notification",
        title="Dismiss",
        on_click=dispatch(DismissNotification(toast.id)),
        toast.message,
      ),
    )
  }
  @html.div(
    class="notifications corner-\{model.notification_corner.wire()}",
    toasts,
  )
}
