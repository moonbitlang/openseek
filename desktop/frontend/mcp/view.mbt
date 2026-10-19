///|
/// What the Settings page's MCP group is about: the OpenSeek conversation
/// whose engine is asked, or why there is none to ask.
pub(all) enum Subject {
  /// An OpenSeek conversation is current; its engine is the one to ask.
  Conversation(@interop.ConversationKey)
  /// A Codex conversation is current. Codex takes its MCP servers from its
  /// own configuration, which this panel does not show.
  CodexConversation
  /// No conversation is current.
  NoConversation
}

///|
/// The rows of the Settings page's MCP group for `subject`: the explanation
/// with its refresh button, then that conversation's engine's latest report.
pub fn rows(
  locale~ : @i18n.Locale = English,
  subject : Subject,
  state : State,
  emit : @cmd.Emit[Msg],
) -> Array[@html.Html] {
  let conversation = match subject {
    Conversation(conversation) => Some(conversation)
    CodexConversation | NoConversation => None
  }
  let phase = state.phase_for(conversation)
  let checking = phase is Checking
  let refresh = match conversation {
    Some(conversation) =>
      @html.button(
        class="button secondary",
        disabled=checking,
        on_click=emit(Refresh(conversation)),
        text(locale, if checking { Refreshing } else { Refresh }),
      )
    // Nothing to ask about without a conversation.
    None =>
      @html.button(
        class="button secondary",
        disabled=true,
        text(locale, Refresh),
      )
  }
  let rows : Array[@html.Html] = [
    @settings.row(
      text(locale, Servers),
      [refresh],
      desc=text(locale, Description),
    ),
  ]
  match subject {
    Conversation(_) => ()
    CodexConversation => {
      rows.push(note(text(locale, CodexConversation)))
      return rows
    }
    NoConversation => {
      rows.push(note(text(locale, NoConversation)))
      return rows
    }
  }
  let reply = match phase {
    Unchecked | Checking => return rows
    CheckFailed(error) => {
      rows.push(problem(text(locale, CheckFailed), error))
      return rows
    }
    Loaded(reply) | Reloading(reply) => reply
  }
  match reply {
    Stopped => rows.push(note(text(locale, EngineStopped)))
    Connecting => rows.push(note(text(locale, EngineConnecting)))
    Running(status) => status_rows(locale, status, rows)
  }
  rows
}

///|
/// What a running engine reported: the files it could not load, then its
/// servers in configuration order.
fn status_rows(
  locale : @i18n.Locale,
  status : @wire.McpStatus,
  rows : Array[@html.Html],
) -> Unit {
  guard !status.configs.is_empty() else {
    rows.push(note(text(locale, NotConfigured)))
    return
  }
  let mut loaded = false
  for config in status.configs {
    match config.state {
      Loaded => loaded = true
      Failed(error) =>
        rows.push(
          item(
            title=text(locale, ConfigFailed(config.path)),
            detail=error,
            state=("danger", text(locale, Failed)),
          ),
        )
    }
  }
  if loaded && status.servers.is_empty() {
    rows.push(note(text(locale, NoServers)))
  }
  for server in status.servers {
    rows.push(server_row(locale, server))
  }
}

///|
/// A row that only says something: nothing to operate, nothing went wrong.
fn note(message : String) -> @html.Html {
  @html.div(class="setting-row", [
    @html.div(class="setting-text", [@html.div(class="setting-desc", message)]),
  ])
}

///|
/// A row for something that went wrong while asking, with the error in the
/// words of whoever reported it.
fn problem(title : String, error : String) -> @html.Html {
  @html.div(class="setting-row", [
    @html.div(class="setting-text", [
      @html.div(class="setting-name", title),
      @html.div(class="setting-desc", error),
    ]),
  ])
}

///|
/// One listed thing — a server or a configuration file — with an optional
/// monospace meta line, a detail line, and its state on the right as the
/// app's status dot and label. `state` is the dot's tone and the label.
fn item(
  title~ : String,
  meta? : String,
  detail~ : String,
  detail_title? : String,
  state~ : (String, String),
) -> @html.Html {
  let (tone, label) = state
  let lines : Array[@html.Html] = [@html.div(class="setting-name", title)]
  if meta is Some(meta) {
    lines.push(@html.div(class="mcp-meta", meta))
  }
  lines.push(
    @html.div(class="setting-desc mcp-detail", title?=detail_title, detail),
  )
  @html.div(class="setting-row mcp-item", [
    @html.div(class="setting-text", lines),
    @html.div(class="run-status mcp-status", [
      @html.span(class="run-dot \{tone}", ""),
      @html.span(class="run-text", label),
    ]),
  ])
}

///|
/// A registered tool's name without the `mcp__<server>__` namespace every
/// MCP tool carries, which the row it is listed under already says.
fn short_tool_name(name : String) -> String {
  guard name.strip_prefix("mcp__") is Some(rest) &&
    rest.split_once("__") is Some((_, tool)) &&
    !tool.is_empty() else {
    return name
  }
  tool.to_owned()
}

///|
/// The tools a server registered, by their short names.
fn tool_line(tools : Array[@wire.McpTool]) -> (String, String) {
  let names = tools.map(tool => short_tool_name(tool.name))
  let full = tools.map(tool => {
    if tool.description.is_empty() {
      tool.name
    } else {
      "\{tool.name} — \{tool.description}"
    }
  })
  (names.join(", "), full.join("\n"))
}

///|
/// One server: its name, how it is reached, and the state the engine found it
/// in.
fn server_row(
  locale : @i18n.Locale,
  server : @wire.McpServerStatus,
) -> @html.Html {
  let transport = match server.transport {
    Stdio => "stdio"
    Http => "http"
  }
  let meta = "\{transport} · \{server.target}"
  match server.state {
    Connected(tools) => {
      let (detail, detail_title) = tool_line(tools)
      item(
        title=server.name,
        meta~,
        detail~,
        detail_title~,
        state=("ok", text(locale, Connected)),
      )
    }
    // The tools are still registered: these are the calls that now fail.
    Lost(tools) => {
      let (_, detail_title) = tool_line(tools)
      item(
        title=server.name,
        meta~,
        detail=text(locale, LostReason),
        detail_title~,
        state=("warn", text(locale, Lost)),
      )
    }
    NoTools =>
      item(
        title=server.name,
        meta~,
        detail=text(locale, NoToolsReason),
        state=("", text(locale, NoTools)),
      )
    Failed(error) =>
      item(
        title=server.name,
        meta~,
        detail=error,
        state=("danger", text(locale, Failed)),
      )
    Skipped =>
      item(
        title=server.name,
        meta~,
        detail=text(locale, SkippedReason),
        state=("", text(locale, Skipped)),
      )
  }
}
