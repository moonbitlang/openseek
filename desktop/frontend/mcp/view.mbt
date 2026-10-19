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
    Running(status~, builtin_config~) =>
      status_rows(locale, status, builtin_config, rows)
  }
  rows
}

///|
/// What a running engine reported: the files it could not load, then its
/// servers in configuration order.
fn status_rows(
  locale : @i18n.Locale,
  status : @wire.McpStatus,
  builtin_config : String?,
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
      Failed(error) => {
        let name = if builtin_config == Some(config.path) {
          text(locale, Builtin)
        } else {
          config.path
        }
        rows.push(problem(text(locale, ConfigFailed(name)), error))
      }
    }
  }
  if loaded && status.servers.is_empty() {
    rows.push(note(text(locale, NoServers)))
  }
  for server in status.servers {
    rows.push(
      server_row(locale, server, builtin=builtin_config == Some(server.source)),
    )
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
/// A row for something that went wrong, with the error in the words of
/// whoever reported it (the host or the engine).
fn problem(title : String, error : String) -> @html.Html {
  @html.div(class="setting-row", [
    @html.div(class="setting-text", [
      @html.div(class="setting-name", title),
      @html.div(class="setting-desc mcp-error", error),
    ]),
  ])
}

///|
/// The tools a server registered, folded until asked for.
fn tool_list(locale : @i18n.Locale, tools : Array[@wire.McpTool]) -> @html.Html {
  @html.details(class="mcp-tools", [
    @html.summary(text(locale, ToolCount(tools.length()))),
    @html.ul(
      [
        for tool in tools => {
          @html.li(title=tool.description, [@html.code(tool.name)])
        }
      ],
    ),
  ])
}

///|
/// One server: its name, how it is reached, where it was configured — the
/// host's built-in file is named as such rather than by its path — and the
/// state the engine found it in.
fn server_row(
  locale : @i18n.Locale,
  server : @wire.McpServerStatus,
  builtin~ : Bool,
) -> @html.Html {
  let transport = match server.transport {
    Stdio => "stdio"
    Http => "http"
  }
  let name : Array[@html.Html] = [@html.text(server.name)]
  if builtin {
    name.push(@html.span(class="mcp-origin", text(locale, Builtin)))
  }
  let details : Array[@html.Html] = [
    @html.div(class="setting-name", name),
    @html.div(class="setting-desc", "\{transport} · \{server.target}"),
  ]
  if !builtin {
    details.push(
      @html.div(class="setting-desc", text(locale, FromFile(server.source))),
    )
  }
  let (badge_class, badge) = match server.state {
    Connected(tools) => {
      details.push(tool_list(locale, tools))
      ("mcp-state ok", Connected)
    }
    // The tools are still registered, so they are still listed: these are
    // the calls that now fail.
    Lost(tools) => {
      details.push(
        @html.div(class="setting-desc mcp-error", text(locale, LostReason)),
      )
      details.push(tool_list(locale, tools))
      ("mcp-state error", Lost)
    }
    NoTools => {
      details.push(@html.div(class="setting-desc", text(locale, NoToolsReason)))
      ("mcp-state", NoTools)
    }
    Failed(error) => {
      details.push(@html.div(class="setting-desc mcp-error", error))
      ("mcp-state error", Failed)
    }
    Skipped => {
      details.push(@html.div(class="setting-desc", text(locale, SkippedReason)))
      ("mcp-state", Skipped)
    }
  }
  @html.div(class="setting-row mcp-server", [
    @html.div(class="setting-text", details),
    @html.span(class=badge_class, text(locale, badge)),
  ])
}
