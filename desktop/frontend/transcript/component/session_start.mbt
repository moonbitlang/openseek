///|
priv enum SessionStartContent {
  Ready(SessionStartReady)
  Unavailable(
    source~ : @session_start.Source,
    request~ : String,
    title~ : String,
    error~ : String
  )
} derive(Eq)

///|
priv struct SessionStartReady {
  card : @session_start.Card
  models : Array[@select_control.ViewOption]
  connected : Bool
  here_available : Bool
  call : @transcript.ToolCall
} derive(Eq)

///|
fn Input::session_start_card(
  self : Input,
  call : @transcript.ToolCall,
) -> @session_start.Card? {
  guard self.source is OpenSeek &&
    self.session_start_source is Some(source) &&
    (
      call.name == "session" ||
      (call.name.has_prefix("mcp__") && call.name.has_suffix("__session"))
    ) &&
    call.outcome is Done(is_error=false, content~, ..) &&
    call.arguments is Some(arguments) &&
    card_fields(arguments) is Some(fields) &&
    fields.get("action") is Some(String("start")) &&
    fields.get("request_id") is Some(String(request)) &&
    card_fields(content.text()) is Some(result) &&
    result.get("id") is Some(String(id)) &&
    result.get("request_id") is Some(String(returned_request)) &&
    returned_request == request else {
    return None
  }
  // A persisted host proposal is the authority: foreign MCP output cannot
  // turn an arbitrary action/request_id pair into a session-start control.
  self.session_starts
  .iter()
  .find_first(card => {
    card.source == source &&
    card.request_id() == request &&
    card.proposal.id == id
  })
}

///|
fn Input::session_start_content(
  self : Input,
  call : @transcript.ToolCall,
) -> SessionStartContent? {
  if self.session_start_card(call) is Some(card) {
    return Some(
      Ready({
        card,
        models: self.session_start_models,
        connected: self.session_start_connected,
        here_available: self.session_start_here_available,
        call,
      }),
    )
  }
  guard self.source is OpenSeek &&
    self.session_start_source is Some(source) &&
    self.session_start_error is Some(error) &&
    (
      call.name == "session" ||
      (call.name.has_prefix("mcp__") && call.name.has_suffix("__session"))
    ) &&
    call.outcome is Done(is_error=false, ..) &&
    call.arguments is Some(arguments) &&
    card_fields(arguments) is Some(fields) &&
    fields.get("action") is Some(String("start")) &&
    fields.get("request_id") is Some(String(request)) &&
    fields.get("title") is Some(String(title)) else {
    return None
  }
  Some(Unavailable(source~, request~, title~, error~))
}

///|
fn SessionStartContent::request_id(self : SessionStartContent) -> String {
  match self {
    Ready(value) => value.card.request_id()
    Unavailable(request~, ..) => request
  }
}

///|
fn Input::extract_session_starts(
  self : Input,
  call : @transcript.ToolCall,
) -> (@transcript.ToolCall?, Array[SessionStartContent]) {
  if self.session_start_content(call) is Some(content) {
    return (None, [content])
  }
  let cards : Array[SessionStartContent] = []
  let children : Array[@transcript.ToolCall] = []
  for child in call.children {
    let (remaining, extracted) = self.extract_session_starts(child)
    cards.append(extracted)
    if remaining is Some(child) {
      children.push(child)
    }
  }
  (Some({ ..call, children, }), cards)
}

///|
fn SessionStartContent::render(
  self : SessionStartContent,
  locale : @i18n.Locale,
  actions : Actions,
) -> @html.Html {
  guard self is Ready(self) else {
    if self is Unavailable(source~, title~, error~, ..) {
      return @html.div(class="session-start-card", [
        @html.div(class="session-start-body", [
          @html.strong(title),
          @html.div(class="session-start-task", error),
        ]),
        @html.button(
          class="session-start-retry",
          on_click=(actions.session_start)(Retry(source)),
          match locale {
            SimplifiedChinese => "重试"
            TraditionalChinese => "重試"
            Japanese => "再試行"
            Spanish => "Reintentar"
            English => "Retry"
          },
        ),
      ])
    }
    return @html.nothing
  }
  let details = @html.details(class="session-start-tool-details", [
    @html.summary(ui(locale, ToolDetails)),
    tool_request_view(locale~, self.call),
    tool_result_view(locale~, self.call),
  ])
  self.card.render(
    locale,
    self.models,
    self.connected,
    actions.session_start,
    details~,
    here_available=self.here_available,
  )
}
