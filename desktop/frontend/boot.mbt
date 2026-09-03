// The app's single entry, shared by the two shell executables:
// `frontend/desktop` (the proton webview) and `frontend/browser` (the
// console page openseek-api serves). Which personality the page runs is
// still decided at runtime by `@interop.page_channel()`.

///|
priv suberror AppShortcutSubscription {
  AppShortcutSubscription(@cmd.Emit[Msg])
}

///|
fn app_shortcut_sub_loader(
  payload : Error,
  scheduler : &Scheduler,
) -> @sub.RunningSub? {
  match payload {
    AppShortcutSubscription(emit) => {
      let mut emit = emit
      let target = @dom.document().as_event_target()
      let is_apple = app_shortcut_platform_is_apple()
      let listener : @dom.Listener = event => {
        guard event.to_keyboard_event() is Some(keyboard) &&
          app_shortcut_message(keyboard, is_apple) is Some(message) else {
          return
        }
        // In a real browser these chords overlap print/new-tab, new-window,
        // and bookmark commands. The app deliberately replaces them in both
        // shells; capture also reaches past Monaco/xterm before either can
        // consume the event.
        event.prevent_default()
        event.stop_propagation()
        scheduler.add(emit(message))
      }
      target.add_event_listener_with_options("keydown", listener, capture=true)
      Some({
        unload: _ => {
          target.remove_event_listener_with_options(
            "keydown",
            listener,
            capture=true,
          )
        },
        update_tagger: payload => {
          guard payload is AppShortcutSubscription(next) else { return }
          emit = next
        },
      })
    }
    _ => None
  }
}

///|
/// Subscribe to application command chords in both the native webview and
/// browser console. Apple platforms use Cmd; other platforms use Ctrl. P/T
/// open Quick Open, N starts a chat, O adds a project, B toggles the left
/// sidebar, Shift+B toggles the right panel, and Shift+F opens Search.
fn app_shortcut_subscription(emit : @cmd.Emit[Msg]) -> @sub.Sub {
  @sub.custom_sub(
    "app-shortcut-capture",
    Global,
    AppShortcutSubscription(emit),
    app_shortcut_sub_loader,
  )
}

///|
/// Browser platform label used to select Cmd on Apple systems and Ctrl
/// elsewhere, leaving Ctrl chords available to terminal programs on Apple.
fn app_shortcut_browser_platform() -> String {
  let navigator = @js.Value::cast_from(@dom.window().navigator())
  if @interop.js_prop(navigator, "userAgentData") is Some(user_agent_data) &&
    @interop.js_prop(user_agent_data, "platform") is Some(value) &&
    (@js.Cast::into(value) : String?) is Some(platform) &&
    !platform.is_empty() {
    return platform
  }
  if @interop.js_prop(navigator, "platform") is Some(value) &&
    (@js.Cast::into(value) : String?) is Some(platform) {
    platform
  } else {
    ""
  }
}

///|
fn browser_platform_is_apple(platform : String) -> Bool {
  let platform = platform.to_lower()
  platform.contains("mac") ||
  platform.contains("iphone") ||
  platform.contains("ipad") ||
  platform.contains("ipod")
}

///|
fn app_shortcut_platform_is_apple() -> Bool {
  browser_platform_is_apple(app_shortcut_browser_platform())
}

///|
fn Model::context_menu_input(self : Model) -> @action_menu.ContextInput {
  let platform = if !self.is_desktop {
    @action_menu.Web
  } else if browser_platform_is_apple(app_shortcut_browser_platform()) {
    @action_menu.MacOS
  } else if @common.platform_is_win32() {
    @action_menu.Windows
  } else {
    @action_menu.Linux
  }
  // The client platform names the file manager, so only a checkout on this
  // same Desktop may expose reveal. `Open` remains available for remote hosts
  // through the existing host-addressed file-link route.
  let reveal_files = self.is_desktop &&
    self.active_checkout() is Some(active) &&
    active.owner.channel is Local &&
    active.placement is Some(placement) &&
    placement.checkout_root() is Some(_)
  let open_web_links_in_app = self.is_desktop &&
    (self.screen is Chat || self.screen is Codex)
  { platform, open_web_links_in_app, reveal_files, }
}

