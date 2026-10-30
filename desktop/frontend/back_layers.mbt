///|
/// The root's open layers, each closed by Back (`@dismiss.on_back`): Escape
/// on a keyboard, the Android shell's Back button, whose event the root
/// answers for the app's lifetime (`@dismiss.host_back`). Components that own
/// their layers' open state register those themselves.
///
/// Within a level, layers stack in the order they open. When several open in
/// one update they stack in this array's order, so it lists them from the
/// bottom up: pages, then the narrow layout's panels, menus, and modals last.
fn back_layers(model : Model, emit : @cmd.Emit[Msg]) -> Array[@sub.Sub] {
  let layers = [@dismiss.host_back()]
  fn layer_at(level : @dismiss.Level, key : String, msg : Msg) {
    layers.push(@dismiss.on_back(key, level~, emit.map((_ : Unit) => msg)))
  }
  fn layer(key : String, msg : Msg) {
    layer_at(Popup, key, msg)
  }

  // A management page returns one page level, as its topbar does. With no
  // level to return to, Back is the host's: on Android it leaves the app.
  if model.screen.work_screen() is None &&
    !model.is_console_gated() &&
    model.navigation.can_back {
    layer_at(Page, "back-management-page", Navigation(Back))
  }
  // On the narrow layout the sidebar is a drawer, and the overview and the
  // files panel cover the conversation. Their places follow the stylesheet:
  // the drawer over the files panel over the overview.
  if model.narrow {
    if model.sidebar_open {
      layer_at(Panel(2), "back-sidebar", CloseSidebar)
    }
    if model.overview_shown() {
      layer_at(Panel(0), "back-overview", CloseOverview)
    }
    if model.file_panel_visible() {
      layer_at(Panel(1), "back-right-panel", CloseRightPanel)
    }
  }
  // Hiding the files panel keeps its highlight, but not the picker on screen.
  if model.file_panel_visible() &&
    model.file_panel.highlighted is Some(directory) {
    layer("back-breadcrumb-picker", FileEditor(HighlightCleared(directory)))
  }
  if model.right_panel_menu_open {
    layer_at(TopLayer, "back-right-panel-menu", CloseRightPanelMenu)
  }
  if model.select_menu is Some(_) {
    layer_at(TopLayer, "back-select-menu", CloseSelectMenu)
  }
  if model.screen is Codex {
    if model.codex.git_details_open() {
      layer(
        "back-git-details",
        Codex(channel=model.focused, @codex.Msg::close_git_details()),
      )
    }
  } else if model.screen is Chat && model.git_details_open {
    layer("back-git-details", CloseGitDetails)
  }
  if model.screen is Codex && model.codex.confirmation_dismissal() is Some(msg) {
    layer("back-codex-confirmation", Codex(channel=model.focused, msg))
  }
  if model.workspace_settings_dialog is Some(_) {
    layer_at(TopLayer, "back-workspace-settings", CloseWorkspaceSettings)
  }
  if model.session_import_dialog.is_open() {
    layer_at(TopLayer, "back-session-import", SessionImport(Close))
  }
  if model.export_dialog.is_open() {
    layer_at(TopLayer, "back-export-dialog", ExportDialog(Close))
  }
  if model.file_share_dialog.is_open() {
    layer_at(TopLayer, "back-file-share-dialog", FileShareDialog(Close))
  }
  if model.ssh_ui.editor_open || model.ssh_ui.details is Some(_) {
    layer("back-ssh", Ssh(Close))
  }
  if model.github.checkout_busy() && !model.github.checking_out() {
    layer("back-github-checkout", Github(DismissCheckout))
  }
  if model.update_ux is ConfirmingRestart(..) {
    layer("back-update-restart", CancelUpdateRestart)
  }
  if model.api_setup_open && !model.cloud_selected() {
    layer("back-api-setup", DismissApiSetup)
  }
  if model.project_picker is Some(_) {
    layer("back-project-picker", ProjectPicker(Close))
  }
  if model.archive_confirm is Some(_) {
    layer("back-archive-confirm", CancelArchiveDiscard)
  }
  if model.delete_confirm is Some(_) {
    layer("back-delete-confirm", CancelDeleteSession)
  }
  if model.quick_open.is_open() {
    layer("back-quick-open", QuickOpen(Dismiss))
  }
  layers
}

///|
/// Whether the conversation overview is on screen: the conversation page
/// renders it beside or over a transcript.
fn Model::overview_shown(self : Model) -> Bool {
  self.overview_open &&
  self.screen is Chat &&
  !(self.is_console_gated() && !self.cloud_selected()) &&
  self.chat_column() is Transcript(..)
}
