// Tests for resolving explicit durable-session roots before the host shares
// them with engine processes and one-shot session queries.

///|
test "explicit relative session roots resolve against the host cwd" {
  let root = ".openseek-test-root"
  let expected = (root : @mbpath.Path).resolve().to_string()
  guard resolved_session_root(Some(root)) is Some(actual) else {
    fail("expected session root")
  }
  assert_eq(actual, expected)
}

///|
test "explicit absolute session roots are normalized" {
  let root = (".openseek-test-root" : @mbpath.Path).resolve().join("..")
  let expected = root.normalize().to_string()
  guard resolved_session_root(Some(root.to_string())) is Some(actual) else {
    fail("expected session root")
  }
  assert_eq(actual, expected)
}
