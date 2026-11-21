///|
/// The launcher's window arrives as the raw `OPENSEEK_CONTEXT_WINDOW` value, and
/// the parse is a pure function of it: only a positive integer counts, so
/// anything else leaves the build's table for the model in charge rather than
/// making the run plan against nonsense.
///
/// The variable itself is deliberately not set here. Async tests in one package
/// run concurrently, so a test that exported a window would decide what every
/// other test's turn plans against: the oversized-result test stopped executing
/// its tool call that way, because 100,000 tokens plus the batch's reserve no
/// longer fitted the window its neighbour had set.
test "the launcher's context window is parsed from its raw value" {
  assert_true(parse_context_window(None) is None)
  assert_eq(parse_context_window(Some(" 1000000 ")), Some(1_000_000))
  assert_eq(parse_context_window(Some("131072")), Some(131_072))
  assert_true(parse_context_window(Some("")) is None)
  assert_true(parse_context_window(Some("0")) is None)
  assert_true(parse_context_window(Some("-4096")) is None)
  assert_true(parse_context_window(Some("plenty")) is None)
}
