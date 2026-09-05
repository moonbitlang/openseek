///|
extern "js" fn titlebar_test_element(
  in_titlebar : Bool,
  excluded : Bool,
) -> @dom.Element =
  #| (inTitlebar, excluded) => ({
  #|   closest(selector) {
  #|     if (selector === ".sidebar-header, .topbar, .editor-tabsbar, .window-titlebar-drag-strip") {
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
  // The chrome selector group includes `.window-titlebar-drag-strip`, so this
  // accepting case also covers the explicit drag strip blank native pages
  // provide.
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

///|
test "blank native pages provide a drag target whose visibility follows geometry" {
  assert_true(window_titlebar_drag_strip_visible(true, true))
  assert_false(window_titlebar_drag_strip_visible(false, true))
  assert_false(window_titlebar_drag_strip_visible(true, false))
}