///|
/// Map only the platform's exact, non-repeating command chords to the same
/// messages used by their corresponding UI buttons.
fn app_shortcut_message(keyboard : @dom.KeyboardEvent, is_apple : Bool) -> Msg? {
  if keyboard.code() == "Backquote" &&
    keyboard.ctrl_key() &&
    !keyboard.meta_key() &&
    !keyboard.alt_key() &&
    !keyboard.shift_key() &&
    !keyboard.is_composing() &&
    !keyboard.repeat() {
    return Some(Terminal(@terminal.ToggleTerminal))
  }
  let command = if is_apple {
    keyboard.meta_key() && !keyboard.ctrl_key()
  } else {
    keyboard.ctrl_key() && !keyboard.meta_key()
  }
  guard command &&
    !keyboard.alt_key() &&
    !keyboard.is_composing() &&
    !keyboard.repeat() else {
    return None
  }
  match (keyboard.code(), keyboard.shift_key()) {
    ("KeyP", false) => Some(QuickOpenOpen(@quick_open.Files))
    ("KeyT", false) => Some(QuickOpenOpen(@quick_open.Symbols))
    ("KeyN", false) => Some(NewChat)
    ("KeyO", false) => Some(AddProjectRequested)
    ("KeyB", false) => Some(ToggleSidebar)
    ("KeyB", true) => Some(ToggleRightPanel)
    ("KeyJ", false) if is_apple => Some(Terminal(@terminal.ToggleTerminal))
    ("KeyF", true) => Some(ExplorerRequested(ExplorerSearch))
    _ => None
  }
}

///|
/// Root message translation for the data-only sidebar component tree. Stable
/// component ids contain every value needed to build a domain message, so no
/// child component captures or stores the application model.
priv struct SidebarDispatcher {
  emit : @cmd.Emit[Msg]
}

///|
fn SidebarDispatcher::emit(self : SidebarDispatcher, message : Msg) -> @cmd.Cmd {
  (self.emit)(message)
}

///|
/// A component id this dispatcher has no route for is a wiring defect — a
/// source string and its dispatch arm out of sync. Surface it as an error
/// toast rather than swallowing the click.
fn SidebarDispatcher::unroutable(
  self : SidebarDispatcher,
  action : String,
  detail : String,
) -> @cmd.Cmd {
  self.emit(HostActionFailed("Sidebar \{action} has no route for \{detail}"))
}

///|
fn SidebarDispatcher::conversation_open(
  self : SidebarDispatcher,
  id : @conversation.Id,
) -> @cmd.Cmd {
  guard @interop.ChannelId::from_uri_authority(id.channel()) is Some(channel) else {
    return self.unroutable("open", "channel \{id.channel()}")
  }
  match id.source() {
    @conversation.OpenSeekLive =>
      self.emit(OpenSession(channel, id.conversation()))
    @conversation.OpenSeekArchived => {
      // The row carries the store its record lives in; without one the click
      // would name a session id in no particular store.
      guard id.root() is Some(root) &&
        @resource.of_path(channel, root) is Some(workspace) else {
        return self.unroutable("open", "archived row with no store")
      }
      self.emit(
        OpenArchivedSession(channel, session=id.conversation(), workspace~),
      )
    }
    @conversation.CodexLive => self.emit(CodexOpenThread(id.conversation()))
    @conversation.CodexDraft => self.emit(OpenCodex)
    source => self.unroutable("open", "source \{Repr(source)}")
  }
}

