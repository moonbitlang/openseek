///|
/// Build the palette's independently updating Html. It re-renders when the
/// palette's own state or the effective UI locale changes.
///
/// The shell holds the `State` rather than the package: opening is a global
/// shortcut whose capture-phase listener the shell already owns, the palette's
/// openness decides whether native browser views may stay on screen, and an
/// accepted row must reach the editor inside the same root transition that
/// closed the palette. The palette draws from `State` and the supplied locale;
/// `Input` reaches the package only through `open`, `handle`, and `reconcile`,
/// so nothing here can read the application model.
pub fn component(
  state : @rabbita.Val[State],
  emit : @cmd.Emit[Msg],
  locale : @rabbita.Val[@i18n.Locale],
) -> @rabbita.Val[@html.Html] {
  // Keep only the rendered picker, not the retired request's credentials or
  // file index. The DOM stays mounted for RUI's native close transition.
  let mut last = @html.nothing
  state.view2(locale, (state, locale) => {
    if state.is_open() {
      last = state.view(emit, locale)
    }
    last
  })
}
