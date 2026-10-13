///|
/// A stable, transparent overlay mounts the shared editor composer directly.
fn office_selection_preview_view(state : State, ctx : Ctx) -> @html.Html {
  let preview = state.pending_office_selection(ctx)
  @html.div(
    id=OfficeFeedbackHostId,
    class=if preview is Some(_) {
      "office-selection-preview editor-shell"
    } else {
      "office-selection-preview editor-shell hidden"
    },
    title=preview
      .map(value => value.summary.heading() + "\n" + value.summary.text)
      .unwrap_or(""),
    attrs=@html.Attrs::build().data_set(
      "theme",
      if ctx.dark_mode {
        "dark"
      } else {
        "light"
      },
    ),
    ([] : Array[@html.Html]),
  )
}
