///|
test "levels follow the drawing order: pages, panels by place, popups, top layer" {
  assert_true(Page.below(Panel(0)))
  assert_true(Panel(0).below(Panel(1)))
  assert_true(Panel(2).below(Popup))
  assert_true(Page.below(Popup))
  assert_true(Popup.below(TopLayer))
  assert_true(Panel(2).below(TopLayer))
  assert_false(TopLayer.below(TopLayer))
  assert_false(TopLayer.below(Popup))
  // A later layer of the same level goes on top: neither is below the other.
  assert_false(Panel(1).below(Panel(1)))
  assert_false(Popup.below(Popup))
  assert_false(Panel(2).below(Panel(1)))
  assert_false(Popup.below(Page))
}
