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
