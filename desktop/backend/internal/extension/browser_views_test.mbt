///|
test "view names round-trip and reject foreign views" {
  assert_true(@extension.browser_view_id("browser-3") == Some(3))
  assert_true(@extension.browser_view_id("browser-42") == Some(42))
  assert_true(@extension.browser_view_id("browser-") is None)
  assert_true(@extension.browser_view_id("sidebar") is None)
  assert_true(@extension.browser_view_id("browser-x") is None)
}
