///|
test "session ids are accepted as store record names" {
  assert_true(@session_store.safe_session_id("desktop-20260611-093045-123"))
  assert_true(@session_store.safe_session_id("my-cli-session"))
  assert_true(@session_store.safe_session_id("a.b"))
}

///|
test "session ids that could escape their root are refused" {
  assert_false(@session_store.safe_session_id(""))
  assert_false(@session_store.safe_session_id("."))
  assert_false(@session_store.safe_session_id(".."))
  assert_false(@session_store.safe_session_id("a/b"))
  assert_false(@session_store.safe_session_id("a\\b"))
  assert_false(@session_store.safe_session_id("../escape"))
}
