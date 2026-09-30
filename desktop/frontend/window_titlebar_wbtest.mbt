///|
extern "js" fn titlebar_test_element(
  in_titlebar : Bool,
  excluded : Bool,
) -> @dom.Element =
  #| (inTitlebar, excluded) => ({
  #|   closest(selector) {
  #|     if (selector === ".sidebar-header, .topbar, .editor-tabsbar") {
  #|       return inTitlebar ? this : null;
  #|     }
  #|     if (selector === "button, a, input, textarea, select, [role=button], [contenteditable=true], .editor-tab, .dock-menu") {
  #|       return excluded ? this : null;
  #|     }
  #|     return null;
  #|   },
  #| })

///|
test "window zoom gesture accepts chrome and excludes controls and popups" {
  assert_true(
    is_window_titlebar_double_click_target(titlebar_test_element(true, false)),
  )
  assert_false(
    is_window_titlebar_double_click_target(titlebar_test_element(true, true)),
  )
  assert_false(
    is_window_titlebar_double_click_target(titlebar_test_element(false, false)),
  )
}
