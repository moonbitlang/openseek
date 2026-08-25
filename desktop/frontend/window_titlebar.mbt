// The native overlay titlebar is painted by the page, so its web content has
// to recreate the operating system's double-click-to-zoom convention. Keep
// the gesture at the document boundary: the visible top chrome is split
// between the left sidebar, conversation topbar, and expanded editor strip.

///|
const WindowTitlebarSelector = ".sidebar-header, .topbar, .editor-tabsbar"

///|
const WindowTitlebarPageSelector = ".window-titlebar-page"

///|
const WindowTitlebarExcludedSelector = "button, a, input, textarea, select, [role=button], .editor-tab, .dock-menu"

///|
const WindowTitlebarPageHeight = 46

///|
fn window_titlebar_platform_supports_overlay(platform : String) -> Bool {
  browser_platform_is_apple(platform) || platform.to_lower().has_prefix("win")
}

///|
fn window_titlebar_overlay_supported() -> Bool {
  window_titlebar_platform_supports_overlay(app_shortcut_browser_platform())
}

///|
fn is_window_titlebar_double_click_target(
  element : @dom.Element,
  client_y : Int,
) -> Bool {
  if element.closest(WindowTitlebarExcludedSelector) is Some(_) {
    return false
  }
  element.closest(WindowTitlebarSelector) is Some(_) ||
  (
    client_y < WindowTitlebarPageHeight &&
    element.closest(WindowTitlebarPageSelector) is Some(_)
  )
}

///|
priv suberror WindowTitlebarSubscription {
  WindowTitlebarSubscription(@cmd.Emit[Unit])
}

///|
fn window_titlebar_sub_loader(
  payload : Error,
  scheduler : &Scheduler,
) -> @sub.RunningSub? {
  match payload {
    WindowTitlebarSubscription(emit) => {
      let mut emit = emit
      let target = @dom.document().as_event_target()
      let listener : @dom.Listener = event => {
        guard event.to_mouse_event() is Some(mouse) &&
          mouse.get_button() == 0 &&
          event.target().to_element() is Some(element) &&
          is_window_titlebar_double_click_target(element, mouse.get_client_y()) else {
          return
        }
        // A title or workspace label is text in the DOM, but within window
        // chrome it behaves as chrome rather than selectable document text.
        event.prevent_default()
        scheduler.add(emit(()))
      }
      target.add_event_listener_with_options("dblclick", listener, capture=true)
      Some({
        unload: _ => {
          target.remove_event_listener_with_options(
            "dblclick",
            listener,
            capture=true,
          )
        },
        update_tagger: payload => {
          guard payload is WindowTitlebarSubscription(next) else { return }
          emit = next
        },
      })
    }
    _ => None
  }
}

///|
/// Install only after the caller has established that this is a desktop page
/// on a platform where Proton overlays web content into the native titlebar.
fn window_titlebar_subscription(emit : @cmd.Emit[Unit]) -> @sub.Sub {
  @sub.custom_sub(
    "window-titlebar-double-click",
    Global,
    WindowTitlebarSubscription(emit),
    window_titlebar_sub_loader,
  )
}
