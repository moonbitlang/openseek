///|
test "model uris round-trip session, workspace, and path" {
  let uri = model_uri("desktop-2026-07-06-abc", "/ws/my proj", "src/a b.mbt")
  guard parse_model_uri(uri) is Some(target) else {
    fail("expected a parsable model uri: \{uri}")
  }
  assert_eq(target.session, "desktop-2026-07-06-abc")
  assert_eq(target.workspace, "/ws/my proj")
  assert_eq(target.path, "src/a b.mbt")
}

///|
test "scratch conversations mint model uris without a workspace" {
  let uri = model_uri("desktop-test", "", "notes/中文.md")
  guard parse_model_uri(uri) is Some(target) else {
    fail("expected a parsable model uri: \{uri}")
  }
  assert_eq(target.workspace, "")
  assert_eq(target.path, "notes/中文.md")
}

///|
test "foreign uris do not parse as model targets" {
  assert_true(parse_model_uri("untitled:one") is None)
  // A model uri without a session addresses nothing.
  assert_true(parse_model_uri("openseek:///a.mbt") is None)
}
