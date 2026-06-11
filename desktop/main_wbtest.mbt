// Tests for the pure workspace-path helper. The full
// `session_workspace_dir` / `workspace_root` chain depends on the
// environment (HOME, an existing Documents folder), so the tests cover the
// pure piece: which ids are allowed under the workspace root.

///|
test "session ids are accepted as workspace folder names" {
  assert_true(safe_workspace_id("desktop-20260611-093045-123"))
  assert_true(safe_workspace_id("my-cli-session"))
  assert_true(safe_workspace_id("a.b"))
}

///|
test "ids that could escape the workspace root are rejected" {
  assert_false(safe_workspace_id(""))
  assert_false(safe_workspace_id("."))
  assert_false(safe_workspace_id(".."))
  assert_false(safe_workspace_id("a/b"))
  assert_false(safe_workspace_id("a\\b"))
  assert_false(safe_workspace_id("../escape"))
}

///|
test "a different endpoint cannot reuse a live engine process" {
  let base : RunConfig = {
    task: "t",
    api_key: "k",
    api_url: None,
    model: "deepseek-v4-pro",
    max_steps: 1000,
    engine: "openseek",
    cwd: None,
    session: None,
    session_root: None,
  }
  let custom = {
    ..base,
    api_url: Some("https://proxy.example/chat/completions"),
  }
  assert_true(engine_fingerprint(base) != engine_fingerprint(custom))
  assert_eq(engine_fingerprint(base), engine_fingerprint({ ..base, task: "u" }))
}
