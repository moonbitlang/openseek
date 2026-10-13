///|
/// The rows of the Settings page's MCP group for `conversation`: the
/// explanation with its refresh button, then that conversation's engine's
/// latest report.
pub fn rows(
  locale~ : @i18n.Locale = English,
  conversation~ : @interop.ConversationKey?,
  state : State,
  emit : @cmd.Emit[Msg],
) -> Array[@html.Html] {
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
  guard conversation is Some(_) else {
    rows.push(note(text(locale, NoConversation)))
    return rows
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
    { config_path, engine: NotRunning, } =>
      rows.push(note(text(locale, EngineNotRunning(config_path))))
    { engine: Connecting, .. } =>
      rows.push(note(text(locale, EngineConnecting)))
    { config_path, engine: Running(NotConfigured), } =>
      rows.push(note(text(locale, NotConfigured(config_path))))
    { engine: Running(ConfigFailed(path~, error~)), .. } =>
      rows.push(problem(text(locale, ConfigFailed(path)), error))
    { engine: Running(Configured(path~, servers=[])), .. } =>
      rows.push(note(text(locale, NoServers(path))))
    { engine: Running(Configured(servers~, ..)), .. } =>
      for server in servers {
        rows.push(server_row(locale, server))
      }
  }
  rows
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
fn server_row(
  locale : @i18n.Locale,
  server : @wire.McpServerStatus,
) -> @html.Html {
  let transport = match server.transport {
    Stdio => "stdio"
    Http => "http"
  }
  let details : Array[@html.Html] = [
    @html.div(class="setting-name", server.name),
    @html.div(class="setting-desc", "\{transport} · \{server.target}"),
  ]
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
