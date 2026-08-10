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
/// open Quick Open, N starts a chat, B toggles the left sidebar, and Shift+B
/// toggles the right panel.
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
    ("KeyB", false) => Some(ToggleSidebar)
    ("KeyB", true) => Some(Dock(@dock.TogglePanel))
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
      // Ctrl+` follows the terminal buttons' existing toggle path. Application
      // command chords use a separate capture subscription because they must
      // beat embedded editors and browser defaults.
      subscriptions=(model, emit) => {
        let subs : Array[@sub.Sub] = [
          @sub.on_resize(
            emit.map(viewport => ViewportResized(width=viewport.width)),
          ),
          app_shortcut_subscription(emit),
          @sub.on_key_down(
            @cmd.Emit((keyboard : @rabbita/common.Keyboard) => {
              if keyboard.code() == "Backquote" &&
                keyboard.ctrl_key() &&
                !keyboard.shift_key() &&
                !keyboard.alt_key() &&
                !keyboard.meta_key() &&
                !keyboard.is_composing() &&
                !keyboard.repeat() {
                emit(Terminal(ToggleTerminal))
              } else {
                @cmd.none
              }
            }),
          ),
          external_link_subscription(emit.map(url => ExternalLinkClicked(url))),
        ]
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
        if model.dock.menu_open {
          subs.push(
            dismiss_subscription(
              "dock-menu-dismiss",
              trigger=".tab-add",
              emit.map((_ : Unit) => CloseDockMenu),
            ),
          )
        }
        @sub.batch(subs)
      },
    )
    state.view(model => view(emit, model))
  })
  app.mount("app")
}
