///|
/// The root's non-native layers, each closed by Back (`@dismiss.on_back`): Escape
/// on a keyboard, the Android shell's Back button, whose event the root
/// answers for the app's lifetime (`@dismiss.host_back`). Components that own
/// their layers' open state register those themselves.
///
/// Within a level, layers stack in the order they open. When several open in
/// one update they stack in this array's order, so it lists them from the
/// bottom up: the narrow layout's panels, then menus and popups.
fn back_layers(model : Model, emit : @cmd.Emit[Msg]) -> Array[@sub.Sub] {
  let layers = [@dismiss.host_back()]
  fn layer_at(level : @dismiss.Level, key : String, msg : Msg) {
    layers.push(@dismiss.on_back(key, level~, emit.map((_ : Unit) => msg)))
  }
  fn layer(key : String, msg : Msg) {
    layer_at(Popup, key, msg)
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
  layers
}

///|
/// Whether the conversation overview is on screen: the conversation page
/// renders it beside or over a transcript, unless the console gate covers
/// the page.
fn Model::overview_shown(self : Model) -> Bool {
  self.overview_conversation() is Some(_) && !self.is_console_gated()
}
