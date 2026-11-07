///|
/// The one line the overview shows for `conversation`'s connectors while
/// their card is folded: how many servers its engine reached, and how many
/// it could not, or where the question stands.
pub fn summary(
  locale~ : @i18n.Locale = English,
  conversation : @interop.ConversationKey,
  state : State,
) -> String {
  match state.phase_for(conversation) {
    Unchecked | Checking => text(locale, Checking)
    CheckFailed(_) => text(locale, CheckFailed)
    Loaded(Stopped) | Reloading(Stopped) => text(locale, NotRunning)
    Loaded(Connecting) | Reloading(Connecting) => text(locale, EngineConnecting)
    Loaded(Running(status)) | Reloading(Running(status)) => {
      let connected = status.servers
        .filter(server => server.state is Connected(_))
        .length()
      let failed = status.servers
        .filter(server => server.state is (Failed(_) | Lost(_)))
        .length() +
        status.configs.filter(config => config.state is Failed(_)).length()
      if failed > 0 {
        "\{text(locale, ConnectedCount(connected))} · \{text(locale, FailedCount(failed))}"
      } else {
        text(locale, ConnectedCount(connected))
      }
    }
  }
}

///|
/// Whether a question about `conversation` is out, so asking again would
/// only repeat it.
pub fn checking(conversation : @interop.ConversationKey, state : State) -> Bool {
  state.phase_for(conversation) is (Checking | Reloading(_))
}

///|
#derive(Eq, Debug)
priv enum ConnectorRow {
  Note(String)
  Item(
    tone~ : String,
    name~ : String,
    note~ : String?,
    detail~ : String?,
    title~ : String
  )
}

///|
/// The rows the overview shows for `conversation`'s connectors when their
/// card is unfolded: what that conversation's engine last reported.
pub fn rows(
  locale~ : @i18n.Locale = English,
  conversation : @interop.ConversationKey,
  state : State,
) -> Array[@html.Html] {
  row_data(locale~, conversation, state).map(row => row.render())
}

///|
fn row_data(
  locale~ : @i18n.Locale = English,
  conversation : @interop.ConversationKey,
  state : State,
) -> Array[ConnectorRow] {
  let rows : Array[ConnectorRow] = []
  match state.phase_for(conversation) {
    Unchecked | Checking => rows.push(Note(text(locale, Checking)))
    CheckFailed(error) =>
      rows.push(
        Item(
          tone="danger",
          name=text(locale, CheckFailed),
          note=None,
          detail=Some(error),
          title=error,
        ),
      )
    Loaded(Stopped) | Reloading(Stopped) =>
      rows.push(Note(text(locale, EngineStopped)))
    Loaded(Connecting) | Reloading(Connecting) =>
      rows.push(Note(text(locale, EngineConnecting)))
    Loaded(Running(status)) | Reloading(Running(status)) =>
      status_rows(locale, status, rows)
  }
  rows
}

///|
/// What a running engine reported: the files it could not load, then its
/// servers in configuration order.
fn status_rows(
  locale : @i18n.Locale,
  status : @wire.McpStatus,
  rows : Array[ConnectorRow],
) -> Unit {
  for config in status.configs {
    if config.state is Failed(error) {
      rows.push(
        Item(
          tone="danger",
          name=config.path,
          note=Some(text(locale, Failed)),
          detail=Some(error),
          title="\{config.path}\n\{error}",
        ),
      )
    }
  }
  if status.servers.is_empty() {
    if status.configs.all(config => config.state is Loaded) {
      rows.push(Note(text(locale, NotConfigured)))
    }
    return
  }
  for server in status.servers {
    rows.push(server_row(locale, server))
  }
}

///|
fn ConnectorRow::render(self : ConnectorRow) -> @html.Html {
  match self {
    Note(message) => @html.div(class="connectors-note", message)
    Item(tone~, name~, note~, detail~, title~) => {
      let text_lines : Array[@html.Html] = [
        @html.span(class="connectors-name", name),
      ]
      if detail is Some(detail) {
        text_lines.push(@html.span(class="connectors-detail", detail))
      }
      let children : Array[@html.Html] = [
        @html.span(class="run-dot \{tone}", ""),
        @html.div(class="connectors-text", text_lines),
      ]
      if note is Some(note) {
        children.push(@html.span(class="connectors-state", note))
      }
      @html.div(class="connectors-row", title~, children)
    }
  }
}

///|
/// One server and the state the engine found it in. How it is reached and
/// its tools are on hover.
fn server_row(
  locale : @i18n.Locale,
  server : @wire.McpServerStatus,
) -> ConnectorRow {
  let transport = match server.transport {
    Stdio => "stdio"
    Http => "http"
  }
  let reached = "\{transport} · \{server.target}"
  match server.state {
    Connected(tools) =>
      Item(
        tone="ok",
        name=server.name,
        note=Some(text(locale, ToolCount(tools.length()))),
        detail=None,
        title="\{reached}\n\{tool_list(tools)}",
      )
    // The tools are still registered: these are the calls that now fail.
    Lost(tools) =>
      Item(
        tone="warn",
        name=server.name,
        note=Some(text(locale, Lost)),
        detail=Some(text(locale, LostReason)),
        title="\{reached}\n\{tool_list(tools)}",
      )
    NoTools =>
      Item(
        tone="",
        name=server.name,
        note=Some(text(locale, NoTools)),
        detail=None,
        title="\{reached}\n\{text(locale, NoToolsReason)}",
      )
    Failed(error) =>
      Item(
        tone="danger",
        name=server.name,
        note=Some(text(locale, Failed)),
        detail=Some(error),
        title="\{reached}\n\{error}",
      )
    Skipped =>
      Item(
        tone="",
        name=server.name,
        note=Some(text(locale, Skipped)),
        detail=None,
        title="\{reached}\n\{text(locale, SkippedReason)}",
      )
  }
}

///|
/// A server's registered tools, one per line, with their descriptions.
fn tool_list(tools : Array[@wire.McpTool]) -> String {
  tools
  .map(tool => {
    if tool.description.is_empty() {
      tool.name
    } else {
      "\{tool.name} — \{tool.description}"
    }
  })
  .join("\n")
}
