// Local tests for the ported `OffsetRange` methods.
//
// Like `position_test.mbt`, this is not a 1:1 reference port: the checked-in
// vscode source has no
// `offsetRange.test.ts`. These cases assert the method semantics transcribed
// from `core/ranges/offsetRange.ts`.

///|
/// Constructor shorthand: a bare `OffsetRange(...)` only resolves when the
/// expected type is known, so build through a helper whose return type supplies
/// it.
fn or_(start : Int32, end_exclusive : Int32) -> OffsetRange {
  OffsetRange(start, end_exclusive)
}

///|
test "is_empty and length" {
  assert_true(or_(4, 4).is_empty())
  assert_false(or_(4, 5).is_empty())
  assert_eq(or_(4, 4).length(), 0)
  assert_eq(or_(2, 9).length(), 7)
}
