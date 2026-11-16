///|
/// A completed assistant message's suggestion. The application binds the
/// source conversation to this request before performing any host operation.
#derive(Eq)
pub(all) struct SessionSuggestionRequest {
  sequence : Int32
  block : Int32
  prompt : String
}

///|
pub extend SessionSuggestionRequest with Eq::{equal, not_equal}

///|
#derive(Eq)
pub(all) enum SessionSuggestionState {
  Starting
  Started(session~ : String, archived~ : Bool)
  Failed(message~ : String)
}

///|
pub extend SessionSuggestionState with Eq::{equal, not_equal}

///|
fn session_suggestion_view(
  locale : @i18n.Locale,
  request : SessionSuggestionRequest,
  states : Array[(Int32, Int32, SessionSuggestionState)],
  actions : Actions,
) -> @html.Html {
  let mut state = None
  for (sequence, block, value) in states {
    if sequence == request.sequence && block == request.block {
      state = Some(value)
      break
    }
  }
  let (label, command, busy) = match state {
    None =>
      (
        ui(locale, CreateSessionAndStart),
        (actions.start_session)(request),
        false,
      )
    Some(Starting) => (ui(locale, SessionCreating), @cmd.none, true)
    Some(Started(session~, ..)) =>
      (ui(locale, OpenCreatedSession), (actions.open_session)(session), false)
    Some(Failed(..)) =>
      (ui(locale, RetryCreateSession), (actions.start_session)(request), false)
  }
  let children = [
    @html.div(
      class="session-suggestion-title",
      ui(locale, NewSessionSuggestion),
    ),
    @html.details(class="session-suggestion-prompt", open=true, [
      @html.summary(ui(locale, SessionSuggestionPrompt)),
      @html.pre(request.prompt),
    ]),
    @html.div(class="session-suggestion-actions", [
      @html.button(
        class="button primary",
        type_="button",
        disabled=busy,
        on_click=command,
        label,
      ),
      @markdown.copy_button(
        locale~,
        request.prompt,
        class="session-suggestion-copy",
        title=ui(locale, CopyMessage),
        label=ui(locale, CopyMessage),
      ),
    ]),
  ]
  if state is Some(Failed(message~)) {
    children.push(
      @html.div(
        class="session-suggestion-error",
        attrs=@html.Attrs::build().role("alert"),
        message,
      ),
    )
  }
  @html.div(
    class="session-suggestion",
    attrs=@html.Attrs::build().aria_busy(busy.to_string()),
    children,
  )
}
