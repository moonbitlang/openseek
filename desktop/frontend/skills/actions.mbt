///|
#derive(Debug, Eq)
priv struct InstalledMenuInput {
  library : String
  locale : @i18n.Locale
  item : InstalledItem
  update : MarketItem?
  pending : Bool
}

///|
fn installed_menu_input(
  locale : @i18n.Locale,
  state : State,
  input : Input,
  item : InstalledItem,
) -> InstalledMenuInput {
  {
    library: input.library.key(),
    locale,
    item,
    update: if item.builtin && input.library.locks_builtins() {
      None
    } else {
      state.update_candidate(item)
    },
    pending: item
    .identity()
    .bind(identity => state.pending_action(input.library, identity))
    is Some(_),
  }
}

///|
fn installed_menu(
  id : String,
  input : @rabbita.Val[InstalledMenuInput?],
  emit : @cmd.Emit[Msg],
  class~ : String,
) -> @rabbita.Val[@html.Html] {
  input.switch_by(
    input => {
      guard input is Some({ item, locale, update, pending: false, .. }) &&
        item.identity() is Some(_) else {
        return @rabbita.Val::constant(@html.nothing)
      }
      let entries : Array[@action_menu.Entry] = []
      if update is Some(candidate) {
        let label = ui(locale, UpdateTo(candidate.version))
        entries.push(
          Action({
            label,
            title: label,
            icon: Some(icon(@icons.icon_arrow_up)),
            enabled: true,
            destructive: false,
            command: emit(Update(candidate)),
          }),
        )
      }
      if !item.builtin {
        if !entries.is_empty() {
          entries.push(Separator)
        }
        entries.push(
          Action({
            label: ui(locale, Uninstall),
            title: ui(locale, Uninstall),
            icon: Some(icon(@icons.icon_trash)),
            enabled: true,
            destructive: true,
            command: emit(Uninstall(item)),
          }),
        )
      }
      guard !entries.is_empty() else {
        return @rabbita.Val::constant(@html.nothing)
      }
      @action_menu.dropdown(
        id,
        { label: ui(locale, ManageSkill), entries, },
        class="skill-menu-trigger \{class}",
        icon(@icons.icon_more),
      )
    },
    by=input => Repr::Repr(input).to_string(),
  )
}
