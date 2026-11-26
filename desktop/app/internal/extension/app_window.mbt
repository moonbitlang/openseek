// Application-window commands share the window's lifetime, but do not depend
// on its browser tabs. Resolve the existing lifecycle-owned handle when a
// command runs rather than retaining a second window owner here.

///|
fn titlebar_overlay(
  style : @protocol.AppTitlebarStylePayload,
  zoom_percent : Int32,
) -> @proton.TitlebarOverlay {
  // Browser zoom and monitor DPI are independent. Convert CSS pixels to
  // DIPs here; Proton scales DIPs to the current monitor's physical pixels.
  let dips = @math.ceil(style.height * zoom_percent.to_double() / 100.0)
  {
    height: @cmp.maximum(16, dips.to_int()),
    background_color: style.background_color,
    symbol_color: style.symbol_color,
  }
}

///|
test "titlebar height converts browser CSS pixels to DIPs" {
  let style : @protocol.AppTitlebarStylePayload = {
    dark: false,
    height: 49.28,
    background_color: "#ffffff",
    symbol_color: "#565d68",
  }
  assert_eq(titlebar_overlay(style, 100).height, 50)
  assert_eq(titlebar_overlay(style, 125).height, 62)
  assert_eq(titlebar_overlay(style, 25).height, 16)
}

///|
priv struct MacTitlebarBaseline {
  position : @proton.WindowButtonPosition
  height_points : Double
}

///|
fn MacTitlebarBaseline::aligned_position(
  self : MacTitlebarBaseline,
  header_height_points : Double,
) -> @proton.WindowButtonPosition {
  // Proton reports a symmetric row around the buttons. Increasing the top
  // inset by one point grows that row by two; round up so CSS uses its height.
  let extra = @cmp.maximum(0.0, header_height_points - self.height_points)
  let inset = @math.ceil(extra / 2.0).to_int()
  // Grow the left inset by the same amount to preserve the corner spacing.
  { x: self.position.x + inset, y: self.position.y + inset, }
}

///|
fn app_window_endpoints(
  window : () -> @proton.WindowHandle raise,
) -> Array[WindowEndpoint] {
  let mut mac_titlebar_baseline : MacTitlebarBaseline? = None
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
    WindowEndpoint(@commands.app_set_titlebar_style, (_, payload) => {
      let theme : @proton.WindowThemePreference = if payload.dark {
        Dark
      } else {
        Light
      }
      match @async.platform {
        Windows => {
          let handle = window()
          handle.set_theme(theme)
          handle.set_titlebar_overlay(
            Some(titlebar_overlay(payload, handle.zoom_percent())),
          )
          { custom_overlay: true, }
        }
        MacOS => {
          let handle = window()
          handle.set_theme(theme)
          let zoom = handle.zoom_percent().to_double() / 100.0
          if handle.window_button_position() is Some(position) {
            // Capture the original inset before moving the buttons. Proton
            // keeps a new position in fullscreen but only exposes the normal
            // overlay geometry outside it.
            if mac_titlebar_baseline is None &&
              handle.titlebar_area() is Some(area) {
              mac_titlebar_baseline = Some({
                position,
                height_points: @math.round(area.height * zoom),
              })
            }
            if mac_titlebar_baseline is Some(baseline) {
              let target = baseline.aligned_position(payload.height * zoom)
              if target.x != position.x || target.y != position.y {
                handle.set_window_button_position(Some(target))
              }
            }
          }
          { custom_overlay: false, }
        }
        _ => { custom_overlay: false, }
      }
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
