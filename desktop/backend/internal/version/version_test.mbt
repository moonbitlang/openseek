///|
fn parsed(text : String) -> @version.Version raise {
  guard @version.parse(text) is Some(version) else {
    fail("\{text} did not parse")
  }
  version
}

///|
test "versions compare numerically per component" {
  assert_true(parsed("0.2.0") > parsed("0.1.0"))
  assert_true(parsed("0.1.10") > parsed("0.1.9"))
  assert_true(parsed("1.0.0") > parsed("0.9.9"))
  assert_true(parsed("0.10.15") > parsed("0.10.9"))
}

///|
test "prefixes, suffixes, and trailing text are not part of a version" {
  assert_true(parsed("v0.2.0") == parsed("0.2.0"))
  assert_true(parsed("0.2.0-beta.1+build5") == parsed("0.2.0"))
  assert_true(
    parsed("v0.10.20+65efd5b93 (2026-11-05)\n") == parsed("0.10.20+b410defd5"),
  )
}

///|
test "malformed versions do not parse" {
  for text in ["latest", "0.2", "0.2.x", "test-version", ""] {
    assert_true(@version.parse(text) is None)
  }
}