///|
fn SidebarDispatcher::conversation_archive(
  self : SidebarDispatcher,
  id : @conversation.Id,
) -> @cmd.Cmd {
  guard @interop.ChannelId::from_uri_authority(id.channel()) is Some(channel) else {
    return self.unroutable("archive", "channel \{id.channel()}")
  }
  match id.source() {
    @conversation.OpenSeekLive =>
      self.emit(ArchiveSession(channel, id.conversation()))
    @conversation.CodexLive => self.emit(CodexArchiveThread(id.conversation()))
    source => self.unroutable("archive", "\{Repr(source)}@\{id.channel()}")
  }
}

///|
fn SidebarDispatcher::conversation_restore(
  self : SidebarDispatcher,
  id : @conversation.Id,
) -> @cmd.Cmd {
  guard @interop.ChannelId::from_uri_authority(id.channel()) is Some(channel) else {
    return self.unroutable("restore", "channel \{id.channel()}")
  }
  match id.source() {
    @conversation.OpenSeekArchived =>
      self.emit(UnarchiveSession(channel, id.conversation()))
    @conversation.CodexArchived =>
      self.emit(CodexUnarchiveThread(id.conversation()))
    source => self.unroutable("restore", "\{Repr(source)}@\{id.channel()}")
  }
}

///|
fn SidebarDispatcher::conversation_delete(
  self : SidebarDispatcher,
  id : @conversation.Id,
) -> @cmd.Cmd {
  // The row carries the store its record lives in; a delete that could not
  // name one would address every same-id record at once.
  guard @interop.ChannelId::from_uri_authority(id.channel()) is Some(channel) &&
    id.source() is @conversation.OpenSeekArchived &&
    id.root() is Some(root) &&
    @resource.of_path(channel, root) is Some(workspace) else {
    return self.unroutable("delete", "\{Repr(id.source())}@\{id.channel()}")
  }
  self.emit(
    DeleteArchivedSession(channel, { session: id.conversation(), workspace, }),
  )
}

///|
fn SidebarDispatcher::project_new(
  self : SidebarDispatcher,
  id : @project.Id,
) -> @cmd.Cmd {
  guard @interop.ChannelId::from_uri_authority(id.channel()) is Some(channel) else {
    return self.unroutable("new chat", "channel \{id.channel()}")
  }
  match id.source() {
    "openseek.projects" => {
      // A click racing the project's detach loses its registry entry; that is
      // a dead row on its way out, not a wiring defect.
      guard @resource.of_path(channel, id.root()) is Some(project) else {
        return @cmd.none
      }
      self.emit(NewChatIn(channel, Some(project)))
    }
    source => self.unroutable("new chat", "\{source}@\{id.channel()}")
  }
}

///|
fn SidebarDispatcher::project_settings(
  self : SidebarDispatcher,
  id : @project.Id,
) -> @cmd.Cmd {
  guard @interop.ChannelId::from_uri_authority(id.channel()) is Some(channel) else {
    return self.unroutable("settings", "channel \{id.channel()}")
  }
  guard @resource.of_path(channel, id.root()) is Some(project) else {
    return @cmd.none
  }
  self.emit(OpenWorkspaceSettings(channel, project))
}

///|
fn SidebarDispatcher::project_detach(
  self : SidebarDispatcher,
  id : @project.Id,
) -> @cmd.Cmd {
  guard @interop.ChannelId::from_uri_authority(id.channel()) is Some(channel) else {
    return self.unroutable("detach", "channel \{id.channel()}")
  }
  guard @resource.of_path(channel, id.root()) is Some(project) else {
    return @cmd.none
  }
  self.emit(RemoveProject(channel, project))
}

///|
fn SidebarDispatcher::section_primary(
  self : SidebarDispatcher,
  id : @section.Id,
) -> @cmd.Cmd {
  guard @interop.ChannelId::from_uri_authority(id.channel()) is Some(channel) else {
    return self.unroutable("section action", "channel \{id.channel()}")
  }
  match id.source() {
    "openseek.projects" => self.emit(PickProject(channel))
    "openseek.chats" => self.emit(NewChatIn(channel, None))
    source => self.unroutable("section action", "source \{source}")
  }
}

