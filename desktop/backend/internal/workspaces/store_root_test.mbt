///|
test "explicit relative session roots resolve against the host cwd" {
  let root = @pathx.Path(".openseek-test-root")
  let expected = root.resolve()
  guard @workspaces.global_store_root(payload_root=root) is Some(actual) else {
    fail("expected session root")
  }
  assert_eq(actual, expected)
}

///|
test "explicit absolute session roots are normalized" {
  let root = @pathx.Path(".openseek-test-root").resolve().join("..")
  let expected = root.normalize()
  guard @workspaces.global_store_root(payload_root=root.to_path())
    is Some(actual) else {
    fail("expected session root")
  }
  assert_eq(actual, expected)
}
