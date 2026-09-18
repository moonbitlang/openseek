///|
/// Project durable panel data into the independent right-panel package.
fn Model::right_panel_input(self : Model) -> @right_panel.Input {
  @right_panel.Input(
    dock=self.dock,
    jobs=self.jobs,
    file_panel=self.file_panel,
    preview=self.preview,
    file_ctx=file_ctx(self),
    is_desktop=self.is_desktop,
    menu_open=self.right_panel_menu_open,
    expanded=self.right_panel_expanded,
    reveal_label=match self.context_menu_input() {
      { reveal_files: true, platform: MacOS, .. } =>
        Some(
          if self.locale is SimplifiedChinese {
            "在访达中打开"
          } else {
            "Open in Finder"
          },
        )
      { reveal_files: true, platform: Windows, .. } =>
        Some(
          if self.locale is SimplifiedChinese {
            "在文件资源管理器中打开"
          } else {
            "Open in File Explorer"
          },
        )
      { reveal_files: true, platform: Linux, .. } =>
        Some(
          if self.locale is SimplifiedChinese {
            "在文件夹中打开"
          } else {
            "Open in Folder"
          },
        )
      _ => None
    },
    workflows=self
      .active_conversation()
      .map(conv => conv.workflows)
      .unwrap_or([]),
  )
}
