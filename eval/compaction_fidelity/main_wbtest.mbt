///|
/// The token matcher must reject matches embedded in longer words or
/// numbers, and must not panic when a rejected match starts with a
/// supplementary character: advancing one UTF-16 unit into a surrogate
/// pair makes the next slice trap.
test "contains_token honors boundaries and surrogate pairs" {
  assert_true(contains_token("no.", "no"))
  assert_true(contains_token("answer: no, not fixed", "no"))
  assert_false(contains_token("yes, it is now fixed", "no"))
  assert_false(contains_token("unknown", "no"))
  assert_false(contains_token("cli/emit.mbt:428", "cli/emit.mbt:42"))
  assert_true(contains_token("crash at cli/emit.mbt:42.", "cli/emit.mbt:42"))
  // First occurrence rejected (word char follows), cursor must step over
  // the whole surrogate pair to reach the accepted second occurrence.
  assert_true(contains_token("😀x 😀", "😀"))
  assert_false(contains_token("", "no"))
  assert_false(contains_token("anything", ""))
}
