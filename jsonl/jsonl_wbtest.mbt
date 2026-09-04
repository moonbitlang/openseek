///|
test "is_blank recognizes whitespace-only lines" {
  assert_true(is_blank(""))
  assert_true(is_blank("   \t \r"))
  assert_false(is_blank("{}"))
  assert_false(is_blank("  x "))
}

///|
test "parse_line skips blanks and decodes values" {
  assert_true(parse_line("   ") is None)
  assert_true(parse_line("{\"k\": 1}").unwrap() == { "k": 1 })
}
