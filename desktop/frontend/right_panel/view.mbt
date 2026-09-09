///|
/// The dock strip sits above the file breadcrumb and its permanent body hosts.
/// Child order is structural because Rabbita diffs by index; the viewer and
/// browser placeholders must not be re-keyed when the active tab changes.
fn panel_view(
  locale? : @i18n.Locale = English,
  input : Input,
  actions : Actions,
  semantic_review? : @html.Html = @html.nothing,
  tab_menu? : @html.Html = @html.nothing,
) -> @html.Html {
  let chips : Array[@dock.TabChip] = input.dock.tabs.map(tab => {
    match tab {
      File(path~) => {
        let (label, missing) = match input.file_panel.docs.get(path) {
          Some(doc) => (doc.name, doc.state is TabDeleted)
          None => (@resource.label(path), false)
        }
        { tab, label, title: path.path, missing, }
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
            let label = @preview.page_label(page, locale~)
            (label, page.url.unwrap_or(label))
          }
          None => (ui(locale, NewTab), ui(locale, NewTab))
        }
        { tab, label, title, missing: false, }
      }
      Github =>
        {
          tab,
          label: "GitHub",
          title: "GitHub pull requests and issues",
          missing: false,
        }
      Jobs =>
        {
          tab,
          label: ui(locale, JobsLabel),
          title: ui(locale, JobsHint),
          missing: false,
        }
      Workflows =>
        {
          tab,
          label: ui(locale, WorkflowsLabel),
          title: ui(locale, WorkflowsHint),
          missing: false,
        }
      FilePicker => {
        let (label, title) = match input.file_panel.explorer_mode {
          ExplorerChanges => (ui(locale, ReviewChanges), ui(locale, ReviewHint))
          ExplorerSearch => (ui(locale, SearchLabel), ui(locale, SearchHint))
          ExplorerFiles => (ui(locale, OpenFile), ui(locale, OpenFileHint))
        }
        { tab, label, title, missing: false, }
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
    jobs: @cmd.batch([actions.jobs, actions.close_menu]),
    github: @cmd.batch([actions.github, actions.close_menu]),
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
    Some(Jobs) => "mode-jobs"
    Some(Github) => "mode-github"
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
        locale~,
        actions.dock,
        input.dock,
        chips,
        launcher,
        menu_open=input.menu_open,
        expanded=input.expanded,
        toggle_menu=actions.toggle_menu,
        close_menu=actions.close_menu,
        close_tabs=actions.close_tabs,
        toggle_expanded=actions.toggle_expanded,
      ),
      @fileeditor.breadcrumb_view(
        locale~,
        actions.file_editor,
        input.file_panel,
        input.file_ctx,
        reveal=match (input.reveal_label, input.file_ctx.active_file) {
          (Some(label), Some(path)) =>
            Some((label, (actions.reveal_file)(path.path)))
          _ => None
        },
      ),
      @fileeditor.body_view(
        locale~,
        actions.file_editor,
        input.file_panel,
        input.file_ctx,
        semantic_review~,
      ),
      @html.div(class="browser-chrome", [
        @preview.toolbar_view(locale~, active_page, toolbar),
        @preview.failure_view(active_page),
        // A native page overlays this measured rectangle after navigation.
        @html.div(
          attrs=@html.Attrs::build().id("browser-pane").class("browser-pane"),
          ([] : Array[@html.Html]),
        ),
      ]),
      @jobs.panel(locale~, input.jobs, actions.job_events),
      @workflow.panel(locale~, input.workflows, {
        open_child: actions.open_child,
      }),
      @dock.launcher_pane(locale~, launcher),
      @github.panel(
        locale~,
        input.github,
        actions.github_events,
        actions.open_link,
      ),
      tab_menu,
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
