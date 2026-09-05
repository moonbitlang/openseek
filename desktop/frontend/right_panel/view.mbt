///|
/// The dock strip sits above the file breadcrumb and its permanent body hosts.
/// Child order is structural because Rabbita diffs by index; the viewer and
/// browser placeholders must not be re-keyed when the active tab changes.
fn panel_view(
  input : Input,
  actions : Actions,
  semantic_review? : @html.Html = @html.nothing,
) -> @html.Html {
  let chips : Array[@dock.TabChip] = input.dock.tabs.map(tab => {
    match tab {
      File(path~) => {
        let (label, missing) = match input.file_panel.docs.get(path) {
          Some(doc) => (doc.name, doc.state is TabDeleted)
          None => (@fileeditor.basename(path), false)
        }
        { tab, label, title: path.0, missing, }
      }
      GitDiff(diff~) => {
        let short = if diff.commit.length() <= 8 {
          diff.commit
        } else {
          diff.commit.view(end_offset=8).to_owned()
        }
        {
          tab,
          label: "\{@fileeditor.basename(diff.path)} (\{short})",
          title: "\{diff.path.0} at \{diff.commit}",
          missing: false,
        }
      }
      Browser(id~) => {
        let (label, title) = match @preview.page(input.preview, id) {
          Some(page) => {
            let label = @preview.page_label(page)
            (label, page.url.unwrap_or(label))
          }
          None => ("New Tab", "New Tab")
        }
        { tab, label, title, missing: false, }
      }
      Workflows =>
        {
          tab,
          label: "Workflows",
          title: "Subagents this conversation delegated to",
          missing: false,
        }
      FilePicker =>
        match input.file_panel.explorer_mode {
          ExplorerChanges =>
            {
              tab,
              label: "Review Changes",
              title: "Review changed files and diffs",
              missing: false,
            }
          ExplorerSearch =>
            {
              tab,
              label: "Search",
              title: "Search across files",
              missing: false,
            }
          ExplorerFiles =>
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
      Some(@cmd.batch([actions.browser_tab, actions.close_menu]))
    } else {
      None
    },
    search: @cmd.batch([actions.search, actions.close_menu]),
    files: @cmd.batch([actions.files, actions.close_menu]),
    review: @cmd.batch([actions.review, actions.close_menu]),
    workflows: @cmd.batch([actions.workflows, actions.close_menu]),
  }
  // Every body remains mounted and CSS selects the active kind. This preserves
  // the imperative Viewer and native browser attachment points.
  let mode = match input.dock.active {
    None => "mode-launcher"
    Some(Browser(_)) => "mode-browser"
    Some(FilePicker) if input.file_panel.explorer_mode is ExplorerChanges =>
      "mode-picker mode-review"
    Some(FilePicker) if input.file_panel.explorer_mode is ExplorerSearch =>
      "mode-picker mode-search-picker"
    Some(FilePicker) => "mode-picker"
    Some(File(_)) => "mode-file"
    Some(GitDiff(_)) => "mode-history"
    Some(Workflows) => "mode-workflows"
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
    attrs=@html.Attrs::build().tabindex(-1),
    [
      @fileeditor.resize_handle_view(),
      @dock.tabs_bar(
        actions.dock,
        input.dock,
        chips,
        launcher,
        menu_open=input.menu_open,
        expanded=input.expanded,
        toggle_menu=actions.toggle_menu,
        close_all_tabs=actions.close_all_tabs,
        close_all_tabs_disabled=input.dock.tabs.is_empty(),
        toggle_expanded=actions.toggle_expanded,
        toggle_panel=actions.toggle_panel,
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
        semantic_review~,
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
      @workflow.panel(input.workflows, { open_child: actions.open_child, }),
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
