///|
fn run_label(model : Model) -> String {
  match model.active_run_id {
    Some(run_id) if model.running => "run \{run_id}"
    _ if model.running => "starting"
    _ => "idle"
  }
}

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
fn status_view(model : Model) -> @html.Html {
  @html.div(
    id="status",
    class="status \{model.status.kind().css()}",
    model.status.label(),
  )
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
fn sidebar_view(dispatch : @cmd.Dispatch[Msg], model : Model) -> @html.Html {
  @html.aside([
    @html.div(class="sidebar-main", [
      @html.div(class="sidebar-section", [
        @html.div(class="sidebar-heading", "Project"),
        @html.div(class="project-row", [
          @html.span(class="sidebar-icon", "▣"),
          @html.span(class="sidebar-label", "openseek"),
        ]),
        @html.div(class="conversation-row active", [
          @html.span(class="sidebar-label", conversation_title(model)),
        ]),
      ]),
    ]),
    @html.div(class="sidebar-footer", [
      @html.button(
        class="sidebar-button",
        on_click=dispatch(OpenSetup),
        [
          @html.span(class="sidebar-icon", "⚙"),
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
      let content_class = if is_danger {
        "msg-content danger"
      } else {
        "msg-content"
      }
      @html.div(class="msg", [
        @html.div(class="avatar agent", "✦"),
        @html.div(class="msg-body", [
          @html.div(class="msg-role", "openseek"),
          @html.div(class=content_class, inline_code_nodes(item.content)),
        ]),
      ])
    }
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
  @html.section(id="transcript", class="transcript", [
    @html.div(id="stream", class="stream", items),
  ])
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
  let can_send = !model.running &&
    model.bridge_ready &&
    !model.api_key.trim().is_empty() &&
    !model.task.trim().is_empty()
  let controls : Array[@html.Html] = [
    @html.span(
      class="composer-model",
      title=model.selected_model,
      model.selected_model,
    ),
  ]
  if model.running {
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
  @html.section(class="composer", [
    @html.div(class="composer-inner", [
      @html.textarea(
        id="task",
        value=model.task,
        placeholder="Ask OpenSeek to inspect, edit, or explain this workspace.",
        on_input=dispatch.map(value => TaskChanged(value)),
        attrs=task_attrs(dispatch),
        "",
      ),
      @html.div(class="composer-toolbar", [
        @html.div(class="composer-controls", controls),
      ]),
    ]),
  ])
}

///|
fn setup_popup(dispatch : @cmd.Dispatch[Msg], model : Model) -> @html.Html {
  let has_key = !model.api_key.trim().is_empty()
  let runtime_items : Array[@html.Html] = [
    @html.span(class="pill", run_label(model)),
    @html.span(class="pill", token_label(model.usage_tokens)),
  ]
  if !model.watcher_status.is_empty() {
    runtime_items.push(
      @html.span(class="pill", "moon_check \{model.watcher_status}"),
    )
  }
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
      @html.div(class="meta", runtime_items),
      status_view(model),
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
          "Working directory",
          model.cwd,
          "current process directory",
          @html.InputType::Text,
          dispatch.map(value => CwdChanged(value)),
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
fn topbar_view(model : Model) -> @html.Html {
  @html.div(class="topbar", [
    @html.span(class="topbar-icon", "✦"),
    @html.span(class="topbar-title", conversation_title(model)),
    @html.span(class="topbar-branch", "main"),
    run_indicator(model),
  ])
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
