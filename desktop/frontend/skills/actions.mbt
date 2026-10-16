///|
fn installed_menu_target(
  channel : @interop.ChannelId,
  item : InstalledItem,
) -> String {
  let host = match channel {
    Local => "local"
    Remote(id) => "remote:\{id.length()}:\{id}"
  }
  "skill:\{host}:\{item.id}"
}

///|
/// Resolve actions from the current library and catalog when the menu opens.
fn installed_menu(
  locale : @i18n.Locale,
  state : State,
  input : Input,
  target : String,
  emit : @cmd.Emit[Msg],
) -> @action_menu.Definition? {
  guard input.installed
    .iter()
    .find_first(item => installed_menu_target(input.channel, item) == target)
    is Some(item) &&
    item.identity() is Some(identity) &&
    state.pending_action(input.channel, identity) is None else {
    return None
  }
  let entries : Array[@action_menu.Entry] = []
  if state.update_candidate(item) is Some(candidate) {
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
  Some({ label: ui(locale, ManageSkill), entries, })
}
