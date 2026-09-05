///|
/// Project durable panel data into the independent right-panel package.
fn Model::right_panel_input(self : Model) -> @right_panel.Input {
  @right_panel.Input(
    dock=self.dock,
    file_panel=self.file_panel,
    preview=self.preview,
    file_ctx=file_ctx(self),
    is_desktop=self.is_desktop,
    menu_open=self.right_panel_menu_open,
    expanded=self.right_panel_expanded,
    workflows=self
      .active_conversation()
      .map(conv => conv.workflows)
      .unwrap_or([]),
  )
}
