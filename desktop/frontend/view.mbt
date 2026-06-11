///|
fn can_stop(model : Model) -> Bool {
  match model.active_run_id {
    Some(_) => model.running
    None => false
  }
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
fn conversation_title(model : Model) -> String {
  let mut title = ""
  for item in model.messages {
    if title.is_empty() {
      match item.kind {
        User => title = item.content.trim().to_owned()
        _ => ()
      }
    }
  }
  if title.is_empty() {
    let task = model.task.trim().to_owned()
    if task.is_empty() {
      "OpenSeek Desktop"
    } else {
      task
    }
  } else {
    title
  }
}

///|
/// Sidebar rows for the engine's durable sessions, newest first. The current
/// conversation is highlighted; until its first turn reaches the store it is
/// not in the engine's list yet, so it gets its own row at the top.
fn session_rows(
  dispatch : @cmd.Dispatch[Msg],
  model : Model,
) -> Array[@html.Html] {
  let rows : Array[@html.Html] = []
  let mut current_listed = false
  for item in model.sessions {
    if item.id == model.session_id {
      current_listed = true
    }
  }
  if !current_listed {
    rows.push(
      @html.div(class="conversation-row active", title=model.session_id, [
        @html.span(class="sidebar-label", conversation_title(model)),
      ]),
    )
  }
  for item in model.sessions {
    let active = item.id == model.session_id
    let label = if active {
      conversation_title(model)
    } else {
      non_empty_or(item.title, item.id)
    }
    rows.push(
      @html.button(
        class=if active {
          "conversation-row active"
        } else {
          "conversation-row"
        },
        title=item.id,
        disabled=model.running,
        on_click=dispatch(OpenSession(item.id)),
        [@html.span(class="sidebar-label", label)],
      ),
    )
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
        @html.button(
          class="sidebar-button",
          disabled=model.running,
          on_click=dispatch(NewChat),
          [
            @html.span(class="sidebar-icon", "+"),
            @html.span(class="sidebar-label", "New chat"),
          ],
        ),
      ]),
      @html.div(class="sidebar-section sessions", sessions_section),
    ]),
    @html.div(class="sidebar-footer", [
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
fn transcript_item_view(item : TranscriptItem) -> @html.Html {
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
        @html.div(class="msg-content markdown", markdown_nodes(item.content))
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
          @html.div(class="tool-head", non_empty_or(name, "tool")),
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
      @html.div(class="msg-content markdown reasoning", markdown_nodes(content)),
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
      @html.div(class="msg-content markdown", markdown_nodes(content)),
    ]),
  ])
}