///|
fn SidebarDispatcher::placeholder_open(
  self : SidebarDispatcher,
  id : String,
) -> @cmd.Cmd {
  self.unroutable("placeholder action", id)
}

///|
fn SidebarDispatcher::actions(self : SidebarDispatcher) -> @sidebar.Actions {
  let conversation : @conversation.Actions = {
    open: id => self.conversation_open(id),
    archive: id => self.conversation_archive(id),
    restore: id => self.conversation_restore(id),
    delete: id => self.conversation_delete(id),
    rename: (id, label) => self.emit(ConversationRenameRequested(id~, label~)),
    rename_changed: (id, value) => {
      self.emit(ConversationRenameChanged(id~, value~))
    },
    rename_submit: id => self.emit(ConversationRenameSubmitted(id)),
    rename_cancel: id => self.emit(ConversationRenameCancelled(id)),
  }
  let project : @project.Actions = {
    new_conversation: id => self.project_new(id),
    open_settings: id => self.project_settings(id),
    detach: id => self.project_detach(id),
    conversation,
  }
  let section : @section.Actions = {
    primary: id => self.section_primary(id),
    placeholder: id => self.placeholder_open(id),
    project,
    conversation,
  }
  {
    update: self.emit(UpdateClicked),
    open_skills: self.emit(OpenSkills),
    open_settings: self.emit(OpenSetup),
    refresh_account: self.emit(Console(RefreshClicked)),
    sign_out: self.emit(Console(SignOutClicked)),
    section,
  }
}

