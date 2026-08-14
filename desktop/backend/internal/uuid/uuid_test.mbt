///|
test "mint returns distinct RFC 9562 version 4 UUIDs" {
  let first = @uuid.mint()
  let second = @uuid.mint()
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
