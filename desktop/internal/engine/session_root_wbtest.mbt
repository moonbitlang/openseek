// Tests for resolving explicit durable-session roots before the host shares
// them with engine processes and one-shot session queries.

///|
test "explicit relative session roots resolve against the host cwd" {
  let root = @path.Path(".openseek-test-root")
  let expected = root.resolve()
  guard resolved_session_root(payload_root=root) is Some(actual) else {
    fail("expected session root")
  }
  assert_eq(actual, expected)
}

///|
test "explicit absolute session roots are normalized" {
  let root = @path.Path(".openseek-test-root").resolve().join("..")
  let expected = root.normalize()
  guard resolved_session_root(payload_root=root) is Some(actual) else {
    fail("expected session root")
  }
  assert_eq(actual, expected)
}
