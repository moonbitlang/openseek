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
/// sidebar, and Shift+B toggles the right panel.
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
fn app_shortcut_platform_is_apple() -> Bool {
  let platform = app_shortcut_browser_platform().to_lower()
  platform.contains("mac") ||
  platform.contains("iphone") ||
  platform.contains("ipad") ||
  platform.contains("ipod")
}

///|
/// Map only the platform's exact, non-repeating command chords to the same
/// messages used by their corresponding UI buttons.
fn app_shortcut_message(keyboard : @dom.KeyboardEvent, is_apple : Bool) -> Msg? {
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
    ("KeyP", false) => Some(QuickOpenOpen(QuickOpenFiles))
    ("KeyT", false) => Some(QuickOpenOpen(QuickOpenSymbols))
    ("KeyN", false) => Some(NewChat)
    ("KeyO", false) => Some(AddProjectRequested)
    ("KeyB", false) => Some(ToggleSidebar)
    // The right-panel component owns Shift+B and updates its own Model.
    ("KeyB", true) => None
    _ => None
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
      // Component-owned chords (Shift+B and Ctrl+`) live with their local
      // Models. Application command chords use a separate capture subscription
      // because they must beat embedded editors and browser defaults.
      subscriptions=(model, emit) => {
        let subs : Array[@sub.Sub] = [
          @sub.on_resize(
            emit.map(viewport => ViewportResized(width=viewport.width)),
          ),
          app_shortcut_subscription(emit),
        ]
        // The project picker's Enter/Escape/paste surface, only while its
        // modal is open — same lifetime rule as the dismissal listeners.
        if model.project_picker is Some(_) {
          subs.push(project_picker_capture_subscription(emit))
        }
        // Click-away dismissal, one listener per menu and only while that menu
        // is open: a document-wide listener should not outlive what it serves.
        if model.git_details_open {
          subs.push(
            dismiss_subscription(
              "composer-git-dismiss",
              trigger=".composer-git-button",
              emit.map((_ : Unit) => CloseGitDetails),
            ),
          )
        }
        if model.launcher.open {
          subs.push(
            dismiss_subscription(
              "launcher-dismiss",
              trigger=".launcher-button",
              emit.map((_ : Unit) => CloseLauncher),
            ),
          )
        }
        if model.project_menu is Some(_) {
          subs.push(
            dismiss_subscription(
              "project-menu-dismiss",
              trigger=".workspace-menu-button",
              emit.map((_ : Unit) => CloseProjectMenu),
            ),
          )
        }
        @sub.batch(subs)
      },
    )
    let right_panel_input = state.map(model => model.right_panel_input())
    let (right_panel_html, right_panel_emit) = @right_panel.component(
      right_panel_input,
      {
        dock: emit.map(msg => Dock(msg)),
        file_editor: emit.map(msg => FileEditor(msg)),
        browser_tab: emit(BrowserTabRequested),
        files: emit(FilePickerRequested),
        review: emit(ReviewRequested),
        browser_input: emit.map(value => BrowserAddressEdited(value)),
        browser_submit: emit(BrowserNavigateSubmitted),
        browser_back: emit(BrowserBack),
        browser_forward: emit(BrowserForward),
        browser_reload: emit(BrowserReload),
        browser_open_external: emit(BrowserOpenExternal),
        external_link: emit.map(url => ExternalLinkClicked(url)),
        opened: @fileeditor.mount_cmds(emit.map(msg => FileEditor(msg))),
        visibility: emit.map(visibility => {
          RightPanelVisibilityChanged(
            open=visibility.open,
            menu_open=visibility.menu_open,
          )
        }),
      },
    )
    let ui_emit : @cmd.Emit[Msg] = @cmd.Emit(msg => {
      // Editor-bound UI messages must update the component's local visibility
      // before the root handles them. In particular, OpenFile completes later
      // as OpenFileAt, so waiting for the root Model would desynchronize the
      // next panel toggle from the visible layout.
      let panel_command = match msg {
        OpenFile(_)
        | JumpToMention(_)
        | JumpToLocation(..)
        | QuickOpenPick(_) => right_panel_emit(@right_panel.OpenPanel)
        _ => @cmd.none
      }
      @cmd.batch([panel_command, emit(msg)])
    })
    let terminal_input = state.map(model => model.terminal_input())
    let (terminal_html, terminal_emit) = @terminal.component(terminal_input, {
      external_link: right_panel_emit.map(url => @right_panel.ExternalLink(url)),
      error: emit.map(message => HostActionFailed(message)),
      visibility: emit.map(open => TerminalVisibilityChanged(open)),
      connect: (terminal_emit, channel, websocket_epoch) => {
        install_bridge(emit, terminal_emit, channel, websocket_epoch)
      },
    })
    let transcript_input = state.map(model => model.transcript_input())
    let transcript_html = @transcript_component.component(transcript_input, {
      open: ui_emit.map(path => OpenFile(path)),
      jump: ui_emit.map(target => {
        JumpToLocation(
          path=target.file,
          range=target.range,
          annotation=target.annotation,
        )
      }),
    })
    state.view4(terminal_html, transcript_html, right_panel_html, (
      model,
      terminal_html,
      transcript_html,
      right_panel_html,
    ) => {
      view(
        ui_emit,
        terminal_emit(@terminal.ToggleTerminal),
        right_panel_emit(@right_panel.TogglePanel),
        model,
        terminal_html,
        transcript_html,
        right_panel_html,
      )
    })
  })
  app.mount("app")
}
