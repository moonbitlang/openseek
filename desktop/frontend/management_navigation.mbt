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
