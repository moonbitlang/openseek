///|
test "mint returns distinct RFC 9562 version 4 UUIDs" {
  guard @uuid.mint() is Some(first) else { fail("OS entropy unavailable") }
  guard @uuid.mint() is Some(second) else { fail("OS entropy unavailable") }
  assert_not_eq(first, second)
  assert_eq(first.length(), 36)
  assert_eq(first[8], '-')
  assert_eq(first[13], '-')
  assert_eq(first[18], '-')
  assert_eq(first[23], '-')
  assert_eq(first[14], '4')
  assert_true(
    first[19] == '8' || first[19] == '9' || first[19] == 'a' || first[19] == 'b',
  )
}
