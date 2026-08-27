///|
test "mint produces distinct RFC 9562 version 4 UUIDs" {
  guard @uuid.mint() is Some(first) else { fail("OS entropy unavailable") }
  guard @uuid.mint() is Some(second) else { fail("OS entropy unavailable") }
  let bytes = @utf8.encode(first)
  assert_eq(bytes.length(), 36)
  assert_eq(bytes.get(8), Some(b'-'))
  assert_eq(bytes.get(13), Some(b'-'))
  assert_eq(bytes.get(14), Some(b'4'))
  assert_eq(bytes.get(18), Some(b'-'))
  assert_eq(bytes.get(23), Some(b'-'))
  assert_true(bytes.get(19) is Some(b'8' | b'9' | b'a' | b'b'))
  assert_true(first != second)
}
