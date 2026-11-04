///|
/// The archived page as a component that owns its filter. The shell mounts
/// one per visit, so each visit starts unfiltered; the rows come from the
/// stores the shell owns and arrive through `groups`.
pub fn component(
  locale : @rabbita.Val[@i18n.Locale],
  groups : @rabbita.Val[Array[Group]],
  actions : Actions,
) -> @rabbita.Val[@html.Html] {
  let (state, emit) = @rabbita.create_pure_state(State::empty(), update=(
    state,
    msg,
  ) => state.update(msg))
  state.view3(groups, locale, (state, groups, locale) => {
    view(locale, groups, state, emit, actions)
  })
}
