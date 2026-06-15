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
  on_input : @cmd.Dispatch[String],
) -> @html.Html {
  @html.label([
    @html.text(label_text),
    @html.input(input_type~, value~, placeholder~, on_input~, @html.nothing),
  ])
}

///|
fn model_select(dispatch : @cmd.Dispatch[Msg], selected : String) -> @html.Html {
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
  dispatch : @cmd.Dispatch[Msg],
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
fn session_rows(
  dispatch : @cmd.Dispatch[Msg],
  model : Model,
) -> Array[@html.Html] {
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
fn sidebar_view(dispatch : @cmd.Dispatch[Msg], model : Model) -> @html.Html {
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
fn transcript_item_view(item : @transcript.TranscriptItem) -> @html.Html {
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
          @markdown.markdown_nodes(item.content),
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
    Reasoning => reasoning_view(item.content, streaming=false)
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
fn reasoning_view(content : String, streaming~ : Bool) -> @html.Html {
  let msg_class = if streaming { "msg streaming" } else { "msg" }
  @html.div(class=msg_class, [
    @html.div(class="avatar agent", "✧"),
    @html.div(class="msg-body", [
      @html.div(class="msg-role", "Thinking"),
      @html.div(
        class="msg-content markdown reasoning",
        @markdown.markdown_nodes(content),
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
fn streaming_response_view(content : String) -> @html.Html {
  @html.div(class="msg streaming", [
    @html.div(class="avatar agent", "✦"),
    @html.div(class="msg-body", [
      @html.div(class="msg-role", "openseek"),
      @html.div(class="msg-content markdown", @markdown.markdown_nodes(content)),
    ]),
  ])
}

///|
fn transcript_view(conv : Conversation) -> @html.Html {
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
      items.push(transcript_item_view(item))
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
      ),
    )
  }
  if !conv.streaming_response.is_empty() {
    items.push(streaming_response_view(conv.streaming_response))
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
fn task_attrs(dispatch : @cmd.Dispatch[Msg]) -> @html.Attrs {
  @html.Attrs::build().on_keydown(fn(event) {
    if is_submit_shortcut(event) {
      event.prevent_default()
      dispatch(Send)
    } else {
      @cmd.none
    }
  })
}

///|
fn composer_view(dispatch : @cmd.Dispatch[Msg], model : Model) -> @html.Html {
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
  children.push(
    @html.div(class="composer-inner", [
      @html.textarea(
        id="task",
        value=conv.task,
        placeholder=if conv.running {
          "Steer the running task — your message joins it at the next step."
        } else {
          "Ask OpenSeek to inspect, edit, or explain this workspace."
        },
        on_input=dispatch.map(value => TaskChanged(value)),
        attrs=task_attrs(dispatch),
        "",
      ),
      @html.div(class="composer-toolbar", [
        @html.div(class="composer-controls", controls),
      ]),
    ]),
  )
  @html.section(class="composer", children)
}

///|
fn provider_select(
  dispatch : @cmd.Dispatch[Msg],
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
fn provider_hint(provider : ApiProvider) -> String {
  match provider {
    Openseek => "Requests go through the OpenSeek service; no key needed."
    Deepseek => "Requests go straight to api.deepseek.com with your key."
    Custom => "Any DeepSeek-compatible chat-completions URL; key optional."
  }
}

///|
fn setup_popup(dispatch : @cmd.Dispatch[Msg], model : Model) -> @html.Html {
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
  dispatch : @cmd.Dispatch[Msg],
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
  dispatch : @cmd.Dispatch[Msg],
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
fn skills_page(dispatch : @cmd.Dispatch[Msg], model : Model) -> @html.Html {
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
      @html.nothing,
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
/// Top bar: conversation identity on the left (session id and workspace in
/// the tooltip), live run state on the right — these are per-conversation
/// runtime facts, not settings, so they live here rather than in the
/// settings popup.
fn topbar_view(model : Model) -> @html.Html {
  let conv = model.active()
  let items : Array[@html.Html] = [
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
  @html.div(class="topbar", items)
}

///|
fn view(dispatch : @cmd.Dispatch[Msg], model : Model) -> @html.Html {
  let content = match model.screen {
    Chat =>
      [
        topbar_view(model),
        transcript_view(model.active()),
        composer_view(dispatch, model),
      ]
    Skills => [skills_page(dispatch, model)]
  }
  let app = @html.div(class="app", [
    sidebar_view(dispatch, model),
    @html.main_(content),
  ])
  if model.setup_open {
    @html.fragment([app, setup_popup(dispatch, model)])
  } else {
    app
  }
}
