///|
/// Build the Skills page's independently updating Html. It re-renders when
/// its own state changes and when the focused host's library does, and at no
/// other time: everything else the model does — a streaming transcript, a
/// sidebar refresh — reuses the subtree already built.
///
/// The shell holds the `State` rather than the package: opening the dialog
/// is a sidebar action, and the library refresh a settled action asks for belongs to the
/// root's focused-host mirror. Everything drawn here comes from `State` and
/// `Input`, so nothing in the package can read the application model.
pub fn component(
  input : @rabbita.Val[Input],
  state : @rabbita.Val[State],
  locale : @rabbita.Val[@i18n.Locale],
  emit : @cmd.Emit[Msg],
) -> @rabbita.Val[(@html.Html, @html.Html)] {
  let localized = state.map3(input, locale, (state, input, locale) => {
    (state, input, locale)
  })
  let list = list_component(localized, emit)
  let detail = detail_component(localized, emit)
  list.map2(detail, (list, detail) => (list, detail))
}

///|
fn list_component(
  localized : @rabbita.Val[(State, Input, @i18n.Locale)],
  emit : @cmd.Emit[Msg],
) -> @rabbita.Val[@html.Html] {
  let installed = localized.map(localized => {
    let (state, input, locale) = localized
    @vector.from_array(
      input.installed
      .filter(item => {
        matches(state.query, [item.name, item.description, item.source])
      })
      .map(item => installed_menu_input(locale, state, input, item)),
    )
  })
  let list_menus = installed.assoc_by(
    (id, input) => {
      installed_menu(
        "skills-library:" + id,
        input.map(input => Some(input)),
        emit,
        class="skill-action",
      ).map2(input, (menu, input) => (input.item.id, menu))
    },
    by=input => "\{input.library}:\{input.item.id}",
  )
  localized.map2(list_menus, (localized, menus) => {
    let (state, input, locale) = localized
    list_page(locale~, state, input, emit, Map::from_array(menus.to_array()))
  })
}

///|
fn detail_component(
  localized : @rabbita.Val[(State, Input, @i18n.Locale)],
  emit : @cmd.Emit[Msg],
) -> @rabbita.Val[@html.Html] {
  let detail_input = localized.map(localized => {
    let (state, input, locale) = localized
    guard state.detail_open(input.library) else { return None }
    let target = match state.preview {
      Closed => return None
      Loading(target~, ..) | Ready(target~, ..) | Failed(target~, ..) => target
    }
    match detail_action_target(target, state, input) {
      Some(Installed(item)) =>
        Some(installed_menu_input(locale, state, input, item))
      _ => None
    }
  })
  let detail_menu = installed_menu(
    "skill-detail-menu",
    detail_input,
    emit,
    class="skill-detail-action",
  )
  localized.map2(detail_menu, (localized, menu) => {
    let (state, input, locale) = localized
    if state.detail_open(input.library) {
      detail_page(locale~, state, input, emit, menu)
    } else {
      @html.nothing
    }
  })
}
