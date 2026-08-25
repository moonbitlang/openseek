///|
extern "js" fn titlebar_test_element(
  in_titlebar : Bool,
  in_titlebar_page : Bool,
  excluded : Bool,
) -> @dom.Element =
  #| (inTitlebar, inTitlebarPage, excluded) => ({
  #|   closest(selector) {
  #|     if (selector === ".sidebar-header, .topbar, .editor-tabsbar") {
  #|       return inTitlebar ? this : null;
  #|     }
  #|     if (selector === ".window-titlebar-page") {
  #|       return inTitlebarPage ? this : null;
  #|     }
  #|     if (selector === "button, a, input, textarea, select, [role=button], .editor-tab, .dock-menu") {
  #|       return excluded ? this : null;
  #|     }
  #|     return null;
  #|   },
  #| })

///|
test "window zoom gesture accepts chrome and excludes controls and popups" {
  assert_true(
    is_window_titlebar_double_click_target(
      titlebar_test_element(true, false, false),
      200,
    ),
  )
  assert_false(
    is_window_titlebar_double_click_target(
      titlebar_test_element(true, false, true),
      20,
    ),
  )
  assert_false(
    is_window_titlebar_double_click_target(
      titlebar_test_element(false, false, false),
      20,
    ),
  )
}

///|
test "top edge remains titlebar chrome on pages without a topbar" {
  let page = titlebar_test_element(false, true, false)
  assert_true(is_window_titlebar_double_click_target(page, 20))
  assert_false(is_window_titlebar_double_click_target(page, 46))
}

///|
test "window titlebar gesture follows Proton overlay platforms" {
  assert_true(window_titlebar_platform_supports_overlay("MacIntel"))
  assert_true(window_titlebar_platform_supports_overlay("Windows"))
  assert_true(window_titlebar_platform_supports_overlay("Win32"))
  assert_false(window_titlebar_platform_supports_overlay("Linux x86_64"))
}
