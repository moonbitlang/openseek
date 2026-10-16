///|
/// Build the Skills page's independently updating Html. It re-renders when
/// its own state changes and when the focused host's library does, and at no
/// other time: everything else the model does — a streaming transcript, a
/// sidebar refresh — reuses the subtree already built.
///
/// The shell holds the `State` rather than the package: the page is one of
/// the shell's screens, opening it is a sidebar action the shell already
/// owns, and the library refresh a settled action asks for belongs to the
/// root's focused-host mirror. Everything drawn here comes from `State` and
/// `Input`, so nothing in the package can read the application model.
pub fn component(
  input : @rabbita.Val[Input],
  state : @rabbita.Val[State],
  locale : @rabbita.Val[@i18n.Locale],
  emit : @cmd.Emit[Msg],
) -> @rabbita.Val[@html.Html] {
  let localized = state.map3(input, locale, (state, input, locale) => {
    (state, input, locale)
  })
  let menu = @action_menu.component(localized, (localized, target) => {
    let (state, input, locale) = localized
    installed_menu(locale, state, input, target, emit)
  })
  localized.view2(menu, (localized, menu) => {
    let (state, input, locale) = localized
    @html.fragment([page(locale~, state, input, emit), menu])
  })
}

///|
/// The persistent header follows the page's current navigation level.
/// The shell owns global history controls and keyboard navigation.
pub fn State::header(
  self : State,
  locale~ : @i18n.Locale = English,
  title : String,
) -> Array[@html.Html] {
  match self.preview {
    Closed => @page_shell.header(title)
    _ => @page_shell.header(ui(locale, Details))
  }
}
