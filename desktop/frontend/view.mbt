///|
fn can_stop(conv : Conversation) -> Bool {
  conv.running && conv.active_run_id is Some(_)
}

///|
fn token_label(tokens : Int) -> String {
  "\{tokens} tokens"
}

///|
fn setting_input(
  label_text : String,
  value : String,
  placeholder : String,
  input_type : @html.InputType,
  on_input : @cmd.Emit[String],
) -> @html.Html {
  @html.label([
    @html.text(label_text),
    @html.input(input_type~, value~, placeholder~, on_input~),
  ])
}

///|
fn model_select(dispatch : @cmd.Emit[Msg], selected : String) -> @html.Html {
  @html.label([
    @html.text("Model"),
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
    ]),
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
fn session_row(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  session_id : String,
  label : String,
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
  @html.button(
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
    if !listed(conv.session_id) {
      rows.push(
        session_row(dispatch, model, conv.session_id, conversation_title(conv)),
      )
    }
  }
  for item in model.sessions {
    let label = if model.find_conversation(item.id) is Some(conv) &&
      item.id == model.active_session {
      conversation_title(conv)
    } else {
      @transcript.non_empty_or(item.title, item.id)
    }
    rows.push(session_row(dispatch, model, item.id, label))
  }
  if !model.sessions_error.is_empty() {
    rows.push(
      @html.div(class="conversation-row error", title=model.sessions_error, [
        @html.span(class="sidebar-label", "sessions unavailable"),
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
          @html.span(class="sidebar-icon", "+"),
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
          @html.span(class="sidebar-icon", "⬡"),
          @html.span(class="sidebar-label", "Skills"),
        ],
      ),
      @html.button(class="sidebar-button", on_click=dispatch(OpenSetup), [
        @html.span(class="sidebar-icon", "⚙"),
        @html.span(class="sidebar-label", "Settings"),
      ]),
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
    Reasoning => reasoning_view(item.content, streaming=false, on_open)
    Tool(name, is_error) =>
      @html.div(class="tool-row", [
        @html.div(class=tool_class(is_error), [
          @html.div(class="tool-head", @transcript.non_empty_or(name, "tool")),
          @html.pre(item.content),
        ]),
      ])
  }
}

///|
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
  conv : Conversation,
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
    for item in conv.messages {
      items.push(transcript_item_view(item, on_open))
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
  @html.section(id="transcript", class="transcript", [
    @html.div(id="stream", class="stream", items),
  ])
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
  let hint = match completion.kind {
    SlashCommands => "Commands"
    SkillMentions => "Skills"
  }
  @html.div(class="completion-menu", [
    @html.div(class="completion-hint", hint),
    @html.div(class="completion-list", rows),
  ])
}

///|
fn composer_view(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let conv = model.active()
  let has_input = model.bridge_ready &&
    model.api_ready() &&
    !conv.task.trim().is_empty()
  let can_send = !conv.running && has_input
  let controls : Array[@html.Html] = [
    @html.span(
      class="composer-model",
      title=model.selected_model,
      model.selected_model,
    ),
  ]
  if conv.running {
    // One morphing button while this conversation's turn runs: typed text
    // turns it into a steer submit, an empty composer leaves it as the
    // interrupt. A turn being cancelled cannot be steered, so the button
    // waits with the user's text in the composer.
    if conv.task.trim().is_empty() {
      controls.push(
        @html.button(
          id="stop",
          class="icon-button stop-button",
          title="Stop",
          disabled=!can_stop(conv),
          on_click=dispatch(Stop),
          "■",
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
          "↑",
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
        "↑",
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
        @html.span(class="composer-notice-icon", "🗜"),
        @html.span(class="composer-notice-text", "Compacting context…"),
      ]),
    )
  }
  let inner : Array[@html.Html] = [
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
  @html.label([
    @html.text("API endpoint"),
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
    ]),
  ])
}

///|
fn wsl_select(dispatch : @cmd.Emit[Msg], enabled : Bool) -> @html.Html {
  @html.label([
    @html.text("Engine environment"),
    @html.select(on_change=dispatch.map(value => WslModeChanged(value)), [
      @html.option(value="native", selected=!enabled, "Windows (native)"),
      @html.option(value="wsl", selected=enabled, "WSL"),
    ]),
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
fn setup_popup(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let ready = model.api_ready()
  let settings : Array[@html.Html] = [
    model_select(dispatch, model.selected_model),
    setting_input(
      "Max steps",
      model.max_steps,
      "1000",
      @html.InputType::Number,
      dispatch.map(value => MaxStepsChanged(value)),
    ),
    provider_select(dispatch, model.api_provider),
    @html.div(class="setting-hint", provider_hint(model.api_provider)),
  ]
  if model.api_provider is Custom {
    settings.push(
      setting_input(
        "Endpoint URL",
        model.custom_api_url,
        "https://host/chat/completions",
        @html.InputType::Text,
        dispatch.map(value => CustomApiUrlChanged(value)),
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
    settings.push(
      setting_input(
        if model.api_provider is Custom {
          "Custom API key"
        } else {
          "DeepSeek API key"
        },
        model.setup_api_key,
        if saved_key.trim().is_empty() {
          "sk-..."
        } else {
          "saved — enter to replace"
        },
        @html.InputType::Password,
        dispatch.map(value => SetupApiKeyChanged(value)),
      ),
    )
    settings.push(
      @html.button(
        id="saveApiKey",
        disabled=model.setup_api_key.trim().is_empty(),
        on_click=dispatch(SaveApiKey),
        "Save API key",
      ),
    )
  }
  // WSL is Windows-only; elsewhere the section would be dead weight.
  if model.is_windows {
    settings.push(wsl_select(dispatch, model.wsl_enabled))
    if model.wsl_enabled {
      settings.push(
        setting_input(
          "WSL distro",
          model.wsl_distro,
          "default distro",
          @html.InputType::Text,
          dispatch.map(value => WslDistroChanged(value)),
        ),
      )
      settings.push(
        setting_input(
          "Engine command in WSL",
          model.wsl_engine,
          "bundled engine",
          @html.InputType::Text,
          dispatch.map(value => WslEngineChanged(value)),
        ),
      )
      settings.push(
        @html.div(
          class="setting-hint",
          "Runs the agent engine inside WSL, so its shell and tools see the distro's Linux environment. By default this uses the Linux engine bundled with the app (falling back to openseek on the distro's PATH). Conversations stay in the shared session store either way.",
        ),
      )
    }
  }
  @html.div(class="setup-backdrop", [
    @html.div(class="setup-popup", [
      @html.div(class="setup-header", [
        @html.div(class="setup-title", [
          @html.h2("Settings"),
          @html.div(
            class="status",
            if ready {
              "Update OpenSeek runtime settings."
            } else if model.api_provider is Custom {
              "Enter a chat-completions endpoint URL to start."
            } else {
              "Enter a DeepSeek API key to start."
            },
          ),
        ]),
        @html.button(
          class="secondary close-button",
          disabled=!ready,
          on_click=dispatch(CloseSetup),
          "Close",
        ),
      ]),
      @html.div(class="settings", settings),
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
    @html.div(class="skill-avatar", "⬡"),
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
    @html.div(class="skill-avatar", "⬡"),
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
fn launcher_menu(dispatch : @cmd.Dispatch[Msg], model : Model) -> @html.Html {
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
          @html.nothing,
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
fn launcher_view(dispatch : @cmd.Dispatch[Msg], model : Model) -> @html.Html {
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
        @html.span(class="launcher-glyph", "↗"),
        @html.span(class="launcher-caret", "▾"),
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
      "☰",
    ),
    @html.span(class="topbar-icon", "✦"),
    @html.span(
      class="topbar-title",
      title=session_tooltip(conv),
      conversation_title(conv),
    ),
    @html.span(class="topbar-branch", "main"),
    run_indicator(model),
  ]
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
      "◨",
    ),
  )
  items.push(launcher_view(dispatch, model))
  @html.div(class="topbar", items)
}

///|
/// The editor part: a read-only code viewer (left) beside the active
/// conversation's file tree (right), the tree fronted by a filter box. The
/// whole part is always rendered so the viewer's host element (`viewer-host`)
/// stays put across renders and screen switches; CSS collapses it to zero width
/// when closed.
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
  // The file-tree column (right): a filter box (in a header bar matching the
  // topbar/breadcrumb height) over the scrollable tree. The collapse toggle
  // lives on the breadcrumb header (always visible), so the column folds away
  // entirely when hidden.
  let column_children : Array[@html.Html] = [
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
    column_children.push(@html.div(class="file-panel-error", panel.error))
  }
  column_children.push(@html.div(class="file-tree", tree_children))
  // The stable element the viewer attaches its imperative DOM into; it must
  // stay empty and never be re-keyed (see editor_panel.mbt).
  // `editor-shell` brings in the viewer's `--vscode-*` / `--editor-*` theme
  // variables (defined on that class in the bundled viewer.css); `data-theme`
  // selects the light palette. The viewer's colors cascade from this host.
  let viewer_host = @html.div(
    attrs=@html.Attrs::build()
      .id(ViewerHostId)
      .class("viewer-host editor-shell")
      .data_set("theme", "light"),
    ([] : Array[@html.Html]),
  )
  // The viewer pane: a breadcrumb header (the open file's path plus the
  // file-tree toggle) over the viewer.
  let viewer_pane = @html.div(class="viewer-pane", [
    viewer_breadcrumb(dispatch, panel),
    viewer_host,
  ])
  // A grab strip on the editor's left edge for drag-to-resize. Absolutely
  // positioned, so it is not a grid item and never disturbs the viewer/tree
  // columns; its drag is wired imperatively (see editor_resize.mbt). Always
  // rendered (CSS hides it while the panel is closed) so its position among the
  // editor's children — and thus the never-re-keyed viewer host — stays stable.
  let resize_handle = @html.div(
    attrs=@html.Attrs::build().id(ResizeHandleId).class("editor-resize-handle"),
    ([] : Array[@html.Html]),
  )
  @html.div(
    class=if panel.tree_open { "editor" } else { "editor tree-collapsed" },
    [
      resize_handle,
      viewer_pane,
      @html.div(class="file-tree-column", column_children),
    ],
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
/// The breadcrumb header over the viewer: the open file's path as
/// `dir › dir › file` (the file segment emphasized, a muted placeholder when
/// nothing is open) on the left, and the file-tree toggle on the right.
fn viewer_breadcrumb(
  dispatch : @cmd.Emit[Msg],
  panel : FilePanel,
) -> @html.Html {
  let crumbs : Array[@html.Html] = []
  if panel.selected is Some(path) {
    let segments = path_segments(path)
    for index, segment in segments {
      if index > 0 {
        crumbs.push(@html.span(class="crumb-sep", "›"))
      }
      let last = index == segments.length() - 1
      crumbs.push(
        @html.span(
          class=if last { "crumb crumb-file" } else { "crumb" },
          segment,
        ),
      )
    }
  } else {
    crumbs.push(@html.span(class="crumb crumb-empty", "No file open"))
  }
  @html.div(class="viewer-breadcrumb", [
    @html.div(class="crumb-path", crumbs),
    @html.button(
      class=if panel.tree_open { "tree-toggle active" } else { "tree-toggle" },
      title=if panel.tree_open { "Hide file tree" } else { "Show file tree" },
      on_click=dispatch(ToggleFileTree),
      "▤",
    ),
  ])
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
  guard model.file_panel.children.get(dir_path) is Some(entries) else {
    return
  }
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
    @html.div(
      class="tree-row tree-dir",
      style=[pad],
      on_click=dispatch(DirToggle(entry.path)),
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
      on_click=dispatch(FileSelected(path=entry.path, name=entry.name)),
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
        transcript_view(model.active(), path => dispatch(OpenFile(path))),
        composer_view(dispatch, model),
      ]
    Skills => [skills_page(dispatch, model)]
  }
  // The app is `sidebar | content`; `content` itself splits into the
  // conversation (left) and the editor (right) as two independent parts, so
  // either side can be swapped out later. The files panel only opens over the
  // chat; on the Skills page it stays collapsed, but the editor column (and the
  // viewer host inside it) is still rendered so the attached viewer is never
  // torn down.
  let panel_open = model.file_panel.open && model.screen is Chat
  // `mac` adds the immersive-titlebar top inset (the native window has no title
  // bar there); `sidebar-collapsed` folds the sidebar.
  let app_class = "app"
  let app_class = if model.sidebar_open {
    app_class
  } else {
    app_class + " sidebar-collapsed"
  }
  let app_class = if model.is_macos { app_class + " mac" } else { app_class }
  let app = @html.div(class=app_class, [
    sidebar_view(dispatch, model),
    @html.div(class=if panel_open { "content panel-open" } else { "content" }, [
      @html.main_(content),
      file_panel_view(dispatch, model),
    ]),
  ])
  if model.setup_open {
    @html.fragment([app, setup_popup(dispatch, model)])
  } else {
    app
  }
}
