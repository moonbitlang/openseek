///|
test "the launcher's context window is parsed from its raw value" {
  assert_true(parse_context_window(None) is None)
  assert_eq(parse_context_window(Some(" 1000000 ")), Some(1_000_000))
  assert_eq(parse_context_window(Some("131072")), Some(131_072))
  assert_true(parse_context_window(Some("")) is None)
  assert_true(parse_context_window(Some("0")) is None)
  assert_true(parse_context_window(Some("-4096")) is None)
  assert_true(parse_context_window(Some("plenty")) is None)
}
