///|
/// The dock strip sits above the file breadcrumb and its permanent body hosts.
/// Child order is structural because Rabbita diffs by index; the viewer and
/// browser placeholders must not be re-keyed when the active tab changes.
fn panel_view(
  input : Input,
  model : Model,
  emit : @cmd.Emit[ComponentMsg],
  actions : Actions,
) -> @html.Html {
  let chips : Array[@dock.TabChip] = input.dock.tabs.map(tab => {
    match tab {
      File(path~) => {
        let (label, missing) = match input.file_panel.docs.get(path) {
          Some(doc) => (doc.name, doc.state is TabDeleted)
          None => (@fileeditor.basename(path), false)
        }
        { tab, label, title: path.0, missing }
      }
      Browser(id~) => {
        let (label, title) = match @preview.page(input.preview, id) {
          Some(page) => {
            let label = @preview.page_label(page)
            (label, page.url.unwrap_or(label))
          }
          None => ("New Tab", "New Tab")
        }
        { tab, label, title, missing: false }
      }
      FilePicker =>
        if input.file_panel.explorer_mode is ExplorerChanges {
          {
            tab,
            label: "Review Changes",
            title: "Review changed files and diffs",
            missing: false,
          }
        } else {
          {
            tab,
            label: "Open File",
            title: "Open a workspace file",
            missing: false,
          }
        }
    }
  })
  let launcher : @dock.LauncherActions = {
    // Browser tabs need this window's native views; a remote console has none.
    browser: if input.is_desktop {
      Some(@cmd.batch([actions.browser_tab, emit(CloseMenu)]))
    } else {
      None
    },
    files: @cmd.batch([actions.files, emit(CloseMenu)]),
    review: @cmd.batch([actions.review, emit(CloseMenu)]),
  }
  // Every body remains mounted and CSS selects the active kind. This preserves
  // the imperative Viewer and native browser attachment points.
  let mode = match input.dock.active {
    None => "mode-launcher"
    Some(Browser(_)) => "mode-browser"
    Some(FilePicker) if input.file_panel.explorer_mode is ExplorerChanges =>
      "mode-picker mode-review"
    Some(FilePicker) => "mode-picker"
    Some(File(_)) => "mode-file"
  }
  let active_page : @preview.PageState = match
    @dock.active_browser(input.dock) {
    Some(id) => @preview.page(input.preview, id).unwrap_or(blank_browser_page)
    None => blank_browser_page
  }
  let toolbar : @preview.ToolbarActions = {
    input: actions.browser_input,
    submit: actions.browser_submit,
    back: actions.browser_back,
    forward: actions.browser_forward,
    reload: actions.browser_reload,
    open_external: actions.browser_open_external,
  }
  @html.div(
    class=@fileeditor.editor_classes(input.file_panel, input.file_ctx) +
      " " +
      mode,
    [
      @fileeditor.resize_handle_view(),
      @dock.tabs_bar(
        actions.dock,
        input.dock,
        chips,
        launcher,
        menu_open=model.menu_open,
        toggle_menu=emit(ToggleMenu),
        toggle_panel=emit(External(TogglePanel)),
      ),
      @fileeditor.breadcrumb_view(
        actions.file_editor,
        input.file_panel,
        input.file_ctx,
      ),
      @fileeditor.body_view(
        actions.file_editor,
        input.file_panel,
        input.file_ctx,
      ),
      @html.div(class="browser-chrome", [
        @preview.toolbar_view(active_page, toolbar),
        @preview.failure_view(active_page),
        // A native page overlays this measured rectangle after navigation.
        @html.div(
          attrs=@html.Attrs::build().id("browser-pane").class("browser-pane"),
          ([] : Array[@html.Html]),
        ),
      ]),
      @dock.launcher_pane(launcher),
    ],
  )
}

///|
let blank_browser_page : @preview.PageState = {
  url: None,
  input: "",
  title: "",
  loading: false,
  failure: None,
}
