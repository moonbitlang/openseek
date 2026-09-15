///|
test "child_session_ordinal parses exactly the runner's derivation" {
  assert_eq(child_session_ordinal("run-sr-3", "run"), Some(3))
  assert_eq(child_session_ordinal("run-sr-12", "run"), Some(12))
  // A child of a DIFFERENT parent, a non-numeric suffix, a bare parent,
  // and an id that merely contains the parent all parse to nothing.
  assert_eq(child_session_ordinal("other-sr-3", "run"), None)
  assert_eq(child_session_ordinal("run-sr-x", "run"), None)
  assert_eq(child_session_ordinal("run", "run"), None)
  assert_eq(child_session_ordinal("run-sr-", "run"), None)
  assert_eq(child_session_ordinal("run-sr-9999999999", "run"), None)
  // A grandchild-shaped id (`run-sr-1-sr-2`) belongs to parent `run-sr-1`.
  assert_eq(child_session_ordinal("run-sr-1-sr-2", "run"), None)
  assert_eq(child_session_ordinal("run-sr-1-sr-2", "run-sr-1"), Some(2))
}
