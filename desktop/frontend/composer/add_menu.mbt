///|
fn Entry::can_attach(self : Entry, input : Input) -> Bool {
  (input.presentation.images_enabled || input.root is Some(_)) &&
  !input.presentation.disabled &&
  input.goal.draft is None &&
  input.shell_command(self.draft) is None
}

///|
fn Entry::add_menu_target(self : Entry) -> String {
  "composer-add:" +
  self.owner.channel.uri_authority() +
  ":" +
  self.owner.session +
  ":" +
  self.action_generation.to_string()
}

///|
fn Entry::add_menu(
  self : Entry,
  locale : @i18n.Locale,
  input : Input,
  target : String,
  emit : @cmd.Emit[Msg],
  action_emit : @cmd.Emit[Action],
) -> @action_menu.Definition? {
  guard target == self.add_menu_target() && self.can_attach(input) else {
    return None
  }
  let identity = self.identity()
  let image_emit = emit.map(event => ImageRead(identity, input.root, event))
  let entries : Array[@action_menu.Entry] = [
    @action_menu.Action({
      label: ui(locale, AddFilesPhotos),
      title: ui(locale, AttachHint),
      icon: Some(@icons.icon(@icons.icon_file_media)),
      enabled: true,
      destructive: false,
      command: pick_attachments(locale, input, image_emit),
    }),
  ]
  let folder_enabled = input.presentation.folder_references_enabled &&
    input.root is Some(_)
  entries.push(
    @action_menu.Action({
      label: ui(locale, AddFolderLabel),
      title: ui(
        locale,
        if folder_enabled {
          FolderReferenceHint
        } else {
          FolderDesktopOnlyHint
        },
      ),
      icon: Some(@icons.icon(@icons.icon_folder)),
      enabled: folder_enabled,
      destructive: false,
      command: match input.root {
        Some(root) if folder_enabled =>
          action_emit(FolderReferenceRequested(identity~, root~))
        _ => @cmd.none
      },
    }),
  )
  Some({ label: ui(locale, AddAttachments), entries, })
}