///|
fn transcript_view(model : Model) -> @html.Html {
  let items : Array[@html.Html] = []
  if model.messages.is_empty() {
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
    for item in model.messages {
      items.push(transcript_item_view(item))
    }
  }
  // Both buffers can be non-empty at once: the answer starts streaming
  // before the engine commits the reasoning. Only the bubble that text is
  // currently appearing in gets the caret.
  if !model.streaming_reasoning.is_empty() {
    items.push(
      reasoning_view(
        model.streaming_reasoning,
        streaming=model.streaming_response.is_empty(),
      ),
    )
  }
  if !model.streaming_response.is_empty() {
    items.push(streaming_response_view(model.streaming_response))
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
fn pending_steers_panel(model : Model) -> @html.Html {
  let rows : Array[@html.Html] = []
  for text in model.pending_steers {
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
  let has_input = model.bridge_ready &&
    !model.api_key.trim().is_empty() &&
    !model.task.trim().is_empty()
  let can_send = !model.running && has_input
  let controls : Array[@html.Html] = [
    @html.span(
      class="composer-model",
      title=model.selected_model,
      model.selected_model,
    ),
  ]
  if model.running {
    // One morphing button while a turn runs: typed text turns it into a
    // steer submit, an empty composer leaves it as the interrupt. A turn
    // being cancelled cannot be steered, so the button waits with the
    // user's text in the composer.
    if model.task.trim().is_empty() {
      controls.push(
        @html.button(
          id="stop",
          class="icon-button stop-button",
          title="Stop",
          disabled=!can_stop(model),
          on_click=dispatch(Stop),
          "■",
        ),
      )
    } else {
      let can_steer = has_input && !(model.status is Cancelling)
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
  if model.pending_steers.length() > 0 {
    children.push(pending_steers_panel(model))
  }
  children.push(
    @html.div(class="composer-inner", [
      @html.textarea(
        id="task",
        value=model.task,
        placeholder=if model.running {
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
fn setup_popup(dispatch : @cmd.Dispatch[Msg], model : Model) -> @html.Html {
  let has_key = !model.api_key.trim().is_empty()
  @html.div(class="setup-backdrop", [
    @html.div(class="setup-popup", [
      @html.div(class="setup-header", [
        @html.div(class="setup-title", [
          @html.h2("Settings"),
          @html.div(
            class="status",
            if has_key {
              "Update OpenSeek runtime settings."
            } else {
              "Enter a DeepSeek API key to start."
            },
          ),
        ]),
        @html.button(
          class="secondary close-button",
          disabled=!has_key,
          on_click=dispatch(CloseSetup),
          "Close",
        ),
      ]),
      @html.div(class="settings", [
        model_select(dispatch, model.selected_model),
        setting_input(
          "Max steps",
          model.max_steps,
          "1000",
          @html.InputType::Number,
          dispatch.map(value => MaxStepsChanged(value)),
        ),
        setting_input(
          "DeepSeek API key",
          model.setup_api_key,
          "sk-...",
          @html.InputType::Password,
          dispatch.map(value => SetupApiKeyChanged(value)),
        ),
        @html.button(
          id="saveApiKey",
          disabled=model.setup_api_key.trim().is_empty(),
          on_click=dispatch(SaveApiKey),
          "Save API key",
        ),
      ]),
    ]),
  ])
}

///|
fn run_indicator(model : Model) -> @html.Html {
  let label = model.status.label()
  if model.running {
    @html.div(class="run-status accent", [
      @html.span(class="run-dot accent pulse", ""),
      @html.span(class="run-text", label),
    ])
  } else {
    @html.div(class="run-status", [
      @html.span(class="run-dot \{model.status.kind().css()}", ""),
      @html.span(class="run-text", label),
    ])
  }
}

///|
/// The workspace line appears once the host has reported it via `started`;
/// before the conversation's first run only the session id is known.
fn session_tooltip(model : Model) -> String {
  if model.cwd.is_empty() {
    "session \{model.session_id}"
  } else {
    "session \{model.session_id}\nworkspace \{model.cwd}"
  }
}

///|
/// Top bar: conversation identity on the left (session id and workspace in
/// the tooltip), live run state on the right — these are per-conversation
/// runtime facts, not settings, so they live here rather than in the
/// settings popup.
fn topbar_view(model : Model) -> @html.Html {
  let items : Array[@html.Html] = [
    @html.span(class="topbar-icon", "✦"),
    @html.span(
      class="topbar-title",
      title=session_tooltip(model),
      conversation_title(model),
    ),
    @html.span(class="topbar-branch", "main"),
    run_indicator(model),
  ]
  if model.usage_tokens > 0 {
    items.push(@html.span(class="pill", token_label(model.usage_tokens)))
  }
  if !model.watcher_status.is_empty() {
    items.push(@html.span(class="pill", "moon_check \{model.watcher_status}"))
  }
  @html.div(class="topbar", items)
}

///|
fn view(dispatch : @cmd.Dispatch[Msg], model : Model) -> @html.Html {
  let app = @html.div(class="app", [
    sidebar_view(dispatch, model),
    @html.main_([
      topbar_view(model),
      transcript_view(model),
      composer_view(dispatch, model),
    ]),
  ])
  if model.setup_open {
    @html.fragment([app, setup_popup(dispatch, model)])
  } else {
    app
  }
}
