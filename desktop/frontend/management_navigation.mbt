///|
/// Conversation state stays in Model and the Codex component, including drafts,
/// loading/error state, and lifecycle fallback. Navigation retains only which
/// of those work surfaces was visible; it must never restore an old snapshot.
priv enum WorkScreen {
  OpenSeekWork
  CodexWork
} derive(Eq)

///|
fn Screen::work_screen(self : Screen) -> WorkScreen? {
  match self {
    Chat => Some(OpenSeekWork)
    Codex => Some(CodexWork)
    Settings | Skills | Schedules => None
  }
}

///|
/// Management pages cover the selected work surface; switching conversations
/// selects a new owner even when the other engine retains component state.
fn Model::codex_work_selected(self : Model) -> Bool {
  match self.screen.work_screen() {
    Some(CodexWork) => true
    Some(OpenSeekWork) => false
    None => self.management_return is Some(CodexWork)
  }
}

///|
fn management_header(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  title : String,
) -> Array[@html.Html] {
  @page_shell.header(
    title,
    shell_text(model.locale, ReturnToWorkLabel),
    dispatch(ReturnToWork),
  )
}
