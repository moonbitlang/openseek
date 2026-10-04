///|
test "a write with a string body gets a Content card" {
  let arguments =
    #|{"path":"scripts/fix.mbtx","content":"fn main {\n  println(1)\n}","revert_on_parse_errors":false}
  guard custom_card("write", arguments) is Some((label, _)) else {
    fail("expected a Content card")
  }
  assert_eq(label, "Content")
}

///|
/// A payload with no string body keeps the generic rendering.
test "an unreadable write payload keeps the generic rendering" {
  assert_true(custom_card("write", "not json") is None)
  assert_true(custom_card("write", "{\"path\":\"a.mbt\"}") is None)
  assert_true(
    custom_card("write", "{\"path\":\"a.mbt\",\"content\":3}") is None,
  )
  let oversized = "{\"path\":\"a.txt\",\"content\":\"\{"x".repeat(200_000)}\"}"
  assert_true(custom_card("write", oversized) is None)
}
