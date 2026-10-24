// Application-window commands share the window's lifetime, but do not depend
// on its browser tabs. Resolve the existing lifecycle-owned handle when a
// command runs rather than retaining a second window owner here.

///|
fn app_window_endpoints(
  window : () -> @proton.WindowHandle raise,
) -> Array[WindowEndpoint] {
  [
    WindowEndpoint(@commands.app_language_apply, (_, payload) => {
      if !(@async.platform is Windows) {
        window().set_menu(
          Some(localized_menu(payload.language.unwrap_or("en"))),
        )
      }
      Acknowledged
    }),
    WindowEndpoint(@commands.app_system_appearance, (_, _) => {
      dark: @proton.system_appearance().color_scheme == Dark,
    }),
    WindowEndpoint(@commands.app_close_window, (_, _) => {
      window().close()
      Acknowledged
    }),
    WindowEndpoint(@commands.app_open_devtools, (_, _) => {
      window().web_contents().open_devtools()
      Acknowledged
    }),
    WindowEndpoint(@commands.app_set_titlebar_theme, (_, payload) => {
      let handle = window()
      if @async.platform is (Windows | MacOS) {
        handle.set_theme(if payload.dark { Dark } else { Light })
      }
      Acknowledged
    }),
    WindowEndpoint(@commands.app_toggle_maximized, (_, _) => {
      // Read the native state at command time: OS window controls may have
      // changed it since the last frontend event.
      let handle = window()
      if handle.state().maximized {
        handle.restore()
      } else {
        handle.maximize()
      }
      Acknowledged
    }),
  ]
}
