///|
/// A second Back can arrive before the first one's close has unmounted the
/// layer, so each overlay's Back message closes and never reopens.
test "Back's overlay dismissals close and never reopen" {
  let dispatch = test_dispatch()
  let model = test_model()
  for open in [true, false] {
    let (_, sidebar) = update(dispatch, CloseSidebar, {
      ..model,
      sidebar_open: open,
    })
    assert_false(sidebar.sidebar_open)
    let (_, overview) = update(dispatch, CloseOverview, {
      ..model,
      overview_open: open,
    })
    assert_false(overview.overview_open)
    let (_, panel) = update(dispatch, CloseRightPanel, {
      ..model,
      right_panel_open: open,
      right_panel_menu_open: open,
    })
    assert_false(panel.right_panel_open)
    assert_false(panel.right_panel_menu_open)
  }
}

///|
test "the overview is a layer only where a conversation page shows it" {
  let model = { ..test_model(), overview_open: true, }
  assert_false({ ..model, screen: Settings, }.overview_shown())
  assert_false({ ..model, overview_open: false, }.overview_shown())
}