///|
#warnings("-alert_unstable")
pub fn boot() -> Unit {
  @crash_page.install()
  let app = @rabbita.new(() => {
    let (state, emit) = @rabbita.create_state_with_init(
      // Init flows through `update` like any other message, as
      // `with_init(dispatch(Init))` did before the 0.13 migration.
      init=emit => (initial_model(), emit(Init)),
      update=(model, msg, emit) => {
        let (cmd, next) = update(emit, msg, model)
        (next, cmd)
      },
      // The narrow-layout flag must track the window: rotating a phone or
      // resizing a desktop window across the breakpoint re-lays the app out.
      // Application command chords use one capture subscription because they
      // must beat embedded editors, xterm, and browser defaults.
      subscriptions=(model, emit) => {
        let subs : Array[@sub.Sub] = [
          @sub.on_resize(
            emit.map(viewport => ViewportResized(width=viewport.width)),
          ),
          app_shortcut_subscription(emit),
          // Host event sources follow the device roster. Removing a device
          // therefore unloads its WebSocket immediately; advancing its retry
          // identity replaces only that device's connection.
          model.bridge_subscriptions(emit),
        ]
        // The project picker's Enter/Escape/paste surface, only while its
        // modal is open — same lifetime rule as the dismissal listeners.
        subs.push(
          @project_picker.subscriptions(
            model.project_picker,
            emit.map(msg => ProjectPicker(msg)),
          ),
        )
        // Click-away dismissal, one listener per menu and only while that menu
        // is open: a document-wide listener should not outlive what it serves.
        if model.git_details_open ||
          (model.screen is Codex && model.codex.git_details_open()) {
          let close = if model.screen is Codex {
            emit.map((_ : Unit) => {
              Codex(channel=model.focused, @codex.Msg::close_git_details())
            })
          } else {
            emit.map((_ : Unit) => CloseGitDetails)
          }
          subs.push(
            @dismiss.on_outside_click(
              "composer-git-dismiss",
              trigger=".composer-git-button",
              close,
            ),
          )
        }
        match model.select_menu {
          Some(ProjectMenu) =>
            subs.push(
              @dismiss.on_outside_click(
                "empty-project-menu-dismiss",
                trigger=".empty-project-control",
                emit.map((_ : Unit) => CloseSelectMenu),
              ),
            )
          Some(_) =>
            subs.push(
              @dismiss.on_outside_click(
                "custom-select-dismiss",
                trigger=".custom-select-button",
                emit.map((_ : Unit) => CloseSelectMenu),
              ),
            )
          None => ()
        }
        if model.right_panel_menu_open {
          subs.push(
            @dismiss.on_outside_click(
              "right-panel-menu-dismiss",
              trigger=".tab-add",
              emit.map((_ : Unit) => CloseRightPanelMenu),
            ),
          )
        }
        if model.is_desktop {
          subs.push(
            window_focus_subscription(
              emit.map(focused => WindowFocusChanged(focused)),
            ),
          )
          // Only overlay titlebars turn the page's top chrome into native
          // window chrome; Linux keeps its separate system titlebar.
          if window_titlebar_overlay_supported() {
            subs.push(
              window_titlebar_subscription(
                emit.map((_ : Unit) => AppToggleMaximizedRequested),
              ),
            )
          }
          // Rabbita captures its own `@html.a` nodes. The embedded Viewer owns
          // foreign DOM below `.viewer-host`, so its anchors need the adjacent
          // document subscription to reach the same root URL policy.
          subs.push(
            @sub.on_url_request(
              emit.map(request => {
                ExternalLinkClicked(
                  match request {
                    @url.Internal(url) => url.to_string()
                    @url.External(url) => url
                  },
                )
              }),
            ),
          )
          subs.push(
            viewer_external_link_subscription(
              emit.map(url => ExternalLinkClicked(url)),
            ),
          )
        }
        if model.file_panel.highlighted is Some(directory) {
          subs.push(
            @dismiss.on_outside_click(
              "breadcrumb-picker-dismiss",
              // Directory crumbs toggle the picker, and the picker itself
              // supports nested folder navigation. Every other click closes
              // it without consuming the action under the pointer.
              trigger=".crumb-directory, .breadcrumb-picker",
              emit.map((_ : Unit) => FileEditor(HighlightCleared(directory))),
            ),
          )
        }
        // The changed-file inventory has no push channel for index-only
        // operations, so it keeps a low-rate fallback refresh. Its lifetime is
        // declared from the panel's own state instead of being chained from
        // each reply, which is what stops a hidden explorer or a switched
        // conversation from leaving an orphaned timer behind.
        subs.push(
          @fileeditor.subscriptions(
            model.file_panel,
            file_ctx(model),
            emit.map(msg => FileEditor(msg)),
          ),
        )
        @sub.batch(subs)
      },
    )
    let right_panel_input = state.map(model => model.right_panel_input())
    let right_panel_html = @right_panel.component(right_panel_input, {
      dock: emit.map(msg => Dock(msg)),
      file_editor: emit.map(msg => FileEditor(msg)),
      browser_tab: emit(BrowserTabRequested),
      search: emit(ExplorerRequested(ExplorerSearch)),
      files: emit(ExplorerRequested(ExplorerFiles)),
      review: emit(ExplorerRequested(ExplorerChanges)),
      browser_input: emit.map(value => BrowserAddressEdited(value)),
      browser_submit: emit(BrowserNavigateSubmitted),
      browser_back: emit(BrowserBack),
      browser_forward: emit(BrowserForward),
      browser_reload: emit(BrowserReload),
      browser_open_external: emit(BrowserOpenExternal),
      toggle_panel: emit(ToggleRightPanel),
      toggle_menu: emit(ToggleRightPanelMenu),
      toggle_expanded: emit(ToggleRightPanelExpanded),
      close_all_tabs: emit(CloseAllTabs),
      close_menu: emit(CloseRightPanelMenu),
    })
    let terminal_input = state.map(model => model.terminal_input())
    let terminal_state = state.map(model => model.terminal)
    let terminal_emit = emit.map(msg => Terminal(msg))
    let terminal_html = @terminal.component(
      terminal_input, terminal_state, terminal_emit,
    )
    let transcript_input = state.map(model => model.transcript_input())
    let transcript_html = @transcript_component.component(transcript_input, {
      open: emit.map(path => OpenFile(path)),
      jump: emit.map(target => {
        JumpToLocation(
          path=target.file,
          range=target.range,
          annotation=target.annotation,
        )
      }),
      open_session: emit.map(session => OpenSessionHere(session)),
      choose_project: emit.map(project => ProjectMenuProjectChosen(project)),
      new_project: emit(AddProjectRequested),
      toggle_project_menu: emit(ToggleSelectMenu(ProjectMenu)),
      dismiss_project_menu: emit(CloseSelectMenu),
      project_query_changed: emit.map(query => ProjectMenuQueryChanged(query)),
    })
    let composer_input = state.map(model => model.composer_input())
    let composer_html = @composer.component(
      composer_input,
      emit.map(action => ComposerAction(action)),
    )
    let codex_composer_input = state.map(model => model.codex_composer_input())
    let codex_composer_html = @composer.component(
      codex_composer_input,
      emit.map(action => CodexComposerAction(action)),
    )
    let sidebar_input = state.map(model => model.sidebar_component_input())
    let sidebar_html = @sidebar.component(
      sidebar_input,
      SidebarDispatcher::{ emit, }.actions(),
    )
    let quick_open_html = @quick_open.component(
      state.map(model => model.quick_open),
      emit.map(msg => QuickOpen(msg)),
    )
    let context_menu_html = @action_menu.context_component(
      state.map(model => model.context_menu_input()),
      {
        open_link: url => emit(ExternalLinkClicked(url)),
        open_external_link: url => open_external_link(emit, url),
        open_file: path => emit(OpenFile(path)),
        reveal_file: path => emit(RevealFile(path)),
      },
    )
    let skills_html = @skills.component(
      state.map(model => model.skills_input()),
      state.map(model => model.skills),
      emit.map(msg => Skills(msg)),
    )
    let workspace_settings_input = state.map(model => {
      model.workspace_settings_input()
    })
    let workspace_settings_html = @workspace_settings.component(
      workspace_settings_input,
      {
        choose_default_mode: (channel, workspace, value) => {
          emit(WorkspaceDefaultModeChosen(channel, workspace, value))
        },
        choose_submodules: (channel, workspace, value) => {
          emit(WorkspaceSubmodulesChosen(channel, workspace, value))
        },
        choose_submodule_timeout: (channel, workspace, value) => {
          emit(WorkspaceSubmoduleTimeoutChosen(channel, workspace, value))
        },
      },
    )
    // `Val::view9` is rabbita's widest composition. Stable overlay pairs share
    // one slot each without moving their state into the root model.
    let skills_and_workspace_settings = @rabbita.Val::map2(
      skills_html,
      workspace_settings_html,
      (skills, workspace_settings) => (skills, workspace_settings),
    )
    let quick_open_and_context_menu = @rabbita.Val::map2(
      quick_open_html,
      context_menu_html,
      (quick_open, context_menu) => (quick_open, context_menu),
    )
    state.view9(
      terminal_html,
      transcript_html,
      right_panel_html,
      composer_html,
      codex_composer_html,
      sidebar_html,
      quick_open_and_context_menu,
      skills_and_workspace_settings,
      (
        model,
        terminal_html,
        transcript_html,
        right_panel_html,
        composer_html,
        codex_composer_html,
        sidebar_html,
        quick_open_and_context_menu,
        skills_and_workspace_settings,
      ) => {
        view(
          emit,
          terminal_emit(@terminal.ToggleTerminal),
          emit(ToggleRightPanel),
          model,
          terminal_html,
          transcript_html,
          right_panel_html,
          composer_html,
          codex_composer_html,
          sidebar_html,
          quick_open_and_context_menu,
          skills_and_workspace_settings,
        )
      },
    )
  })
  app.mount("app")
}
